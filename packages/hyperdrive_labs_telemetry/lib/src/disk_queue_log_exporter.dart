import 'dart:convert';
import 'dart:io';

import 'package:hyperdrive_labs_telemetry/src/otel_log_severity.dart';
import 'package:hyperdrive_labs_telemetry/src/version.dart';

/// An offline-first log exporter that formats logs as OTLP JSON
/// and writes them to local disk storage for later flushing to `/v1/logs`.
class DiskQueueLogExporter {
  /// The local directory where queued OTLP log payloads are saved as JSON.
  final Directory queueDir;

  /// Global resource attributes attached to exported logs (e.g., service.name).
  final Map<String, String> resourceAttributes;

  /// Creates a new [DiskQueueLogExporter] targeting the specified [queueDir].
  DiskQueueLogExporter({
    required this.queueDir,
    this.resourceAttributes = const {},
  });

  /// Formats a log record as OTLP JSON and queues it to disk.
  void exportLog({
    required String message,
    OtelLogSeverity severity = OtelLogSeverity.info,
    String? traceId,
    String? spanId,
    Map<String, dynamic>? attributes,
  }) {
    try {
      if (!queueDir.existsSync()) queueDir.createSync(recursive: true);

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      // Use 'log_' prefix to distinguish from 'trace_' files in the same directory
      final file = File('${queueDir.path}/log_$timestamp.json');

      final otlpPayload = {
        'resourceLogs': [
          {
            'resource': {
              'attributes': resourceAttributes.entries.map((e) {
                return {
                  'key': e.key,
                  'value': {'stringValue': e.value},
                };
              }).toList(),
            },
            'scopeLogs': [
              {
                'scope': {
                  'name': 'hyperdrive_labs_telemetry',
                  'version': packageVersion,
                },
                'logRecords': [
                  {
                    'timeUnixNano':
                        '${DateTime.now().microsecondsSinceEpoch * 1000}',
                    'severityNumber': severity.number,
                    'severityText': severity.text,
                    'body': {'stringValue': message},
                    'traceId': ?traceId,
                    'spanId': ?spanId,
                    if (attributes != null)
                      'attributes': attributes.entries.map((e) {
                        return {
                          'key': e.key,
                          'value': {'stringValue': e.value.toString()},
                        };
                      }).toList(),
                  },
                ],
              },
            ],
          },
        ],
      };

      file.writeAsStringSync(jsonEncode(otlpPayload), flush: true);
    } catch (_) {}
  }
}
