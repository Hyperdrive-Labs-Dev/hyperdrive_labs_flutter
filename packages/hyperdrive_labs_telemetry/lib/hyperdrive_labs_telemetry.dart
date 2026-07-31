import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';
import 'package:hyperdrive_labs_telemetry/src/build_device_resource.dart';
import 'package:hyperdrive_labs_telemetry/src/disk_queue_log_exporter.dart';
import 'package:hyperdrive_labs_telemetry/src/disk_queue_span_exporter.dart';
import 'package:hyperdrive_labs_telemetry/src/otel_logging_handler.dart';
import 'package:hyperdrive_labs_telemetry/src/otel_signal_type.dart';
import 'package:logging/logging.dart' as log;
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

  /// Maximum times a file can fail before being moved to the Dead-Letter Queue.
  static const int _maxRetries = 3;

  static Future<Directory> _getStorageDir() async {
    if (testDirectoryPath != null) {
      return Directory(testDirectoryPath!);
    }
    return await getApplicationDocumentsDirectory();
  }

  /// Initializes the offline-first OpenTelemetry SDK pipeline.
  ///
  /// Connects global error handlers, starts a background flush timer set to [flushInterval],
  /// configures log severity thresholds via [logLevel], attaches app lifecycle observers,
  /// and executes [runAppCallback].
  ///
  /// Parameters default to `--dart-define` environment variables:
  /// - [otlpEndpoint]: Fallback `--dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=...`
  /// - [headers]: Fallback `--dart-define=OTEL_EXPORTER_OTLP_HEADERS=...`
  /// - [serviceName]: Fallback `--dart-define=OTEL_SERVICE_NAME=...`
  /// - [logLevel]: Minimum severity for OTLP log export (Default: [log.Level.INFO]). Fallback `--dart-define=OTEL_LOG_LEVEL=...`
  /// - [flushInterval]: Periodic auto-flush interval (Default: 10 seconds).
  static Future<void> init({
    Uri? otlpEndpoint,
    Map<String, String>? headers,
    String? serviceName,
    log.Level? logLevel,
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

    final resolvedLogLevel = logLevel ?? _parseLogLevel(_envLogLevel);

    final storageDir = await _getStorageDir();
    final queueDir = Directory('${storageDir.path}/otel_queue');

    final deviceResource = await buildDeviceResource(resolvedServiceName);

    final spanExporter = DiskQueueSpanExporter(queueDir: queueDir);
    final processor = otel_sdk.SimpleSpanProcessor(spanExporter);

    otel.registerGlobalTracerProvider(
      otel_sdk.TracerProviderBase(
        processors: [processor],
        resource: deviceResource,
      ),
    );

    final logExporter = DiskQueueLogExporter(
      queueDir: queueDir,
      resourceAttributes: deviceResource.attributes.keys
          .fold<Map<String, String>>({}, (map, key) {
            map[key] = deviceResource.attributes.get(key).toString();
            return map;
          }),
    );

    // Ensure package:logging captures all events globally
    log.Logger.root.level = log.Level.ALL;
    // Attach handler using configured minimum log level
    OtelLoggingHandler(logExporter, minLevel: resolvedLogLevel).attach();

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

      // Filter out .retry sidecar files and dead_letter folder items
      final files = queueDir
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.retry'))
          .toList();

      if (files.isEmpty) {
        _isFlushing = false;
        return;
      }

      // Sort files sequentially so older logs/traces are delivered first
      files.sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        final fileName = file.uri.pathSegments.last;

        // Determine the correct signal endpoint based on filename prefix
        OtelSignalType? signal;
        if (fileName.startsWith('trace_')) {
          signal = OtelSignalType.traces;
        } else if (fileName.startsWith('log_')) {
          signal = OtelSignalType.logs;
        } else if (fileName.startsWith('metric_')) {
          signal = OtelSignalType.metrics;
        }

        // Unrecognized filename prefix -> Poisoned file -> Move to DLQ immediately
        if (signal == null) {
          await _moveToDeadLetterQueue(file, queueDir);
          continue;
        }

        // Cleanly append the signal sub-path
        // E.g. '/api/default' + '/v1/logs' -> '/api/default/v1/logs'
        final currentPath = _otlpEndpoint.path.endsWith('/')
            ? _otlpEndpoint.path.substring(0, _otlpEndpoint.path.length - 1)
            : _otlpEndpoint.path;

        final targetEndpoint = _otlpEndpoint.replace(
          path: '$currentPath${signal.path}',
        );

        String content;
        try {
          content = await file.readAsString();
          // Quick validation: verify it's valid non-empty JSON
          final decoded = jsonDecode(content);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Invalid OTLP root object');
          }
        } catch (_) {
          // Unparseable / Corrupted JSON payload -> Move to DLQ immediately
          await _moveToDeadLetterQueue(file, queueDir);
          continue;
        }

        try {
          final response = await client.post(
            targetEndpoint,
            headers: {'Content-Type': 'application/json', ..._headers},
            body: content,
          );

          if (response.statusCode >= 200 && response.statusCode < 300) {
            // Success -> Remove main file & its sidecar counter
            await _clearRetryCount(file);
            await file.delete();
          } else if (response.statusCode >= 400 && response.statusCode < 500) {
            // 4xx Client Error (Bad Request, Malformed Schema, Invalid Auth)
            // The collector rejected the payload structure permanently.
            await _moveToDeadLetterQueue(file, queueDir);
          } else {
            // 5xx Server Error or Rate Limits (429) -> Retriable failure
            final attempts = await _incrementRetryCount(file);
            if (attempts >= _maxRetries) {
              await _moveToDeadLetterQueue(file, queueDir);
            } else {
              // Pause execution so we don't spam a struggling server
              break;
            }
          }
        } catch (_) {
          // Network disconnected / host unreachable -> stop loop until next run
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

  /// Moves a failed/unparseable file into the dead_letter directory
  /// so it stops blocking the active telemetry queue.
  static Future<void> _moveToDeadLetterQueue(
    File file,
    Directory queueDir,
  ) async {
    try {
      final dlqDir = Directory('${queueDir.path}/dead_letter');
      if (!dlqDir.existsSync()) {
        await dlqDir.create(recursive: true);
      }

      final fileName = file.uri.pathSegments.last;
      final targetPath = '${dlqDir.path}/$fileName';

      // Move file to DLQ folder
      await file.rename(targetPath);

      // Clean up sidecar retry counter file if it exists
      final retryFile = File('${file.path}.retry');
      if (retryFile.existsSync()) {
        await retryFile.delete();
      }
    } catch (_) {}
  }

  /// Increments the local retry count for a file using a sidecar `.retry` file.
  /// Returns the updated retry count.
  static Future<int> _incrementRetryCount(File file) async {
    try {
      final retryFile = File('${file.path}.retry');
      int count = 0;

      if (retryFile.existsSync()) {
        final content = await retryFile.readAsString();
        count = int.tryParse(content.trim()) ?? 0;
      }

      count++;
      await retryFile.writeAsString('$count', flush: true);
      return count;
    } catch (_) {
      return 1;
    }
  }

  /// Cleans up the sidecar `.retry` file when a payload succeeds.
  static Future<void> _clearRetryCount(File file) async {
    try {
      final retryFile = File('${file.path}.retry');
      if (retryFile.existsSync()) {
        await retryFile.delete();
      }
    } catch (_) {}
  }

  static const String _envLogLevel = String.fromEnvironment(
    'OTEL_LOG_LEVEL',
    defaultValue: 'INFO',
  );

  static log.Level _parseLogLevel(String levelName) {
    switch (levelName.toUpperCase()) {
      case 'ALL':
        return log.Level.ALL;
      case 'FINEST':
      case 'TRACER':
        return log.Level.FINEST;
      case 'FINER':
        return log.Level.FINER;
      case 'FINE':
      case 'DEBUG':
        return log.Level.FINE;
      case 'CONFIG':
        return log.Level.CONFIG;
      case 'INFO':
        return log.Level.INFO;
      case 'WARNING':
      case 'WARN':
        return log.Level.WARNING;
      case 'SEVERE':
      case 'ERROR':
        return log.Level.SEVERE;
      case 'SHOUT':
        return log.Level.SHOUT;
      case 'OFF':
        return log.Level.OFF;
      default:
        return log.Level.INFO;
    }
  }
}
