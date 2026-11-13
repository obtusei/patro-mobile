import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/calendar_format.dart';
import '../../core/platform.dart';
import '../../models/app_settings.dart';
import '../../models/patro_day.dart';
import '../../providers/calendar_sync_provider.dart';
import '../../providers/events_provider.dart';
import '../../providers/remote_sync_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/feedback_service.dart';
import '../../services/system_bridge.dart';
import '../../theme/patro_style.dart';
import '../../widgets/common.dart';
import '../../widgets/select.dart';
import 'settings_parts.dart';

void _set(WidgetRef ref, AppSettings Function(AppSettings) change) =>
    ref.read(settingsProvider.notifier).update(change);

/// Weekday names, NepaliDateTime order (Sunday = 1).
const _weekdayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

String weekendLabel(AppSettings settings) =>
    settings.weekendPresetLabel ??
    settings.weekendDays
        .map((w) => _weekdayNames[w - 1].substring(0, 3))
        .join(', ');

/// Calendar system, numerals, week layout, weekly holidays and what each day
/// shows.
class CalendarSettings extends ConsumerWidget {
  const CalendarSettings({super.key});

  Future<void> _customWeekend(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<List<int>>(
      context: context,
      builder: (_) =>
          _WeekendDialog(initial: ref.read(settingsProvider).weekendDays),
    );
    if (picked != null) _set(ref, (x) => x.copyWith(weekendDays: picked));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return SettingsSubpage(
      title: 'Calendar',
      children: [
        const SectionLabel('Dates'),
        SelectRow<CalendarSystem>(
          title: 'Primary calendar',
          value: settings.primaryCalendar,
          options: const [
            SelectOption(CalendarSystem.bs, 'Bikram Sambat'),
            SelectOption(CalendarSystem.ad, 'Gregorian'),
          ],
          onChanged: (v) => _set(ref, (x) => x.copyWith(primaryCalendar: v)),
        ),
        SelectRow<bool>(
          title: 'Numerals & names',
          value: settings.nepaliDigits,
          options: [
            SelectOption(true, 'नेपाली ${devanagariDigits('123')}'),
            const SelectOption(false, 'English 123'),
          ],
          onChanged: (v) => _set(ref, (x) => x.copyWith(nepaliDigits: v)),
        ),
        SelectRow<bool>(
          title: 'Week starts on',
          value: settings.weekStartsMonday,
          options: const [
            SelectOption(false, 'Sunday'),
            SelectOption(true, 'Monday'),
          ],
          onChanged: (v) => _set(ref, (x) => x.copyWith(weekStartsMonday: v)),
        ),
        SelectRow<String?>(
          title: 'Weekly holidays',
          subtitle: 'Shown in the holiday colour every week',
          value: settings.weekendPresetLabel,
          valueLabel: weekendLabel(settings),
          options: [
            for (final (label, days) in weekendPresets)
              SelectOption(
                label,
                label,
                detail: days.isEmpty ? 'No weekly day off' : null,
              ),
          ],
          onChanged: (label) {
            final days = weekendPresets.firstWhere((p) => p.$1 == label).$2;
            _set(ref, (x) => x.copyWith(weekendDays: days));
          },
          onCustom: () => _customWeekend(context, ref),
        ),
        const SectionLabel('Each day shows'),
        SettingsSwitchRow(
          title: 'Tithi',
          subtitle: 'Lunar day and moon phase beside each date',
          value: settings.showTithi,
          onChanged: (v) => _set(ref, (x) => x.copyWith(showTithi: v)),
        ),
        SettingsSwitchRow(
          title: 'Gregorian dates',
          subtitle: 'AD date beside each BS date',
          value: settings.showAdDates,
          onChanged: (v) => _set(ref, (x) => x.copyWith(showAdDates: v)),
        ),
        SettingsSwitchRow(
          title: 'Festivals & holidays',
          subtitle: 'Dashain, Tihar, national days and more',
          value: settings.showObservances,
          onChanged: (v) => _set(ref, (x) => x.copyWith(showObservances: v)),
        ),
      ],
    );
  }
}

