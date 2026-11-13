import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:nepali_utils/nepali_utils.dart';

/// One day on the Patro timeline: a Bikram Sambat date, its Gregorian
/// equivalent, the tithi prevailing at sunrise and any observances.
@immutable
class PatroDay {
  const PatroDay({
    required this.bsDate,
    required this.adDate,
    required this.tithi,
    required this.tithiIndex,
    required this.events,
    this.observances = const [],
    required this.isToday,
    required this.isPublicHoliday,
  });

  /// Builds a day from a Gregorian date. Only the calendar date is used;
  /// time and timezone are discarded.
  ///
  /// [extra] are observances published on the Patro server; one with the
  /// same name as a built-in observance replaces it.
  factory PatroDay.fromAd(
    DateTime ad, {
    required DateTime today,
    List<Observance> extra = const [],
  }) {
    final adDate = BsCalendar.dateOnly(ad);
    return PatroDay._resolve(BsCalendar.fromAd(adDate), adDate, today, extra);
  }

  /// Builds a day from a Bikram Sambat date.
  factory PatroDay.fromBs(
    NepaliDateTime bs, {
    required DateTime today,
    List<Observance> extra = const [],
  }) {
    final bsDate = NepaliDateTime(bs.year, bs.month, bs.day);
    return PatroDay._resolve(bsDate, BsCalendar.toAd(bsDate), today, extra);
  }

  factory PatroDay._resolve(
    NepaliDateTime bsDate,
    DateTime adDate,
    DateTime today,
    List<Observance> extra,
  ) {
    final sunrise = Lunar.julianDay(Lunar.sunriseUtc(adDate));
    final tithiIndex = Lunar.tithiAt(sunrise);
    final published = {for (final o in extra) o.name.toLowerCase()};
    final observances = [
      for (final o in PatroObservances.resolve(bsDate, adDate))
        if (!published.contains(o.name.toLowerCase())) o,
      ...extra,
    ];

    return PatroDay(
      bsDate: bsDate,
      adDate: adDate,
      tithi: Lunar.tithiName(tithiIndex),
      tithiIndex: tithiIndex,
      events: [for (final o in observances) o.name],
      observances: observances,
      isToday: adDate == BsCalendar.dateOnly(today),
      isPublicHoliday: observances.any((o) => o.isHoliday),
    );
  }

  final NepaliDateTime bsDate;

  /// Gregorian calendar date, normalised to UTC midnight so date math is
  /// immune to DST transitions.
  final DateTime adDate;

  /// Nepali tithi label, e.g. "शुक्ल पञ्चमी".
  final String tithi;

  /// 0–29: 0 is Shukla Pratipada, 14 Purnima, 29 Aunsi.
  final int tithiIndex;

  /// Festival and holiday names; see [observances] for holiday flags.
  final List<String> events;
  final List<Observance> observances;
  final bool isToday;
  final bool isPublicHoliday;

  /// Saturday is the weekly public holiday in Nepal. NepaliDateTime numbers
  /// weekdays Sunday = 1 … Saturday = 7.
  bool get isSaturday => bsDate.weekday == 7;

  bool get isRestDay => isSaturday || isPublicHoliday;
  bool get isFirstOfMonth => bsDate.day == 1;

  /// Moon phase in [0, 1): 0 new, 0.5 full.
  double get moonPhase => (tithiIndex + 0.5) / 30;

  String get dayNumeral => NepaliUnicode.convert('${bsDate.day}');
  String get yearNumeral => NepaliUnicode.convert('${bsDate.year}');
  String get monthName => bsDate.format('MMMM', Language.nepali);
  String get weekdayName => bsDate.format('EEE', Language.nepali);

  @override
  String toString() =>
      'PatroDay(${bsDate.year}-${bsDate.month}-${bsDate.day} BS, '
      '${adDate.toIso8601String().substring(0, 10)} AD, $tithi, $events)';
}

