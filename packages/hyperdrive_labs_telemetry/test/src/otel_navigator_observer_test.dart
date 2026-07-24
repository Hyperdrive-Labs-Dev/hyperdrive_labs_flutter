import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';
import 'package:opentelemetry/api.dart' as otel;
import 'package:opentelemetry/sdk.dart' as otel_sdk;

void main() {
  group('OTelNavigatorObserver Tests', () {
    late List<otel_sdk.ReadOnlySpan> exportedSpans;
    late OTelNavigatorObserver observer;

    setUp(() {
      exportedSpans = [];

      final exporter = _TestSpanExporter(exportedSpans);
      final processor = otel_sdk.SimpleSpanProcessor(exporter);
      final tracerProvider = otel_sdk.TracerProviderBase(
        processors: [processor],
      );

      HyperdriveLabsTelemetry.tracer = tracerProvider.getTracer(
        'test_navigation_tracer',
      );
      observer = OTelNavigatorObserver();

      // Reset static states between tests
      OTelNavigatorObserver.activeScreenName = 'unknown_screen';
      OTelNavigatorObserver.activeScreenContext = null;
    });

    test('traces push route and sanitizes dynamic IDs in route name', () {
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/users/12345/profile'),
        builder: (_) => const Scaffold(),
      );

      observer.didPush(route, null);

      expect(
        OTelNavigatorObserver.activeScreenName,
        equals('/users/:id/profile'),
      );
      expect(OTelNavigatorObserver.activeScreenContext, isNotNull);
    });

    test('ignores non-PageRoute navigation items without names', () {
      // Create a generic, non-PageRoute instance (e.g., PopupRoute / Dialog route mock)
      final popupRoute = _MockPopupRoute();

      observer.didPush(popupRoute, null);

      // Should remain untouched since it's ignored
      expect(OTelNavigatorObserver.activeScreenName, equals('unknown_screen'));
      expect(exportedSpans, isEmpty);
    });

    test(
      'closes previous screen span and links new screen on push sequence',
      () {
        final routeA = MaterialPageRoute(
          settings: const RouteSettings(name: '/home'),
          builder: (_) => const Scaffold(),
        );

        final routeB = MaterialPageRoute(
          settings: const RouteSettings(name: '/settings'),
          builder: (_) => const Scaffold(),
        );

        // Push first screen
        observer.didPush(routeA, null);
        expect(OTelNavigatorObserver.activeScreenName, equals('/home'));
        expect(exportedSpans, isEmpty); // Active screen span is still open

        // Push second screen (should close /home span and export it)
        observer.didPush(routeB, routeA);

        expect(OTelNavigatorObserver.activeScreenName, equals('/settings'));
        expect(exportedSpans.length, equals(1));
        expect(exportedSpans.first.name, equals('View Screen: /home'));
        expect(exportedSpans.first.status.code, equals(otel.StatusCode.ok));
      },
    );

    test('traces returned screen context on route pop', () {
      final routeA = MaterialPageRoute(
        settings: const RouteSettings(name: '/dashboard'),
        builder: (_) => const Scaffold(),
      );

      final routeB = MaterialPageRoute(
        settings: const RouteSettings(name: '/detail'),
        builder: (_) => const Scaffold(),
      );

      observer.didPush(routeA, null);
      observer.didPush(routeB, routeA);

      // Pop back to routeA
      observer.didPop(routeB, routeA);

      expect(OTelNavigatorObserver.activeScreenName, equals('/dashboard'));
      expect(exportedSpans.length, equals(2));
      expect(exportedSpans.last.name, equals('View Screen: /detail'));
    });
  });
}

/// A mock route extending [Route] that is not a [PageRoute] to test filter checks.
class _MockPopupRoute extends Route<dynamic> {
  @override
  // ignore: unnecessary_overrides
  bool didPop(dynamic result) => super.didPop(result);
}

class _TestSpanExporter implements otel_sdk.SpanExporter {
  final List<otel_sdk.ReadOnlySpan> spanList;

  _TestSpanExporter(this.spanList);

  @override
  void export(List<otel_sdk.ReadOnlySpan> spans) {
    spanList.addAll(spans);
  }

  @override
  void shutdown() {}

  @override
  void forceFlush() {}
}