class _WeekendDialog extends StatefulWidget {
  const _WeekendDialog({required this.initial});

  final List<int> initial;

  @override
  State<_WeekendDialog> createState() => _WeekendDialogState();
}

class _WeekendDialogState extends State<_WeekendDialog> {
  late final Set<int> _days = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Weekly holidays'),
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var w = 1; w <= 7; w++)
            CheckboxListTile(
              dense: true,
              title: Text(_weekdayNames[w - 1]),
              value: _days.contains(w),
              onChanged: (on) =>
                  setState(() => on == true ? _days.add(w) : _days.remove(w)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _days.toList()..sort()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Which pages the app shows and opens on.
class PagesSettings extends ConsumerWidget {
  const PagesSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return SettingsSubpage(
      title: 'Pages',
      children: [
        const SectionLabel('Start'),
        SelectRow<ShellPage>(
          title: 'Open the app on',
          value: settings.effectiveStartPage,
          options: [
            for (final page in settings.visiblePages)
              if (page != ShellPage.settings) SelectOption(page, page.label),
          ],
          onChanged: (v) => _set(ref, (x) => x.copyWith(startPage: v)),
        ),
        const SectionLabel('Pages'),
        SettingsSwitchRow(
          title: 'Date page',
          subtitle: 'One date at a time, just before Settings',
          value: settings.showDatePage,
          onChanged: (v) => _set(ref, (x) => x.copyWith(showDatePage: v)),
        ),
        SettingsSwitchRow(
          title: 'Sky page',
          subtitle: 'Sun and Moon in 3D and AR, with the panchanga',
          value: settings.showSkyPage,
          onChanged: (v) => _set(ref, (x) => x.copyWith(showSkyPage: v)),
        ),
        if (isPhone)
          SettingsSwitchRow(
            title: 'Compass page',
            subtitle: 'Heading, level and where the Sun and Moon are',
            value: settings.showCompassPage,
            onChanged: (v) => _set(ref, (x) => x.copyWith(showCompassPage: v)),
          ),
        SettingsSwitchRow(
          title: 'Timeline',
          subtitle: 'Lay a day\'s events out hour by hour',
          value: settings.showTimeline,
          onChanged: (v) => _set(ref, (x) => x.copyWith(showTimeline: v)),
        ),
        if (SystemBridge.isSupported) ...[
          const SectionLabel('Notification shade'),
          SettingsSwitchRow(
            title: 'Sticky date notification',
            subtitle:
                'Today\'s date, tithi and events in the notification shade',
            value: settings.stickyNotification,
            onChanged: (v) =>
                _set(ref, (x) => x.copyWith(stickyNotification: v)),
          ),
          SettingsSwitchRow(
            title: 'Date in status bar',
            subtitle: settings.stickyNotification
                ? 'Today\'s date as the icon at the top of the screen'
                : 'Needs the sticky date notification',
            value: settings.stickyNotification && settings.statusBarDate,
            onChanged: settings.stickyNotification
                ? (v) => _set(ref, (x) => x.copyWith(statusBarDate: v))
                : null,
          ),
          if (settings.stickyNotification && settings.statusBarDate)
            SelectRow<CalendarSystem>(
              title: 'Status bar date',
              value: settings.statusBarCalendar,
              options: [
                SelectOption(
                  CalendarSystem.bs,
                  'Nepali ${devanagariDigits('${BsCalendar.fromAd(DateTime.now()).day}')}',
                  detail: 'Bikram Sambat day',
                ),
                SelectOption(
                  CalendarSystem.ad,
                  'English ${DateTime.now().day}',
                  detail: 'Gregorian day',
                ),
              ],
              onChanged: (v) =>
                  _set(ref, (x) => x.copyWith(statusBarCalendar: v)),
            ),
        ],
      ],
    );
  }
}

/// Lead times offered for the default reminder; null is none.
const _defaultReminderOptions = <int?>[null, 0, 5, 10, 15, 30, 60, 120, 1440];

/// New-event defaults.
class EventsSettings extends ConsumerWidget {
  const EventsSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final settings = ref.watch(settingsProvider);
    final current = settings.defaultReminder;
    String label(int? m) =>
        m == null ? 'None' : reminderLabel(context, m, allDay: false);

    return SettingsSubpage(
      title: 'Events & reminders',
      children: [
        const SectionLabel('New events'),
        SelectRow<int?>(
          title: 'Default reminder',
          subtitle: 'Added to new timed events',
          value: current,
          valueLabel: label(current),
          options: [
            for (final m in _defaultReminderOptions) SelectOption(m, label(m)),
          ],
          onChanged: (m) =>
              _set(ref, (x) => x.copyWith(defaultReminder: () => m)),
          onCustom: () async {
            final m = await pickCustomReminder(
              context,
              allDay: false,
              initial: current,
            );
            if (m != null) {
              _set(ref, (x) => x.copyWith(defaultReminder: () => m));
            }
          },
        ),
        const SizedBox(height: 4),
        Text(
          SystemBridge.isSupported
              ? 'Patro sends the notification, or your phone calendar does '
                    'if the event is saved there.'
              : 'Reminders are sent on Android phones.',
          style: s.bodySmall,
        ),
      ],
    );
  }
}