/// Timezone-safe Bikram Sambat conversions.
///
/// `DateTime.toNepaliDateTime()` from nepali_utils diffs *local* DateTimes
/// against a 1913 reference, which is off by one day in DST-observing
/// timezones (e.g. New York in summer). Here all day counting happens in UTC
/// and only the library's month-length tables are used.
abstract final class BsCalendar {
  static const int minYear = 1970;
  static const int maxYear = 2250;

  /// AD 1913-04-13 is BS 1970-01-01.
  static final DateTime firstSupportedAd = DateTime.utc(1913, 4, 13);
  static final DateTime lastSupportedAd = firstSupportedAd.add(
    Duration(days: _yearStartDays.last - 1),
  );

  /// Days from [firstSupportedAd] to 1 Baishakh of each year, plus one
  /// trailing entry for the end of [maxYear].
  static final List<int> _yearStartDays = () {
    final starts = <int>[0];
    for (var y = minYear; y <= maxYear; y++) {
      starts.add(starts.last + NepaliDateTime(y).totalDaysInYear);
    }
    return starts;
  }();

  static DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static bool isSupportedAd(DateTime ad) {
    final d = dateOnly(ad);
    return !d.isBefore(firstSupportedAd) && !d.isAfter(lastSupportedAd);
  }

  static NepaliDateTime fromAd(DateTime ad) {
    var remaining = dateOnly(ad).difference(firstSupportedAd).inDays;
    if (remaining < 0 || remaining >= _yearStartDays.last) {
      throw RangeError('$ad is outside BS $minYear–$maxYear');
    }

    var yearIndex = 0;
    while (_yearStartDays[yearIndex + 1] <= remaining) {
      yearIndex++;
    }
    final year = minYear + yearIndex;
    remaining -= _yearStartDays[yearIndex];

    var month = 1;
    var monthLength = NepaliDateTime(year, month).totalDays;
    while (remaining >= monthLength) {
      remaining -= monthLength;
      month++;
      monthLength = NepaliDateTime(year, month).totalDays;
    }
    return NepaliDateTime(year, month, remaining + 1);
  }

  static NepaliDateTime? tryFromAd(DateTime ad) =>
      isSupportedAd(ad) ? fromAd(ad) : null;

  static DateTime toAd(NepaliDateTime bs) {
    // toDateTime() is pure calendar arithmetic, so only its fields are kept.
    final local = NepaliDateTime(bs.year, bs.month, bs.day).toDateTime();
    return DateTime.utc(local.year, local.month, local.day);
  }
}

/// Low-precision lunar ephemeris (Meeus, ch. 25 & 47), accurate to roughly
/// 0.2° of elongation, i.e. tithi boundaries within ~25 minutes. Good enough
/// for display; swap in a panchanga feed for liturgical use.
abstract final class Lunar {
  static const double _rad = math.pi / 180;
  static const double _meanElongationPerDay = 12.190749;

  static const List<String> _tithiNames = [
    'प्रतिपदा', 'द्वितीया', 'तृतीया', 'चतुर्थी', 'पञ्चमी', //
    'षष्ठी', 'सप्तमी', 'अष्टमी', 'नवमी', 'दशमी', //
    'एकादशी', 'द्वादशी', 'त्रयोदशी', 'चतुर्दशी', //
  ];

  static double julianDay(DateTime utc) =>
      utc.millisecondsSinceEpoch / Duration.millisecondsPerDay + 2440587.5;

  static DateTime _fromJulianDay(double jd) =>
      DateTime.fromMillisecondsSinceEpoch(
        ((jd - 2440587.5) * Duration.millisecondsPerDay).round(),
        isUtc: true,
      );

