import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'widget_bridge.dart';

/// Event reminders and the launcher icon, handled by the Android side
/// (`android/.../reminder/` and `AppIcons.kt`).
abstract final class SystemBridge {
  static const _channel = MethodChannel('patro/system');

  static bool get isSupported => WidgetBridge.isSupported;

  /// Replaces every scheduled reminder with [reminders].
  static Future<void> scheduleReminders(List<Map<String, dynamic>> reminders) =>
      _invoke('scheduleReminders', jsonEncode(reminders));

  /// Switches the launcher icon to the one with [id]; see `appIcons`.
  static Future<void> setAppIcon(String id) => _invoke('setAppIcon', id);

  static Future<void> _invoke(String method, Object argument) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method, argument);
    } on PlatformException catch (e) {
      debugPrint('Patro: $method failed: ${e.message}');
    } on MissingPluginException {
      // Running under a test harness or an engine without MainActivity.
    }
  }
}
