import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/astronomy.dart';
import 'common.dart';

const double _rad = math.pi / 180;

/// A direction or point in the observer's frame: x east, y north, z up.
@immutable
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  /// Unit vector toward altitude [alt] and azimuth [az], degrees.
  factory Vec3.sky(double alt, double az) {
    final ca = math.cos(alt * _rad);
    return Vec3(
      ca * math.sin(az * _rad),
      ca * math.cos(az * _rad),
      math.sin(alt * _rad),
    );
  }

  static const zero = Vec3(0, 0, 0);
  static const up = Vec3(0, 0, 1);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  Vec3 get normalized {
    final l = length;
    return l == 0 ? this : this * (1 / l);
  }

  /// Altitude of this direction, degrees.
  double get altitude => math.asin((z / length).clamp(-1.0, 1.0)) / _rad;

  /// Azimuth of this direction, degrees east of north.
  double get azimuth => (math.atan2(x, y) / _rad) % 360;
}

/// Maps the observer's frame onto the screen.
abstract class SkyProjector {
  SkyProjector(this.size);

  final Size size;

  /// Whether the eye stands at the observer, as in AR, rather than looking
  /// at the dome from outside.
  bool get immersive;

  /// [p] in camera space: x right, y up, z forward.
  Vec3 cameraSpace(Vec3 p);

  double get focal;
  Offset get center;

  /// Screen point for [p], or null when it is behind the eye.
  Offset? project(Vec3 p) {
    final c = cameraSpace(p);
    if (c.z < 0.02) return null;
    return center + Offset(c.x / c.z * focal, -c.y / c.z * focal);
  }

  /// How far back [p] sits, 0 near … 1 far; used to fade the far side.
  double depth(Vec3 p) => 0;
}

/// Looks at the sky dome from outside, orbiting around it.
class OrbitProjector extends SkyProjector {
  OrbitProjector(
    super.size, {
    required double yaw,
    required double pitch,
    required double zoom,
  }) : _distance = 3.4 / zoom {
    final cp = math.cos(pitch * _rad);
    _eye = Vec3(
      _distance * cp * math.sin(yaw * _rad),
      _distance * cp * math.cos(yaw * _rad),
      _distance * math.sin(pitch * _rad),
    );
    const target = Vec3(0, 0, 0.22);
    _forward = (target - _eye).normalized;
    _right = _forward.cross(Vec3.up).normalized;
    _up = _right.cross(_forward);
  }

  final double _distance;
  late final Vec3 _eye, _forward, _right, _up;

  @override
  bool get immersive => false;

  @override
  double get focal => size.shortestSide * 1.25;

  @override
  Offset get center => Offset(size.width / 2, size.height * 0.52);

  @override
  Vec3 cameraSpace(Vec3 p) {
    final v = p - _eye;
    return Vec3(v.dot(_right), v.dot(_up), v.dot(_forward));
  }

  @override
  double depth(Vec3 p) =>
      ((cameraSpace(p).z - (_distance - 1.1)) / 2.2).clamp(0.0, 1.0);
}

/// Looks out from the observer along the phone's back camera.
class DeviceProjector extends SkyProjector {
  /// [east], [north] and [up] are the world axes in device coordinates
  /// (x right, y toward the top of the screen, z out of the screen).
  DeviceProjector(
    super.size, {
    required this.east,
    required this.north,
    required this.up,
    this.verticalFov = 62,
  });

  final Vec3 east;
  final Vec3 north;
  final Vec3 up;
  final double verticalFov;

  @override
  bool get immersive => true;

  @override
  double get focal =>
      size.height / 2 / math.tan(verticalFov / 2 * _rad);

  @override
  Offset get center => size.center(Offset.zero);

  @override
  Vec3 cameraSpace(Vec3 p) {
    final d = east * p.x + north * p.y + up * p.z;
    // The back camera looks along -z.
    return Vec3(d.x, d.y, -d.z);
  }

