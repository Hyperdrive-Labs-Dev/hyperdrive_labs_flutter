import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperdrive_labs_telemetry/src/disk_queue_span_exporter.dart';
import 'package:opentelemetry/api.dart' as otel;
import 'package:opentelemetry/sdk.dart' as otel_sdk;

void main() {
  group('DiskQueueSpanExporter Tests', () {
    late Directory tempDir;
    late DiskQueueSpanExporter exporter;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('otel_queue_test_');
      exporter = DiskQueueSpanExporter(queueDir: tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('does not create file or write when span list is empty', () {
      exporter.export([]);

      final files = tempDir.listSync().whereType<File>().toList();
      expect(files, isEmpty);
    });

    test('exports spans to local disk as OTLP JSON format', () {
      // Create a mock or dummy ReadOnlySpan using Tracer/Processor setup or test doubles.
      // Since ReadOnlySpan is an SDK class, we can spin up a TracerProvider with our exporter
      // and let it generate a real ReadOnlySpan via a dummy trace.

      final resource = otel_sdk.Resource([
        otel.Attribute.fromString('service.name', 'unit_test_service'),
      ]);

      final localExporter = DiskQueueSpanExporter(queueDir: tempDir);
      final processor = otel_sdk.SimpleSpanProcessor(localExporter);

      final tracerProvider = otel_sdk.TracerProviderBase(
        processors: [processor],
        resource: resource,
      );

      final tracer = tracerProvider.getTracer('test_scope');

      // Act: Start and end a span to trigger export
      final span = tracer.startSpan('test_span');
      span.setAttribute(otel.Attribute.fromString('test.attr', 'hello_world'));
      span.setStatus(otel.StatusCode.ok, 'All good');
      span.end();

      // Assert: Verify a json file was written to disk
      final files = tempDir.listSync().whereType<File>().toList();
      expect(files.length, equals(1));

      final jsonContent = files.first.readAsStringSync();
      final Map<String, dynamic> decoded = jsonDecode(jsonContent);

      // Verify OTLP payload structure
      expect(decoded.containsKey('resourceSpans'), isTrue);

      final resourceSpans = decoded['resourceSpans'] as List;
      expect(resourceSpans.isNotEmpty, isTrue);

      final scopeSpans = resourceSpans[0]['scopeSpans'] as List;
      expect(
        scopeSpans[0]['scope']['name'],
        equals('hyperdrive_labs_telemetry'),
      );

      final spans = scopeSpans[0]['spans'] as List;
      expect(spans.length, equals(1));
      expect(spans[0]['name'], equals('test_span'));
      expect(spans[0]['status']['code'], equals(1)); // 1 for OK
      expect(spans[0]['status']['message'], equals(''));

      // Check span attributes
      final spanAttrs = spans[0]['attributes'] as List;
      final foundAttr = spanAttrs.firstWhere(
        (attr) => attr['key'] == 'test.attr',
        orElse: () => null,
      );
      expect(foundAttr, isNotNull);
      expect(foundAttr['value']['stringValue'], equals('hello_world'));
    });
  });
}
