# hyperdrive_labs_telemetry

An offline-first OpenTelemetry (OTLP) crash log collector and reporter for Flutter applications. `hyperdrive_labs_telemetry` automatically intercepts uncaught Flutter framework errors and asynchronous Dart platform errors, formats them into standard OpenTelemetry JSON log records, queues them locally on disk when offline, and flushes them to your OTLP backend endpoint.

---

## Features

- **Automatic Error Interception:** Hooks directly into `FlutterError.onError` and `PlatformDispatcher.instance.onError` to capture both UI and background Dart crashes.
- **OTLP Standard Format:** Formats exception reports into valid OpenTelemetry `resourceLogs` with standard attributes (`service.name`, `os.type`, `exception.stacktrace`, severity levels, and Unix nanosecond timestamps).
- **Offline Disk Buffering:** Saves unsent crash payloads as JSON files in a dedicated local directory (`otel_queue/`), ensuring logs persist across application restarts.
- **Robust Queue Flushing:** Attempts to flush queued logs upon application boot and immediately after writing new crash reports, safely stopping on HTTP errors or network disconnections without crashing the UI thread.
- **Test-Friendly Design:** Exposes testing hooks for injecting HTTP mock clients and specifying custom directory paths during automated testing.

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

## Usage

Initialize `HyperdriveLabsTelemetry` inside your `main()` function prior to running the app. Pass your OTLP endpoint URI, custom headers (such as authorization or API keys), service name, and execution callback:

```dart
import 'package:flutter/material.dart';
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await HyperdriveLabsTelemetry.init(
    otlpEndpoint: Uri.parse('https://otlp.your-collector.com/v1/logs'),
    headers: {
      'Authorization': 'Bearer YOUR_OTLP_TOKEN',
      'X-Scope-OrgID': 'my-organization',
    },
    serviceName: 'my_flutter_app',
    runAppCallback: () {
      runApp(const MyApp());
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Telemetry Example')),
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              // Uncaught errors will automatically be intercepted, queued, and sent
              throw Exception('Test uncaught error');
            },
            child: const Text('Trigger Error'),
          ),
        ),
      ),
    );
  }
}
```

---

## Architecture & OTLP Schema

When an error occurs, `HyperdriveLabsTelemetry` serializes the payload into the standard OTLP JSON structure before writing to disk:

```json
{
  "resourceLogs": [
    {
      "resource": {
        "attributes": [
          {
            "key": "service.name",
            "value": { "stringValue": "my_flutter_app" }
          },
          { "key": "os.type", "value": { "stringValue": "ios" } }
        ]
      },
      "scopeLogs": [
        {
          "logRecords": [
            {
              "timeUnixNano": "1710000000000000000",
              "severityText": "ERROR",
              "severityNumber": 17,
              "body": { "stringValue": "Exception: Test uncaught error" },
              "attributes": [
                {
                  "key": "exception.stacktrace",
                  "value": {
                    "stringValue": "#0      MyApp.build.<anonymous closure>..."
                  }
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

---

## License

This package is licensed under the [MIT License](LICENSE).
