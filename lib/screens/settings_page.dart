import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform.dart';
import '../models/app_settings.dart';
import '../providers/calendar_sync_provider.dart';
import '../providers/events_provider.dart';
import '../providers/remote_sync_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/patro_style.dart';
import '../widgets/common.dart';
import '../widgets/date_converter_sheet.dart';
import 'scan_event_screen.dart';
import 'settings/appearance_settings.dart';
import 'settings/general_settings.dart';
import 'settings/settings_parts.dart';
import 'settings/sky_settings.dart';

/// The Settings page: a short list of groups, each opening its own page.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final settings = ref.watch(settingsProvider);
    final eventCount = ref.watch(eventsProvider.select((e) => e.all.length));
    final phoneConnected = ref.watch(
      calendarSyncProvider.select((c) => c.connected),
    );
    final remoteCount = ref.watch(
      remoteSyncProvider.select((r) => r.items.length),
    );

    void open(Widget page) =>
        Navigator.of(context).push(SettingsSubpage.route(page));

    final themeName = settings.allThemes
        .where((t) => t.id == settings.presetId)
        .map((t) => t.name)
        .firstOrNull;

    String reminder() => settings.defaultReminder == null
        ? 'No default reminder'
        : 'Remind ${reminderLabel(context, settings.defaultReminder!, allDay: false).toLowerCase()}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PatroLogo(),
              const SizedBox(height: 6),
              Text('Settings', style: s.monthTitle),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SettingsGroupRow(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          summary: [
            themeName ?? 'Custom colours',
            '${settings.dayIndicator.label.toLowerCase()} marks',
          ].join(' · '),
          onTap: () => open(const AppearanceSettings()),
        ),
        SettingsGroupRow(
          icon: Icons.calendar_month_outlined,
          title: 'Calendar',
          summary: [
            settings.primaryCalendar == CalendarSystem.bs
                ? 'Bikram Sambat'
                : 'Gregorian',
            settings.nepaliDigits ? 'नेपाली' : 'English',
            settings.weekendDays.isEmpty
                ? 'no weekly holiday'
                : '${weekendLabel(settings)} off',
          ].join(' · '),
          onTap: () => open(const CalendarSettings()),
        ),
        SettingsGroupRow(
          icon: Icons.view_carousel_outlined,
          title: 'Pages',
          summary:
              'Opens on ${settings.effectiveStartPage.label}'
              '${settings.showTimeline ? ' · timeline' : ''}'
              '${settings.showSkyPage ? ' · sky' : ''}'
              '${settings.visiblePages.contains(ShellPage.compass) ? ' · compass' : ''}',
          onTap: () => open(const PagesSettings()),
        ),
        SettingsGroupRow(
          icon: Icons.wb_twilight_rounded,
          title: 'Sun & Moon',
          summary: settings.showSkyPage
              ? 'Sky page on · ${placeLabel(settings.skyLocation)}'
              : 'Sky page off',
          onTap: () => open(const SkySettings()),
        ),
        SettingsGroupRow(
          icon: Icons.notifications_none_rounded,
          title: 'Events & reminders',
          summary: reminder(),
          onTap: () => open(const EventsSettings()),
        ),
        SettingsGroupRow(
          icon: Icons.sync_rounded,
          title: 'Calendars & sync',
          summary: [
            if (isPhone)
              phoneConnected ? 'Phone calendars on' : 'Phone calendars off',
            settings.onlineEvents
                ? 'Patro online${remoteCount > 0 ? ' ($remoteCount)' : ''}'
                : 'Offline',
          ].join(' · '),
          onTap: () => open(const SyncSettings()),
        ),
        SettingsGroupRow(
          icon: Icons.graphic_eq_rounded,
          title: 'Sound & haptics',
          summary: [
            settings.soundEffects ? 'Sound on' : 'Sound off',
            settings.haptics ? 'haptics on' : 'haptics off',
          ].join(' · '),
          onTap: () => open(const FeelSettings()),
        ),
        SettingsGroupRow(
          icon: Icons.storage_rounded,
          title: 'Data',
          summary: eventCount == 1
              ? '1 saved event'
              : '$eventCount saved events',
          onTap: () => open(const DataSettings()),
        ),
        const SectionLabel('Tools'),
        SettingsActionRow(
          icon: Icons.swap_vert_rounded,
          title: 'Date converter',
          subtitle: 'Between Bikram Sambat and Gregorian',
          onTap: () => showDateConverter(context),
        ),
        if (isPhone)
          SettingsActionRow(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Scan event QR code',
            subtitle: 'Add an event someone shared with you',
            onTap: () => scanEventQr(context),
          ),
        const SizedBox(height: 32),
        Center(child: Text('PATRO · 0.3.0', style: s.mono)),
      ],
    );
  }
}