  /// Approximate Kathmandu sunrise for [adDate], returned in UTC. Ranges from
  /// ~05:08 NPT in June to ~06:52 NPT in January.
  static DateTime sunriseUtc(DateTime adDate) {
    final date = BsCalendar.dateOnly(adDate);
    final dayOfYear = date.difference(DateTime.utc(date.year)).inDays;
    final hoursNpt =
        6.0 + 0.87 * math.cos(2 * math.pi * (dayOfYear + 10) / 365.25);
    return date.add(Duration(minutes: (hoursNpt * 60).round() - 345));
  }

  /// Midnight NPT at the end of [adDate] (the night of that day), in UTC.
  static DateTime midnightUtc(DateTime adDate) =>
      BsCalendar.dateOnly(adDate).add(const Duration(hours: 18, minutes: 15));

  /// Moon–Sun elongation in degrees, [0, 360).
  static double elongation(double jd) {
    final t = (jd - 2451545.0) / 36525;
    final d = (297.8501921 + 445267.1114034 * t) * _rad;
    final m = (357.5291092 + 35999.0502909 * t) * _rad;
    final mp = (134.9633964 + 477198.8675055 * t) * _rad;
    final f = (93.2720950 + 483202.0175233 * t) * _rad;

    final moon =
        218.3164477 +
        481267.88123421 * t +
        6.288774 * math.sin(mp) +
        1.274027 * math.sin(2 * d - mp) +
        0.658314 * math.sin(2 * d) +
        0.213618 * math.sin(2 * mp) -
        0.185116 * math.sin(m) -
        0.114332 * math.sin(2 * f) +
        0.058793 * math.sin(2 * d - 2 * mp) +
        0.057066 * math.sin(2 * d - m - mp) +
        0.053322 * math.sin(2 * d + mp) +
        0.045758 * math.sin(2 * d - m) -
        0.040923 * math.sin(m - mp) -
        0.034720 * math.sin(d) -
        0.030383 * math.sin(m + mp);
    final sun =
        280.46646 +
        36000.76983 * t +
        (1.914602 - 0.004817 * t) * math.sin(m) +
        0.019993 * math.sin(2 * m) +
        0.000289 * math.sin(3 * m);

    return (moon - sun) % 360;
  }

  static int tithiAt(double jd) => (elongation(jd) / 12).floor().clamp(0, 29);

  /// The amanta lunar month at [jd], expressed as the BS solar month (1–12)
  /// in which its opening new moon fell. Lunar Ashwin starts with the new
  /// moon while the Sun is in Kanya, i.e. during BS Ashwin. Returns 0 if
  /// that new moon is outside the supported range.
  static int lunarMonthAt(double jd) {
    var t = jd - elongation(jd) / _meanElongationPerDay;
    for (var i = 0; i < 4; i++) {
      var e = elongation(t);
      if (e > 180) e -= 360;
      t -= e / _meanElongationPerDay;
    }
    final nepalDate = _fromJulianDay(
      t,
    ).add(const Duration(hours: 5, minutes: 45));
    return BsCalendar.tryFromAd(nepalDate)?.month ?? 0;
  }

  static String tithiName(int index) {
    if (index == 14) return 'पूर्णिमा';
    if (index == 29) return 'औंसी';
    final paksha = index < 15 ? 'शुक्ल' : 'कृष्ण';
    return '$paksha ${_tithiNames[index % 15]}';
  }
}

/// The moment at which a lunar observance's tithi is reckoned.
enum Reckoning {
  /// Udaya tithi: the tithi prevailing at sunrise. The default.
  sunrise,

  /// Nishita: the tithi prevailing at midnight (Shivaratri, Janmashtami).
  midnight;

  DateTime instantOn(DateTime adDate) => switch (this) {
    sunrise => Lunar.sunriseUtc(adDate),
    midnight => Lunar.midnightUtc(adDate),
  };
}

@immutable
class Observance {
  const Observance(
    this.name, {
    this.isHoliday = false,
    this.reckoning = Reckoning.sunrise,
  });

  final String name;
  final bool isHoliday;
  final Reckoning reckoning;
}

