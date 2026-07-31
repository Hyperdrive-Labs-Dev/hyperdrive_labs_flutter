import 'package:flutter_test/flutter_test.dart';
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';
import 'package:hyperdrive_labs_telemetry/src/disk_queue_log_exporter.dart';
import 'package:hyperdrive_labs_telemetry/src/otel_log_severity.dart';
import 'package:hyperdrive_labs_telemetry/src/otel_logging_handler.dart';
import 'package:logging/logging.dart' as log;
import 'package:mocktail/mocktail.dart';
import 'package:opentelemetry/api.dart' as otel;

class MockDiskQueueLogExporter extends Mock implements DiskQueueLogExporter {}

void main() {
  group('OtelLoggingHandler Tests', () {
    late MockDiskQueueLogExporter mockExporter;
    late OtelLoggingHandler handler;
    late log.Logger logger;

    setUpAll(() {
      registerFallbackValue(OtelLogSeverity.info);
    });

    setUp(() {
      mockExporter = MockDiskQueueLogExporter();
      logger = log.Logger('TestLogger');
      log.Logger.root.level = log.Level.ALL;

      when(
        () => mockExporter.exportLog(
          message: any(named: 'message'),
          severity: any(named: 'severity'),
          traceId: any(named: 'traceId'),
          spanId: any(named: 'spanId'),
          attributes: any(named: 'attributes'),
        ),
      ).thenReturn(null);
    });

    tearDown(() {
      log.Logger.root.clearListeners();
      OTelNavigatorObserver.activeScreenContext = null;
    });

    test('captures log records and forwards them to exporter', () async {
      handler = OtelLoggingHandler(mockExporter, minLevel: log.Level.INFO);
      handler.attach();

      logger.info('User logged in successfully');
      await Future<void>.delayed(Duration.zero);

      verify(
        () => mockExporter.exportLog(
          message: 'User logged in successfully',
          severity: OtelLogSeverity.info,
          traceId: any(named: 'traceId'),
          spanId: any(named: 'spanId'),
          attributes: {'logger.name': 'TestLogger'},
        ),
      ).called(1);
    });

    test('filters out log records strictly below minLevel', () async {
      handler = OtelLoggingHandler(mockExporter, minLevel: log.Level.WARNING);
      handler.attach();

      logger.fine('Debug message - ignored');
      logger.warning('Warning message - exported');
      await Future<void>.delayed(Duration.zero);

      verify(
        () => mockExporter.exportLog(
          message: 'Warning message - exported',
          severity: OtelLogSeverity.warn,
          traceId: any(named: 'traceId'),
          spanId: any(named: 'spanId'),
          attributes: any(named: 'attributes'),
        ),
      ).called(1);
    });

    test('correctly maps package:logging levels to OtelLogSeverity', () async {
      handler = OtelLoggingHandler(mockExporter, minLevel: log.Level.ALL);
      handler.attach();

      logger.severe('Fatal error');
      await Future<void>.delayed(Duration.zero);

      verify(
        () => mockExporter.exportLog(
          message: 'Fatal error',
          severity: OtelLogSeverity.error,
          traceId: any(named: 'traceId'),
          spanId: any(named: 'spanId'),
          attributes: any(named: 'attributes'),
        ),
      ).called(1);
    });

    test(
      'attaches error object and stackTrace to log attributes when present',
      () async {
        handler = OtelLoggingHandler(mockExporter, minLevel: log.Level.INFO);
        handler.attach();

        final testException = Exception('Timeout');
        final testStackTrace = StackTrace.current;

        logger.severe('Failed', testException, testStackTrace);
        await Future<void>.delayed(Duration.zero);

        verify(
          () => mockExporter.exportLog(
            message: 'Failed',
            severity: OtelLogSeverity.error,
            traceId: any(named: 'traceId'),
            spanId: any(named: 'spanId'),
            attributes: {
              'logger.name': 'TestLogger',
              'error.object': testException.toString(),
              'error.stacktrace': testStackTrace.toString(),
            },
          ),
        ).called(1);
      },
    );

    test(
      'extracts traceId and spanId from OTelNavigatorObserver.activeScreenContext',
      () async {
        handler = OtelLoggingHandler(mockExporter, minLevel: log.Level.INFO);
        handler.attach();

        // 32-hex-char trace ID and 16-hex-char span ID strings
        final fakeTraceId = otel.TraceId.fromString(
          '4bf92f3577b34da6a3ce929d0e0e4736',
        );
        final fakeSpanId = otel.SpanId.fromString('00f067aa0ba902b7');

        // Assign a valid SpanContext directly
        OTelNavigatorObserver.activeScreenContext = otel.SpanContext(
          fakeTraceId,
          fakeSpanId,
          otel.TraceFlags.sampled,
          otel.TraceState.empty(),
        );

        logger.info('Screen log');
        await Future<void>.delayed(Duration.zero);

        verify(
          () => mockExporter.exportLog(
            message: 'Screen log',
            severity: OtelLogSeverity.info,
            traceId: fakeTraceId.toString(),
            spanId: fakeSpanId.toString(),
            attributes: any(named: 'attributes'),
          ),
        ).called(1);
      },
    );
  });
}
