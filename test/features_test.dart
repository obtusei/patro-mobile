import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nepali_utils/nepali_utils.dart';
import 'package:patro/core/event_qr.dart';
import 'package:patro/models/app_settings.dart';
import 'package:patro/models/patro_day.dart';
import 'package:patro/models/patro_event.dart';
import 'package:patro/providers/events_provider.dart';
import 'package:patro/providers/reminder_sync_provider.dart';
import 'package:patro/providers/settings_provider.dart';
import 'package:patro/providers/storage_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final today = DateTime.utc(2026, 10, 31);
  PatroDay ad(int y, int m, int d) =>
      PatroDay.fromAd(DateTime.utc(y, m, d), today: today);

  group('More repeats', () {
    test('daily and weekly, never before the first date', () {
      final daily = PatroEvent.create(
        date: today,
        title: 'Walk',
        repeat: EventRepeat.daily,
      );
      final weekly = PatroEvent.create(
        date: today,
        title: 'Class',
        repeat: EventRepeat.weekly,
      );
      expect(daily.occursOn(ad(2026, 11, 3)), isTrue);
      expect(daily.occursOn(ad(2026, 10, 30)), isFalse);
      expect(weekly.occursOn(ad(2026, 11, 7)), isTrue);
      expect(weekly.occursOn(ad(2026, 11, 8)), isFalse);
      expect(weekly.occursOn(ad(2026, 10, 24)), isFalse);
    });

    test('monthly AD on the 31st falls on the last day of short months', () {
      final rent = PatroEvent.create(
        date: DateTime.utc(2026, 1, 31),
        title: 'Rent',
        repeat: EventRepeat.monthlyAd,
      );
      expect(rent.occursOn(ad(2026, 2, 28)), isTrue);
      expect(rent.occursOn(ad(2026, 4, 30)), isTrue);
      expect(rent.occursOn(ad(2026, 5, 31)), isTrue);
      expect(rent.occursOn(ad(2026, 5, 30)), isFalse);
    });

    test('monthly BS repeats on the same BS day', () {
      final origin = BsCalendar.toAd(NepaliDateTime(2083, 1, 15));
      final e = PatroEvent.create(
        date: origin,
        title: 'Puja',
        repeat: EventRepeat.monthlyBs,
      );
      PatroDay bs(int y, int m, int d) =>
          PatroDay.fromBs(NepaliDateTime(y, m, d), today: today);
      expect(e.occursOn(bs(2083, 5, 15)), isTrue);
      expect(e.occursOn(bs(2084, 2, 15)), isTrue);
      expect(e.occursOn(bs(2083, 5, 16)), isFalse);
    });

    test('repeat until stops after the last date', () {
      final e = PatroEvent.create(
        date: today,
        title: 'Course',
        repeat: EventRepeat.daily,
        repeatUntil: DateTime.utc(2026, 11, 2),
      );
      expect(e.occursOn(ad(2026, 11, 2)), isTrue);
      expect(e.occursOn(ad(2026, 11, 3)), isFalse);
    });

    test('JSON round-trip keeps the new fields', () {
      final e = PatroEvent.create(
        date: today,
        title: 'Meeting',
        startMinutes: 600,
        endMinutes: 660,
        repeat: EventRepeat.weekly,
        location: 'Patan Durbar Square',
        url: 'https://example.com/m',
        reminders: const [10, 60],
        repeatUntil: DateTime.utc(2027, 1, 1),
      ).copyWith(deviceEventId: () => 'g-1', deviceCalendarId: () => 'cal-1');
      final back = PatroEvent.fromJson(e.toJson());
      expect(back.toJson(), e.toJson());
      expect(back.reminders, [10, 60]);
      expect(back.repeatUntil, DateTime.utc(2027, 1, 1));
      expect(back.deviceEventId, 'g-1');
    });
  });

  test('phone-calendar copies of Patro events are shown once', () {
    final mine = PatroEvent.create(
      date: today,
      title: 'Mine',
    ).copyWith(deviceEventId: () => 'g-1', deviceCalendarId: () => 'cal');
    PatroEvent external(String id, String title) => PatroEvent(
      id: 'calendar-$id',
      date: today,
      title: title,
      calendarName: 'Google',
      deviceEventId: id,
    );
    final state = EventsState(
      [mine],
      external: [external('g-1', 'Mine'), external('g-2', 'Other')],
    );
    expect(state.on(ad(2026, 10, 31)).map((e) => e.title), ['Mine', 'Other']);
    expect(state.on(ad(2026, 10, 31)).first.isExternal, isFalse);
  });

  group('Reminders', () {
    final now = DateTime(2026, 10, 31, 8);

    test('timed and all-day reminders, soonest first', () {
      final meeting = PatroEvent.create(
        date: today,
        title: 'Meeting',
        startMinutes: 10 * 60,
        location: 'Office',
        reminders: const [10, 1440],
      );
      final holiday = PatroEvent.create(
        date: DateTime.utc(2026, 11, 1),
        title: 'Trip',
        reminders: const [-540],
      );
      final due = upcomingReminders([holiday, meeting], now);
      // The day-before reminder for today's meeting has already passed.
      expect(due.map((r) => r.at), [
        DateTime(2026, 10, 31, 9, 50),
        DateTime(2026, 11, 1, 9),
      ]);
      expect(due.first.text, contains('Today'));
      expect(due.first.text, contains('Office'));
    });

    test('events kept in a phone calendar are left to it', () {
      final pushed = PatroEvent.create(
        date: today,
        title: 'Synced',
        startMinutes: 900,
        reminders: const [10],
      ).copyWith(deviceEventId: () => 'g-1');
      expect(upcomingReminders([pushed], now), isEmpty);
    });

    test('repeating events stay within the window and the limit', () {
      final daily = PatroEvent.create(
        date: today,
        title: 'Pills',
        startMinutes: 9 * 60,
        repeat: EventRepeat.daily,
        reminders: const [0],
      );
      final due = upcomingReminders([daily], now, horizonDays: 10, limit: 5);
      expect(due, hasLength(5));
      expect(due.first.at, DateTime(2026, 10, 31, 9));
      expect(due.map((r) => r.key).toSet(), hasLength(5));
    });
  });

  test('QR codes carry location, link and repeats', () {
    final e = PatroEvent.create(
      date: today,
      title: 'Class',
      startMinutes: 420,
      endMinutes: 480,
      repeat: EventRepeat.weekly,
      repeatUntil: DateTime.utc(2026, 12, 31),
      location: 'Hall A; floor 2',
      url: 'https://example.com',
    );
    final back = eventFromQr(eventToQr(e))!;
    expect(back.location, 'Hall A; floor 2');
    expect(back.url, 'https://example.com');
    expect(back.repeat, EventRepeat.weekly);
    expect(back.repeatUntil, DateTime.utc(2026, 12, 31));

    final bs = eventFromQr(
      eventToQr(e.copyWith(repeat: EventRepeat.monthlyBs)),
    )!;
    expect(bs.repeat, EventRepeat.monthlyBs);
  });

  group('Settings', () {
    test('a retired preset leaves its colours as an unsaved set', () {
      final s = AppSettings.fromJson({
        'presetId': 'paper',
        'colors': {'background': 0xFFF3EEE3},
      });
      expect(s.presetId, isNull);
      expect(s.colors.background, const Color(0xFFF3EEE3));
      expect(themePresets.map((p) => p.name), isNot(contains('Moleskine')));
    });

    test('pages, start page and saved themes round-trip', () {
      final theme = ThemePreset(
        '${ThemePreset.customPrefix}x',
        'Dusk',
        AppSettings().colors,
      );
      final s = const AppSettings().copyWith(
        presetId: () => theme.id,
        customThemes: [theme],
        startPage: ShellPage.date,
        showTimeline: false,
        defaultReminder: () => 15,
        eventCalendarId: () => 'cal-1',
        appIcon: 'midnight',
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
      expect(back.presetId, theme.id);
      expect(back.effectiveStartPage, ShellPage.date);

      final hidden = back.copyWith(showDatePage: false);
      expect(hidden.visiblePages, isNot(contains(ShellPage.date)));
      expect(hidden.effectiveStartPage, ShellPage.day);
    });

    test('editing a saved theme updates it; editing a preset does not', () {
      SharedPreferences.setMockInitialValues({});
      return SharedPreferences.getInstance().then((prefs) {
        final c = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(c.dispose);
        final n = c.read(settingsProvider.notifier);

        n.setColor(ColorRole.accent, const Color(0xFF00FF00));
        expect(c.read(settingsProvider).presetId, isNull);

        n.saveCustomTheme('Green');
        final saved = c.read(settingsProvider).customThemes.single;
        expect(c.read(settingsProvider).presetId, saved.id);

        n.setColor(ColorRole.ink, const Color(0xFF123456));
        final s = c.read(settingsProvider);
        expect(s.presetId, saved.id);
        expect(s.customThemes.single.colors.ink, const Color(0xFF123456));

        n.renameCustomTheme(saved.id, 'Forest');
        n.reset();
        expect(c.read(settingsProvider).customThemes.single.name, 'Forest');

        n.applyPreset(c.read(settingsProvider).customThemes.single);
        n.deleteCustomTheme(saved.id);
        expect(c.read(settingsProvider).customThemes, isEmpty);
        expect(c.read(settingsProvider).presetId, isNull);
      });
    });
  });
}
