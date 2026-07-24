import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';
import 'package:opentelemetry/api.dart' as otel;
import 'package:opentelemetry/sdk.dart' as otel_sdk;
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HyperdriveLabsTelemetry Tests', () {
    late Directory tempDir;
    late Directory queueDir;
    late List<otel_sdk.ReadOnlySpan> exportedSpans;

    setUpAll(() async {
      PackageInfo.setMockInitialValues(
        appName: 'Test App',
        packageName: 'com.test.app',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
        installerStore: '',
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/device_info'),
            (MethodCall methodCall) async {
              return {
                'version': {'release': '14', 'sdkInt': 34},
                'id': 'test_id',
                'model': 'Test Model',
                'manufacturer': 'Google',
                'isPhysicalDevice': true,
              };
            },
          );

      tempDir = Directory.systemTemp.createTempSync('telemetry_coverage_');
      queueDir = Directory('${tempDir.path}/otel_queue');
      HyperdriveLabsTelemetry.testDirectoryPath = tempDir.path;

      exportedSpans = [];
      final exporter = _TestSpanExporter(exportedSpans);
      final processor = otel_sdk.SimpleSpanProcessor(exporter);
      final tracerProvider = otel_sdk.TracerProviderBase(
        processors: [processor],
      );

      // Assign tracer and initialize once globally for the test suite
      HyperdriveLabsTelemetry.tracer = tracerProvider.getTracer('test_tracer');

      await HyperdriveLabsTelemetry.init(
        otlpEndpoint: Uri.parse('https://api.test.com'),
        runAppCallback: () {},
      );
    });

    setUp(() {
      exportedSpans.clear();
      HyperdriveLabsTelemetry.client = MockClient((request) async {
        return http.Response('{}', 200);
      });
      OTelNavigatorObserver.activeScreenContext = null;
      OTelNavigatorObserver.activeScreenName = 'unknown_screen';
    });

    tearDownAll(() {
      HyperdriveLabsTelemetry.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('init throws if OTLP endpoint is completely missing', () async {
      expect(
        () => HyperdriveLabsTelemetry.init(
          otlpEndpoint: null,
          runAppCallback: () {},
        ),
        throwsArgumentError,
      );
    });

    test('FlutterError.onError is intercepted and recorded', () {
      final originalFlutterError = FlutterError.onError;

      FlutterError.onError = (details) {
        HyperdriveLabsTelemetry.recordException(
          exception: details.exception,
          stackTrace: details.stack,
          reason: details.context?.toString() ?? 'Flutter Framework Error',
        );
      };

      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('Flutter widget exploded'),
          stack: StackTrace.fromString('flutter_stack_1'),
          context: ErrorDescription('During build'),
        ),
      );

      expect(exportedSpans.length, equals(1));
      expect(exportedSpans.first.name, equals('Error: During build'));
      expect(
        exportedSpans.first.status.description,
        equals('Bad state: Flutter widget exploded'),
      );

      FlutterError.onError = originalFlutterError;
    });

    test('PlatformDispatcher.instance.onError is intercepted and recorded', () {
      PlatformDispatcher.instance.onError = (error, stack) {
        HyperdriveLabsTelemetry.recordException(
          exception: error,
          stackTrace: stack,
          reason: 'Unhandled Platform Exception',
        );
        return true;
      };

      PlatformDispatcher.instance.onError!(
        Exception('Platform channel failed'),
        StackTrace.fromString('platform_stack_1'),
      );

      expect(exportedSpans.length, equals(1));
      expect(
        exportedSpans.first.name,
        equals('Error: Unhandled Platform Exception'),
      );
    });

    test('recordException links to active screen context when available', () {
      OTelNavigatorObserver.activeScreenContext = otel.SpanContext(
        otel.TraceId.fromString('0102030405060708090a0b0c0d0e0f10'),
        otel.SpanId.fromString('0102030405060708'),
        otel.TraceFlags.sampled,
        otel.TraceState.empty(),
      );
      OTelNavigatorObserver.activeScreenName = 'DashboardScreen';

      HyperdriveLabsTelemetry.recordException(
        exception: ArgumentError('Invalid input'),
        reason: 'User action failed',
      );

      expect(exportedSpans.length, equals(1));
      final span = exportedSpans.first;
      expect(span.parentSpanId.toString(), equals('0102030405060708'));

      final attrs = _spanAttributesToMap(span);
      expect(attrs['screen.name'], equals('DashboardScreen'));
    });

    test(
      'flushQueue aborts safely if queue directory does not exist',
      () async {
        if (queueDir.existsSync()) queueDir.deleteSync(recursive: true);

        await HyperdriveLabsTelemetry.flushQueue();
        expect(queueDir.existsSync(), isFalse);
      },
    );

    test('flushQueue aborts safely if queue directory is empty', () async {
      queueDir.createSync(recursive: true);

      await HyperdriveLabsTelemetry.flushQueue();
      expect(queueDir.listSync(), isEmpty);
    });

    test(
      'flushQueue recovers from network exceptions (offline mode)',
      () async {
        queueDir.createSync(recursive: true);
        final file = File('${queueDir.path}/trace_offline.json')
          ..writeAsStringSync('{"data":1}');

        HyperdriveLabsTelemetry.client = MockClient((request) async {
          throw const SocketException('No Internet Connection');
        });

        await HyperdriveLabsTelemetry.flushQueue();

        expect(file.existsSync(), isTrue);
      },
    );

    test(
      'didChangeAppLifecycleState triggers flush strictly on hidden/paused',
      () async {
        int requestCount = 0;
        HyperdriveLabsTelemetry.client = MockClient((request) async {
          requestCount++;
          return http.Response('ok', 200);
        });

        // Clear directory completely and create only 1 test file
        if (queueDir.existsSync()) queueDir.deleteSync(recursive: true);
        queueDir.createSync(recursive: true);
        File('${queueDir.path}/trace_1.json').writeAsStringSync('{"data":1}');

        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        expect(requestCount, equals(0));

        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        expect(requestCount, equals(1));
      },
    );
  });
}

Map<String, dynamic> _spanAttributesToMap(otel_sdk.ReadOnlySpan span) {
  final map = <String, dynamic>{};
  for (final key in span.attributes.keys) {
    map[key] = span.attributes.get(key);
  }
  return map;
}

class _TestSpanExporter implements otel_sdk.SpanExporter {
  final List<otel_sdk.ReadOnlySpan> spanList;

  _TestSpanExporter(this.spanList);

  @override
  void export(List<otel_sdk.ReadOnlySpan> spans) {
    spanList.addAll(spans);
  }

  @override
  void shutdown() {}

  @override
  void forceFlush() {}
}
