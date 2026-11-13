import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nepali_utils/nepali_utils.dart';
import 'package:patro/models/app_settings.dart';
import 'package:patro/models/patro_event.dart';
import 'package:patro/providers/events_provider.dart';
import 'package:patro/providers/widget_sync_provider.dart';

void main() {
  final today = DateTime.utc(2026, 10, 31);
  const s = AppSettings();
  final settings = (
    colors: s.colors,
    nepaliDigits: true,
    weekStartsMonday: false,
    showTithi: true,
    showObservances: true,
    stickyNotification: true,
    statusBarDate: true,
    statusBarCalendar: CalendarSystem.bs,
    weekendDays: const [7],
  );

  test(
    'widget snapshot spans whole BS months from last month to a year ahead',
    () {
      final snapshot = buildWidgetSnapshot(
        today,
        EventsState(const []),
        settings,
      );
      expect(snapshot['statusBarDate'], isTrue);
      expect(snapshot['statusBarBs'], isTrue);
      final days = (snapshot['days'] as List).cast<Map<String, dynamic>>();

      expect([days.first['y'], days.first['m'], days.first['d']], [2083, 6, 1]);
      final last = days.last;
      expect([last['y'], last['m']], [2084, 7]);
      expect(last['d'], NepaliDateTime(2084, 7).totalDays);
      expect(() => jsonEncode(snapshot), returnsNormally);
    },
  );

  test('widget snapshot lists user events with their start time', () {
    final events = EventsState([
      PatroEvent.create(date: today, title: 'Dentist', startMinutes: 630),
    ]);
    final snapshot = buildWidgetSnapshot(today, events, settings);
    final day = (snapshot['days'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((d) => d['ad'] == '2026-10-31');

    expect([day['y'], day['m'], day['d'], day['wd']], [2083, 7, 14, 7]);
    expect(day['e'], [
      {'t': 'Dentist', 's': '10:30\u202fAM'}, // intl's narrow no-break space
    ]);
  });

  test('widget snapshot names holidays even when festivals are hidden', () {
    List<Map<String, dynamic>> holidays(bool showObservances) {
      final snapshot = buildWidgetSnapshot(today, EventsState(const []), (
        colors: settings.colors,
        nepaliDigits: true,
        weekStartsMonday: false,
        showTithi: true,
        showObservances: showObservances,
        stickyNotification: true,
        statusBarDate: false,
        statusBarCalendar: CalendarSystem.ad,
        weekendDays: const [7],
      ));
      return [
        for (final d in (snapshot['days'] as List).cast<Map<String, dynamic>>())
          if (d['h'] == true) d,
      ];
    }

    final hidden = holidays(false);
    expect(hidden, isNotEmpty);
    for (final day in hidden) {
      expect(day['hn'], isA<String>());
      expect(day['e'], isNull);
    }
    // Shown festivals carry the name in their entries instead.
    expect(holidays(true).every((d) => d['hn'] == null), isTrue);
  });
}
