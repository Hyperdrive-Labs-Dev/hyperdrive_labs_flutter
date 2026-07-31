/// Represents standard OpenTelemetry log severity levels and their corresponding
/// OTLP numerical severity numbers and string representations.
///
/// Maps directly to the official OpenTelemetry logs data model specifications
/// (e.g., DEBUG = 5, INFO = 9, WARN = 13, ERROR = 17).
enum OtelLogSeverity {
  /// Fine-grained informational messages used primarily for debugging.
  debug(5, 'DEBUG'),

  /// General operational information messages highlighting standard application flow.
  info(9, 'INFO'),

  /// Warnings indicating potential issues or degraded performance that do not stop execution.
  warn(13, 'WARN'),

  /// Errors or failure conditions that require attention or indicate operational issues.
  error(17, 'ERROR');

  /// The official OTLP numerical severity value associated with this level.
  final int number;

  /// The standard human-readable OTLP string representation of the severity level.
  final String text;

  /// Creates an [OtelLogSeverity] instance with its corresponding OTLP [number] and [text].
  const OtelLogSeverity(this.number, this.text);
}
