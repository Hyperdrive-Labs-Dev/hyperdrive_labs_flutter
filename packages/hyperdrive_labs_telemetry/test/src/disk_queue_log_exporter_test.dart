import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperdrive_labs_telemetry/src/disk_queue_log_exporter.dart';
import 'package:hyperdrive_labs_telemetry/src/otel_log_severity.dart';
import 'package:hyperdrive_labs_telemetry/src/version.dart';

void main() {
  group('DiskQueueLogExporter Tests', () {
    late Directory tempDir;

    setUp(() async {
      // Create a fresh temporary directory before each test
      tempDir = await Directory.systemTemp.createTemp('otel_logs_test_');
    });

    tearDown(() async {
      // Clean up temporary files after each test
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates the queue directory automatically if it does not exist', () {
      final nonExistentDir = Directory('${tempDir.path}/nested/queue');
      final exporter = DiskQueueLogExporter(queueDir: nonExistentDir);

      expect(nonExistentDir.existsSync(), isFalse);

      exporter.exportLog(message: 'Test message');

      expect(nonExistentDir.existsSync(), isTrue);
    });

    test(
      'writes a valid OTLP JSON log file to disk with default parameters',
      () {
        final exporter = DiskQueueLogExporter(
          queueDir: tempDir,
          resourceAttributes: {'service.name': 'test_service'},
        );

        exporter.exportLog(message: 'Hello World');

        final files = tempDir.listSync().whereType<File>().toList();
        expect(files.length, equals(1));

        final logFile = files.first;
        expect(logFile.path.contains('log_'), isTrue);
        expect(logFile.path.endsWith('.json'), isTrue);

        final content =
            jsonDecode(logFile.readAsStringSync()) as Map<String, dynamic>;

        // Validate OTLP JSON structure
        final resourceLogs = content['resourceLogs'] as List;
        expect(resourceLogs.length, equals(1));

        final resource = resourceLogs.first['resource'];
        final resourceAttrs = resource['attributes'] as List;
        expect(
          resourceAttrs,
          contains(
            equals({
              'key': 'service.name',
              'value': {'stringValue': 'test_service'},
            }),
          ),
        );

        final scopeLogs = resourceLogs.first['scopeLogs'] as List;
        final scope = scopeLogs.first['scope'];
        expect(scope['name'], equals('hyperdrive_labs_telemetry'));
        expect(scope['version'], equals(packageVersion));

        final logRecords = scopeLogs.first['logRecords'] as List;
        final record = logRecords.first as Map<String, dynamic>;

        expect(record['body'], equals({'stringValue': 'Hello World'}));
        expect(record['severityNumber'], equals(OtelLogSeverity.info.number));
        expect(record['severityText'], equals(OtelLogSeverity.info.text));
        expect(record['timeUnixNano'], isNotEmpty);
      },
    );

    test(
      'correctly attaches severity, traceId, spanId, and custom attributes',
      () {
        final exporter = DiskQueueLogExporter(queueDir: tempDir);

        exporter.exportLog(
          message: 'Database query failed',
          severity: OtelLogSeverity.error,
          traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
          spanId: '00f067aa0ba902b7',
          attributes: {'db.system': 'postgresql', 'error.code': 500},
        );

        final file = tempDir.listSync().whereType<File>().first;
        final content =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

        final record =
            (content['resourceLogs'][0]['scopeLogs'][0]['logRecords'] as List)
                .first;

        expect(record['severityNumber'], equals(OtelLogSeverity.error.number));
        expect(record['severityText'], equals(OtelLogSeverity.error.text));
        expect(record['traceId'], equals('4bf92f3577b34da6a3ce929d0e0e4736'));
        expect(record['spanId'], equals('00f067aa0ba902b7'));

        final attributes = record['attributes'] as List;
        expect(
          attributes,
          containsAll([
            {
              'key': 'db.system',
              'value': {'stringValue': 'postgresql'},
            },
            {
              'key': 'error.code',
              'value': {'stringValue': '500'},
            },
          ]),
        );
      },
    );

    test(
      'generates multiple unique log files for subsequent exports',
      () async {
        final exporter = DiskQueueLogExporter(queueDir: tempDir);

        exporter.exportLog(message: 'First log');
        // Delay slightly so DateTime.now().microsecondsSinceEpoch increments
        await Future<void>.delayed(const Duration(milliseconds: 2));
        exporter.exportLog(message: 'Second log');

        final files = tempDir.listSync().whereType<File>().toList();
        expect(files.length, equals(2));
      },
    );

    test('swallows write/FS exceptions silently without throwing', () {
      // Use a file path as directory path to trigger a FileSystemException on write
      final invalidDir = File('${tempDir.path}/file_instead_of_dir');
      invalidDir.writeAsStringSync('blocker');

      final exporter = DiskQueueLogExporter(
        queueDir: Directory(invalidDir.path),
      );

      // Should complete without throwing an exception
      expect(
        () => exporter.exportLog(message: 'This should fail silently'),
        returnsNormally,
      );
    });
  });
}
