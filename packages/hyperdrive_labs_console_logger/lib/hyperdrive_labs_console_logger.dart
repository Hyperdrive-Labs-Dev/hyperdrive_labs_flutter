import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Attaches a custom console listener to [Logger.root.onRecord] that formats
/// and prints log records to the developer console in debug mode.
///
/// Only logs with a severity level greater than or equal to [minLevel]
/// will be processed and printed.
void attachConsoleLogger({Level minLevel = Level.INFO}) {
  Logger.root.onRecord.listen((LogRecord record) {
    if (!kDebugMode) return;

    // Filter out anything below your chosen console threshold
    if (record.level < minLevel) return;

    final output = _formatConsoleOutput(record);

    developer.log(
      output,
      time: record.time,
      level: record.level.value,
      name: _getEmojiForLevel(record.level),
    );
  });
}

/// Formats a given [LogRecord] into a structured, multi-line boxed string.
///
/// Exposed for testing purposes.
@visibleForTesting
String formatConsoleOutput(LogRecord record) => _formatConsoleOutput(record);

String _formatConsoleOutput(LogRecord record) {
  final timestamp = _formatTime(record.time);
  final color = _getColorForLevel(record.level);
  const reset = AnsiCodes.reset;
  const gray = AnsiCodes.gray;
  const bold = AnsiCodes.bold;

  String title = record.level.name.toUpperCase();

  // Buffer to assemble the multi-line block frame
  final buffer = StringBuffer();

  // Top border with timestamp and tag: ┌ 12:34:56.789 • INFO • [MyLogger]
  buffer.write(
    '\t$gray┌────────────────────────────────────────────────────────$reset\n',
  );
  buffer.write(
    '\t$gray│$reset $bold$timestamp$reset  $color$bold[$title]$reset  $gray${record.loggerName}$reset\n',
  );
  buffer.write('\t$gray│$reset $color${record.message}$reset');

  // If an error or exception is attached, format it inside the box structure
  if (record.error != null) {
    buffer.write(
      '\n\t$gray│$reset ${AnsiCodes.red}Error: ${record.error}$reset',
    );
  }

  // If stacktrace is present, cleanly format lines
  if (record.stackTrace != null) {
    buffer.write('\n\t$gray│$reset ${AnsiCodes.gray}Stacktrace:\n');
    final stackLines = record.stackTrace.toString().trim().split('\n');
    for (final line in stackLines.take(5)) {
      // Limit lines for clean console
      buffer.write('\t$gray│$reset   $gray$line$reset\n');
    }
  }

  // Bottom border: └────────────────────────
  buffer.write(
    '\n\t$gray└────────────────────────────────────────────────────────$reset',
  );

  return buffer.toString();
}

/// Formats a [DateTime] into a zero-padded string with milliseconds (HH:mm:ss.SSS).
///
/// Exposed for testing purposes.
@visibleForTesting
String formatTime(DateTime time) => _formatTime(time);

String _formatTime(DateTime time) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  String threeDigits(int n) => n.toString().padLeft(3, '0');

  final hours = twoDigits(time.hour);
  final minutes = twoDigits(time.minute);
  final seconds = twoDigits(time.second);
  final milliseconds = threeDigits(time.millisecond);

  return '$hours:$minutes:$seconds.$milliseconds';
}

/// Returns the corresponding ANSI color code for a given log [level].
///
/// Exposed for testing purposes.
@visibleForTesting
String getColorForLevel(Level level) => _getColorForLevel(level);

String _getColorForLevel(Level level) {
  if (level >= Level.SHOUT) return AnsiCodes.magenta;
  if (level >= Level.SEVERE) return AnsiCodes.red;
  if (level >= Level.WARNING) return AnsiCodes.yellow;
  if (level >= Level.INFO) return AnsiCodes.blue;
  return AnsiCodes.gray;
}

/// Returns an appropriate emoji indicator for a given log [level].
///
/// Exposed for testing purposes.
@visibleForTesting
String getEmojiForLevel(Level level) => _getEmojiForLevel(level);

String _getEmojiForLevel(Level level) {
  if (level >= Level.SHOUT) return '💥'; // Fatal / Shout
  if (level >= Level.SEVERE) return '❌'; // Error
  if (level >= Level.WARNING) return '⚠️'; // Warning
  if (level >= Level.INFO) return 'ℹ️'; // Info
  return '🔍'; // Debug / Fine
}

/// ANSI escape codes for stylized terminal output.
class AnsiCodes {
  /// Resets all color and style attributes.
  static const reset = '\x1b[0m';

  /// Muted gray color for borders, timestamps, and metadata.
  static const gray = '\x1b[90m';

  /// Blue color for informational logs.
  static const blue = '\x1b[34m';

  /// Green color for successful or fine-level logs.
  static const green = '\x1b[32m';

  /// Yellow color for warning-level logs.
  static const yellow = '\x1b[33m';

  /// Red color for error-level logs and exception details.
  static const red = '\x1b[31m';

  /// Magenta color for fatal or shout-level logs.
  static const magenta = '\x1b[35m';

  /// Bold style modifier for text emphasis.
  static const bold = '\x1b[1m';
}
