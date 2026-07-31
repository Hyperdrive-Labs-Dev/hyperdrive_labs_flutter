import 'package:flutter/material.dart';
import 'package:hyperdrive_labs_console_logger/hyperdrive_labs_console_logger.dart';
import 'package:logging/logging.dart';

void main() {
  // 1. Let your telemetry package manage global capture
  Logger.root.level = Level.ALL;

  // 2. Attach the console logger for pretty local development output
  attachConsoleLogger(minLevel: Level.INFO);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Hyperdrive Labs Console Logger')),
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              Logger("Test Logger").info("Testing log message!");
            },
            child: const Text('Trigger info log message'),
          ),
        ),
      ),
    );
  }
}
