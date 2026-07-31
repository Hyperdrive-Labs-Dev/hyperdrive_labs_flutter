/// Represents the supported OpenTelemetry (OTLP) signal types and their
/// corresponding API endpoint paths over HTTP.
///
/// Used by exporters to route telemetry data payloads to the correct
/// collector endpoint (`/v1/traces`, `/v1/logs`, or `/v1/metrics`).
enum OtelSignalType {
  /// Distributed tracing telemetry data sent to the OTLP `/v1/traces` endpoint.
  traces('/v1/traces'),

  /// Event log telemetry data sent to the OTLP `/v1/logs` endpoint.
  logs('/v1/logs'),

  /// Numerical measurement and metric telemetry data sent to the OTLP `/v1/metrics` endpoint.
  metrics('/v1/metrics');

  /// The HTTP URL path extension for this OTLP signal type.
  final String path;

  /// Creates an [OtelSignalType] associated with its OTLP endpoint [path].
  const OtelSignalType(this.path);
}
