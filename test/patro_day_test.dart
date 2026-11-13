import 'package:flutter_test/flutter_test.dart';
import 'package:nepali_utils/nepali_utils.dart';
import 'package:patro/models/patro_day.dart';

void main() {
  final today = DateTime.utc(2026, 10, 23);

  group('BsCalendar', () {
    test('known New Year dates', () {
      expect(BsCalendar.toAd(NepaliDateTime(2081)), DateTime.utc(2024, 4, 13));
      expect(BsCalendar.toAd(NepaliDateTime(2082)), DateTime.utc(2025, 4, 14));
      final bs = BsCalendar.fromAd(DateTime.utc(2025, 4, 14));
      expect([bs.year, bs.month, bs.day], [2082, 1, 1]);
    });

    test('round-trips every day across the supported range', () {
      var ad = BsCalendar.firstSupportedAd;
      var expected = NepaliDateTime(BsCalendar.minYear);
      while (true) {
        final bs = BsCalendar.fromAd(ad);
        expect(
          [bs.year, bs.month, bs.day],
          [expected.year, expected.month, expected.day],
        );
        expect(BsCalendar.toAd(bs), ad);
        if (ad == BsCalendar.lastSupportedAd) break;
        ad = ad.add(const Duration(days: 1));
        expected = expected.day < expected.totalDays
            ? NepaliDateTime(expected.year, expected.month, expected.day + 1)
            : expected.month < 12
            ? NepaliDateTime(expected.year, expected.month + 1)
            : NepaliDateTime(expected.year + 1);
      }
      expect(
        [expected.year, expected.month, expected.day],
        [BsCalendar.maxYear, 12, expected.totalDays],
      );
      expect(
        BsCalendar.isSupportedAd(ad.add(const Duration(days: 1))),
        isFalse,
      );
    });

    test('ignores local time and timezone', () {
      final a = BsCalendar.fromAd(DateTime(2026, 7, 15, 23, 59));
      final b = BsCalendar.fromAd(DateTime.utc(2026, 7, 15));
      expect([a.year, a.month, a.day], [b.year, b.month, b.day]);
    });
  });

  group('PatroDay', () {
    test('flags today and Saturdays', () {
      final day = PatroDay.fromAd(DateTime(2026, 10, 23), today: today);
      expect(day.isToday, isTrue);
      expect(
        PatroDay.fromAd(DateTime.utc(2026, 10, 24), today: today).isSaturday,
        isTrue,
      );
    });

    test('fixed BS holidays', () {
      final day = PatroDay.fromBs(NepaliDateTime(2083, 6, 3), today: today);
      expect(day.events, contains('Constitution Day'));
      expect(day.isPublicHoliday, isTrue);
    });

    // Dates from the 2082 BS government holiday list.
    final lunarFestivals = {
      'Janai Purnima': DateTime.utc(2025, 8, 9),
      'Krishna Janmashtami': DateTime.utc(2025, 8, 16),
      'Haritalika Teej': DateTime.utc(2025, 8, 26),
      'Ghatasthapana': DateTime.utc(2025, 9, 22),
      'Vijaya Dashami': DateTime.utc(2025, 10, 2),
      'Laxmi Puja': DateTime.utc(2025, 10, 21),
      'Bhai Tika': DateTime.utc(2025, 10, 23),
      'Maha Shivaratri': DateTime.utc(2026, 2, 15),
    };
    for (final MapEntry(key: name, value: date) in lunarFestivals.entries) {
      test('$name falls on ${date.toIso8601String().substring(0, 10)}', () {
        expect(PatroDay.fromAd(date, today: today).events, contains(name));
        for (final offset in [-1, 1]) {
          final neighbour = date.add(Duration(days: offset));
          expect(
            PatroDay.fromAd(neighbour, today: today).events,
            isNot(contains(name)),
          );
        }
      });
    }
  });
}
