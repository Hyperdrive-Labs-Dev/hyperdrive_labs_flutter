import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';
import 'package:opentelemetry/api.dart' as otel;
import 'package:opentelemetry/sdk.dart' as otel_sdk;

void main() {
  group('OTelDioInterceptor Tests', () {
    late Dio dio;
    late OTelDioInterceptor interceptor;
    late List<otel_sdk.ReadOnlySpan> exportedSpans;

    setUp(() {
      exportedSpans = [];

      // Setup a custom TracerProvider with a local capturing span exporter
      final exporter = _TestSpanExporter(exportedSpans);
      final processor = otel_sdk.SimpleSpanProcessor(exporter);
      final tracerProvider = otel_sdk.TracerProviderBase(
        processors: [processor],
      );

      // Initialize global tracer for the telemetry class
      HyperdriveLabsTelemetry.tracer = tracerProvider.getTracer('test_tracer');

      dio = Dio(BaseOptions(baseUrl: 'https://api.hyperdrivelabs.com'));
      interceptor = OTelDioInterceptor();
      dio.interceptors.add(interceptor);
    });

    test(
      'injects W3C traceparent header and records HTTP span on success',
      () async {
        final adapter = _MockAdapter((options) async {
          // Verify W3C header injection happened on the outgoing request
          expect(options.headers.containsKey('traceparent'), isTrue);
          expect(
            options.headers['traceparent'],
            matches(RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]+$')),
          );

          return ResponseBody.fromString(
            '{"status":"ok"}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        dio.httpClientAdapter = adapter;

        final response = await dio.get('/test-endpoint');

        expect(response.statusCode, equals(200));

        // Verify the span was properly exported and closed
        expect(exportedSpans.length, equals(1));
        final span = exportedSpans.first;
        expect(span.name, equals('HTTP GET /test-endpoint'));
        expect(span.status.code, equals(otel.StatusCode.ok));
      },
    );

    test('records exception and error status on DioException', () async {
      final adapter = _MockAdapter((options) async {
        throw DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 500),
          message: 'Internal Server Error',
          type: DioExceptionType.badResponse,
        );
      });

      dio.httpClientAdapter = adapter;

      // Use catchError or runZoned/try-catch on dio.get to capture the interceptor flow execution
      try {
        await dio.get('/error-endpoint');
      } catch (_) {
        // DioException caught from interceptor chain propagation
      }

      // Verify the error span was exported with error status
      expect(exportedSpans.length, equals(1));
      final span = exportedSpans.first;
      expect(span.name, equals('HTTP GET /error-endpoint'));
      expect(span.status.code, equals(otel.StatusCode.error));
    });
  });
}

/// A mock [HttpClientAdapter] used to intercept and test Dio requests without network calls.
class _MockAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _MockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return await handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// A simple test span exporter that collects exported spans into a list.
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
