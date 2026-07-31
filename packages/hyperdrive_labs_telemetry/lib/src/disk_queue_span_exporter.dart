import 'dart:convert';
import 'dart:io';
import 'package:hyperdrive_labs_telemetry/src/version.dart';
import 'package:opentelemetry/api.dart' as otel;
import 'package:opentelemetry/sdk.dart' as otel_sdk;

/// An offline-first OpenTelemetry [otel_sdk.SpanExporter] that intercepts
/// completed trace spans and writes them to local disk storage as OTLP JSON.
class DiskQueueSpanExporter implements otel_sdk.SpanExporter {
  /// The local directory where exported OTLP span payloads are queued as JSON.
  final Directory queueDir;

  /// Creates a new [DiskQueueSpanExporter] targeting the specified [queueDir].
  DiskQueueSpanExporter({required this.queueDir});

  @override
  void export(List<otel_sdk.ReadOnlySpan> spans) {
    if (spans.isEmpty) return;

    try {
      if (!queueDir.existsSync()) queueDir.createSync(recursive: true);

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final file = File('${queueDir.path}/trace_$timestamp.json');

      final resourceAttributes = spans.first.resource.attributes;

      final otlpPayload = {
        'resourceSpans': [
          {
            'resource': {
              'attributes': resourceAttributes.keys.map((key) {
                return {
                  'key': key,
                  'value': {
                    'stringValue': resourceAttributes.get(key).toString(),
                  },
                };
              }).toList(),
            },
            'scopeSpans': [
              {
                'scope': {
                  'name': 'hyperdrive_labs_telemetry',
                  'version': packageVersion,
                },
                'spans': spans.map(_spanToOtlpJson).toList(),
              },
            ],
          },
        ],
      };

      file.writeAsStringSync(jsonEncode(otlpPayload), flush: true);
    } catch (_) {}
  }

  Map<String, dynamic> _spanToOtlpJson(otel_sdk.ReadOnlySpan span) {
    // Map OTel StatusCode enum to OTLP JSON spec integer values 0 = UNSET, 1 = OK, 2 = ERROR
    int statusCode = 0;

    if (span.status.code == otel.StatusCode.ok) {
      statusCode = 1;
    } else if (span.status.code == otel.StatusCode.error) {
      statusCode = 2;
    }

    return {
      'traceId': span.spanContext.traceId.toString(),
      'spanId': span.spanContext.spanId.toString(),
      'parentSpanId': span.parentSpanId.toString(),
      'name': span.name,
      'kind': 1, // SPAN_KIND_INTERNAL (must be int)
      'startTimeUnixNano': span.startTime.toString(),
      'endTimeUnixNano': span.endTime.toString(),
      'attributes': span.attributes.keys.map((key) {
        return {
          'key': key,
          'value': {'stringValue': span.attributes.get(key).toString()},
        };
      }).toList(),
      'status': {
        'code': statusCode, // MUST be an integer: 0, 1, or 2
        'message': span.status.description,
      },
    };
  }

  @override
  void shutdown() {}

  @override
  void forceFlush() {}
}