/// Placeholder festival and holiday registry. Lunar festivals are derived
/// from the computed tithi; the government gazette announces the official
/// dates each year, so replace these tables with that feed in production.
abstract final class PatroObservances {
  /// Keyed by `bsMonth * 100 + bsDay`.
  static const Map<int, Observance> _bsFixed = {
    101: Observance('Nepali New Year', isHoliday: true),
    215: Observance('Republic Day', isHoliday: true),
    401: Observance('Saune Sankranti'),
    603: Observance('Constitution Day', isHoliday: true),
    927: Observance('Prithvi Jayanti', isHoliday: true),
    1001: Observance('Maghe Sankranti', isHoliday: true),
    1016: Observance('Martyrs\' Day'),
    1107: Observance('Democracy Day', isHoliday: true),
  };

  /// Keyed by `adMonth * 100 + adDay`.
  static const Map<int, Observance> _adFixed = {
    308: Observance('International Women\'s Day'),
    501: Observance('Labour Day'),
    1225: Observance('Christmas', isHoliday: true),
  };

  /// Keyed by `lunarMonth * 100 + tithiIndex` (see [Lunar.lunarMonthAt]).
  static const Map<int, Observance> _lunar = {
    114: Observance('Buddha Jayanti', isHoliday: true),
    414: Observance('Janai Purnima', isHoliday: true),
    415: Observance('Gai Jatra'),
    422: Observance(
      'Krishna Janmashtami',
      isHoliday: true,
      reckoning: Reckoning.midnight,
    ),
    502: Observance('Haritalika Teej', isHoliday: true),
    600: Observance('Ghatasthapana', isHoliday: true),
    606: Observance('Fulpati', isHoliday: true),
    607: Observance('Maha Ashtami', isHoliday: true),
    608: Observance('Maha Navami', isHoliday: true),
    609: Observance('Vijaya Dashami', isHoliday: true),
    614: Observance('Kojagrat Purnima'),
    629: Observance('Laxmi Puja', isHoliday: true),
    700: Observance('Govardhan Puja', isHoliday: true),
    701: Observance('Bhai Tika', isHoliday: true),
    705: Observance('Chhath', isHoliday: true),
    1028: Observance(
      'Maha Shivaratri',
      isHoliday: true,
      reckoning: Reckoning.midnight,
    ),
    1114: Observance('Fagu Purnima', isHoliday: true),
    1208: Observance('Ram Navami', isHoliday: true),
  };

  static List<Observance> resolve(NepaliDateTime bsDate, DateTime adDate) {
    return [
      ?_bsFixed[bsDate.month * 100 + bsDate.day],
      ?_adFixed[adDate.month * 100 + adDate.day],
      for (final reckoning in Reckoning.values)
        ..._lunarObservances(adDate, reckoning),
    ];
  }

  static Iterable<Observance> _lunarObservances(
    DateTime adDate,
    Reckoning reckoning,
  ) sync* {
    final at = Lunar.julianDay(reckoning.instantOn(adDate));
    final lunarMonth = Lunar.lunarMonthAt(at);
    if (lunarMonth == 0) return;

    final tithi = Lunar.tithiAt(at);
    final prevTithi = Lunar.tithiAt(
      Lunar.julianDay(
        reckoning.instantOn(adDate.subtract(const Duration(days: 1))),
      ),
    );

    final keys = [
      // A tithi spanning two reckoning instants (vriddhi) is observed on the
      // first day only.
      if (tithi != prevTithi) lunarMonth * 100 + tithi,
      // A tithi that falls between two instants (kshaya) is folded into the
      // day on which it begins and ends.
      if ((tithi - prevTithi) % 30 == 2)
        (tithi == 0 ? (lunarMonth + 10) % 12 + 1 : lunarMonth) * 100 +
            (tithi + 29) % 30,
    ];
    for (final key in keys) {
      final o = _lunar[key];
      if (o != null && o.reckoning == reckoning) yield o;
    }
  }
}
