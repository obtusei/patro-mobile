import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/astronomy.dart';
import '../providers/calendar_provider.dart';
import '../providers/settings_provider.dart';
import '../services/compass_sensor.dart';
import '../theme/patro_style.dart';
import '../widgets/common.dart';
import '../widgets/sky_scene.dart';
import 'sky_page.dart' show SkyFormat;

const double _rad = math.pi / 180;

/// A compass in the manner of the iPhone's: a dial that turns under a fixed
/// heading line, a spirit level in the middle, and the Sun and Moon marked
/// where they are. Tap the dial to lock a bearing; a red arc then shows how
/// far you have turned from it. Turned off and on in Settings.
class CompassPage extends ConsumerStatefulWidget {
  const CompassPage({super.key});

  @override
  ConsumerState<CompassPage> createState() => _CompassPageState();
}

class _CompassPageState extends ConsumerState<CompassPage> {
  final _compass = CompassSensor();
  late final AppLifecycleListener _lifecycle;
  bool _resumed = true;

  /// A bearing the user locked; null when unlocked.
  double? _locked;

  /// The last 30° sector, for a haptic tick on crossing into a new one.
  int? _sector;

  /// Refreshes the Sun and Moon markers.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        final resumed = state == AppLifecycleState.resumed;
        if (resumed != _resumed && mounted) setState(() => _resumed = resumed);
      },
    );
    _compass.axes.addListener(_tick);
    _compass.error.addListener(_rebuild);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    _compass.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Runs the sensors and the clock only while the page is on screen.
  void _setActive(bool on) {
    if (on && !_compass.running) {
      _compass.start();
      _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _rebuild());
    } else if (!on && _compass.running) {
      _compass.stop();
      _ticker?.cancel();
      _ticker = null;
      _sector = null;
    }
  }

  void _tick() {
    final axes = _compass.axes.value;
    if (axes == null) return;
    final sector = ((headingOf(axes) + 15) % 360) ~/ 30;
    if (_sector != null &&
        sector != _sector &&
        ref.read(settingsProvider).haptics) {
      unawaited(
        sector % 3 == 0
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.selectionClick(),
      );
    }
    _sector = sector;
  }

  void _toggleLock() {
    final axes = _compass.axes.value;
    if (axes == null) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() => _locked = _locked == null ? headingOf(axes) : null);
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final active = ref.watch(shellPageProvider) == ShellPage.compass;
    _setActive(active && _resumed);

    final location = ref.watch(settingsProvider.select((x) => x.skyLocation));
    final now = DateTime.now();
    final snap = SkySnapshot.at(now, location);
    final f = SkyFormat(context, s, now);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 12, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: s.hairline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PatroLogo(),
                    const SizedBox(height: 4),
                    Text(
                      f.w('कम्पास', 'Compass'),
                      style: s.monthTitle.copyWith(fontSize: 28),
                    ),
                    Row(
                      children: [
                        Icon(Icons.place_outlined, size: 13, color: s.inkMuted),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            location.name.isEmpty
                                ? f.coords(location)
                                : '${location.name.toUpperCase()} · '
                                      '${f.coords(location)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: s.mono,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<DeviceAxes?>(
            valueListenable: _compass.axes,
            builder: (context, axes, _) {
              if (axes == null) {
                return _Waiting(
                  format: f,
                  failed: _compass.error.value != null,
                );
              }
              return _Dial(
                heading: headingOf(axes),
                level: levelOf(axes),
                locked: _locked,
                snap: snap,
                format: f,
                onTap: _toggleLock,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.format, required this.failed});

  final SkyFormat format;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final f = format;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed ? Icons.explore_off_outlined : Icons.explore_outlined,
              size: 40,
              color: s.inkFaint,
            ),
            const SizedBox(height: 12),
            Text(
              failed
                  ? f.w(
                      'यो फोनमा कम्पास सेन्सर छैन।',
                      'This phone has no compass sensor.',
                    )
                  : f.w('कम्पास पर्खँदै…', 'Waiting for the compass…'),
              textAlign: TextAlign.center,
              style: s.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// The dial with the heading, bearing lock and Sun and Moon readouts.
class _Dial extends StatelessWidget {
  const _Dial({
    required this.heading,
    required this.level,
    required this.locked,
    required this.snap,
    required this.format,
    required this.onTap,
  });

  final double heading;
  final ({double x, double y}) level;
  final double? locked;
  final SkySnapshot snap;
  final SkyFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final f = format;
    final shown = heading.round() % 360;
    final lock = locked;
    final off = lock == null ? 0.0 : wrap180(heading - lock);

    return LayoutBuilder(
      builder: (context, box) {
        // Room left for the readouts under the dial.
        final size = math
            .min(box.maxWidth - 40, box.maxHeight - 190)
            .clamp(200.0, 400.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Semantics(
                button: true,
                label: f.w(
                  'कम्पास, ${f.deg(shown.toDouble(), digits: 0)} '
                      '${f.direction(heading)}',
                  'Compass, heading $shown° ${f.direction(heading)}',
                ),
                hint: lock == null
                    ? f.w('दिशा थुन्न ट्याप गर्नुहोस्', 'Tap to lock bearing')
                    : f.w('खोल्न ट्याप गर्नुहोस्', 'Tap to unlock'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: SizedBox.square(
                    dimension: size,
                    child: CustomPaint(
                      painter: CompassDialPainter(
                        heading: heading,
                        level: level,
                        locked: lock,
                        sun: snap.sun,
                        moon: snap.moon,
                        nepali: f.nepali,
                        digits: f.n,
                        ink: s.ink,
                        faint: s.inkFaint,
                        north: s.holiday,
                        levelOn: s.highlight,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    f.n('$shown°'),
                    style: s.numeral.copyWith(
                      fontSize: 60,
                      fontWeight: FontWeight.w200,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    f.direction(heading),
                    style: s.body.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                lock == null
                    ? f.w(
                        'दिशा थुन्न डायलमा ट्याप गर्नुहोस्',
                        'Tap the dial to lock a bearing',
                      )
                    : off.abs() < 1
                    ? f.w(
                        '${f.deg(lock, digits: 0)} मा मिल्यो',
                        'On ${f.deg(lock, digits: 0)}',
                      )
                    : f.w(
                        '${f.deg(lock, digits: 0)} बाट ${f.deg(off.abs(), digits: 0)} '
                            '${off > 0 ? 'दायाँ' : 'बायाँ'}',
                        '${f.deg(off.abs(), digits: 0)} '
                            '${off > 0 ? 'right' : 'left'} of '
                            '${f.deg(lock, digits: 0)}',
                      ),
                style: s.bodySmall.copyWith(
                  color: lock == null ? s.inkFaint : s.holiday,
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: _BodyReadout(
                        body: snap.sun,
                        name: f.w('सूर्य', 'Sun'),
                        color: SkyColors.sun,
                        heading: heading,
                        format: f,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BodyReadout(
                        body: snap.moon,
                        name: f.w('चन्द्र', 'Moon'),
                        color: SkyColors.moonPath,
                        heading: heading,
                        format: f,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  f.w(
                    'चुम्बकीय उत्तर। फोन समतल राखेर टुप्पोले देखाएको दिशा, '
                        'वा ठाडो राखेर क्यामेराले हेरेको दिशा। दिशा मिलेन भने '
                        'फोनलाई ८ आकारमा घुमाउनुहोस्।',
                    'Magnetic north. Flat, the heading is where the top of '
                        'the phone points; upright, where the camera looks. '
                        'If it seems off, wave the phone in a figure 8.',
                  ),
                  textAlign: TextAlign.center,
                  style: s.bodySmall.copyWith(
                    color: s.inkFaint,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Where a body is and which way to turn to face it.
class _BodyReadout extends StatelessWidget {
  const _BodyReadout({
    required this.body,
    required this.name,
    required this.color,
    required this.heading,
    required this.format,
  });

  final BodyPosition body;
  final String name;
  final Color color;
  final double heading;
  final SkyFormat format;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final f = format;
    final turn = wrap180(body.azimuth - heading);
    final turnText = turn.abs() < 3
        ? f.w('सामुन्ने', 'ahead')
        : '${turn > 0 ? '→' : '←'} ${f.deg(turn.abs(), digits: 0)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: s.surface, borderRadius: s.borderRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Dot(color: color, size: 9),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  name,
                  style: s.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(turnText, style: s.mono.copyWith(color: s.ink)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${f.deg(body.azimuth, digits: 0)} ${f.direction(body.azimuth)}',
            style: s.mono,
          ),
          Text(
            body.isUp
                ? f.w(
                    'उचाइ ${f.deg(body.altitude, digits: 0)}',
                    '${f.deg(body.altitude, digits: 0)} up',
                  )
                : f.w('क्षितिजमुनि', 'below horizon'),
            style: s.mono.copyWith(color: s.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// The compass face. The dial turns so the heading sits under the fixed line
/// at the top; numbers and letters stay upright.
class CompassDialPainter extends CustomPainter {
  CompassDialPainter({
    required this.heading,
    required this.level,
    required this.locked,
    required this.sun,
    required this.moon,
    required this.nepali,
    required this.digits,
    required this.ink,
    required this.faint,
    required this.north,
    required this.levelOn,
  });

  final double heading;
  final ({double x, double y}) level;
  final double? locked;
  final BodyPosition sun;
  final BodyPosition moon;
  final bool nepali;
  final String Function(String) digits;
  final Color ink;
  final Color faint;
  final Color north;
  final Color levelOn;

  static const _english = ['N', 'E', 'S', 'W'];
  static const _nepali = ['उ', 'पू', 'द', 'प'];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // Room outside the ticks for the heading line and the body markers.
    final r = size.shortestSide / 2 - 20;
    final tick = r * 0.1;

    /// Screen point at azimuth [az] (degrees) and radius [radius].
    Offset at(double az, double radius) {
      final a = (az - heading) * _rad;
      return c + Offset(math.sin(a) * radius, -math.cos(a) * radius);
    }

    final line = Paint()..strokeCap = StrokeCap.butt;

    // Bearing lock: an arc from the locked bearing to the heading.
    if (locked case final lock?) {
      final sweep = wrap180(heading - lock);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - tick / 2),
        (lock - heading - 90) * _rad,
        sweep * _rad,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = tick
          ..color = north.withValues(alpha: 0.55),
      );
    }

    // Ticks: every 2°, longer every 10°, longest at the cardinals.
    for (var az = 0; az < 360; az += 2) {
      final major = az % 30 == 0;
      final ten = az % 10 == 0;
      final len = major ? tick : (ten ? tick * 0.8 : tick * 0.55);
      final color = az == 0 ? north : (ten ? ink : faint);
      canvas.drawLine(
        at(az.toDouble(), r),
        at(az.toDouble(), r - len),
        line
          ..color = color
          ..strokeWidth = az == 0 ? 3 : (major ? 2 : (ten ? 1.4 : 1)),
      );
    }
    if (locked case final lock?) {
      canvas.drawLine(
        at(lock, r + 4),
        at(lock, r - tick - 4),
        line
          ..color = north
          ..strokeWidth = 2.4,
      );
    }

    // Degrees every 30°, inside the ticks.
    final numberR = r - tick - 16;
    for (var az = 0; az < 360; az += 30) {
      _text(
        canvas,
        digits('$az'),
        at(az.toDouble(), numberR),
        size: 12,
        color: ink,
        weight: FontWeight.w500,
      );
    }

    // Cardinal letters further in.
    final letterR = r - tick - 46;
    for (var i = 0; i < 4; i++) {
      _text(
        canvas,
        nepali ? _nepali[i] : _english[i],
        at(i * 90.0, letterR),
        size: i == 0 ? 26 : 22,
        color: i == 0 ? north : ink,
        weight: FontWeight.w600,
      );
    }

    // The Sun and Moon just outside the ring; faded below the horizon.
    for (final b in [moon, sun]) {
      final isSun = b.body == Body.sun;
      final p = at(b.azimuth, r + 11);
      final alpha = b.isUp ? 1.0 : 0.35;
      final color = isSun ? SkyColors.sun : SkyColors.moonPath;
      canvas.drawCircle(
        p,
        isSun ? 7 : 6,
        Paint()..color = color.withValues(alpha: alpha),
      );
      if (!b.isUp) {
        canvas.drawCircle(
          p,
          isSun ? 7 : 6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = color,
        );
      }
    }

    // The fixed heading line at the top.
    canvas.drawLine(
      c + Offset(0, -r - 18),
      c + Offset(0, -r + tick + 6),
      line
        ..color = ink
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round,
    );

    _level(canvas, c, r);
  }

  /// A fixed cross with a bubble that drifts toward the high side; both
  /// light up when the phone is flat.
  void _level(Canvas canvas, Offset c, double r) {
    final reach = r * 0.3;
    final tilt = math.sqrt(level.x * level.x + level.y * level.y);
    final flat = tilt < 0.035; // About 2°.
    final color = flat ? levelOn : faint;
    final cross = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    canvas
      ..drawLine(c - Offset(reach, 0), c + Offset(reach, 0), cross)
      ..drawLine(c - Offset(0, reach), c + Offset(0, reach), cross);

    // Upright the bubble would leave the dial; keep it on the edge.
    var offset = Offset(level.x, -level.y) * (reach * 2.2);
    if (offset.distance > reach) offset = offset / offset.distance * reach;
    final bubble = c + offset;
    final bubbleR = r * 0.09;
    canvas.drawCircle(
      bubble,
      bubbleR,
      Paint()..color = (flat ? levelOn : ink).withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      bubble,
      bubbleR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = flat ? levelOn : ink,
    );
    final small = Paint()
      ..color = flat ? levelOn : ink
      ..strokeWidth = 1.6;
    canvas
      ..drawLine(
        bubble - Offset(bubbleR * 0.5, 0),
        bubble + Offset(bubbleR * 0.5, 0),
        small,
      )
      ..drawLine(
        bubble - Offset(0, bubbleR * 0.5),
        bubble + Offset(0, bubbleR * 0.5),
        small,
      );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center, {
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w500,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(CompassDialPainter old) =>
      old.heading != heading ||
      old.level != level ||
      old.locked != locked ||
      old.sun.azimuth != sun.azimuth ||
      old.moon.azimuth != moon.azimuth ||
      old.nepali != nepali ||
      old.ink != ink ||
      old.north != north ||
      old.levelOn != levelOn;
}
