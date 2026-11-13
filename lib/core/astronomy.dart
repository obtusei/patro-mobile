import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Sun and Moon positions for an observer, and the Hindu panchanga built on
/// them.
///
/// Positions follow Meeus, *Astronomical Algorithms* (ch. 13, 22, 25, 47),
/// truncated to the largest terms: the Sun to ~0.01° and the Moon to ~0.05°
/// in longitude, so rise and set times land within a minute or two and
/// panchanga boundaries within a few minutes. Sidereal (nirayana) longitudes
/// use the Lahiri ayanamsa, as Nepali and Indian almanacs do.

const double _rad = math.pi / 180;
const double _deg = 180 / math.pi;

double _sin(double deg) => math.sin(deg * _rad);
double _cos(double deg) => math.cos(deg * _rad);

/// [x] wrapped to [-180, 180).
double wrap180(double x) => (x + 180) % 360 - 180;

/// A place on Earth. Longitude is east-positive.
@immutable
class GeoLocation {
  const GeoLocation(this.latitude, this.longitude, [this.name = '']);

  static const kathmandu = GeoLocation(27.7172, 85.3240, 'Kathmandu');

  final double latitude;
  final double longitude;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is GeoLocation &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.name == name;

  @override
  int get hashCode => Object.hash(latitude, longitude, name);
}

enum Body { sun, moon }

/// Where a body is at one instant, seen from one place.
@immutable
class BodyPosition {
  const BodyPosition({
    required this.body,
    required this.eclipticLongitude,
    required this.eclipticLatitude,
    required this.rightAscension,
    required this.declination,
    required this.distanceKm,
    required this.altitude,
    required this.geometricAltitude,
    required this.azimuth,
    required this.hourAngle,
    required this.ayanamsa,
  });

  final Body body;

  /// Apparent tropical (sayana) ecliptic longitude, degrees [0, 360).
  final double eclipticLongitude;
  final double eclipticLatitude;

  /// Degrees [0, 360); divide by 15 for hours.
  final double rightAscension;
  final double declination;
  final double distanceKm;

  /// Topocentric altitude including atmospheric refraction: where the body
  /// appears to the eye.
  final double altitude;

  /// Topocentric altitude without refraction, used for rise and set.
  final double geometricAltitude;

  /// Degrees east of true north, [0, 360).
  final double azimuth;

  /// Local hour angle, degrees [-180, 180): negative before the meridian.
  final double hourAngle;
  final double ayanamsa;

  /// Nirayana longitude (Lahiri), degrees [0, 360).
  double get siderealLongitude => (eclipticLongitude - ayanamsa) % 360;

  /// 0 Mesha … 11 Meena.
  int get rashi => siderealLongitude ~/ 30;

  /// Apparent angular diameter in degrees.
  double get angularDiameter =>
      2 * math.asin(_radiusKm / distanceKm) * _deg;

  double get _radiusKm => body == Body.sun ? 696000 : 1737.4;

  bool get isUp => altitude > -angularDiameter / 2;
}

/// Sun and Moon together at one instant.
@immutable
class SkySnapshot {
  const SkySnapshot({
    required this.time,
    required this.location,
    required this.sun,
    required this.moon,
  });

  factory SkySnapshot.at(DateTime time, GeoLocation location) {
    final jd = Astro.julianDay(time);
    return SkySnapshot(
      time: time,
      location: location,
      sun: Astro.position(Body.sun, jd, location),
      moon: Astro.position(Body.moon, jd, location),
    );
  }

  final DateTime time;
  final GeoLocation location;
  final BodyPosition sun;
  final BodyPosition moon;

  /// Moon's longitude ahead of the Sun's, [0, 360): 0 new, 180 full.
  double get elongation =>
      (moon.eclipticLongitude - sun.eclipticLongitude) % 360;

  /// [0, 1): 0 new, 0.5 full; for moon glyphs.
  double get phase => elongation / 360;

  bool get waxing => elongation < 180;

  /// Sun–Moon–Earth angle, degrees.
  double get phaseAngle {
    final psi = math.acos(
      (_cos(moon.eclipticLatitude) *
              _cos(moon.eclipticLongitude - sun.eclipticLongitude))
          .clamp(-1.0, 1.0),
    );
    final r = sun.distanceKm;
    final d = moon.distanceKm;
    return math.atan2(r * math.sin(psi), d - r * math.cos(psi)) * _deg;
  }

  /// Lit fraction of the Moon's disc, [0, 1].
  double get illumination => (1 + _cos(phaseAngle)) / 2;

