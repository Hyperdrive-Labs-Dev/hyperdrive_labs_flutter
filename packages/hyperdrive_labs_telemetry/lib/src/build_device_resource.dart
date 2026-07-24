import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:opentelemetry/api.dart' as otel;
import 'package:opentelemetry/sdk.dart' as otel_sdk;
import 'package:package_info_plus/package_info_plus.dart';

/// Collects device, OS, and application metadata into an OpenTelemetry [otel_sdk.Resource].
///
/// Attaches standard OpenTelemetry Semantic Conventions such as `service.name`,
/// `service.version`, `os.name`, `os.version`, and `device.id`.
Future<otel_sdk.Resource> buildDeviceResource(String serviceName) async {
  final attributes = <otel.Attribute>[
    otel.Attribute.fromString('service.name', serviceName),
  ];

  try {
    final packageInfo = await PackageInfo.fromPlatform();
    attributes.addAll([
      otel.Attribute.fromString('service.version', packageInfo.version),
      otel.Attribute.fromString('app.version', packageInfo.version),
      otel.Attribute.fromString('app.build_number', packageInfo.buildNumber),
      otel.Attribute.fromString('app.name', packageInfo.appName),
      otel.Attribute.fromString('app.package_name', packageInfo.packageName),
    ]);

    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      attributes.addAll([
        otel.Attribute.fromString('os.name', 'Android'),
        otel.Attribute.fromString('os.version', android.version.release),
        otel.Attribute.fromString('device.id', android.id),
        otel.Attribute.fromString('device.model.identifier', android.model),
        otel.Attribute.fromString('device.manufacturer', android.manufacturer),
      ]);
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      attributes.addAll([
        otel.Attribute.fromString('os.name', 'iOS'),
        otel.Attribute.fromString('os.version', ios.systemVersion),
        otel.Attribute.fromString(
          'device.id',
          ios.identifierForVendor ?? 'unknown',
        ),
        otel.Attribute.fromString(
          'device.model.identifier',
          ios.utsname.machine,
        ),
        otel.Attribute.fromString('device.manufacturer', 'Apple'),
      ]);
    } else {
      attributes.addAll([
        otel.Attribute.fromString('os.name', Platform.operatingSystem),
        otel.Attribute.fromString(
          'os.version',
          Platform.operatingSystemVersion,
        ),
      ]);
    }
  } catch (_) {
    // Fallback if device info plugin fails during early startup
  }

  return otel_sdk.Resource(attributes);
}
