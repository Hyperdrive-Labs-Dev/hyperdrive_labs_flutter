import 'package:flutter/material.dart';
import 'package:hyperdrive_labs_telemetry/hyperdrive_labs_telemetry.dart';
import 'package:opentelemetry/api.dart' as otel;

/// A [NavigatorObserver] that generates OpenTelemetry spans for Flutter
/// route transitions according to standard Mobile APM specifications.
///
/// This observer tracks user navigation by ending the current screen view span
/// upon route transitions and starting a new span linked to the preceding screen
/// context. This maintains continuous trace lineage without keeping screen spans
/// open indefinitely.
class OTelNavigatorObserver extends NavigatorObserver {
  otel.Span? _activeScreenSpan;

  /// The [otel.SpanContext] of the currently active screen.
  ///
  /// Network client interceptors (e.g., Dio or HTTP wrapper) can inspect this
  /// property to parent outgoing API requests directly under the active screen span.
  static otel.SpanContext? activeScreenContext;

  /// The sanitized or class-based name of the currently active screen view.
  ///
  /// Useful for attaching screen context metadata to unhandled exceptions,
  /// logs, or background operations.
  static String activeScreenName = 'unknown_screen';

  /// Traces transitions between routes, ending the active screen view span
  /// and starting a new span linked to the previous screen context.
  void _traceScreen(Route<dynamic>? route) {
    if (route == null) return;

    // 1. Resolve screen name (URL style, explicit name, or PageRoute class fallback)
    String? screenName = route.settings.name;
    if (screenName == null || screenName.trim().isEmpty) {
      if (route is PageRoute) {
        screenName = route.runtimeType.toString();
      } else {
        return; // Ignore non-page routes (e.g., dialogs, bottom sheets, tooltips)
      }
    }

    final safeName = _sanitizeRouteName(screenName);
    activeScreenName = safeName;

    // 2. Capture the outgoing screen's context as the parent before closing it
    otel.Context parentContext = otel.Context.current;
    if (_activeScreenSpan != null) {
      parentContext = otel.contextWithSpan(parentContext, _activeScreenSpan!);

      // Close outgoing screen span cleanly to trigger immediate APM export
      _activeScreenSpan!.setStatus(otel.StatusCode.ok);
      _activeScreenSpan!.end();
      _activeScreenSpan = null;
    }

    // 3. Start the new screen view span linked to the previous screen's context
    _activeScreenSpan = HyperdriveLabsTelemetry.tracer.startSpan(
      'View Screen: $safeName',
      context: parentContext,
    );

    _activeScreenSpan?.setAttribute(
      otel.Attribute.fromString('screen.name', safeName),
    );

    // 4. Expose active span context for network interceptors
    activeScreenContext = _activeScreenSpan?.spanContext;
  }

  /// Sanitizes route paths by masking dynamic parameters like IDs or UUIDs.
  String _sanitizeRouteName(String rawRoute) {
    final idPattern = RegExp(
      r'/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|/\d+',
    );
    return rawRoute.replaceAll(idPattern, '/:id');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _traceScreen(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    // Trace the screen the user is returning to when popping
    _traceScreen(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _traceScreen(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _traceScreen(previousRoute);
  }
}