  /// Days since the last new moon, approximately.
  double get moonAgeDays => elongation / Astro.meanElongationPerDay;

  /// 0 new … 7 waning crescent; see [moonPhaseNames].
  int get phaseIndex {
    final e = elongation;
    if (e < 6 || e >= 354) return 0;
    if (e < 84) return 1;
    if (e < 96) return 2;
    if (e < 174) return 3;
    if (e < 186) return 4;
    if (e < 264) return 5;
    if (e < 276) return 6;
    return 7;
  }

  /// Local sidereal time, degrees.
  double get localSiderealTime =>
      (Astro.gmst(Astro.julianDay(time)) + location.longitude) % 360;
}

const moonPhaseNames = [
  ('औंसी', 'New moon'),
  ('बढ्दो अर्धचन्द्र', 'Waxing crescent'),
  ('प्रथम चौथाइ', 'First quarter'),
  ('बढ्दो उन्नत', 'Waxing gibbous'),
  ('पूर्णिमा', 'Full moon'),
  ('घट्दो उन्नत', 'Waning gibbous'),
  ('अन्तिम चौथाइ', 'Last quarter'),
  ('घट्दो अर्धचन्द्र', 'Waning crescent'),
];

/// Rise, culmination and set within one local day.
@immutable
class RiseSet {
  const RiseSet({
    this.rise,
    this.set,
    this.transit,
    this.transitAltitude,
    this.alwaysUp = false,
  });

  final DateTime? rise;
  final DateTime? set;
  final DateTime? transit;
  final double? transitAltitude;

  /// No rise or set that day, and above the horizon throughout.
  final bool alwaysUp;

  /// Daylight span when [rise] precedes [set].
  Duration? get upFor {
    final r = rise, s = set;
    if (r == null || s == null || !s.isAfter(r)) return null;
    return s.difference(r);
  }
}

/// A body's track across the sky, sampled through a day.
@immutable
class PathPoint {
  const PathPoint(this.time, this.altitude, this.azimuth);

  final DateTime time;
  final double altitude;
  final double azimuth;
}

abstract final class Astro {
  static const double meanElongationPerDay = 12.190749;
  static const double _sunPerDay = 0.98564736;

  static double julianDay(DateTime t) =>
      t.toUtc().millisecondsSinceEpoch / Duration.millisecondsPerDay +
      2440587.5;

  static DateTime fromJulianDay(double jd) =>
      DateTime.fromMillisecondsSinceEpoch(
        ((jd - 2440587.5) * Duration.millisecondsPerDay).round(),
        isUtc: true,
      );

  static double _centuries(double jd) => (jd - 2451545.0) / 36525;

  /// Nutation in longitude, degrees (largest term only).
  static double _nutation(double t) => -0.00478 * _sin(125.04 - 1934.136 * t);

  /// True obliquity of the ecliptic, degrees.
  static double obliquity(double jd) {
    final t = _centuries(jd);
    return 23.439291 -
        0.0130042 * t +
        0.00256 * _cos(125.04 - 1934.136 * t);
  }

  /// Lahiri (Chitrapaksha) ayanamsa, degrees.
  static double ayanamsa(double jd) =>
      23.85306 + 0.0139689 * (jd - 2451545.0) / 365.25;

  /// Apparent geocentric ecliptic position of the Sun.
  static ({double lon, double lat, double distanceKm}) sunEcliptic(
    double jd,
  ) {
    final t = _centuries(jd);
    final l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
    final m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t;
    final e = 0.016708634 - 0.000042037 * t;
    final c =
        (1.914602 - 0.004817 * t - 0.000014 * t * t) * _sin(m) +
        (0.019993 - 0.000101 * t) * _sin(2 * m) +
        0.000289 * _sin(3 * m);
    final nu = m + c;
    final au = 1.000001018 * (1 - e * e) / (1 + e * _cos(nu));
    final lon = l0 + c - 0.00569 + _nutation(t);
    return (lon: lon % 360, lat: 0, distanceKm: au * 149597870.7);
  }

