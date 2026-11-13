import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/calendar_sync_provider.dart';
import 'providers/reminder_sync_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/storage_provider.dart';
import 'providers/widget_sync_provider.dart';
import 'screens/home_shell.dart';
import 'theme/patro_style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const PatroApp(),
    ),
  );
}

class PatroApp extends ConsumerWidget {
  const PatroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the Android home-screen widgets and notification in sync.
    ref.watch(widgetSyncProvider);
    // Schedules event reminders and applies the chosen launcher icon.
    ref.watch(reminderSyncProvider);
    ref.watch(appIconSyncProvider);
    // Starts reading the phone's calendars once they are connected.
    ref.watch(calendarSyncProvider.select((sync) => sync.connected));
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Patro',
      debugShowCheckedModeBanner: false,
      theme: buildPatroTheme(settings),
      themeAnimationDuration: const Duration(milliseconds: 380),
      themeAnimationCurve: Curves.easeOutCubic,
      home: const HomeShell(),
    );
  }
}
