# HyperdriveLabsTelemetry

An offline-first OpenTelemetry SDK manager for Flutter. It seamlessly configures distributed tracing, captures unhandled exceptions (Flutter framework errors and platform crashes), auto-tracks navigation screens, routes application logs through OpenTelemetry, and queues OTLP telemetry payloads (traces and logs) to disk when the device is offline for reliable batch uploading later.

---

## Features

- **Offline-First Disk Queueing:** Automatically buffers OpenTelemetry traces and OTLP log exports to local disk storage if the network drops and flushes them when connectivity is restored or the app pauses/hides.
- **Robust Error Handling & DLQ:** Features automatic sidecar retry tracking (`.retry`) for 5xx errors and immediate routing of poisoned payloads, malformed JSON, or 4xx client errors into a dedicated Dead-Letter Queue (`dead_letter/`).
- **Global Error Interception:** Automatically catches and records unhandled `FlutterError` framework exceptions and `PlatformDispatcher` crashes.
- **Integrated Logging Handler:** Bridges [`package:logging`](https://pub.dev/packages/logging) directly into OpenTelemetry log severity levels, capturing log attributes, exception objects, and stack traces automatically.
- **Route & Navigation Tracing:** Includes custom `NavigatorObserver` bindings for automatic screen-view journey tracking.
- **Dio Network Interceptor:** Easily pluggable Dio interceptor for recording outgoing HTTP requests as distributed spans.
- **Rich Metadata Enrichment:** Automatically attaches device hardware info, OS attributes, and package version metadata using `device_info_plus` and `package_info_plus`.

---

## Installation

Add `hyperdrive_labs_telemetry` to your `pubspec.yaml`:

```yaml
dependencies:
  hyperdrive_labs_telemetry: ^1.0.0
```

Then install the dependency:

```bash
flutter pub get
```

---

## Quick Start

Initialize the telemetry manager inside your `main()` function before calling `runApp()`. You can supply your OTLP collector endpoint directly or fallback to standard `--dart-define` environment flags.

All parameters in `HyperdriveLabsTelemetry.init()` are optional. If omitted, the package automatically attempts to read configuration values from compile-time environment variables (`--dart-define`) or sensible defaults.

### Minimal Initialization Example

```dart
await HyperdriveLabsTelemetry.init(
  runAppCallback: () => runApp(const MyApp()),
);
```

### Example using all parameters

```dart
import 'package:flutter/widgets.dart';
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await HyperdriveLabsTelemetry.init(
    otlpEndpoint: Uri.parse('https://your-otel-collector.com/v1/traces'),
    serviceName: 'my_flutter_app',
    logLevel: log.Level.INFO,
    headers: {'Authorization': 'Bearer YOUR_TOKEN'},
    flushInterval: const Duration(seconds: 15),
    runAppCallback: () {
      runApp(const MyApp());
    },
  );
}
```

### Alternatively via `--dart-define`

You can configure initialization parameters at compile-time without passing them in code:

```bash
flutter run \
  --dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=https://your-otel-collector.com/v1/traces \
  --dart-define=OTEL_SERVICE_NAME=my_flutter_app \
  --dart-define=OTEL_LOG_LEVEL=INFO \
  --dart-define=OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer TOKEN
```

Headers passed through `--dart-define` should be comma-separated like so:

```bash
--dart-define=OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer TOKEN,Other-Header=X,Last-Header=Y
```

---

## Integration Guides

### 1. Navigation Tracking (`OTelNavigatorObserver`)

To automatically capture screen navigation telemetry and attach active screen context to errors, add the observer to your `MaterialApp` or `CupertinoApp`:

```dart
MaterialApp(
  navigatorObservers: [
    OTelNavigatorObserver(),
  ],
  home: const HomeScreen(),
);
```

### 2. Network Tracing (`OTelDioInterceptor`)

If you use `Dio` for networking, attach the `OTelDioInterceptor` to record outgoing HTTP calls as distributed traces:

```dart
import 'package:dio/dio.dart';
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';

final dio = Dio(BaseOptions(baseUrl: '[https://api.example.com](https://api.example.com)'));
dio.interceptors.add(OTelDioInterceptor());
```

### 3. Manual Error Recording

You can manually capture caught exceptions, network errors, or custom business logic failures at any time:

```dart
try {
  // Your risky operation
} catch (e, stackTrace) {
  HyperdriveLabsTelemetry.recordException(
    exception: e,
    stackTrace: stackTrace,
    reason: 'Failed to parse user profile payload',
  );
}
```

---

## Architecture & Lifecycle Management

- **App Lifecycle Hooks:** The package implements `WidgetsBindingObserver` under the hood. When your app transitions to the `paused` or `hidden` state, it triggers an immediate queue flush to ensure pending telemetry is sent before the OS suspends the process.
- **Reliability & Dead-Letter Queues (DLQ):**
  - **5xx / Network Failures:** Retried up to 3 times with sidecar counter tracking before being safely routed to the `dead_letter/` directory.
  - **4xx Client Errors & Corrupted Data:** Malformed JSON files or permanent schema rejection errors bypass retries and go straight to the DLQ to prevent queue gridlock.
- **Graceful Degradation:** If the device loses internet connection during a background flush, files remain safely locked in local disk storage (`otel_queue/`) and are retried on the next cycle.

---

## License

This package is licensed under the [MIT License](LICENSE).
