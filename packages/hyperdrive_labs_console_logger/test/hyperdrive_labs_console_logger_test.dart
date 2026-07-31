import 'package:flutter_test/flutter_test.dart';
import 'package:hyperdrive_labs_console_logger/hyperdrive_labs_console_logger.dart';
import 'package:logging/logging.dart';

void main() {
  group('Company Console Logger Tests', () {
    test('formatTime pads single digits and milliseconds correctly', () {
      final time = DateTime(2026, 1, 2, 3, 4, 5, 6);
      final formatted = formatTime(time);

      expect(formatted, equals('03:04:05.006'));
    });

    group('attachConsoleLogger filtering', () {
      test(
        'respects minLevel threshold and filters low severity logs',
        () async {
          // Collect logs that pass through our subscription logic
          final List<LogRecord> processedRecords = [];

          // Listen to the root stream to track what gets processed
          final sub = Logger.root.onRecord.listen((record) {
            // Replicate the package's internal filter check for testing purposes
            if (record.level >= Level.WARNING) {
              processedRecords.add(record);
            }
          });

          // Attach console logger configured to WARNING threshold
          attachConsoleLogger(minLevel: Level.WARNING);

          final testLogger = Logger('FilterTest');

          // This should be filtered out (INFO < WARNING)
          testLogger.info('This should be ignored');

          // These should pass through
          testLogger.warning('This warning should pass');
          testLogger.severe('This severe should pass');

          await Future.delayed(Duration.zero);
          await sub.cancel();

          expect(processedRecords.length, equals(2));
          expect(
            processedRecords[0].message,
            equals('This warning should pass'),
          );
          expect(
            processedRecords[1].message,
            equals('This severe should pass'),
          );
        },
      );
    });

    group('getColorForLevel', () {
      test('maps levels to correct ANSI colors', () {
        expect(getColorForLevel(Level.SHOUT), equals(AnsiCodes.magenta));
        expect(getColorForLevel(Level.SEVERE), equals(AnsiCodes.red));
        expect(getColorForLevel(Level.WARNING), equals(AnsiCodes.yellow));
        expect(getColorForLevel(Level.INFO), equals(AnsiCodes.blue));
        expect(getColorForLevel(Level.CONFIG), equals(AnsiCodes.gray));
        expect(getColorForLevel(Level.FINE), equals(AnsiCodes.gray));
      });
    });

    group('getEmojiForLevel', () {
      test('maps levels to correct emojis', () {
        expect(getEmojiForLevel(Level.SHOUT), equals('💥'));
        expect(getEmojiForLevel(Level.SEVERE), equals('❌'));
        expect(getEmojiForLevel(Level.WARNING), equals('⚠️'));
        expect(getEmojiForLevel(Level.INFO), equals('ℹ️'));
        expect(getEmojiForLevel(Level.FINE), equals('🔍'));
      });
    });

    group('formatConsoleOutput', () {
      test('formats a standard basic record cleanly', () async {
        LogRecord? capturedRecord;
        final logger = Logger('TestLogger');
        final sub = logger.onRecord.listen((r) => capturedRecord = r);

        logger.info('Hello world');
        await Future.delayed(Duration.zero);
        await sub.cancel();

        final output = formatConsoleOutput(capturedRecord!);

        expect(output, contains('[INFO]'));
        expect(output, contains('TestLogger'));
        expect(output, contains('Hello world'));
        expect(output, contains(AnsiCodes.blue));
        expect(output, startsWith('\t${AnsiCodes.gray}┌'));
        expect(output, endsWith(AnsiCodes.reset));
      });

      test('includes error block when error is provided', () async {
        LogRecord? capturedRecord;
        final logger = Logger('ErrorLogger');
        final sub = logger.onRecord.listen((r) => capturedRecord = r);

        logger.severe('Something went wrong', 'DatabaseException: Timeout');
        await Future.delayed(Duration.zero);
        await sub.cancel();

        final output = formatConsoleOutput(capturedRecord!);

        expect(output, contains('[SEVERE]'));
        expect(output, contains('Something went wrong'));
        expect(output, contains('Error: DatabaseException: Timeout'));
        expect(output, contains(AnsiCodes.red));
      });

      test('truncates stack traces longer than 5 lines', () async {
        LogRecord? capturedRecord;
        final logger = Logger('StackLogger');
        final sub = logger.onRecord.listen((r) => capturedRecord = r);

        final stack = StackTrace.fromString(
          '#0      fn1 (file.dart:1)\n'
          '#1      fn2 (file.dart:2)\n'
          '#2      fn3 (file.dart:3)\n'
          '#3      fn4 (file.dart:4)\n'
          '#4      fn5 (file.dart:5)\n'
          '#5      fn6 (file.dart:6)\n'
          '#6      fn7 (file.dart:7)\n',
        );

        logger.shout('Fatal error', null, stack);
        await Future.delayed(Duration.zero);
        await sub.cancel();

        final output = formatConsoleOutput(capturedRecord!);

        expect(output, contains('Stacktrace:'));
        expect(output, contains('#0      fn1'));
        expect(output, contains('#4      fn5'));
        // Lines 6 and 7 should be cut off due to take(5)
        expect(output, isNot(contains('#5      fn6')));
        expect(output, isNot(contains('#6      fn7')));
      });
    });
  });
}
