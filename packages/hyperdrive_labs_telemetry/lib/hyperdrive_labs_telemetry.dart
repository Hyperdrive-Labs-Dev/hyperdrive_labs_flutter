import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';
import 'package:hyperdrive_labs_telemetry/src/build_device_resource.dart';
import 'package:hyperdrive_labs_telemetry/src/disk_queue_span_exporter.dart';
import 'package:opentelemetry/api.dart' as otel;
import 'package:opentelemetry/sdk.dart' as otel_sdk;
import 'package:path_provider/path_provider.dart';

export 'src/otel_dio_interceptor.dart';
export 'src/otel_navigator_observer.dart';

/// An offline-first telemetry manager that configures OpenTelemetry SDK
/// tracing, intercepts unhandled errors, and queues OTLP payloads to disk.
class HyperdriveLabsTelemetry with WidgetsBindingObserver {
  static const String _envEndpoint = String.fromEnvironment(
    'OTEL_EXPORTER_OTLP_ENDPOINT',
  );
  static const String _envHeaders = String.fromEnvironment(
    'OTEL_EXPORTER_OTLP_HEADERS',
  );
  static const String _envServiceName = String.fromEnvironment(
    'OTEL_SERVICE_NAME',
    defaultValue: 'flutter_app',
  );

  static late Uri _otlpEndpoint;
  static late Map<String, String> _headers;
  static bool _isFlushing = false;
  static Timer? _flushTimer;
  static final HyperdriveLabsTelemetry _instance = HyperdriveLabsTelemetry._();
  static otel.Tracer _tracer = otel.globalTracerProvider.getTracer(
    'hyperdrive_labs_telemetry',
  );

  HyperdriveLabsTelemetry._();

  /// The [http.Client] instance used to post queued OTLP telemetry to the collector.
  ///
  /// Can be overridden during unit testing to mock network calls.
  @visibleForTesting
  static http.Client client = http.Client();

  /// Overrides the local storage directory path during automated tests.
  @visibleForTesting
  static String? testDirectoryPath;

  /// Sets the global OpenTelemetry [otel.Tracer] instance.
  ///
  /// Can be overridden during unit testing
  @visibleForTesting
  static set tracer(otel.Tracer newTracer) {
    _tracer = newTracer;
  }

  /// Returns the global OpenTelemetry [otel.Tracer] instance.
  static otel.Tracer get tracer => _tracer;

  static Future<Directory> _getStorageDir() async {
    if (testDirectoryPath != null) {
      return Directory(testDirectoryPath!);
    }
    return await getApplicationDocumentsDirectory();
  }

  /// Initializes the offline-first OpenTelemetry SDK pipeline.
  ///
  /// Connects global error handlers, starts a background flush timer set to [flushInterval],
  /// attaches app lifecycle observers, and executes [runAppCallback].
  ///
  /// Parameters default to `--dart-define` environment variables:
  /// - [otlpEndpoint]: Fallback `--dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=...`
  /// - [headers]: Fallback `--dart-define=OTEL_EXPORTER_OTLP_HEADERS=...`
  /// - [serviceName]: Fallback `--dart-define=OTEL_SERVICE_NAME=...`
  /// - [flushInterval]: Periodic auto-flush interval (Default: 10 seconds).
  static Future<void> init({
    Uri? otlpEndpoint,
    Map<String, String>? headers,
    String? serviceName,
    Duration flushInterval = const Duration(seconds: 10),
    required FutureOr<void> Function() runAppCallback,
  }) async {
    final resolvedEndpoint = otlpEndpoint?.toString() ?? _envEndpoint;
    if (resolvedEndpoint.isEmpty) {
      throw ArgumentError(
        'OTLP Endpoint must be provided via `otlpEndpoint` parameter or '
        '--dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=...',
      );
    }
    _otlpEndpoint = Uri.parse(resolvedEndpoint);
    _headers = (headers != null && headers.isNotEmpty)
        ? headers
        : _parseHeaders(_envHeaders);

    final resolvedServiceName =
        serviceName ??
        (_envServiceName.isNotEmpty ? _envServiceName : 'flutter_app');

    final storageDir = await _getStorageDir();
    final queueDir = Directory('${storageDir.path}/otel_queue');

    final deviceResource = await buildDeviceResource(resolvedServiceName);

    final exporter = DiskQueueSpanExporter(queueDir: queueDir);
    final processor = otel_sdk.SimpleSpanProcessor(exporter);

    otel.registerGlobalTracerProvider(
      otel_sdk.TracerProviderBase(
        processors: [processor],
        resource: deviceResource,
      ),
    );

    WidgetsBinding.instance.addObserver(_instance);

    final originalFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      recordException(
        exception: details.exception,
        stackTrace: details.stack,
        reason: details.context?.toString() ?? 'Flutter Framework Error',
      );
      if (originalFlutterOnError != null) {
        originalFlutterOnError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      recordException(
        exception: error,
        stackTrace: stack,
        reason: 'Unhandled Platform Exception',
      );
      return true;
    };

    await flushQueue();
    _startPeriodicFlush(flushInterval);

    runAppCallback();
  }

