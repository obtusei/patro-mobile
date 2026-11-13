import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../services/system_bridge.dart';
import 'storage_provider.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  static const storageKey = 'patro.settings.v1';

  Timer? _saveTimer;
  AppSettings? _unsaved;
  late SharedPreferences _prefs;

  @override
  AppSettings build() {
    _prefs = ref.read(sharedPreferencesProvider);
    ref.onDispose(() {
      _saveTimer?.cancel();
      _save();
    });
    final raw = _prefs.getString(storageKey);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (e) {
      debugPrint('Patro: discarding unreadable settings: $e');
      return const AppSettings();
    }
  }

  void update(AppSettings Function(AppSettings current) change) {
    state = _unsaved = change(state);
    // Colour sliders fire every frame; coalesce the writes.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _save);
  }

  void applyPreset(ThemePreset preset) => update(
    (s) => s.copyWith(presetId: () => preset.id, colors: preset.colors),
  );

  /// Editing a saved theme's colours updates that theme; editing a built-in
  /// preset turns the colours into an unsaved custom set.
  void setColor(ColorRole role, Color color) => update((s) {
    final colors = s.colors.withRole(role, color);
    final editing =
        s.presetId != null && s.presetId!.startsWith(ThemePreset.customPrefix);
    return s.copyWith(
      presetId: editing ? null : () => null,
      colors: colors,
      customThemes: editing
          ? [
              for (final t in s.customThemes)
                t.id == s.presetId ? t.copyWith(colors: colors) : t,
            ]
          : null,
    );
  });

  /// Saves the current colours as a new theme and selects it.
  void saveCustomTheme(String name) => update((s) {
    final theme = ThemePreset(
      '${ThemePreset.customPrefix}'
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      name,
      s.colors,
    );
    return s.copyWith(
      presetId: () => theme.id,
      customThemes: [...s.customThemes, theme],
    );
  });

  void renameCustomTheme(String id, String name) => update(
    (s) => s.copyWith(
      customThemes: [
        for (final t in s.customThemes) t.id == id ? t.copyWith(name: name) : t,
      ],
    ),
  );

  /// Removes a saved theme. If it is in use its colours stay, unsaved.
  void deleteCustomTheme(String id) => update(
    (s) => s.copyWith(
      presetId: s.presetId == id ? () => null : null,
      customThemes: [
        for (final t in s.customThemes)
          if (t.id != id) t,
      ],
    ),
  );

  /// Back to defaults, keeping the user's saved themes.
  void reset() => update((s) => AppSettings(customThemes: s.customThemes));

  void _save() {
    final settings = _unsaved;
    if (settings == null) return;
    _unsaved = null;
    unawaited(_prefs.setString(storageKey, jsonEncode(settings.toJson())));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Keeps the Android launcher icon on the one picked in Settings. Watch it
/// once from the app root.
final appIconSyncProvider = Provider<void>((ref) {
  final id = ref.watch(settingsProvider.select((s) => s.appIcon));
  unawaited(SystemBridge.setAppIcon(id));
});