  /// Where the back camera points.
  Vec3 get pointing => Vec3(-east.z, -north.z, -up.z);
}

/// Fixed colours: the scene always sits on a sky or a camera image, so the
/// theme's colours would not read.
abstract final class SkyColors {
  static const sun = Color(0xFFFFB547);
  static const sunPath = Color(0xFFFFA14D);
  static const moon = Color(0xFFF1F0FF);
  static const moonPath = Color(0xFFB9C6FF);
  static const ecliptic = Color(0xFFFFD86B);
  static const equator = Color(0xFF6FD3FF);
  static const grid = Colors.white;
  static const ground = Color(0xFF7FA37B);
  static const north = Color(0xFFFF7A70);

  /// Background gradient for a Sun at [altitude] degrees.
  static List<Color> sky(double altitude) {
    const night = [Color(0xFF050814), Color(0xFF111A35)];
    const twilight = [Color(0xFF1A2350), Color(0xFF7A5A86)];
    const day = [Color(0xFF2F68A8), Color(0xFF8DBDE6)];
    List<Color> mix(List<Color> a, List<Color> b, double t) => [
      Color.lerp(a[0], b[0], t)!,
      Color.lerp(a[1], b[1], t)!,
    ];
    if (altitude <= -18) return night;
    if (altitude <= -4) return mix(night, twilight, (altitude + 18) / 14);
    if (altitude <= 8) return mix(twilight, day, (altitude + 4) / 12);
    return day;
  }
}

/// Everything the scene draws, computed outside the painter.
@immutable
class SkySceneData {
  const SkySceneData({
    required this.snapshot,
    required this.sunPath,
    required this.moonPath,
    required this.nepali,
    required this.timeLabel,
    this.focus = Body.sun,
    this.digits = _plain,
  });

  static String _plain(String s) => s;

  final SkySnapshot snapshot;
  final List<PathPoint> sunPath;
  final List<PathPoint> moonPath;
  final bool nepali;

  /// Short clock label for hour marks along the paths.
  final String Function(DateTime) timeLabel;

  /// Converts numerals for display (Devanagari digits).
  final String Function(String) digits;

  /// The body whose coordinates get full guides.
  final Body focus;
}

/// The sky as a 3D scene: horizon and compass, altitude rings, celestial
/// equator and pole, the ecliptic divided into the twelve rashis, today's
/// paths of the Sun and Moon, and both bodies with their coordinates.
class SkyScenePainter extends CustomPainter {
  SkyScenePainter({
    required this.data,
    required this.projectorFor,
    this.showPointer = false,
  });

  final SkySceneData data;
  final SkyProjector Function(Size size) projectorFor;

  /// Draws a centre reticle and arrows toward off-screen bodies (AR).
  final bool showPointer;