  static void _startPeriodicFlush(Duration interval) {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(interval, (_) {
      flushQueue();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      flushQueue();
    }
  }

  /// Disposes background flush timers and unregisters lifecycle listeners.
  static void dispose() {
    _flushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(_instance);
  }

  /// Manually records an [exception] as an error span into the current OTel context.
  ///
  /// - [exception]: The caught error or exception object.
  /// - [stackTrace]: Optional stack trace associated with the error.
  /// - [reason]: Contextual description of where or why the exception occurred.
  static void recordException({
    required Object exception,
    StackTrace? stackTrace,
    required String reason,
  }) {
    // 1. Resolve parent context from the active screen if available
    otel.Context parentContext = otel.Context.current;
    if (OTelNavigatorObserver.activeScreenContext != null) {
      parentContext = otel.contextWithSpanContext(
        otel.Context.root,
        OTelNavigatorObserver.activeScreenContext!,
      );
    }

    // 2. Start span parented to the current screen journey
    final span = tracer.startSpan('Error: $reason', context: parentContext);

    // 3. Attach rich standard APM attributes
    span.setAttribute(
      otel.Attribute.fromString('os.type', Platform.operatingSystem),
    );
    span.setAttribute(
      otel.Attribute.fromString('os.version', Platform.operatingSystemVersion),
    );
    span.setAttribute(
      otel.Attribute.fromString(
        'screen.name',
        OTelNavigatorObserver.activeScreenName,
      ),
    );
    span.setAttribute(otel.Attribute.fromString('error.reason', reason));

    final st = stackTrace ?? StackTrace.current;

    // Explicitly set the semantic exception attributes so backends like OpenObserve
    // parse them reliably into error/stacktrace views
    span.setAttribute(
      otel.Attribute.fromString(
        'exception.type',
        exception.runtimeType.toString(),
      ),
    );
    span.setAttribute(
      otel.Attribute.fromString('exception.message', exception.toString()),
    );
    span.setAttribute(
      otel.Attribute.fromString('exception.stacktrace', st.toString()),
    );

    // 4. Record exception details and set error status
    span.recordException(exception, stackTrace: st);
    span.setStatus(otel.StatusCode.error, exception.toString());
    span.end();
  }

  /// Reads buffered OTLP JSON files from local disk storage and uploads them over HTTP.
  ///
  /// Successfully uploaded files are removed from storage. If a request fails,
  /// execution halts to preserve remaining files for the next network cycle.
  static Future<void> flushQueue() async {
    if (_isFlushing) return;
    _isFlushing = true;

    try {
      final storageDir = await _getStorageDir();
      final queueDir = Directory('${storageDir.path}/otel_queue');
      if (!queueDir.existsSync()) {
        _isFlushing = false;
        return;
      }

      final files = queueDir.listSync().whereType<File>().toList();
      if (files.isEmpty) {
        _isFlushing = false;
        return;
      }

      for (final file in files) {
        final content = await file.readAsString();

        final response = await client.post(
          _otlpEndpoint,
          headers: {'Content-Type': 'application/json', ..._headers},
          body: content,
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await file.delete();
        } else {
          await file.delete();
          break;
        }
      }
    } catch (_) {
      // Offline state
    } finally {
      _isFlushing = false;
    }
  }

  static Map<String, String> _parseHeaders(String headerString) {
    if (headerString.trim().isEmpty) return {};
    final map = <String, String>{};
    final pairs = headerString.split(',');

    for (final pair in pairs) {
      final equalsIndex = pair.indexOf('=');
      if (equalsIndex != -1) {
        final key = pair.substring(0, equalsIndex).trim();
        final value = pair.substring(equalsIndex + 1).trim();

        if (key.isNotEmpty && value.isNotEmpty) {
          map[key] = value;
        }
      }
    }
    return map;
  }
}