  // Meeus table 47.A: D, M, M', F, Σl (1e-6°), Σr (1e-3 km).
  static const List<List<int>> _moonLr = [
    [0, 0, 1, 0, 6288774, -20905355],
    [2, 0, -1, 0, 1274027, -3699111],
    [2, 0, 0, 0, 658314, -2955968],
    [0, 0, 2, 0, 213618, -569925],
    [0, 1, 0, 0, -185116, 48888],
    [0, 0, 0, 2, -114332, -3149],
    [2, 0, -2, 0, 58793, 246158],
    [2, -1, -1, 0, 57066, -152138],
    [2, 0, 1, 0, 53322, -170733],
    [2, -1, 0, 0, 45758, -204586],
    [0, 1, -1, 0, -40923, -129620],
    [1, 0, 0, 0, -34720, 108743],
    [0, 1, 1, 0, -30383, 104755],
    [2, 0, 0, -2, 15327, 10321],
    [0, 0, 1, 2, -12528, 0],
    [0, 0, 1, -2, 10980, 79661],
    [4, 0, -1, 0, 10675, -34782],
    [0, 0, 3, 0, 10034, -23210],
    [4, 0, -2, 0, 8548, -21636],
    [2, 1, -1, 0, -7888, 24208],
    [2, 1, 0, 0, -6766, 30824],
    [1, 0, -1, 0, -5163, -8379],
    [1, 1, 0, 0, 4987, -16675],
    [2, -1, 1, 0, 4036, -12831],
    [2, 0, 2, 0, 3994, -10445],
    [4, 0, 0, 0, 3861, -11650],
    [2, 0, -3, 0, 3665, 14403],
    [0, 1, -2, 0, -2689, -7003],
    [2, 0, -1, 2, -2602, 0],
    [2, -1, -2, 0, 2390, 10056],
    [1, 0, 1, 0, -2348, 6322],
    [2, -2, 0, 0, 2236, -9884],
  ];

  // Meeus table 47.B: D, M, M', F, Σb (1e-6°).
  static const List<List<int>> _moonB = [
    [0, 0, 0, 1, 5128122],
    [0, 0, 1, 1, 280602],
    [0, 0, 1, -1, 277693],
    [2, 0, 0, -1, 173237],
    [2, 0, -1, 1, 55413],
    [2, 0, -1, -1, 46271],
    [2, 0, 0, 1, 32573],
    [0, 0, 2, 1, 17198],
    [2, 0, 1, -1, 9266],
    [0, 0, 2, -1, 8822],
    [2, -1, 0, -1, 8216],
    [2, 0, -2, -1, 4324],
    [2, 0, 1, 1, 4200],
    [2, 1, 0, -1, -3359],
    [2, -1, -1, 1, 2463],
    [2, -1, 0, 1, 2211],
    [2, -1, -1, -1, 2065],
    [0, 1, -1, -1, -1870],
    [4, 0, -1, -1, 1828],
    [0, 1, 0, 1, -1794],
  ];

  /// Apparent geocentric ecliptic position of the Moon.
  static ({double lon, double lat, double distanceKm}) moonEcliptic(
    double jd,
  ) {
    final t = _centuries(jd);
    final lp = 218.3164477 + 481267.88123421 * t - 0.0015786 * t * t;
    final d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t * t;
    final m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t * t;
    final mp = 134.9633964 + 477198.8675055 * t + 0.0087414 * t * t;
    final f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t * t;
    final e = 1 - 0.002516 * t - 0.0000074 * t * t;
    final a1 = 119.75 + 131.849 * t;
    final a2 = 53.09 + 479264.290 * t;
    final a3 = 313.45 + 481266.484 * t;

    double eFactor(int mCoeff) => switch (mCoeff.abs()) {
      1 => e,
      2 => e * e,
      _ => 1,
    };

    var sl = 0.0, sr = 0.0, sb = 0.0;
    for (final row in _moonLr) {
      final arg = row[0] * d + row[1] * m + row[2] * mp + row[3] * f;
      final k = eFactor(row[1]);
      sl += row[4] * k * _sin(arg);
      sr += row[5] * k * _cos(arg);
    }
    for (final row in _moonB) {
      final arg = row[0] * d + row[1] * m + row[2] * mp + row[3] * f;
      sb += row[4] * eFactor(row[1]) * _sin(arg);
    }
    sl += 3958 * _sin(a1) + 1962 * _sin(lp - f) + 318 * _sin(a2);
    sb +=
        -2235 * _sin(lp) +
        382 * _sin(a3) +
        175 * _sin(a1 - f) +
        175 * _sin(a1 + f) +
        127 * _sin(lp - mp) -
        115 * _sin(lp + mp);

    return (
      lon: (lp + sl / 1e6 + _nutation(t)) % 360,
      lat: sb / 1e6,
      distanceKm: 385000.56 + sr / 1000,
    );
  }

