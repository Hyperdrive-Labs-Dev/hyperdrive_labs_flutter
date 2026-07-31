import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

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

@visibleForTesting
String formatConsoleOutput(LogRecord record) => _formatConsoleOutput(record);

String _formatConsoleOutput(LogRecord record) {
  final timestamp = _formatTime(record.time);
  final color = _getColorForLevel(record.level);
  const reset = AnsiCodes.reset;
  const gray = AnsiCodes.gray;
  const bold = AnsiCodes.bold;

  String title = record.level.name.toUpperCase();

  // Buffer to assemble the Talker multi-line block frame
  final buffer = StringBuffer();

  // Top border with timestamp and tag: ┌ 12:34:56.789 • INFO • [MyLogger]
  buffer.write(
    '\t$gray┌────────────────────────────────────────────────────────$reset\n',
  );
  buffer.write(
    '\t$gray│$reset $bold$timestamp$reset  $color$bold[$title]$reset  $gray${record.loggerName}$reset\n',
  );
  buffer.write('\t$gray│$reset $color${record.message}$reset');

  // If an error or exception is attached, format it inside the box structure like Talker
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

@visibleForTesting
String getColorForLevel(Level level) => _getColorForLevel(level);

String _getColorForLevel(Level level) {
  if (level >= Level.SHOUT) return AnsiCodes.magenta;
  if (level >= Level.SEVERE) return AnsiCodes.red;
  if (level >= Level.WARNING) return AnsiCodes.yellow;
  if (level >= Level.INFO) return AnsiCodes.blue;
  return AnsiCodes.gray;
}

@visibleForTesting
String getEmojiForLevel(Level level) => _getEmojiForLevel(level);

String _getEmojiForLevel(Level level) {
  if (level >= Level.SHOUT) return '💥'; // Fatal / Shout
  if (level >= Level.SEVERE) return '❌'; // Error
  if (level >= Level.WARNING) return '⚠️'; // Warning
  if (level >= Level.INFO) return 'ℹ️'; // Info
  return '🔍'; // Debug / Fine
}

/// ANSI escape codes for Talker-like colors in the console
class AnsiCodes {
  static const reset = '\x1b[0m';

  // Foreground Colors
  static const gray = '\x1b[90m';
  static const blue = '\x1b[34m';
  static const green = '\x1b[32m';
  static const yellow = '\x1b[33m';
  static const red = '\x1b[31m';
  static const magenta = '\x1b[35m';

  // Styles
  static const bold = '\x1b[1m';
}