/// Phone calendars and the Patro server.
class SyncSettings extends ConsumerWidget {
  const SyncSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SettingsSubpage(
      title: 'Calendars & sync',
      children: [
        SectionLabel('Phone calendars'),
        _CalendarSection(),
        SectionLabel('Patro online'),
        _ServerSection(),
      ],
    );
  }
}

/// Holidays and events the Patro team publishes.
class _ServerSection extends ConsumerWidget {
  const _ServerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final settings = ref.watch(settingsProvider);
    final remote = ref.watch(remoteSyncProvider);
    final synced = remote.lastSynced;
    final host = Uri.tryParse(settings.serverUrl)?.host ?? settings.serverUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSwitchRow(
          title: 'Published holidays & events',
          subtitle: 'Official holiday dates and notices, kept up to date',
          value: settings.onlineEvents,
          onChanged: (v) => _set(ref, (x) => x.copyWith(onlineEvents: v)),
        ),
        if (settings.onlineEvents) ...[
          SettingsActionRow(
            icon: Icons.dns_outlined,
            title: 'Server',
            subtitle: host,
            onTap: () async {
              final url = await askText(
                context,
                title: 'Patro server',
                initial: settings.serverUrl,
                hint: defaultServerUrl,
                keyboardType: TextInputType.url,
                capitalization: TextCapitalization.none,
              );
              if (url == null) return;
              final withScheme = url.contains('://') ? url : 'https://$url';
              _set(ref, (x) => x.copyWith(serverUrl: withScheme));
            },
          ),
          const SizedBox(height: 4),
          Text(switch (remote.status) {
            RemoteStatus.syncing => 'Syncing…',
            RemoteStatus.failed => remote.error ?? 'Could not sync',
            RemoteStatus.idle when synced != null =>
              '${remote.items.length} published items · synced '
                  '${DateFormat.MMMd().add_jm().format(synced)}',
            RemoteStatus.idle => 'Not synced yet',
          }, style: s.bodySmall),
          Row(
            children: [
              TextButton(
                onPressed: remote.status == RemoteStatus.syncing
                    ? null
                    : ref.read(remoteSyncProvider.notifier).refresh,
                child: const Text('Sync now'),
              ),
              const Spacer(),
              if (settings.serverUrl != defaultServerUrl)
                TextButton(
                  onPressed: () =>
                      _set(ref, (x) => x.copyWith(serverUrl: defaultServerUrl)),
                  child: const Text('Use default server'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Connects the calendars of the accounts on this phone.
class _CalendarSection extends ConsumerWidget {
  const _CalendarSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final sync = ref.watch(calendarSyncProvider);
    final notifier = ref.read(calendarSyncProvider.notifier);

    if (!isPhone) {
      return Text(
        'Calendar sync is available on Android and iOS.',
        style: s.bodySmall,
      );
    }

    if (!sync.connected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            sync.status == SyncStatus.denied
                ? 'Patro needs calendar access to show your events.'
                : 'Show events from Google, Outlook and any other calendar '
                      'account on this phone.',
            style: s.bodySmall,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: sync.status == SyncStatus.denied
                ? DeviceCalendar.instance.openAppSettings
                : notifier.connect,
            child: Text(
              sync.status == SyncStatus.denied
                  ? 'Open app settings'
                  : 'Connect calendars',
            ),
          ),
        ],
      );
    }

    final syncedAt = sync.lastSynced;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in sync.calendars)
          SettingsSwitchRow(
            title: c.name,
            subtitle: c.accountName ?? '',
            value: sync.selected.contains(c.id),
            onChanged: (v) => notifier.toggle(c.id, on: v),
          ),
        const SizedBox(height: 6),
        Text(switch (sync.status) {
          SyncStatus.syncing => 'Syncing…',
          SyncStatus.denied => 'Calendar access is turned off',
          SyncStatus.failed => 'Could not read your calendars',
          SyncStatus.idle when syncedAt != null =>
            'Synced at ${TimeOfDay.fromDateTime(syncedAt).format(context)}. '
                'New events in Patro stay in Patro.',
          SyncStatus.idle => '',
        }, style: s.bodySmall),
        Row(
          children: [
            TextButton(
              onPressed: notifier.refresh,
              child: const Text('Sync now'),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: s.holiday),
              onPressed: notifier.disconnect,
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Sound effects and haptics.
class FeelSettings extends ConsumerWidget {
  const FeelSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return SettingsSubpage(
      title: 'Sound & haptics',
      children: [
        const SectionLabel('Feel'),
        SettingsSwitchRow(
          title: 'Sound effects',
          subtitle: 'A soft chalk touch on swipes and taps',
          value: settings.soundEffects,
          onChanged: (v) {
            _set(ref, (x) => x.copyWith(soundEffects: v));
            if (v) ref.read(feedbackProvider).play(PatroSound.pageTurn);
          },
        ),
        SettingsSwitchRow(
          title: 'Haptics',
          subtitle: 'A light tap with every turn and touch',
          value: settings.haptics,
          onChanged: (v) => _set(ref, (x) => x.copyWith(haptics: v)),
        ),
      ],
    );
  }
}

/// Saved events and resetting.
class DataSettings extends ConsumerWidget {
  const DataSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final eventCount = ref.watch(eventsProvider.select((e) => e.all.length));
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSubpage(
      title: 'Data',
      children: [
        const SectionLabel('Events'),
        Row(
          children: [
            Expanded(
              child: Text(
                eventCount == 1 ? '1 saved event' : '$eventCount saved events',
                style: s.body,
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: s.holiday),
              onPressed: eventCount == 0
                  ? null
                  : () async {
                      final ok = await confirmSetting(
                        context,
                        title: 'Delete all events?',
                        body:
                            'All $eventCount events will be removed from '
                            'Patro. Copies saved to phone calendars stay '
                            'there. This cannot be undone.',
                        action: 'Delete all',
                      );
                      if (ok) ref.read(eventsProvider.notifier).clear();
                    },
              child: const Text('Delete all'),
            ),
          ],
        ),
        const SectionLabel('Settings'),
        OutlinedButton(
          onPressed: () async {
            final ok = await confirmSetting(
              context,
              title: 'Reset settings?',
              body:
                  'Theme, colours, shape, pages and display options go back '
                  'to their defaults. Your events and saved themes are kept.',
              action: 'Reset',
            );
            if (ok) notifier.reset();
          },
          child: const Text('Reset settings'),
        ),
      ],
    );
  }
}
