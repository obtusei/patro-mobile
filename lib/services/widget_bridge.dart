import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hands precomputed calendar data to the Android home-screen widgets and the
/// sticky date notification, which run without a Dart isolate.
///
/// The native side (`android/.../widget/`) stores the latest snapshot and
/// redraws from it at midnight, so the app only has to publish when the data
/// changes.
abstract final class WidgetBridge {
  static const _channel = MethodChannel('patro/widgets');

  /// The real host OS, not [defaultTargetPlatform], which `flutter test`
  /// reports as Android.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<void> publish(Map<String, dynamic> snapshot) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('publish', jsonEncode(snapshot));
    } on PlatformException catch (e) {
      debugPrint('Patro: widget publish failed: ${e.message}');
    } on MissingPluginException {
      // Running under a test harness or an engine without MainActivity.
    }
  }

  /// Calls [onDay] with the day a widget was tapped on: once now if a widget
  /// launched the app, and again each time one is tapped while it runs.
  static Future<void> listenForDays(void Function(DateTime day) onDay) async {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openDay' && call.arguments is String) {
        final day = _parseDay(call.arguments as String);
        if (day != null) onDay(day);
      }
    });
    try {
      final launch = await _channel.invokeMethod<String>('takeLaunchDay');
      final day = launch == null ? null : _parseDay(launch);
      if (day != null) onDay(day);
    } on PlatformException catch (e) {
      debugPrint('Patro: reading the widget launch day failed: ${e.message}');
    } on MissingPluginException {
      // As in [publish].
    }
  }

  /// A `yyyy-MM-dd` date as the UTC midnight the calendar uses.
  static DateTime? _parseDay(String ad) {
    final parsed = DateTime.tryParse(ad);
    if (parsed == null) return null;
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }
}
