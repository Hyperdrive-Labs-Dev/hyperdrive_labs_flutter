# HyperdriveLabsTelemetry

An offline-first OpenTelemetry SDK manager for Flutter. It seamlessly configures distributed tracing, captures unhandled exceptions (Flutter framework errors and platform crashes), auto-tracks navigation screens, and queues OTLP telemetry payloads to disk when the device is offline for reliable batch uploading later.

---

## Features

- **Offline-First Disk Queueing:** Automatically buffers OpenTelemetry spans to local disk storage if the network drops and flushes them when connectivity is restored or the app pauses/hides.
- **Global Error Interception:** Automatically catches and records unhandled `FlutterError` framework exceptions and `PlatformDispatcher` crashes.
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
- **Graceful Degradation:** If the device loses internet connection during a background flush, files remain safely locked in local disk storage (`otel_queue/`) and are retried on the next cycle.

---

## License

This package is licensed under the [MIT License](LICENSE).