  /// Ecliptic → equatorial, degrees.
  static ({double ra, double dec}) toEquatorial(
    double lon,
    double lat,
    double obliquity,
  ) {
    final ra = math.atan2(
      _sin(lon) * _cos(obliquity) - math.tan(lat * _rad) * _sin(obliquity),
      _cos(lon),
    );
    final dec = math.asin(
      (_sin(lat) * _cos(obliquity) +
              _cos(lat) * _sin(obliquity) * _sin(lon))
          .clamp(-1.0, 1.0),
    );
    return (ra: (ra * _deg) % 360, dec: dec * _deg);
  }

  /// Greenwich mean sidereal time, degrees.
  static double gmst(double jd) {
    final t = _centuries(jd);
    return (280.46061837 +
            360.98564736629 * (jd - 2451545.0) +
            0.000387933 * t * t -
            t * t * t / 38710000) %
        360;
  }

  /// Hour-angle and declination → altitude and azimuth (from north).
  static ({double alt, double az}) hourAngleToHorizontal(
    double hourAngle,
    double dec,
    double latitude,
  ) {
    final alt = math.asin(
      (_sin(latitude) * _sin(dec) +
              _cos(latitude) * _cos(dec) * _cos(hourAngle))
          .clamp(-1.0, 1.0),
    );
    final az = math.atan2(
      -_cos(dec) * _sin(hourAngle),
      _sin(dec) * _cos(latitude) - _cos(dec) * _sin(latitude) * _cos(hourAngle),
    );
    return (alt: alt * _deg, az: (az * _deg) % 360);
  }

  /// Geocentric altitude and azimuth of a point on the sky, no refraction.
  static ({double alt, double az}) equatorialToHorizontal(
    double ra,
    double dec,
    double jd,
    GeoLocation at,
  ) {
    final h = wrap180(gmst(jd) + at.longitude - ra);
    return hourAngleToHorizontal(h, dec, at.latitude);
  }

  /// Where a point on the ecliptic stands in the sky, no refraction.
  static ({double alt, double az}) eclipticToHorizontal(
    double lon,
    double lat,
    double jd,
    GeoLocation at,
  ) {
    final eq = toEquatorial(lon, lat, obliquity(jd));
    return equatorialToHorizontal(eq.ra, eq.dec, jd, at);
  }

  /// Atmospheric refraction for a true altitude, degrees (Sæmundsson).
  static double refraction(double alt) {
    if (alt < -1.5) return 0;
    final h = math.max(alt, -1.0);
    return 1.02 / math.tan((h + 10.3 / (h + 5.11)) * _rad) / 60;
  }

  static BodyPosition position(Body body, double jd, GeoLocation at) {
    final ecl = body == Body.sun ? sunEcliptic(jd) : moonEcliptic(jd);
    final eq = toEquatorial(ecl.lon, ecl.lat, obliquity(jd));
    final h = wrap180(gmst(jd) + at.longitude - eq.ra);
    final hor = hourAngleToHorizontal(h, eq.dec, at.latitude);
    // Seen from the surface rather than the centre of the Earth; matters
    // for the Moon (up to ~1°), negligible for the Sun.
    final parallax = math.asin(6378.14 / ecl.distanceKm) * _deg;
    final geometric = hor.alt - parallax * _cos(hor.alt);
    return BodyPosition(
      body: body,
      eclipticLongitude: ecl.lon,
      eclipticLatitude: ecl.lat,
      rightAscension: eq.ra,
      declination: eq.dec,
      distanceKm: ecl.distanceKm,
      altitude: geometric + refraction(geometric),
      geometricAltitude: geometric,
      azimuth: hor.az,
      hourAngle: h,
      ayanamsa: ayanamsa(jd),
    );
  }

