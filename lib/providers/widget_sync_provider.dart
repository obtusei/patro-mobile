import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nepali_utils/nepali_utils.dart';

import '../core/calendar_format.dart';
import '../models/app_settings.dart';
import '../models/patro_day.dart';
import '../services/widget_bridge.dart';
import 'calendar_provider.dart';
import 'events_provider.dart';
import 'remote_sync_provider.dart';
import 'settings_provider.dart';

/// The slice of [AppSettings] that changes how the widgets look.
typedef WidgetSettings = ({
  PatroColorSet colors,
  bool nepaliDigits,
  bool weekStartsMonday,
  bool showTithi,
  bool showObservances,
  bool stickyNotification,
  bool statusBarDate,
  CalendarSystem statusBarCalendar,
  List<int> weekendDays,
});

WidgetSettings _widgetSettingsOf(AppSettings s) => (
  colors: s.colors,
  nepaliDigits: s.nepaliDigits,
  weekStartsMonday: s.weekStartsMonday,
  showTithi: s.showTithi,
  showObservances: s.showObservances,
  stickyNotification: s.stickyNotification,
  statusBarDate: s.statusBarDate,
  statusBarCalendar: s.statusBarCalendar,
  weekendDays: s.weekendDays,
);

/// Indexed by NepaliDateTime.weekday - 1 (Sunday first).
const _nepaliWeekdays = [
  'आइतबार', 'सोमबार', 'मंगलबार', 'बुधबार', 'बिहीबार', 'शुक्रबार', 'शनिबार', //
];

/// Keeps the Android widgets and sticky notification in step with today's
/// date, the user's events and the settings that affect how they look.
/// Watch it once from the app root.
final widgetSyncProvider = Provider<void>((ref) {
  if (!WidgetBridge.isSupported) return;
  final today = ref.watch(calendarProvider);
  final events = ref.watch(eventsProvider);
  final settings = ref.watch(settingsProvider.select(_widgetSettingsOf));
  final published = ref.watch(remoteObservancesProvider);

  // Event edits and colour sliders arrive in bursts; publish once they settle.
  var cancelled = false;
  final timer = Timer(const Duration(milliseconds: 600), () async {
    final snapshot = await _buildInBackground(
      today,
      events,
      settings,
      published,
    );
    if (!cancelled) await WidgetBridge.publish(snapshot);
  });
  ref.onDispose(() {
    cancelled = true;
    timer.cancel();
  });
});

// Top-level so the isolate closure captures only its arguments.
Future<Map<String, dynamic>> _buildInBackground(
  DateTime today,
  EventsState events,
  WidgetSettings settings,
  Map<DateTime, List<Observance>> published,
) => Isolate.run(() => buildWidgetSnapshot(today, events, settings, published));

/// Every day from the start of last BS month to the end of the BS month a
/// year ahead, so the month widget can page around and the notification
/// keeps rolling over even if the app is not opened for months.
Map<String, dynamic> buildWidgetSnapshot(
  DateTime today,
  EventsState events,
  WidgetSettings settings, [
  Map<DateTime, List<Observance>> published = const {},
]) {
  final current = bsMonthIndex(bsMonthOf(today));
  final first = bsMonthAt(math.max(current - 1, 0));
  final last = bsMonthAt(math.min(current + 12, bsMonthCount - 1));
  final end = BsCalendar.toAd(
    NepaliDateTime(last.year, last.month, last.totalDays),
  );
  final time = DateFormat.jm();

  Map<String, dynamic> dayJson(PatroDay day) {
    final entries = [
      if (settings.showObservances)
        for (final o in day.observances)
          {'t': o.name, if (o.isHoliday) 'h': true},
      for (final e in events.on(day))
        {
          't': e.title,
          if (e.startMinutes case final start?)
            's': time.format(DateTime(2000, 1, 1, 0, start)),
          'c': ?e.color?.toARGB32(),
        },
    ];
    return {
      'ad': day.adDate.toIso8601String().substring(0, 10),
      'y': day.bsDate.year,
      'm': day.bsDate.month,
      'd': day.bsDate.day,
      'wd': day.bsDate.weekday,
      if (settings.showTithi) 't': day.tithi,
      if (day.isPublicHoliday) 'h': true,
      // The holiday's name, for the countdown widget, when festivals are
      // hidden from the entries.
      if (day.isPublicHoliday && !settings.showObservances)
        'hn': day.observances.firstWhere((o) => o.isHoliday).name,
      if (settings.weekendDays.contains(day.bsDate.weekday)) 'w': true,
      if (entries.isNotEmpty) 'e': entries,
    };
  }

  return {
    'v': 1,
    'sticky': settings.stickyNotification,
    'statusBarDate': settings.statusBarDate,
    'statusBarBs': settings.statusBarCalendar == CalendarSystem.bs,
    'nepaliDigits': settings.nepaliDigits,
    'weekStartsMonday': settings.weekStartsMonday,
    'weekendDays': settings.weekendDays,
    'colors': settings.colors.toJson(),
    'months': [
      for (var m = 1; m <= 12; m++)
        bsMonthName(m, nepali: settings.nepaliDigits),
    ],
    'weekdays': _nepaliWeekdays,
    'weekdaysShort': nepaliWeekdaysShort,
    'days': [
      for (
        var ad = BsCalendar.toAd(first);
        !ad.isAfter(end);
        ad = ad.add(const Duration(days: 1))
      )
        dayJson(
          PatroDay.fromAd(ad, today: today, extra: published[ad] ?? const []),
        ),
    ],
  };
}
