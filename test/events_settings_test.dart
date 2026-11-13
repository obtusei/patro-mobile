import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nepali_utils/nepali_utils.dart';
import 'package:patro/models/app_settings.dart';
import 'package:patro/models/patro_day.dart';
import 'package:patro/models/patro_event.dart';
import 'package:patro/providers/events_provider.dart';
import 'package:patro/providers/storage_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final today = DateTime.utc(2026, 10, 31);
  PatroDay bs(int y, int m, int d) =>
      PatroDay.fromBs(NepaliDateTime(y, m, d), today: today);

  group('PatroEvent recurrence', () {
    test('yearly BS repeats on the same BS date, not before the origin', () {
      final birthday = PatroEvent.create(
        date: BsCalendar.toAd(NepaliDateTime(2080, 7, 12)),
        title: 'Birthday',
        repeat: EventRepeat.yearlyBs,
      );
      final state = EventsState([birthday]);
      expect(state.on(bs(2083, 7, 12)), [birthday]);
      expect(state.on(bs(2083, 7, 13)), isEmpty);
      expect(state.on(bs(2079, 7, 12)), isEmpty);
    });

    test('a day-32 origin falls on the last day of shorter months', () {
      // Find a 32-day month followed, a year later, by a shorter one.
      var year = 2075;
      var month = 1;
      while (!(NepaliDateTime(year, month).totalDays == 32 &&
          NepaliDateTime(year + 1, month).totalDays < 32)) {
        month = month % 12 + 1;
        if (month == 1) year++;
      }
      final event = PatroEvent.create(
        date: BsCalendar.toAd(NepaliDateTime(year, month, 32)),
        title: 'Edge',
        repeat: EventRepeat.yearlyBs,
      );
      final next = NepaliDateTime(year + 1, month);
      final state = EventsState([event]);
      expect(state.on(bs(year + 1, month, next.totalDays)), hasLength(1));
      expect(state.on(bs(year + 1, month, next.totalDays - 1)), isEmpty);
    });

    test('yearly AD and one-off events', () {
      final once = PatroEvent.create(date: today, title: 'Once');
      final annual = PatroEvent.create(
        date: DateTime.utc(2020, 12, 25),
        title: 'Annual',
        repeat: EventRepeat.yearlyAd,
      );
      final state = EventsState([once, annual]);
      expect(state.on(PatroDay.fromAd(today, today: today)), [once]);
      expect(
        state.on(PatroDay.fromAd(DateTime.utc(2031, 12, 25), today: today)),
        [annual],
      );
    });

    test('timed events sort after all-day ones, by start time', () {
      final late = PatroEvent.create(
        date: today,
        title: 'b',
        startMinutes: 900,
      );
      final early = PatroEvent.create(
        date: today,
        title: 'a',
        startMinutes: 60,
      );
      final allDay = PatroEvent.create(date: today, title: 'z');
      expect(
        EventsState([
          late,
          early,
          allDay,
        ]).on(PatroDay.fromAd(today, today: today)),
        [allDay, early, late],
      );
    });

    test('JSON round-trip keeps every field', () {
      final e = PatroEvent.create(
        date: today,
        title: 'Puja',
        note: 'Bring flowers',
        startMinutes: 360,
        endMinutes: 420,
        repeat: EventRepeat.yearlyBs,
        color: const Color(0xFF5FBF7F),
      );
      final back = PatroEvent.fromJson(e.toJson());
      expect(back.toJson(), e.toJson());
    });
  });

  test('EventsNotifier persists and restores', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer make() => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );

    final first = make();
    final event = PatroEvent.create(date: today, title: 'Saved');
    first.read(eventsProvider.notifier).upsert(event);
    first.dispose();

    final second = make();
    addTearDown(second.dispose);
    expect(second.read(eventsProvider).all.single.title, 'Saved');
    second.read(eventsProvider.notifier).remove(event.id);
    expect(second.read(eventsProvider).all, isEmpty);
  });

  test('AppSettings JSON round-trip and tolerant parsing', () {
    final custom = const AppSettings().copyWith(
      presetId: () => null,
      colors: themePresets[1].colors.withRole(
        ColorRole.highlight,
        const Color(0xFF123456),
      ),
      cornerRadius: 3,
      primaryCalendar: CalendarSystem.ad,
      nepaliDigits: false,
      weekStartsMonday: true,
      soundEffects: false,
    );
    final back = AppSettings.fromJson(custom.toJson());
    expect(back.toJson(), custom.toJson());
    expect(back.colors.highlight, const Color(0xFF123456));

    // Unknown or missing keys fall back to defaults.
    final partial = AppSettings.fromJson({'cornerRadius': 9, 'bogus': 1});
    expect(partial.cornerRadius, 9);
    expect(partial.colors, const AppSettings().colors);
  });
}
