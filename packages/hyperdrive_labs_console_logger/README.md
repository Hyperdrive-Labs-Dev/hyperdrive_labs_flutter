# Hyperdrive Labs Console Logger (`hyperdrive_labs_console_logger`)

A lightweight, developer-friendly Flutter/Dart console logger that transforms [`package:logging`](https://pub.dev/packages/logging) records into structured, ANSI-colored box frames with emoji tags.

---

## Features

- **Visual Framing:** Renders clean, multi-line boxed logs with distinct top and bottom borders.
- **Color-Coded Severity:** Uses native ANSI escape sequences to color-code logs by severity level.
- **Emoji Categorization:** Automatically maps log levels to intuitive emoji tags (`ℹ️`, `⚠️`, `❌`, `💥`, `🐛`).
- **Non-Truncating Output:** Leverages Dart's `developer.log` under the hood to bypass IDE string-length truncations for large payloads or stack traces.
- **Complete Separation of Concerns:** Acts purely as a terminal visualizer. It leaves global filtering, log level definitions, and telemetry storage entirely to your upstream analytics/telemetry packages.

---

## Installation

Add `hyperdrive_labs_console_logger` to your `pubspec.yaml`:

```yaml
dependencies:
  hyperdrive_labs_console_logger: ^1.0.0
```

Then install the dependency:

```bash
flutter pub get
```

---

## Usage

Initialize the console logger early in your app lifecycle (e.g., inside `main()`), typically right after setting up your telemetry system.

```dart
import 'package:hyperdrive_labs_console_logger/hyperdrive_labs_console_logger.dart';
import 'package:logging/logging.dart';

void main() {
  // 1. Let your telemetry package manage global capture
  Logger.root.level = Level.ALL;

  // 2. Attach the console logger for pretty local development output
  attachConsoleLogger(minLevel: Level.INFO);

  runApp(const ProviderScope(child: MyApp()));
}

```

### Logging Messages

Because this package builds natively on top of standard `package:logging`, you can use standard loggers anywhere in your codebase:

```dart
final log = Logger('AuthService');

void login() {
  log.info('User successfully authenticated.');
  log.warning('Token is expiring soon.');
  log.severe('Failed to refresh authentication token.', error, stackTrace);
}

```

---

## Console Output Preview

```text
	┌────────────────────────────────────────────────────────
	│ ℹ️  20:29:45.548  [INFO]  AuthService
	│ User successfully authenticated.
	└────────────────────────────────────────────────────────
	┌────────────────────────────────────────────────────────
	│ ❌  20:29:45.551  [SEVERE]  AuthService
	│ Failed to refresh authentication token.
	│ Error: DioException [connection error]...
	│ Stacktrace:
	│   #0      AuthService.login (package:app/auth.dart:42)
	└────────────────────────────────────────────────────────

```

---

## License

This package is licensed under the [MIT License](LICENSE).
