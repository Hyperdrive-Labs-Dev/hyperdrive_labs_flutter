import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperdrive_labs_telemetry/src/build_device_resource.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Hyperdrive Labs',
      packageName: 'com.hyperdrivelabs.app',
      version: '1.0.0',
      buildNumber: '42',
      buildSignature: 'mock_signature',
      installerStore: 'com.sec.android.app.samsungapps',
    );
  });

  group('buildDeviceResource Tests', () {
    test('contains mandatory service.name and app metadata', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/device_info'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'getAndroidDeviceInfo') {
                return {
                  'version': {'release': '14', 'sdkInt': 34},
                  'id': 'test_android_id',
                  'model': 'Pixel 8',
                  'manufacturer': 'Google',
                  'isPhysicalDevice': true,
                };
              }
              return null;
            },
          );

      final resource = await buildDeviceResource('test_service');

      // Map resource attributes safely using the package's iterable/collection structure
      final attributesMap = <String, dynamic>{};
      for (final key in resource.attributes.keys) {
        attributesMap[key] = resource.attributes.get(key);
      }

      expect(attributesMap['service.name'], 'test_service');
      expect(attributesMap['service.version'], '1.0.0');
      expect(attributesMap['app.version'], '1.0.0');
      expect(attributesMap['app.build_number'], '42');
      expect(attributesMap['app.name'], 'Hyperdrive Labs');
      expect(attributesMap['app.package_name'], 'com.hyperdrivelabs.app');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/device_info'),
            null,
          );
    });

    test(
      'handles plugin exceptions gracefully and returns base attributes',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/package_info'),
              (MethodCall methodCall) async =>
                  throw PlatformException(code: 'ERROR'),
            );

        final resource = await buildDeviceResource('fallback_service');

        final attributesMap = <String, dynamic>{};
        for (final key in resource.attributes.keys) {
          attributesMap[key] = resource.attributes.get(key);
        }

        expect(attributesMap['service.name'], 'fallback_service');

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/package_info'),
              null,
            );
      },
    );
  });
}
