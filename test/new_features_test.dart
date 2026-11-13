import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patro/models/app_settings.dart';
import 'package:patro/models/patro_day.dart';
import 'package:patro/providers/remote_sync_provider.dart';
import 'package:patro/services/patro_api.dart';
import 'package:patro/theme/patro_style.dart';

void main() {
  final today = DateTime.utc(2026, 11, 7);

  test('indicator, weekly holidays and server settings round-trip', () {
    final s = const AppSettings().copyWith(
      dayIndicator: DayIndicator.dots,
      weekendDays: [7, 6, 6],
      onlineEvents: false,
      serverUrl: 'https://example.com',
    );
    final back = AppSettings.fromJson(s.toJson());
    expect(back.dayIndicator, DayIndicator.dots);
    expect(back.weekendDays, [6, 7]);
    expect(back.weekendPresetLabel, 'Friday & Saturday');
    expect(back.onlineEvents, isFalse);
    expect(back.serverUrl, 'https://example.com');

    // Defaults: faded marks, Saturday off, the Patro server.
    const d = AppSettings();
    expect(d.dayIndicator, DayIndicator.faded);
    expect(d.yearColumns, 2);
    expect(AppSettings.fromJson({'yearColumns': 3}).yearColumns, 3);
    expect(AppSettings.fromJson({'yearColumns': 5}).yearColumns, 2);
    expect(d.weekendDays, [7]);
    expect(d.serverUrl, defaultServerUrl);
    expect(AppSettings.fromJson({'weekendDays': 'bogus'}).weekendDays, [7]);
  });

  test('weekly holidays follow the setting', () {
    final style = PatroStyle.fromSettings(
      const AppSettings().copyWith(weekendDays: [1]),
    );
    // 2026-11-07 is a Saturday, 2026-11-08 a Sunday.
    final saturday = PatroDay.fromAd(DateTime.utc(2026, 11, 7), today: today);
    final sunday = PatroDay.fromAd(DateTime.utc(2026, 11, 8), today: today);
    expect(style.isWeekend(saturday), isFalse);
    expect(style.isWeekend(sunday), isTrue);
    expect(style.dayColor(sunday), style.holiday);
    expect(style.isWeekendColumn(0), isTrue);
    expect(style.isWeekendColumn(6), isFalse);
  });

  test('server items parse and become observances and events', () {
    final items = [
      for (final json in [
        {
          'id': 'h1',
          'date': '2026-11-08',
          'title': 'Gazetted Holiday',
          'kind': 'holiday',
        },
        {
          'id': 'e1',
          'date': '2026-11-09',
          'title': 'Town hall',
          'kind': 'event',
          'startMinutes': 600,
          'endMinutes': 660,
          'color': '#4A80F0',
        },
        {'id': 'bad'},
      ])
        ?RemoteItem.fromJson(json),
    ];
    expect(items, hasLength(2));
    final state = RemoteSyncState(items: items);
    final holiday = state.observances[DateTime.utc(2026, 11, 8)]!.single;
    expect(holiday.isHoliday, isTrue);
    final event = state.events.single;
    expect(event.title, 'Town hall');
    expect(event.isExternal, isTrue);
    expect(event.color, const Color(0xFF4A80F0));
    expect(RemoteItem.fromJson(items[1].toJson())!.color, event.color);

    // Published observances join the day and replace same-named built-ins.
    final day = PatroDay.fromAd(
      DateTime.utc(2026, 11, 8),
      today: today,
      extra: [holiday],
    );
    expect(day.isPublicHoliday, isTrue);
    expect(day.observances.map((o) => o.name), contains('Gazetted Holiday'));
  });
}