  late SkyProjector _p;
  late Canvas _c;
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    _p = projectorFor(size);
    _c = canvas;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    if (!_p.immersive) _ground();
    _grid();
    _compass();
    _equator();
    _ecliptic();
    _path(data.sunPath, SkyColors.sunPath);
    _path(data.moonPath, SkyColors.moonPath);
    final sun = data.snapshot.sun;
    final moon = data.snapshot.moon;
    // The unfocused body first, so the focused one draws on top.
    final order = data.focus == Body.sun ? [moon, sun] : [sun, moon];
    for (final b in order) {
      _guides(b, focused: b.body == data.focus);
    }
    for (final b in order) {
      _body(b);
    }
    if (!_p.immersive) _observer();
    if (showPointer) _pointer([sun, moon]);
    canvas.restore();
  }

  // Primitives --------------------------------------------------------------

  String _t(String nepali, String english) => data.nepali ? nepali : english;

  /// Strokes [points], fading the far side and dashing what lies below the
  /// horizon.
  void _stroke(
    List<Vec3> points,
    Color color, {
    double width = 1.2,
    double opacity = 1,
    bool dashed = false,
    bool dimBelow = true,
  }) {
    final jump = _p.size.longestSide * 0.9;
    _line.strokeWidth = width;
    Offset? prev;
    for (var i = 0; i < points.length; i++) {
      final v = points[i];
      final o = _p.project(v);
      if (prev != null && o != null && (o - prev).distance < jump) {
        final below = dimBelow && v.z < -1e-6 && points[i - 1].z < -1e-6;
        final skip = (dashed || below) && i.isOdd;
        if (!skip) {
          final fade = 1 - 0.6 * _p.depth(v);
          final a = opacity * fade * (below ? 0.35 : 1);
          _line.color = color.withValues(alpha: a.clamp(0.0, 1.0));
          _c.drawLine(prev, o, _line);
        }
      }
      prev = o;
    }
  }

  void _text(
    String text,
    Offset at, {
    Color color = Colors.white,
    double size = 11,
    FontWeight weight = FontWeight.w600,
    Alignment anchor = Alignment.center,
    Color? pill,
    double opacity = 1,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withValues(alpha: opacity),
          fontSize: size,
          fontWeight: weight,
          height: 1.15,
          shadows: pill == null
              ? const [Shadow(blurRadius: 4, color: Color(0xCC000000))]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final topLeft =
        at -
        Offset(
          (anchor.x + 1) / 2 * tp.width,
          (anchor.y + 1) / 2 * tp.height,
        );
    if (pill != null) {
      final r = RRect.fromRectAndRadius(
        (topLeft & tp.size).inflate(4),
        const Radius.circular(6),
      );
      _c.drawRRect(r, Paint()..color = pill.withValues(alpha: 0.72 * opacity));
    }
    tp.paint(_c, topLeft);
  }

  /// A circle at altitude [alt], as a list of points.
  List<Vec3> _ring(double alt, {double step = 3, double radius = 1}) => [
    for (var az = 0.0; az <= 360; az += step) Vec3.sky(alt, az) * radius,
  ];

  // Layers ------------------------------------------------------------------

  void _ground() {
    final horizon = [
      for (var az = 0.0; az < 360; az += 4) _p.project(Vec3.sky(0, az)),
    ];
    if (horizon.any((o) => o == null)) return;
    final path = Path()..addPolygon(horizon.cast<Offset>(), true);
    final center = _p.project(Vec3.zero)!;
    _c.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          colors: [
            SkyColors.ground.withValues(alpha: 0.34),
            SkyColors.ground.withValues(alpha: 0.12),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 200)),
    );
    // Rings and a cross on the ground plane.
    for (final r in [0.33, 0.66]) {
      _stroke(
        _ring(0, radius: r),
        SkyColors.grid,
        width: 0.8,
        opacity: 0.16,
        dimBelow: false,
      );
    }
    for (final az in [0.0, 90.0]) {
      _stroke(
        [Vec3.sky(0, az), Vec3.sky(0, az + 180)],
        SkyColors.grid,
        width: 0.8,
        opacity: 0.16,
        dimBelow: false,
      );
    }
  }

  void _grid() {
    // Horizon.
    _stroke(_ring(0, step: 2), SkyColors.grid, width: 1.6, opacity: 0.7);
    // Altitude rings.
    for (final alt in [30.0, 60.0]) {
      _stroke(_ring(alt), SkyColors.grid, width: 0.8, opacity: 0.2);
      final at = _p.project(Vec3.sky(alt, _labelAzimuth));
      if (at != null) {
        _text(
          data.digits('${alt.round()}°'),
          at,
          size: 9,
          opacity: 0.55,
          anchor: Alignment.bottomCenter,
        );
      }
    }
    if (_p.immersive) {
      _stroke(_ring(-30), SkyColors.grid, width: 0.6, opacity: 0.12);
    }
    // Meridians every 30°, horizon to zenith.
    for (var az = 0.0; az < 360; az += 30) {
      _stroke(
        [for (var alt = 0.0; alt <= 90; alt += 3) Vec3.sky(alt, az)],
        SkyColors.grid,
        width: 0.7,
        opacity: az % 90 == 0 ? 0.24 : 0.12,
      );
    }
    final zenith = _p.project(Vec3.up);
    if (zenith != null && _p.immersive) {
      _text(_t('शिरोबिन्दु', 'Zenith'), zenith, size: 9, opacity: 0.6);
    }
  }

  /// Azimuth for ring labels: away from the camera in orbit, so they read.
  double get _labelAzimuth {
    if (_p.immersive) return (_p as DeviceProjector).pointing.azimuth;
    // The point on the horizon nearest the eye; label the far side.
    final near = [for (var az = 0; az < 360; az += 45) az].reduce(
      (a, b) =>
          _p.cameraSpace(Vec3.sky(0, a.toDouble())).z <
              _p.cameraSpace(Vec3.sky(0, b.toDouble())).z
          ? a
          : b,
    );
    return (near + 180) % 360.0;
  }

  void _compass() {
    const english = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    const nepali = ['उत्तर', '', 'पूर्व', '', 'दक्षिण', '', 'पश्चिम', ''];
    for (var az = 0; az < 360; az += 10) {
      final major = az % 90 == 0;
      final mid = az % 30 == 0;
      final len = major ? 0.07 : (mid ? 0.045 : 0.025);
      final a = _p.immersive
          ? Vec3.sky(len * 40, az.toDouble())
          : Vec3.sky(0, az.toDouble()) * (1 + len);
      _stroke(
        [Vec3.sky(0, az.toDouble()), a],
        az == 0 ? SkyColors.north : SkyColors.grid,
        width: major ? 1.6 : 1,
        opacity: major ? 0.9 : 0.5,
        dimBelow: false,
      );
      if (az % 45 == 0) {
        final i = az ~/ 45;
        final name = data.nepali ? nepali[i] : english[i];
        if (name.isEmpty) continue;
        final at = _p.project(
          _p.immersive
              ? Vec3.sky(5, az.toDouble())
              : Vec3.sky(0, az.toDouble()) * 1.17,
        );
        if (at != null) {
          _text(
            name,
            at,
            size: major ? 13 : 10,
            weight: major ? FontWeight.w800 : FontWeight.w600,
            color: az == 0 ? SkyColors.north : Colors.white,
            opacity: major ? 1 : 0.7,
            anchor: _p.immersive ? Alignment.bottomCenter : Alignment.center,
          );
        }
      } else if (_p.immersive && az % 30 == 0) {
        final at = _p.project(Vec3.sky(3, az.toDouble()));
        if (at != null) {
          _text(
            data.digits('$az°'),
            at,
            size: 9,
            opacity: 0.6,
            anchor: Alignment.bottomCenter,
          );
        }
      }
    }
  }

  void _equator() {
    final lat = data.snapshot.location.latitude;
    final pts = [
      for (var h = -180.0; h <= 180; h += 3)
        () {
          final hor = Astro.hourAngleToHorizontal(h, 0, lat);
          return Vec3.sky(hor.alt, hor.az);
        }(),
    ];
    _stroke(pts, SkyColors.equator, width: 1, opacity: 0.55, dashed: true);
    // The celestial pole, Dhruva, stands at the latitude's altitude.
    final poleAlt = lat.abs();
    final poleAz = lat >= 0 ? 0.0 : 180.0;
    final pole = Vec3.sky(poleAlt, poleAz);
    _stroke(
      [Vec3.zero, pole],
      SkyColors.equator,
      width: 0.8,
      opacity: _p.immersive ? 0 : 0.35,
      dashed: true,
    );
    final at = _p.project(pole);
    if (at != null) {
      _c.drawCircle(at, 3, Paint()..color = SkyColors.equator);
      _text(
        _t('ध्रुव', 'Pole'),
        at + const Offset(0, -6),
        size: 9,
        color: SkyColors.equator,
        anchor: Alignment.bottomCenter,
      );
    }
    // Label the equator where it crosses the meridian.
    final eqTop = Astro.hourAngleToHorizontal(0, 0, lat);
    final eqAt = _p.project(Vec3.sky(eqTop.alt, eqTop.az));
    if (eqAt != null) {
      _text(
        _t('विषुवत् वृत्त', 'Celestial equator'),
        eqAt + const Offset(0, 8),
        size: 9,
        color: SkyColors.equator,
        opacity: 0.8,
        anchor: Alignment.topCenter,
      );
    }
  }

  void _ecliptic() {
    final snap = data.snapshot;
    final jd = Astro.julianDay(snap.time);
    final ayan = snap.sun.ayanamsa;
    final loc = snap.location;
    Vec3 at(double tropicalLon) {
      final h = Astro.eclipticToHorizontal(tropicalLon, 0, jd, loc);
      return Vec3.sky(h.alt, h.az);
    }

    _stroke(
      [for (var l = 0.0; l <= 360; l += 2) at(l)],
      SkyColors.ecliptic,
      width: 1.4,
      opacity: 0.75,
    );
    for (var r = 0; r < 12; r++) {
      final boundary = at(r * 30 + ayan);
      final o = _p.project(boundary);
      if (o != null) {
        _c.drawCircle(
          o,
          2.2,
          Paint()
            ..color = SkyColors.ecliptic.withValues(
              alpha: boundary.z < 0 ? 0.3 : 0.9,
            ),
        );
      }
      final mid = at(r * 30 + 15 + ayan);
      final m = _p.project(mid);
      if (m == null) continue;
      final (ne, en, glyph) = rashiNames[r];
      final occupied = snap.sun.rashi == r || snap.moon.rashi == r;
      _text(
        '$glyph ${data.nepali ? ne : en}',
        m,
        size: occupied ? 11 : 9.5,
        weight: occupied ? FontWeight.w800 : FontWeight.w600,
        color: SkyColors.ecliptic,
        opacity: mid.z < 0 ? 0.35 : (occupied ? 1 : 0.75),
        anchor: Alignment.bottomCenter,
      );
    }
  }

  void _path(List<PathPoint> path, Color color) {
    if (path.isEmpty) return;
    _stroke(
      [for (final p in path) Vec3.sky(p.altitude, p.azimuth)],
      color,
      width: 1.6,
      opacity: 0.8,
    );
    // Hour marks; labels every hour in AR, every three in orbit.
    final every = _p.immersive ? 1 : 3;
    for (final p in path) {
      final t = p.time.toLocal();
      if (t.minute != 0 || p.altitude < -2) continue;
      final o = _p.project(Vec3.sky(p.altitude, p.azimuth));
      if (o == null) continue;
      _c.drawCircle(o, 2, Paint()..color = color.withValues(alpha: 0.9));
      if (t.hour % every == 0) {
        _text(
          data.timeLabel(p.time),
          o + const Offset(5, 0),
          size: 8.5,
          color: color,
          opacity: 0.85,
          anchor: Alignment.centerLeft,
        );
      }
    }
  }

  Color _colorOf(Body b) => b == Body.sun ? SkyColors.sun : SkyColors.moon;

  /// Lines tying a body to the horizon and the compass: its azimuth on the
  /// ground and its altitude above it.
  void _guides(BodyPosition b, {required bool focused}) {
    final color = _colorOf(b.body);
    final dir = Vec3.sky(b.altitude, b.azimuth);
    final foot = Vec3.sky(0, b.azimuth);
    final opacity = focused ? 0.9 : 0.4;

    // Drop line along the vertical circle, body to horizon.
    _stroke(
      [
        for (var i = 0; i <= 24; i++)
          Vec3.sky(b.altitude * (1 - i / 24), b.azimuth),
      ],
      color,
      width: focused ? 1.3 : 0.9,
      opacity: opacity,
      dashed: true,
      dimBelow: false,
    );
    final footAt = _p.project(foot);
    if (footAt != null) {
      _c.drawCircle(footAt, 2.6, Paint()..color = color.withValues(alpha: opacity));
    }

    if (_p.immersive) {
      if (focused && footAt != null) {
        _text(
          data.digits('${b.azimuth.toStringAsFixed(1)}°'),
          footAt + const Offset(0, 6),
          size: 10,
          color: color,
          anchor: Alignment.topCenter,
          pill: Colors.black,
        );
      }
      return;
    }

    // Ray from the observer, and its shadow on the ground.
    _stroke(
      [for (var i = 0; i <= 12; i++) dir * (i / 12)],
      color,
      width: 1,
      opacity: opacity * 0.8,
      dashed: true,
      dimBelow: false,
    );
    _stroke(
      [for (var i = 0; i <= 12; i++) foot * (i / 12)],
      color,
      width: 0.9,
      opacity: opacity * 0.6,
      dimBelow: false,
    );
    if (!focused) return;

    // Azimuth arc on the ground, from north round to the body.
    const azR = 0.3;
    final azArc = [
      for (var a = 0.0; a <= b.azimuth; a += 3) Vec3.sky(0, a) * azR,
      Vec3.sky(0, b.azimuth) * azR,
    ];
    _stroke(azArc, color, width: 1.6, opacity: 0.95, dimBelow: false);
    final azLabel = _p.project(Vec3.sky(0, b.azimuth / 2) * (azR + 0.08));
    if (azLabel != null) {
      _text(
        data.digits('${_t('दिगंश', 'Az')} ${b.azimuth.toStringAsFixed(1)}°'),
        azLabel,
        size: 10,
        color: color,
        pill: Colors.black,
      );
    }

    // Altitude arc in the body's vertical plane.
    const altR = 0.5;
    final altArc = [
      for (var i = 0; i <= 16; i++)
        Vec3.sky(b.altitude * i / 16, b.azimuth) * altR,
    ];
    _stroke(altArc, color, width: 1.6, opacity: 0.95, dimBelow: false);
    final altLabel = _p.project(
      Vec3.sky(b.altitude / 2, b.azimuth) * (altR + 0.1),
    );
    if (altLabel != null) {
      _text(
        data.digits('${_t('उन्नतांश', 'Alt')} ${b.altitude.toStringAsFixed(1)}°'),
        altLabel,
        size: 10,
        color: color,
        pill: Colors.black,
      );
    }
  }

  void _body(BodyPosition b) {
    final dir = Vec3.sky(b.altitude, b.azimuth);
    final o = _p.project(dir);
    if (o == null) return;
    final below = b.altitude < -b.angularDiameter / 2;
    final r = _p.immersive
        ? 13.0
        : (10 * (1.25 - 0.5 * _p.depth(dir))).clamp(6.0, 14.0);

    if (b.body == Body.sun) {
      _c.drawCircle(
        o,
        r * 3.2,
        Paint()
          ..shader = RadialGradient(
            colors: [
              SkyColors.sun.withValues(alpha: below ? 0.15 : 0.55),
              SkyColors.sun.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: o, radius: r * 3.2)),
      );
      _c.drawCircle(
        o,
        r,
        Paint()..color = SkyColors.sun.withValues(alpha: below ? 0.45 : 1),
      );
    } else {
      _c.drawCircle(
        o,
        r * 2.2,
        Paint()
          ..shader = RadialGradient(
            colors: [
              SkyColors.moon.withValues(alpha: below ? 0.06 : 0.25),
              SkyColors.moon.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: o, radius: r * 2.2)),
      );
      // Turn the lit limb toward the Sun.
      final angle = _towardSun(dir, o);
      _c.save();
      _c.translate(o.dx, o.dy);
      _c.rotate(angle);
      final phase = data.snapshot.phase;
      paintMoonPhase(
        _c,
        Offset.zero,
        r,
        math.min(phase, 1 - phase),
        lit: SkyColors.moon,
        dark: const Color(0xFF8890A8),
        litAlpha: below ? 0.4 : 0.95,
      );
      _c.restore();
    }
    if (_p.immersive) {
      _c.drawCircle(
        o,
        r + 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _colorOf(b.body).withValues(alpha: 0.8),
      );
    }

    final name = b.body == Body.sun ? _t('सूर्य', 'Sun') : _t('चन्द्र', 'Moon');
    final coords = data.digits(
      '${b.altitude.toStringAsFixed(1)}° · ${b.azimuth.toStringAsFixed(1)}°',
    );
    _text(
      '$name\n$coords',
      o + Offset(r + 6, 0),
      size: 10.5,
      weight: FontWeight.w700,
      color: _colorOf(b.body),
      anchor: Alignment.centerLeft,
      pill: Colors.black,
      opacity: below ? 0.7 : 1,
    );
  }

  /// Screen angle from the Moon toward the Sun, for the lit limb.
  double _towardSun(Vec3 moonDir, Offset moonAt) {
    final s = data.snapshot.sun;
    final sunDir = Vec3.sky(s.altitude, s.azimuth);
    final tangent = (sunDir - moonDir * moonDir.dot(sunDir)).normalized;
    // A point a few degrees from the Moon along the great circle to the Sun.
    final near = moonDir * math.cos(4 * _rad) + tangent * math.sin(4 * _rad);
    final o = _p.project(near);
    if (o == null) return 0;
    final d = o - moonAt;
    return math.atan2(d.dy, d.dx);
  }

  void _observer() {
    final o = _p.project(Vec3.zero);
    if (o == null) return;
    _c.drawCircle(o, 5, Paint()..color = Colors.white);
    _c.drawCircle(
      o,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  void _pointer(List<BodyPosition> bodies) {
    final size = _p.size;
    final center = size.center(Offset.zero);
    final reticle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.85);
    _c.drawCircle(center, 18, reticle);
    for (final d in const [
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
    ]) {
      _c.drawLine(center + d * 24, center + d * 34, reticle);
    }

    // Arrows at the screen edge toward bodies out of view.
    final bounds = (Offset.zero & size).deflate(28);
    for (final b in bodies) {
      final dir = Vec3.sky(b.altitude, b.azimuth);
      final o = _p.project(dir);
      if (o != null && bounds.contains(o)) continue;
      final cam = _p.cameraSpace(dir);
      var v = Offset(cam.x, -cam.y);
      if (v.distance < 1e-6) v = const Offset(0, -1);
      v = v / v.distance;
      // Walk from the centre along v to the edge of [bounds].
      final tx = v.dx.abs() < 1e-6
          ? double.infinity
          : (v.dx > 0 ? bounds.right - center.dx : center.dx - bounds.left) /
                v.dx.abs();
      final ty = v.dy.abs() < 1e-6
          ? double.infinity
          : (v.dy > 0 ? bounds.bottom - center.dy : center.dy - bounds.top) /
                v.dy.abs();
      final edge = center + v * math.min(tx, ty);
      final color = _colorOf(b.body);
      final angle = math.atan2(v.dy, v.dx);
      _c.save();
      _c.translate(edge.dx, edge.dy);
      _c.rotate(angle);
      _c.drawPath(
        Path()
          ..moveTo(12, 0)
          ..lineTo(-6, -9)
          ..lineTo(-2, 0)
          ..lineTo(-6, 9)
          ..close(),
        Paint()..color = color,
      );
      _c.restore();
      _text(
        b.body == Body.sun ? _t('सूर्य', 'Sun') : _t('चन्द्र', 'Moon'),
        edge - v * 22,
        size: 10,
        color: color,
        pill: Colors.black,
      );
    }
  }

  @override
  bool shouldRepaint(SkyScenePainter old) => true;
}