  /// Rise, transit and set between [dayStart] and 24 hours later.
  static RiseSet riseSet(Body body, DateTime dayStart, GeoLocation at) {
    final jd0 = julianDay(dayStart);
    // Standard altitudes of the upper limb touching the horizon, refraction
    // included.
    double target(BodyPosition p) => body == Body.sun
        ? -0.8333
        : -0.5667 - p.angularDiameter / 2;
    double f(double jd) {
      final p = position(body, jd, at);
      return p.geometricAltitude - target(p);
    }

    double bisect(double a, double b, double Function(double) g) {
      var lo = a, hi = b;
      final rising = g(a) < 0;
      for (var i = 0; i < 22; i++) {
        final mid = (lo + hi) / 2;
        if ((g(mid) < 0) == rising) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      return (lo + hi) / 2;
    }

    double ha(double jd) => position(body, jd, at).hourAngle;

    const step = 10 / 1440;
    double? rise, set, transit;
    var a = jd0;
    var fa = f(a);
    var ha0 = ha(a);
    var anyUp = fa > 0;
    for (var i = 1; i <= 144; i++) {
      final b = jd0 + i * step;
      final fb = f(b);
      final hb = ha(b);
      if (fb > 0) anyUp = true;
      if (fa < 0 && fb >= 0) rise ??= bisect(a, b, f);
      if (fa >= 0 && fb < 0) set ??= bisect(a, b, f);
      // The meridian: hour angle passing from negative to positive (not the
      // ±180° wrap).
      if (ha0 < 0 && hb >= 0 && hb - ha0 < 90) transit ??= bisect(a, b, ha);
      a = b;
      fa = fb;
      ha0 = hb;
    }
    return RiseSet(
      rise: rise == null ? null : fromJulianDay(rise),
      set: set == null ? null : fromJulianDay(set),
      transit: transit == null ? null : fromJulianDay(transit),
      transitAltitude: transit == null
          ? null
          : position(body, transit, at).altitude,
      alwaysUp: rise == null && set == null && anyUp,
    );
  }

  /// [body]'s track from [dayStart] for 24 hours, every [minutes].
  static List<PathPoint> path(
    Body body,
    DateTime dayStart,
    GeoLocation at, {
    int minutes = 10,
  }) {
    final jd0 = julianDay(dayStart);
    return [
      for (var m = 0; m <= 1440; m += minutes)
        () {
          final jd = jd0 + m / 1440;
          final p = position(body, jd, at);
          return PathPoint(fromJulianDay(jd), p.altitude, p.azimuth);
        }(),
    ];
  }

  /// Sidereal longitudes of Sun and Moon, and their elongation.
  static ({double sun, double moon, double elongation}) _sidereal(double jd) {
    final ayan = ayanamsa(jd);
    final s = sunEcliptic(jd).lon;
    final m = moonEcliptic(jd).lon;
    return (
      sun: (s - ayan) % 360,
      moon: (m - ayan) % 360,
      elongation: (m - s) % 360,
    );
  }

  /// Moon–Sun elongation, degrees [0, 360).
  static double elongation(double jd) => _sidereal(jd).elongation;

  /// Next instant after [jd] at which [index] changes value, within
  /// [maxDays]; to ~20 seconds.
  static DateTime? _nextChange(
    int Function(double jd) index,
    double jd, {
    required double stepDays,
    required double maxDays,
  }) {
    final i0 = index(jd);
    var a = jd;
    for (var b = jd + stepDays; b <= jd + maxDays; b += stepDays) {
      if (index(b) != i0) {
        var lo = a, hi = b;
        while (hi - lo > 20 / 86400) {
          final mid = (lo + hi) / 2;
          if (index(mid) == i0) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        return fromJulianDay(hi);
      }
      a = b;
    }
    return null;
  }

  /// The first instant at or after [jd] when the elongation reaches
  /// [target] degrees (0 new moon, 180 full).
  static double _nextElongation(double jd, double target) {
    var t = jd + ((target - elongation(jd)) % 360) / meanElongationPerDay;
    for (var i = 0; i < 5; i++) {
      t -= wrap180(elongation(t) - target) / meanElongationPerDay;
    }
    return t;
  }

  /// The new moon that opened the lunar month containing [jd].
  static double _previousNewMoon(double jd) {
    var t = jd - elongation(jd) / meanElongationPerDay;
    for (var i = 0; i < 5; i++) {
      t -= wrap180(elongation(t)) / meanElongationPerDay;
    }
    return t;
  }

  static double _siderealSun(double jd) => _sidereal(jd).sun;
}

/// The five limbs of the day (tithi, vara, nakshatra, yoga, karana) and the
/// solar and lunar context around them, at one instant.
@immutable
class Panchanga {
  const Panchanga({
    required this.time,
    required this.tithi,
    required this.tithiProgress,
    required this.tithiEnds,
    required this.nakshatra,
    required this.pada,
    required this.nakshatraProgress,
    required this.nakshatraEnds,
    required this.yoga,
    required this.yogaEnds,
    required this.karana,
    required this.karanaEnds,
    required this.sunRashi,
    required this.moonRashi,
    required this.moonRashiEnds,
    required this.weekday,
    required this.uttarayana,
    required this.ritu,
    required this.lunarMonth,
    required this.adhikaMasa,
    required this.nextSankranti,
    required this.nextSankrantiRashi,
    required this.nextPurnima,
    required this.nextAunsi,
    required this.ayanamsa,
    this.rahuKaal,
    this.abhijit,
  });

  /// [sun] is the Sun's rise and set on the local day of [time], for Rahu
  /// Kaal and Abhijit muhurta.
  factory Panchanga.at(DateTime time, {RiseSet? sun}) {
    final jd = Astro.julianDay(time);
    final sid = Astro._sidereal(jd);
    const nakSpan = 360 / 27;

    int tithiOf(double t) => Astro._sidereal(t).elongation ~/ 12;
    int karanaOf(double t) => Astro._sidereal(t).elongation ~/ 6;
    int nakshatraOf(double t) => Astro._sidereal(t).moon ~/ nakSpan;
    int moonRashiOf(double t) => Astro._sidereal(t).moon ~/ 30;
    int yogaOf(double t) {
      final s = Astro._sidereal(t);
      return ((s.sun + s.moon) % 360) ~/ nakSpan;
    }

    const step = 1 / 48; // 30 minutes
    final sunRashi = sid.sun ~/ 30;

    // Lunar month (amanta): named for the rashi the Sun occupies at its
    // opening new moon; Sun in Meena opens Chaitra. When two new moons fall
    // in one rashi, the first month is adhika (intercalary).
    final newMoon = Astro._previousNewMoon(jd);
    final nextNewMoon = Astro._nextElongation(newMoon + 25, 0);
    final rashiAtNewMoon = Astro._siderealSun(newMoon) ~/ 30;
    final rashiAtNext = Astro._siderealSun(nextNewMoon) ~/ 30;

    final sankrantiTarget = (sunRashi + 1) * 30.0;
    var sankranti =
        jd + ((sankrantiTarget - sid.sun) % 360) / Astro._sunPerDay;
    for (var i = 0; i < 4; i++) {
      sankranti -=
          wrap180(Astro._siderealSun(sankranti) - sankrantiTarget) /
          Astro._sunPerDay;
    }

    (DateTime, DateTime)? rahu, abhijit;
    final rise = sun?.rise, set = sun?.set;
    if (rise != null && set != null && set.isAfter(rise)) {
      final part = set.difference(rise) ~/ 8;
      // Eighth of the daytime ruled by Rahu, by weekday (Monday = 1).
      const segment = {7: 7, 1: 1, 2: 6, 3: 4, 4: 5, 5: 3, 6: 2};
      final start = rise.add(part * segment[time.toLocal().weekday]!);
      rahu = (start, start.add(part));
      final muhurta = set.difference(rise) ~/ 15;
      final a = rise.add(muhurta * 7);
      abhijit = (a, a.add(muhurta));
    }

    return Panchanga(
      time: time,
      tithi: sid.elongation ~/ 12,
      tithiProgress: (sid.elongation % 12) / 12,
      tithiEnds: Astro._nextChange(tithiOf, jd, stepDays: step, maxDays: 2),
      nakshatra: sid.moon ~/ nakSpan,
      pada: ((sid.moon % nakSpan) / (nakSpan / 4)).floor() + 1,
      nakshatraProgress: (sid.moon % nakSpan) / nakSpan,
      nakshatraEnds: Astro._nextChange(
        nakshatraOf,
        jd,
        stepDays: step,
        maxDays: 2,
      ),
      yoga: ((sid.sun + sid.moon) % 360) ~/ nakSpan,
      yogaEnds: Astro._nextChange(yogaOf, jd, stepDays: step, maxDays: 2),
      karana: sid.elongation ~/ 6,
      karanaEnds: Astro._nextChange(karanaOf, jd, stepDays: step, maxDays: 1),
      sunRashi: sunRashi,
      moonRashi: sid.moon ~/ 30,
      moonRashiEnds: Astro._nextChange(
        moonRashiOf,
        jd,
        stepDays: 1 / 12,
        maxDays: 3,
      ),
      weekday: time.toLocal().weekday % 7,
      // Makar Sankranti to Karka Sankranti, as reckoned in Nepal.
      uttarayana: sid.sun >= 270 || sid.sun < 90,
      ritu: ((sunRashi + 1) % 12) ~/ 2,
      lunarMonth: (rashiAtNewMoon + 1) % 12,
      adhikaMasa: rashiAtNewMoon == rashiAtNext,
      nextSankranti: Astro.fromJulianDay(sankranti),
      nextSankrantiRashi: (sunRashi + 1) % 12,
      nextPurnima: Astro.fromJulianDay(Astro._nextElongation(jd, 180)),
      nextAunsi: Astro.fromJulianDay(Astro._nextElongation(jd + 0.01, 0)),
      ayanamsa: Astro.ayanamsa(jd),
      rahuKaal: rahu,
      abhijit: abhijit,
    );
  }

  final DateTime time;

  /// 0–29: 0 Shukla Pratipada, 14 Purnima, 29 Aunsi.
  final int tithi;
  final double tithiProgress;
  final DateTime? tithiEnds;

  /// 0 Ashwini … 26 Revati.
  final int nakshatra;

  /// Quarter of the nakshatra, 1–4.
  final int pada;
  final double nakshatraProgress;
  final DateTime? nakshatraEnds;

  /// 0 Vishkambha … 26 Vaidhriti.
  final int yoga;
  final DateTime? yogaEnds;

  /// Half-tithi, 0–59; see [karanaName].
  final int karana;
  final DateTime? karanaEnds;

  /// 0 Mesha … 11 Meena.
  final int sunRashi;
  final int moonRashi;
  final DateTime? moonRashiEnds;

  /// 0 Sunday … 6 Saturday.
  final int weekday;

  /// The Sun's northward half-year, from Makar Sankranti.
  final bool uttarayana;

  /// 0 Basanta … 5 Shishir.
  final int ritu;

  /// Amanta lunar month: 0 Chaitra … 11 Phalguna.
  final int lunarMonth;
  final bool adhikaMasa;
  final DateTime nextSankranti;
  final int nextSankrantiRashi;
  final DateTime nextPurnima;
  final DateTime nextAunsi;
  final double ayanamsa;

  /// Inauspicious eighth of the daytime; null when the Sun does not both
  /// rise and set.
  final (DateTime, DateTime)? rahuKaal;

  /// The midday muhurta.
  final (DateTime, DateTime)? abhijit;

  bool get shukla => tithi < 15;
}

/// Karana for half-tithi [index] (0–59): four fixed karanas at the ends of
/// the month, seven movable ones cycling between.
(String, String) karanaName(int index) {
  if (index == 0) return ('किंस्तुघ्न', 'Kimstughna');
  if (index == 57) return ('शकुनि', 'Shakuni');
  if (index == 58) return ('चतुष्पद', 'Chatushpada');
  if (index == 59) return ('नाग', 'Naga');
  const movable = [
    ('बव', 'Bava'),
    ('बालव', 'Balava'),
    ('कौलव', 'Kaulava'),
    ('तैतिल', 'Taitila'),
    ('गर', 'Gara'),
    ('वणिज', 'Vanija'),
    ('विष्टि', 'Vishti'),
  ];
  return movable[(index - 1) % 7];
}

const rashiNames = [
  ('मेष', 'Mesha', '♈'),
  ('वृष', 'Vrisha', '♉'),
  ('मिथुन', 'Mithuna', '♊'),
  ('कर्कट', 'Karkata', '♋'),
  ('सिंह', 'Simha', '♌'),
  ('कन्या', 'Kanya', '♍'),
  ('तुला', 'Tula', '♎'),
  ('वृश्चिक', 'Vrishchika', '♏'),
  ('धनु', 'Dhanu', '♐'),
  ('मकर', 'Makara', '♑'),
  ('कुम्भ', 'Kumbha', '♒'),
  ('मीन', 'Meena', '♓'),
];

const nakshatraNames = [
  ('अश्विनी', 'Ashwini'),
  ('भरणी', 'Bharani'),
  ('कृत्तिका', 'Krittika'),
  ('रोहिणी', 'Rohini'),
  ('मृगशिरा', 'Mrigashira'),
  ('आर्द्रा', 'Ardra'),
  ('पुनर्वसु', 'Punarvasu'),
  ('पुष्य', 'Pushya'),
  ('आश्लेषा', 'Ashlesha'),
  ('मघा', 'Magha'),
  ('पूर्वाफाल्गुनी', 'Purva Phalguni'),
  ('उत्तराफाल्गुनी', 'Uttara Phalguni'),
  ('हस्त', 'Hasta'),
  ('चित्रा', 'Chitra'),
  ('स्वाती', 'Swati'),
  ('विशाखा', 'Vishakha'),
  ('अनुराधा', 'Anuradha'),
  ('ज्येष्ठा', 'Jyeshtha'),
  ('मूल', 'Mula'),
  ('पूर्वाषाढा', 'Purva Ashadha'),
  ('उत्तराषाढा', 'Uttara Ashadha'),
  ('श्रवण', 'Shravana'),
  ('धनिष्ठा', 'Dhanishtha'),
  ('शतभिषा', 'Shatabhisha'),
  ('पूर्वभाद्रपदा', 'Purva Bhadrapada'),
  ('उत्तरभाद्रपदा', 'Uttara Bhadrapada'),
  ('रेवती', 'Revati'),
];

const yogaNames = [
  ('विष्कम्भ', 'Vishkambha'),
  ('प्रीति', 'Priti'),
  ('आयुष्मान्', 'Ayushman'),
  ('सौभाग्य', 'Saubhagya'),
  ('शोभन', 'Shobhana'),
  ('अतिगण्ड', 'Atiganda'),
  ('सुकर्मा', 'Sukarma'),
  ('धृति', 'Dhriti'),
  ('शूल', 'Shula'),
  ('गण्ड', 'Ganda'),
  ('वृद्धि', 'Vriddhi'),
  ('ध्रुव', 'Dhruva'),
  ('व्याघात', 'Vyaghata'),
  ('हर्षण', 'Harshana'),
  ('वज्र', 'Vajra'),
  ('सिद्धि', 'Siddhi'),
  ('व्यतीपात', 'Vyatipata'),
  ('वरीयान्', 'Variyan'),
  ('परिघ', 'Parigha'),
  ('शिव', 'Shiva'),
  ('सिद्ध', 'Siddha'),
  ('साध्य', 'Sadhya'),
  ('शुभ', 'Shubha'),
  ('शुक्ल', 'Shukla'),
  ('ब्रह्म', 'Brahma'),
  ('इन्द्र', 'Indra'),
  ('वैधृति', 'Vaidhriti'),
];

/// Indexed by [Panchanga.weekday] (Sunday first).
const varaNames = [
  ('आइतबार', 'Ravivara · Sun'),
  ('सोमबार', 'Somavara · Moon'),
  ('मंगलबार', 'Mangalavara · Mars'),
  ('बुधबार', 'Budhavara · Mercury'),
  ('बिहीबार', 'Guruvara · Jupiter'),
  ('शुक्रबार', 'Shukravara · Venus'),
  ('शनिबार', 'Shanivara · Saturn'),
];

const rituNames = [
  ('वसन्त', 'Basanta · spring'),
  ('ग्रीष्म', 'Grishma · summer'),
  ('वर्षा', 'Barsha · monsoon'),
  ('शरद्', 'Sharad · autumn'),
  ('हेमन्त', 'Hemanta · pre-winter'),
  ('शिशिर', 'Shishir · winter'),
];

const lunarMonthNames = [
  ('चैत्र', 'Chaitra'),
  ('वैशाख', 'Vaishakha'),
  ('ज्येष्ठ', 'Jyeshtha'),
  ('आषाढ', 'Ashadha'),
  ('श्रावण', 'Shravana'),
  ('भाद्र', 'Bhadra'),
  ('आश्विन', 'Ashwin'),
  ('कार्तिक', 'Kartik'),
  ('मार्गशीर्ष', 'Margashirsha'),
  ('पौष', 'Pausha'),
  ('माघ', 'Magha'),
  ('फाल्गुन', 'Phalguna'),
];

const _tithiEnglish = [
  'Pratipada', 'Dwitiya', 'Tritiya', 'Chaturthi', 'Panchami', //
  'Shashthi', 'Saptami', 'Ashtami', 'Navami', 'Dashami', //
  'Ekadashi', 'Dwadashi', 'Trayodashi', 'Chaturdashi', //
];

/// Romanised tithi name, e.g. "Shukla Panchami".
String tithiEnglishName(int index) {
  if (index == 14) return 'Purnima';
  if (index == 29) return 'Aunsi';
  return '${index < 15 ? 'Shukla' : 'Krishna'} ${_tithiEnglish[index % 15]}';
}

/// Rise and set times and the day's paths of both bodies, for the local day
/// containing an instant. Computed once and reused while time ticks.
@immutable
class SkyDay {
  SkyDay(this.start, this.location)
    : sun = Astro.riseSet(Body.sun, start, location),
      moon = Astro.riseSet(Body.moon, start, location),
      sunPath = Astro.path(Body.sun, start, location),
      moonPath = Astro.path(Body.moon, start, location);

  /// Local midnight of the day containing [time].
  static DateTime startOf(DateTime time) {
    final l = time.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  final DateTime start;
  final GeoLocation location;
  final RiseSet sun;
  final RiseSet moon;
  final List<PathPoint> sunPath;
  final List<PathPoint> moonPath;

  bool covers(DateTime time, GeoLocation at) =>
      at == location && startOf(time) == start;
}
