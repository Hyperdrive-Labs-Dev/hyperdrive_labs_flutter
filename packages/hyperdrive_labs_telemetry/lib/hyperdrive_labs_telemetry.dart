import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hyperdrive_labs_telemetry/src/version.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// An offline-first crash reporter that intercepts uncaught Flutter and Dart
/// errors and flushes them to an OpenTelemetry (OTLP) endpoint.
class HyperdriveLabsTelemetry {
  static late Uri _otlpEndpoint;
  static late Map<String, String> _headers;
  static bool _isFlushing = false;

  /// The HTTP client instance used to dispatch OTLP log payloads.
  ///
  /// Can be overridden in unit or integration tests to mock network calls.
  @visibleForTesting
  static http.Client client = http.Client();

  /// Overrides the local storage directory path during tests.
  ///
  /// When non-null, queued log files are written here instead of the default
  /// application documents directory.
  @visibleForTesting
  static String? testDirectoryPath;

  static Future<Directory> _getStorageDir() async {
    if (testDirectoryPath != null) {
      return Directory(testDirectoryPath!);
    }
    return await getApplicationDocumentsDirectory();
  }

  /// Initializes the telemetry reporter, attaches error handlers, and executes
  /// the [runAppCallback].
  ///
  /// - [otlpEndpoint]: The HTTP collector URL to post OTLP JSON logs to.
  /// - [headers]: Custom HTTP headers (e.g., authorization or tenant keys).
  /// - [serviceName]: The name of the service/app sending the telemetry.
  /// - [runAppCallback]: A callback executing `runApp()` after setup.
  static Future<void> init({
    required Uri otlpEndpoint,
    required Map<String, String> headers,
    required String serviceName,
    required FutureOr<void> Function() runAppCallback,
  }) async {
    _otlpEndpoint = otlpEndpoint;
    _headers = headers;

    FlutterError.onError = (FlutterErrorDetails details) {
      queueCrashLocally(
        serviceName: serviceName,
        exception: details.exceptionAsString(),
        stackTrace: details.stack?.toString() ?? '',
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      queueCrashLocally(
        serviceName: serviceName,
        exception: error.toString(),
        stackTrace: stack.toString(),
      );
      return true;
    };

    await flushQueue();
    runAppCallback();
  }

  /// Formats an error into an OTLP log payload and saves it to local disk storage.
  ///
  /// Immediately initiates a [flushQueue] call after writing the file.
  @visibleForTesting
  static Future<void> queueCrashLocally({
    required String serviceName,
    required String exception,
    required String stackTrace,
  }) async {
    try {
      final dir = await _getStorageDir();
      final queueDir = Directory('${dir.path}/otel_queue');

      if (!queueDir.existsSync()) queueDir.createSync(recursive: true);

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final file = File('${queueDir.path}/log_$timestamp.json');

      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = "${packageInfo.version}+${packageInfo.buildNumber}";

      final otlpPayload = {
        "resourceLogs": [
          {
            "resource": {
              "attributes": [
                {
                  "key": "service.name",
                  "value": {"stringValue": serviceName},
                },
                {
                  "key": "service.version",
                  "value": {"stringValue": appVersion},
                },
                {
                  "key": "os.type",
                  "value": {"stringValue": Platform.operatingSystem},
                },
                {
                  "key": "os.version",
                  "value": {"stringValue": Platform.operatingSystemVersion},
                },
              ],
            },
            "scopeLogs": [
              {
                "scope": {
                  "name": "hyperdrive_labs_telemetry",
                  "version": packageVersion,
                },
                "logRecords": [
                  {
                    "timeUnixNano": "${timestamp * 1000}",
                    "severityText": "ERROR",
                    "severityNumber": 17,
                    "body": {"stringValue": exception},
                    "attributes": [
                      {
                        "key": "exception.type",
                        "value": {
                          "stringValue": exception.split(':').first.trim(),
                        },
                      },
                      {
                        "key": "exception.message",
                        "value": {"stringValue": exception},
                      },
                      {
                        "key": "exception.stacktrace",
                        "value": {"stringValue": stackTrace},
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      };

      file.writeAsStringSync(jsonEncode(otlpPayload), flush: true);
      await flushQueue();
    } catch (_) {}
  }

  /// Iterates through all locally buffered OTLP log files in `otel_queue` and
  /// posts them to the configured OTLP endpoint.
  ///
  /// Successfully sent files are deleted. If a request fails, flushing halts
  /// to preserve bandwidth and battery until the next attempt.
  @visibleForTesting
  static Future<void> flushQueue() async {
    if (_isFlushing) return;
    _isFlushing = true;

    try {
      final dir = await _getStorageDir();
      final queueDir = Directory('${dir.path}/otel_queue');
      if (!queueDir.existsSync()) {
        _isFlushing = false;
        return;
      }

      final files = queueDir.listSync().whereType<File>().toList();

      for (var file in files) {
        final content = await file.readAsString();

        final response = await client.post(
          _otlpEndpoint,
          headers: {'Content-Type': 'application/json', ..._headers},
          body: content,
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await file.delete();
        } else {
          break; // Stop flushing if server fails or device is offline
        }
      }
    } catch (_) {
      // Offline state
    } finally {
      _isFlushing = false;
    }
  }
}
