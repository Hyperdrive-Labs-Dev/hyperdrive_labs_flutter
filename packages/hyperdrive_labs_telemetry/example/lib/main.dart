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
