import 'package:dio/dio.dart';
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';
import 'package:opentelemetry/api.dart' as otel;

/// A Dio [Interceptor] that wraps HTTP requests inside OpenTelemetry spans,
/// injects W3C trace context headers, and records network performance using
/// OpenTelemetry Semantic Conventions.
class OTelDioInterceptor extends Interceptor {
  /// Storage key for associating an active OTel span with a Dio request.
  static const String _spanExtraKey = 'otel_http_span';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Default to root context if no active screen context exists
    otel.Context parentContext = otel.Context.root;

    // 1. Link request span to the current screen span if available
    final activeContext = OTelNavigatorObserver.activeScreenContext;
    if (activeContext != null) {
      parentContext = otel.contextWithSpanContext(
        otel.Context.root,
        activeContext,
      );
    }

    // 2. Start HTTP Client span
    final span = HyperdriveLabsTelemetry.tracer.startSpan(
      'HTTP ${options.method.toUpperCase()} ${options.uri.path}',
      context: parentContext,
    );

    // OTel v1.24+ Stable Semantic Conventions
    span.setAttribute(
      otel.Attribute.fromString(
        'http.request.method',
        options.method.toUpperCase(),
      ),
    );
    span.setAttribute(
      otel.Attribute.fromString('url.full', options.uri.toString()),
    );
    span.setAttribute(
      otel.Attribute.fromString('server.address', options.uri.host),
    );
    span.setAttribute(
      otel.Attribute.fromString(
        'screen.name',
        OTelNavigatorObserver.activeScreenName,
      ),
    );

    // 3. Inject valid W3C Trace Context headers (traceparent)
    final spanContext = span.spanContext;
    if (spanContext.isValid) {
      // Use toString() or hex string representation for TraceId and SpanId
      final traceIdStr = spanContext.traceId.toString();
      final spanIdStr = spanContext.spanId.toString();
      final traceFlagsStr = spanContext.traceFlags.toString();

      options.headers['traceparent'] =
          '00-$traceIdStr-$spanIdStr-$traceFlagsStr';
    }

    // 4. Save span in RequestOptions extra map to retrieve in onResponse/onError
    options.extra[_spanExtraKey] = span;

    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final span = response.requestOptions.extra[_spanExtraKey] as otel.Span?;

    if (span != null) {
      span.setAttribute(
        otel.Attribute.fromInt(
          'http.response.status_code',
          response.statusCode ?? 0,
        ),
      );
      span.setStatus(otel.StatusCode.ok);
      span.end();
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final span = err.requestOptions.extra[_spanExtraKey] as otel.Span?;

    if (span != null) {
      if (err.response?.statusCode != null) {
        span.setAttribute(
          otel.Attribute.fromInt(
            'http.response.status_code',
            err.response!.statusCode!,
          ),
        );
      }

      span.recordException(err, stackTrace: err.stackTrace);
      span.setStatus(
        otel.StatusCode.error,
        err.message ?? 'HTTP Request Failed',
      );
      span.end();
    }

    handler.next(err);
  }
}
