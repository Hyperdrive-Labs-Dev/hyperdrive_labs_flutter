import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';
import 'package:hyperdrive_labs_telemetry/src/disk_queue_log_exporter.dart';
import 'package:hyperdrive_labs_telemetry/src/otel_log_severity.dart';
import 'package:logging/logging.dart' as log;
import 'package:opentelemetry/api.dart' as otel;

/// Intercepts log records from [log.Logger.root.onRecord], filters them based on
/// [minLevel], enriches them with active OpenTelemetry trace and span contexts,
/// and forwards them to a [DiskQueueLogExporter] as OTLP-compliant log payloads.
class OtelLoggingHandler {
  final DiskQueueLogExporter _exporter;

  /// The minimum severity threshold required for a log record to be exported.
  ///
  /// Any log record with a [log.Level] strictly below [minLevel] will be
  /// ignored by this handler, keeping disk storage and bandwidth consumption low.
  final log.Level minLevel;

  /// Creates an [OtelLoggingHandler] that forwards processed log records to [_exporter].
  ///
  /// Filters out any record with a severity lower than [minLevel] (defaults to [log.Level.INFO]).
  OtelLoggingHandler(this._exporter, {this.minLevel = log.Level.INFO});

  /// Attaches a listener to [log.Logger.root.onRecord] to automatically capture,
  /// filter, enrich, and queue application log records.
  void attach() {
    log.Logger.root.onRecord.listen((record) {
      // Filter out records below the configured minimum level
      if (record.level < minLevel) return;
      _handleLogRecord(record);
    });
  }

  void _handleLogRecord(log.LogRecord record) {
    // 1. Map package:logging Level to OtelLogSeverity
    final severity = _mapLevelToOtelSeverity(record.level);

    // 2. Extract active OpenTelemetry trace and span IDs if a span is running
    String? traceId;
    String? spanId;

    // 1. Check if your NavigatorObserver has an active screen context
    final activeSpanContext = OTelNavigatorObserver.activeScreenContext;

    if (activeSpanContext != null && activeSpanContext.isValid) {
      traceId = activeSpanContext.traceId.toString();
      spanId = activeSpanContext.spanId.toString();
    } else {
      // 2. Fallback: check if there is an active span in the current ambient execution context
      final currentSpan = otel.spanFromContext(otel.Context.current);
      if (currentSpan.spanContext.isValid) {
        traceId = currentSpan.spanContext.traceId.toString();
        spanId = currentSpan.spanContext.spanId.toString();
      }
    }

    // 3. Format attributes/metadata
    final attributes = <String, dynamic>{
      'logger.name': record.loggerName,
      if (record.error != null) 'error.object': record.error.toString(),
      if (record.stackTrace != null)
        'error.stacktrace': record.stackTrace.toString(),
    };

    // 4. Export OTLP log to disk queue
    _exporter.exportLog(
      message: record.message,
      severity: severity,
      traceId: traceId,
      spanId: spanId,
      attributes: attributes,
    );
  }

  OtelLogSeverity _mapLevelToOtelSeverity(log.Level level) {
    if (level >= log.Level.SEVERE) return OtelLogSeverity.error;
    if (level >= log.Level.WARNING) return OtelLogSeverity.warn;
    if (level >= log.Level.INFO) return OtelLogSeverity.info;
    return OtelLogSeverity.debug;
  }
}
