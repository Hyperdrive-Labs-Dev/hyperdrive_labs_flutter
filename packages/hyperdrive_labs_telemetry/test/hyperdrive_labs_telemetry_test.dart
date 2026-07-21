import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final testEndpoint = Uri.parse('https://uptrace.test/v1/logs');
  final testHeaders = {'uptrace-dsn': 'https://token@uptrace.test/1'};

  setUp(() async {
    // Create an isolated temp directory for each test run
    tempDir = await Directory.systemTemp.createTemp('otel_test_');
    HyperdriveLabsTelemetry.testDirectoryPath = tempDir.path;
  });

  tearDown(() async {
    // Clean up temporary files
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'Queues exception locally when offline or server returns error',
    () async {
      // Mock HTTP client returning 500 Internal Server Error
      HyperdriveLabsTelemetry.client = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      await HyperdriveLabsTelemetry.init(
        otlpEndpoint: testEndpoint,
        headers: testHeaders,
        serviceName: 'test_service',
        runAppCallback: () {},
      );

      // Act: Queue a crash
      await HyperdriveLabsTelemetry.queueCrashLocally(
        serviceName: 'test_service',
        exception: 'StateError: Bad state',
        stackTrace: '#0 main (main.dart:10)',
      );

      // Assert: File should remain stored in local queue
      final queueDir = Directory('${tempDir.path}/otel_queue');
      expect(queueDir.existsSync(), isTrue);

      final queuedFiles = queueDir.listSync().whereType<File>().toList();
      expect(queuedFiles.length, equals(1));

      // Verify file content matches OTLP format
      final content = jsonDecode(await queuedFiles.first.readAsString());
      final logRecord =
          content['resourceLogs'][0]['scopeLogs'][0]['logRecords'][0];

      expect(
        logRecord['body']['stringValue'],
        contains('StateError: Bad state'),
      );
    },
  );

  test(
    'Flushes queue and deletes local files on successful HTTP 200 upload',
    () async {
      late Map<String, String> sentHeaders;
      late String sentBody;

      // Mock HTTP client returning 200 OK
      HyperdriveLabsTelemetry.client = MockClient((request) async {
        sentHeaders = request.headers;
        sentBody = request.body;
        return http.Response('{"status":"success"}', 200);
      });

      await HyperdriveLabsTelemetry.init(
        otlpEndpoint: testEndpoint,
        headers: testHeaders,
        serviceName: 'test_service',
        runAppCallback: () {},
      );

      // Act: Queue crash
      await HyperdriveLabsTelemetry.queueCrashLocally(
        serviceName: 'test_service',
        exception: 'FormatException: Invalid JSON',
        stackTrace: '#0 parseJson (parser.dart:42)',
      );

      // Assert: Local queue file should be deleted after successful sync
      final queueDir = Directory('${tempDir.path}/otel_queue');
      final remainingFiles = queueDir.listSync().whereType<File>().toList();
      expect(remainingFiles.isEmpty, isTrue);

      // Assert: Headers and OTLP payload payload were sent correctly
      expect(
        sentHeaders['uptrace-dsn'],
        equals('https://token@uptrace.test/1'),
      );
      expect(sentHeaders['Content-Type'], equals('application/json'));

      final payload = jsonDecode(sentBody);
      expect(payload['resourceLogs'], isNotEmpty);
    },
  );

  test('Validates complete OTLP JSON LogRecord schema compliance', () async {
    late Map<String, dynamic> payload;

    // Mock client intercepting the outbound request body
    HyperdriveLabsTelemetry.client = MockClient((request) async {
      payload = jsonDecode(request.body);
      return http.Response('{"status":"success"}', 200);
    });

    await HyperdriveLabsTelemetry.init(
      otlpEndpoint: testEndpoint,
      headers: testHeaders,
      serviceName: 'my_flutter_app',
      runAppCallback: () {},
    );

    // Act: Queue a sample crash
    await HyperdriveLabsTelemetry.queueCrashLocally(
      serviceName: 'my_flutter_app',
      exception: 'FormatException: Bad character',
      stackTrace: '#0 main (main.dart:15)',
    );

    // --- Explicit OTLP Schema Assertions ---

    // 1. Top-level resourceLogs array
    expect(payload, contains('resourceLogs'));
    final resourceLogs = payload['resourceLogs'] as List;
    expect(resourceLogs, isNotEmpty);

    // 2. Resource & Attributes
    final resource = resourceLogs[0]['resource'];
    final attributes = resource['attributes'] as List;
    final serviceNameAttr = attributes.firstWhere(
      (attr) => attr['key'] == 'service.name',
    );
    expect(serviceNameAttr['value']['stringValue'], equals('my_flutter_app'));

    // 3. Scope Logs
    final scopeLogs = resourceLogs[0]['scopeLogs'] as List;
    expect(scopeLogs, isNotEmpty);

    // 4. Log Records
    final logRecords = scopeLogs[0]['logRecords'] as List;
    final record = logRecords[0];

    // OTLP LogRecord mandatory fields
    expect(record['severityText'], equals('ERROR'));
    expect(record['severityNumber'], equals(17)); // 17 = ERROR in OTel spec
    expect(record['timeUnixNano'], isA<String>()); // Nanoseconds string
    expect(
      record['body']['stringValue'],
      equals('FormatException: Bad character'),
    );

    // 5. StackTrace Attribute
    final recordAttrs = record['attributes'] as List;
    final stackTraceAttr = recordAttrs.firstWhere(
      (attr) => attr['key'] == 'exception.stacktrace',
    );
    expect(
      stackTraceAttr['value']['stringValue'],
      equals('#0 main (main.dart:15)'),
    );
  });
}
