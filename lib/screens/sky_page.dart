import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../core/astronomy.dart';
import '../core/calendar_format.dart';
import '../core/platform.dart';
import '../models/patro_day.dart';
import '../providers/calendar_provider.dart';
import '../providers/settings_provider.dart';
import '../services/compass_sensor.dart';
import '../services/feedback_service.dart';
import '../theme/patro_style.dart';
import '../widgets/common.dart';
import '../widgets/sky_scene.dart';
import 'settings/settings_parts.dart';
import 'settings/sky_settings.dart';
import 'sky_ar_screen.dart';

/// Live positions of the Sun and Moon: a 3D sky dome with their paths and
/// coordinates, a time scrubber, rise and set times and the day's panchanga.
/// Turned off and on in Settings.
class SkyPage extends ConsumerStatefulWidget {
  const SkyPage({super.key});

  @override
  ConsumerState<SkyPage> createState() => _SkyPageState();
}

class _SkyPageState extends ConsumerState<SkyPage> {
  Timer? _ticker;

  /// A moment picked with the scrubber; null follows the clock.
  DateTime? _manual;
  Body _focus = Body.sun;

  static const _defaultYaw = 0.0;
  static const _defaultPitch = 26.0;
  double _yaw = _defaultYaw;
  double _pitch = _defaultPitch;
  double _zoom = 1;
  double _zoomAtStart = 1;

  /// Turns the dome with the phone, so what is ahead of you on screen is
  /// ahead of you in the sky.
  bool _follow = false;
  final _compass = CompassSensor();

  SkyDay? _day;
  Panchanga? _panchanga;
  (DateTime, GeoLocation)? _panchangaKey;

  @override
  void initState() {
    super.initState();
    _compass.error.addListener(_compassFailed);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _compass.dispose();
    super.dispose();
  }

  void _compassFailed() {
    if (!mounted || _compass.error.value == null || !_follow) return;
    setState(() => _follow = false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          ref.read(settingsProvider).nepaliDigits
              ? 'यो फोनमा कम्पास सेन्सर छैन।'
              : 'This phone has no compass sensor.',
        ),
      ),
    );
  }

  /// The orbit yaw that puts the eye behind you when you face [heading].
  /// The eye sits at azimuth yaw and looks toward the opposite one.
  static double _yawFacing(double heading) => (heading + 180) % 360;

  void _toggleFollow() {
    ref.read(feedbackProvider).play(PatroSound.pageTurn);
    if (!isPhone) {
      // No compass to follow: just turn to face north.
      setState(() => _yaw = _yawFacing(0));
      return;
    }
    setState(() {
      _follow = !_follow;
      if (!_follow) {
        // Stay where the compass left the view.
        final axes = _compass.axes.value;
        if (axes != null) _yaw = _yawFacing(headingOf(axes));
      }
    });
  }

  /// Ticks once a second while the page is on screen and following the
  /// clock.
  void _setTicking(bool on) {
    if (on && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  SkyDay _dayFor(DateTime time, GeoLocation at) {
    final day = _day;
    if (day != null && day.covers(time, at)) return day;
    return _day = SkyDay(SkyDay.startOf(time), at);
  }

  Panchanga _panchangaFor(DateTime time, SkyDay day) {
    final minute = DateTime.fromMillisecondsSinceEpoch(
      time.millisecondsSinceEpoch ~/ 60000 * 60000,
    );
    final key = (minute, day.location);
    if (_panchangaKey != key || _panchanga == null) {
      _panchangaKey = key;
      _panchanga = Panchanga.at(minute, sun: day.sun);
    }
    return _panchanga!;
  }

  void _pick(DateTime? time) {
    setState(() => _manual = time);
  }

  void _openSettings() =>
      Navigator.of(context).push(SettingsSubpage.route(const SkySettings()));

  void _openAr() {
    ref.read(feedbackProvider).play(PatroSound.pageTurn);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SkyArScreen(at: _manual),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final location = ref.watch(settingsProvider.select((x) => x.skyLocation));
    final active = ref.watch(shellPageProvider) == ShellPage.sky;
    _setTicking(active && _manual == null);
    if (active && _follow) {
      _compass.start();
    } else {
      _compass.stop();
    }

    final time = _manual ?? DateTime.now();
    final day = _dayFor(time, location);
    final snap = SkySnapshot.at(time, location);
    final panchanga = _panchangaFor(time, day);
    final f = SkyFormat(context, s, time);

    final scene = SkySceneData(
      snapshot: snap,
      sunPath: day.sunPath,
      moonPath: day.moonPath,
      nepali: s.nepaliDigits,
      timeLabel: f.hour,
      digits: f.n,
      focus: _focus,
    );

    return Column(
      children: [
        _header(s, f, location, time),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
            children: [
              _dome(s, f, scene),
              const SizedBox(height: 14),
              _TimeBar(
                time: time,
                live: _manual == null,
                day: day,
                format: f,
                onChanged: _pick,
              ),
              const SizedBox(height: 18),
              _SunCard(snap: snap, day: day, format: f),
              const SizedBox(height: 12),
              _MoonCard(snap: snap, day: day, panchanga: panchanga, format: f),
              const SizedBox(height: 12),
              _PanchangaCard(
                panchanga: panchanga,
                bsDay: ref
                    .read(calendarProvider.notifier)
                    .dayOn(
                      DateTime.utc(
                        day.start.year,
                        day.start.month,
                        day.start.day,
                      ),
                    ),
                format: f,
              ),
              const SizedBox(height: 12),
              _UpcomingCard(panchanga: panchanga, format: f),
              const SizedBox(height: 16),
              Text(
                f.w(
                  'स्थिति, उदय र अस्त तपाईंको फोनमै गणना गरिन्छ, करिब एक '
                      'मिनेटसम्मको शुद्धतामा। समय फोनको समय क्षेत्रमा देखाइन्छ। '
                      'धार्मिक कार्यका लागि पण्डितसँग सोध्नुहोस्।',
                  'Positions, rise and set times are computed on your phone, '
                      'accurate to about a minute; sidereal positions use the '
                      'Lahiri ayanamsa. Times are in your phone\'s time zone. '
                      'Ask a pandit for ritual timings.',
                ),
                style: s.bodySmall.copyWith(color: s.inkFaint),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(
    PatroStyle s,
    SkyFormat f,
    GeoLocation location,
    DateTime time,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 8, 12),
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
                  f.w('आकाश', 'Sky'),
                  style: s.monthTitle.copyWith(fontSize: 28),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openSettings,
                  child: Row(
                    children: [
                      Icon(Icons.place_outlined, size: 13, color: s.inkMuted),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          '${location.name.isEmpty ? f.coords(location) : location.name.toUpperCase()}'
                          ' · ${f.clock(time, seconds: _manual == null)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: s.mono,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isPhone)
            IconButton(
              tooltip: f.w('एआर दृश्य', 'AR view'),
              icon: const Icon(Icons.view_in_ar_rounded),
              onPressed: _openAr,
            ),
          IconButton(
            tooltip: f.w('स्थान र सेटिङ', 'Location & settings'),
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _dome(PatroStyle s, SkyFormat f, SkySceneData scene) {
    return ClipRRect(
      borderRadius: s.borderRadius,
      child: SizedBox(
        height: 380,
        // Rebuilds with each compass reading while following, and with
        // setState otherwise.
        child: ValueListenableBuilder<DeviceAxes?>(
          valueListenable: _compass.axes,
          builder: (context, axes, _) {
            final heading = _follow && axes != null ? headingOf(axes) : null;
            return _domeLayers(s, f, scene, heading);
          },
        ),
      ),
    );
  }

  /// [heading] is the phone's while following the compass, else null.
  Widget _domeLayers(
    PatroStyle s,
    SkyFormat f,
    SkySceneData scene,
    double? heading,
  ) {
    final sky = SkyColors.sky(scene.snapshot.sun.altitude);
    final yaw = heading == null ? _yaw : _yawFacing(heading);
    final moved =
        (!_follow && _yaw != _defaultYaw) ||
        _pitch != _defaultPitch ||
        _zoom != 1;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: sky,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: RawGestureDetector(
            // Claims touches at once so dragging turns the dome rather
            // than the pages or the list.
            gestures: {
              _EagerScaleRecognizer:
                  GestureRecognizerFactoryWithHandlers<_EagerScaleRecognizer>(
                    _EagerScaleRecognizer.new,
                    (r) {
                      r
                        ..onStart = (_) {
                          _zoomAtStart = _zoom;
                        }
                        ..onUpdate = (d) => setState(() {
                          // Following the compass, the phone sets the yaw.
                          if (!_follow) {
                            _yaw = (_yaw - d.focalPointDelta.dx * 0.4) % 360;
                          }
                          _pitch = (_pitch + d.focalPointDelta.dy * 0.3).clamp(
                            2.0,
                            88.0,
                          );
                          if (d.pointerCount > 1) {
                            _zoom = (_zoomAtStart * d.scale).clamp(0.7, 2.4);
                          }
                        });
                    },
                  ),
            },
            child: Semantics(
              label: f.w(
                'सूर्य र चन्द्रको त्रिआयामिक आकाश',
                '3D sky with the Sun and Moon',
              ),
              child: CustomPaint(
                painter: SkyScenePainter(
                  data: scene,
                  projectorFor: (size) => OrbitProjector(
                    size,
                    yaw: yaw,
                    pitch: _pitch,
                    zoom: _zoom,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: _LiveBadge(live: _manual == null, format: f),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (moved)
                IconButton(
                  tooltip: f.w('दृश्य रिसेट', 'Reset view'),
                  color: Colors.white,
                  icon: const Icon(Icons.threesixty_rounded),
                  onPressed: () => setState(() {
                    if (!_follow) _yaw = _defaultYaw;
                    _pitch = _defaultPitch;
                    _zoom = 1;
                  }),
                ),
              _DomeCompass(
                facing: (yaw + 180) % 360,
                following: _follow,
                waiting: _follow && heading == null,
                format: f,
                onTap: _toggleFollow,
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Center(
            child: _FocusSwitch(
              focus: _focus,
              format: f,
              onChanged: (b) => setState(() => _focus = b),
            ),
          ),
        ),
      ],
    );
  }
}

/// A small compass on the dome, as in a maps app: its needle shows where
/// north is in the view, and the readout which way the view faces. Tap to
/// make the dome follow the phone (or, without a compass, to face north).
class _DomeCompass extends StatelessWidget {
  const _DomeCompass({
    required this.facing,
    required this.following,
    required this.waiting,
    required this.format,
    required this.onTap,
  });

  /// The azimuth the view looks toward, degrees.
  final double facing;
  final bool following;

  /// Following, but no reading yet.
  final bool waiting;
  final SkyFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = format;
    final active = following && !waiting;
    final tooltip = !isPhone
        ? f.w('उत्तरतिर फर्काउनुहोस्', 'Face north')
        : following
        ? f.w('कम्पास बन्द', 'Stop following the compass')
        : f.w('कम्पास अनुसार घुमाउनुहोस्', 'Turn with the phone');
    return Semantics(
      button: true,
      toggled: isPhone ? following : null,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF4A80F0).withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 32,
                  child: CustomPaint(
                    painter: _NeedlePainter(rotation: -facing),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  waiting
                      ? '…'
                      : '${f.deg(facing.roundToDouble() % 360, digits: 0)} '
                            '${f.direction(facing)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compass needle, red end north, turned by [rotation] degrees.
class _NeedlePainter extends CustomPainter {
  _NeedlePainter({required this.rotation});

  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white38,
    );
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(rotation * math.pi / 180);
    final w = r * 0.3, l = r * 0.78;
    canvas
      ..drawPath(
        Path()
          ..moveTo(0, -l)
          ..lineTo(w, 0)
          ..lineTo(-w, 0)
          ..close(),
        Paint()..color = SkyColors.north,
      )
      ..drawPath(
        Path()
          ..moveTo(0, l)
          ..lineTo(w, 0)
          ..lineTo(-w, 0)
          ..close(),
        Paint()..color = Colors.white70,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => old.rotation != rotation;
}

/// Wins the gesture arena on touch-down.
class _EagerScaleRecognizer extends ScaleGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolvePointer(event.pointer, GestureDisposition.accepted);
  }
}

/// Number, time and name formatting in the display language.
class SkyFormat {
  SkyFormat(this.context, this.s, this.reference);

  final BuildContext context;
  final PatroStyle s;

  /// The moment shown; times on its local day omit the weekday.
  final DateTime reference;

  bool get nepali => s.nepaliDigits;

  String w(String ne, String en) => nepali ? ne : en;

  String n(String text) => nepali ? devanagariDigits(text) : text;

  String name((String, String) pair) => nepali ? pair.$1 : pair.$2;

  String clock(DateTime t, {bool seconds = false}) {
    final l = t.toLocal();
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    if (seconds) {
      return n(DateFormat(use24 ? 'HH:mm:ss' : 'h:mm:ss a').format(l));
    }
    return n(
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(l),
        alwaysUse24HourFormat: use24,
      ),
    );
  }

  /// Short hour label for marks along a path.
  String hour(DateTime t) {
    final l = t.toLocal();
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    return n(use24 ? '${l.hour}:00' : DateFormat('ha').format(l));
  }

  String weekdayShort(DateTime t) {
    final l = t.toLocal();
    return nepali
        ? nepaliWeekdaysShort[l.weekday % 7]
        : DateFormat('EEE').format(l);
  }

  /// A time, with its weekday when not on the reference day.
  String when(DateTime t) {
    final l = t.toLocal();
    final r = reference.toLocal();
    final sameDay = l.year == r.year && l.month == r.month && l.day == r.day;
    return sameDay ? clock(t) : '${weekdayShort(t)} ${clock(t)}';
  }

  /// "Mon 16 Nov, 7:51 PM".
  String dateTime(DateTime t) {
    final l = t.toLocal();
    return '${weekdayShort(t)} ${n(DateFormat('d MMM').format(l))}, ${clock(t)}';
  }

  String day(DateTime t) {
    final l = t.toLocal();
    return '${weekdayShort(t)}, ${n(DateFormat('d MMM yyyy').format(l))}';
  }

  String deg(double d, {int digits = 1}) => n('${d.toStringAsFixed(digits)}°');

  String signedDeg(double d) =>
      n('${d >= 0 ? '+' : '−'}${d.abs().toStringAsFixed(2)}°');

  /// "24°13′".
  String degMin(double d) {
    final m = ((d % 1) * 60).floor();
    return n('${d.floor()}°${m.toString().padLeft(2, '0')}′');
  }

  /// Degrees and minutes within a 30° sign: "27°14′".
  String inSign(double lon) => degMin(lon % 30);

  String rightAscension(double deg) {
    final h = deg / 15;
    final m = ((h % 1) * 60).floor();
    return n('${h.floor()}h ${m.toString().padLeft(2, '0')}m');
  }

  String duration(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return nepali ? n('$h घण्टा $m मिनेट') : '${h}h ${m}m';
  }

  /// "in 3 d 4 h" from [reference].
  String relative(DateTime t) {
    final d = t.difference(reference);
    if (d.isNegative) return '';
    final days = d.inDays, hours = d.inHours % 24, mins = d.inMinutes % 60;
    final parts = nepali
        ? [
            if (days > 0) '$days दिन',
            if (hours > 0) '$hours घण्टा',
            if (days == 0) '$mins मिनेट',
          ]
        : [
            if (days > 0) '${days}d',
            if (hours > 0) '${hours}h',
            if (days == 0) '${mins}m',
          ];
    return n(nepali ? '${parts.join(' ')} पछि' : 'in ${parts.join(' ')}');
  }

  String coords(GeoLocation at) => n(
    '${at.latitude.abs().toStringAsFixed(2)}°${at.latitude >= 0 ? 'N' : 'S'} '
    '${at.longitude.abs().toStringAsFixed(2)}°${at.longitude >= 0 ? 'E' : 'W'}',
  );

  String direction(double az) {
    const en = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    const ne = [
      'उत्तर',
      'उत्तर-पूर्व',
      'पूर्व',
      'दक्षिण-पूर्व',
      'दक्षिण',
      'दक्षिण-पश्चिम',
      'पश्चिम',
      'उत्तर-पश्चिम',
    ];
    final i = ((az + 22.5) % 360) ~/ 45;
    return nepali ? ne[i] : en[i];
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.live, required this.format});

  final bool live;
  final SkyFormat format;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Dot(color: live ? const Color(0xFFFF5A5F) : Colors.white54, size: 7),
          const SizedBox(width: 6),
          Text(
            live
                ? format.w('प्रत्यक्ष', 'LIVE')
                : format.w('चयन गरिएको समय', 'PICKED TIME'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks which body gets full coordinate guides in the dome.
class _FocusSwitch extends StatelessWidget {
  const _FocusSwitch({
    required this.focus,
    required this.format,
    required this.onChanged,
  });

  final Body focus;
  final SkyFormat format;
  final ValueChanged<Body> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(Body b, String label, Color color) {
      final on = focus == b;
      return Pressable(
        onTap: () => onChanged(b),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.9) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? Colors.black : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(Body.sun, format.w('☀ सूर्य', '☀ Sun'), SkyColors.sun),
          option(Body.moon, format.w('☾ चन्द्र', '☾ Moon'), SkyColors.moon),
        ],
      ),
    );
  }
}

/// The date and time shown: step by day, scrub through the day, or go back
/// to now.
class _TimeBar extends StatelessWidget {
  const _TimeBar({
    required this.time,
    required this.live,
    required this.day,
    required this.format,
    required this.onChanged,
  });

  final DateTime time;
  final bool live;
  final SkyDay day;
  final SkyFormat format;

  /// Null returns to the clock.
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final f = format;
    final local = time.toLocal();

    void shiftDays(int days) => onChanged(
      DateTime(
        local.year,
        local.month,
        local.day + days,
        local.hour,
        local.minute,
      ),
    );

    Future<void> pickDate() async {
      final picked = await pickAdDate(context, initial: local);
      if (picked == null) return;
      onChanged(
        DateTime(
          picked.year,
          picked.month,
          picked.day,
          local.hour,
          local.minute,
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            ChevronButton(
              tooltip: f.w('अघिल्लो दिन', 'Previous day'),
              icon: Icons.chevron_left_rounded,
              onPressed: () => shiftDays(-1),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: pickDate,
                child: Column(
                  children: [
                    Text(
                      f.clock(time, seconds: live),
                      style: s.numeral.copyWith(fontSize: 24),
                    ),
                    Text(f.day(time).toUpperCase(), style: s.mono),
                  ],
                ),
              ),
            ),
            ChevronButton(
              tooltip: f.w('अर्को दिन', 'Next day'),
              icon: Icons.chevron_right_rounded,
              onPressed: () => shiftDays(1),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DayScrubber(time: time, day: day, format: f, onChanged: onChanged),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: live
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Center(
                    child: TodayButton(onPressed: () => onChanged(null)),
                  ),
                ),
        ),
      ],
    );
  }
}

/// A day/night bar from midnight to midnight, marked with sunrise, sunset,
/// moonrise and moonset; drag along it to move through the day.
class _DayScrubber extends StatelessWidget {
  const _DayScrubber({
    required this.time,
    required this.day,
    required this.format,
    required this.onChanged,
  });

  final DateTime time;
  final SkyDay day;
  final SkyFormat format;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        void seek(double dx) {
          final fraction = (dx / width).clamp(0.0, 1.0);
          final minutes = (fraction * 1440).round().clamp(0, 1439);
          onChanged(day.start.add(Duration(minutes: minutes)));
        }

        return Semantics(
          slider: true,
          label: format.w('दिनको समय', 'Time of day'),
          value: format.clock(time),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seek(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
            child: SizedBox(
              height: 46,
              width: width,
              child: CustomPaint(
                painter: _ScrubberPainter(
                  day: day,
                  time: time,
                  ink: s.ink,
                  highlight: s.highlight,
                  labelStyle: s.mono.copyWith(fontSize: 9),
                  format: format,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  _ScrubberPainter({
    required this.day,
    required this.time,
    required this.ink,
    required this.highlight,
    required this.labelStyle,
    required this.format,
  });

  final SkyDay day;
  final DateTime time;
  final Color ink;
  final Color highlight;
  final TextStyle labelStyle;
  final SkyFormat format;

  double _x(DateTime t, double width) =>
      (t.difference(day.start).inSeconds / 86400).clamp(0.0, 1.0) * width;

  @override
  void paint(Canvas canvas, Size size) {
    const barTop = 10.0, barH = 12.0;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, barTop, size.width, barH),
      const Radius.circular(6),
    );
    // Sky colour through the day, from the Sun's altitude.
    final samples = [
      for (var i = 0; i < day.sunPath.length; i += 6) day.sunPath[i],
    ];
    canvas.drawRRect(
      bar,
      Paint()
        ..shader = LinearGradient(
          colors: [for (final p in samples) SkyColors.sky(p.altitude)[1]],
          stops: [
            for (var i = 0; i < samples.length; i++) i / (samples.length - 1),
          ],
        ).createShader(bar.outerRect),
    );

    void mark(DateTime? t, Color color, {bool tall = false}) {
      if (t == null) return;
      final x = _x(t, size.width);
      canvas.drawLine(
        Offset(x, barTop - (tall ? 5 : 2)),
        Offset(x, barTop + barH + (tall ? 5 : 2)),
        Paint()
          ..color = color
          ..strokeWidth = tall ? 2 : 1.4,
      );
    }

    mark(day.sun.rise, SkyColors.sun, tall: true);
    mark(day.sun.set, SkyColors.sun, tall: true);
    mark(day.moon.rise, SkyColors.moonPath);
    mark(day.moon.set, SkyColors.moonPath);

    // Hour labels.
    for (var h = 0; h <= 24; h += 6) {
      final tp = TextPainter(
        text: TextSpan(text: format.n('$h'.padLeft(2, '0')), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (h / 24 * size.width - tp.width / 2).clamp(
        0.0,
        size.width - tp.width,
      );
      tp.paint(canvas, Offset(x, barTop + barH + 6));
    }

    // Thumb.
    final x = _x(time, size.width);
    final c = Offset(x, barTop + barH / 2);
    canvas.drawCircle(
      c,
      10,
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );
    canvas.drawCircle(c, 9, Paint()..color = highlight);
    canvas.drawCircle(
      c,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) =>
      old.time != time ||
      old.day != day ||
      old.ink != ink ||
      old.highlight != highlight;
}

// Cards ---------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({
    required this.leading,
    required this.title,
    required this.children,
    this.trailing,
  });

  final Widget leading;
  final String title;
  final String? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: s.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: s.body.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing case final t?)
                Flexible(
                  child: Text(
                    t,
                    textAlign: TextAlign.end,
                    style: s.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// Altitude and azimuth in large type.
class _Coordinates extends StatelessWidget {
  const _Coordinates({required this.body, required this.format});

  final BodyPosition body;
  final SkyFormat format;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final f = format;
    Widget big(String label, String value, String sub) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: s.sectionLabel),
          const SizedBox(height: 2),
          Text(value, style: s.numeral.copyWith(fontSize: 30)),
          Text(sub, style: s.bodySmall),
        ],
      ),
    );
    final up = body.isUp;
    return Row(
      children: [
        big(
          f.w('उन्नतांश', 'Altitude'),
          f.deg(body.altitude),
          up
              ? f.w('क्षितिजमाथि', 'above horizon')
              : f.w('क्षितिजमुनि', 'below horizon'),
        ),
        big(
          f.w('दिगंश', 'Azimuth'),
          f.deg(body.azimuth),
          f.w(
            '${f.direction(body.azimuth)} तर्फ',
            'toward ${f.direction(body.azimuth)}',
          ),
        ),
      ],
    );
  }
}

@immutable
class _Fact {
  const _Fact(this.label, this.value, [this.sub]);

  final String label;
  final String value;
  final String? sub;
}

/// Labelled values, two to a row.
class _Facts extends StatelessWidget {
  const _Facts(this.facts);

  final List<_Fact> facts;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 14.0;
        final cols = box.maxWidth > 460 ? 3 : 2;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            for (final fact in facts)
              SizedBox(
                width: w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fact.label.toUpperCase(),
                      style: s.sectionLabel.copyWith(letterSpacing: 1),
                    ),
                    const SizedBox(height: 2),
                    Text(fact.value, style: s.body),
                    if (fact.sub case final sub?)
                      Text(sub, style: s.bodySmall.copyWith(fontSize: 12)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SunCard extends StatelessWidget {
  const _SunCard({required this.snap, required this.day, required this.format});

  final SkySnapshot snap;
  final SkyDay day;
  final SkyFormat format;

  @override
  Widget build(BuildContext context) {
    final f = format;
    final sun = snap.sun;
    final rs = day.sun;
    String time(DateTime? t) => t == null ? '—' : f.when(t);
    return _Card(
      leading: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: SkyColors.sun,
          shape: BoxShape.circle,
        ),
      ),
      title: f.w('सूर्य', 'Sun'),
      trailing: f.w(
        '${rashiNames[sun.rashi].$1} राशिमा',
        'in ${rashiNames[sun.rashi].$2}',
      ),
      children: [
        _Coordinates(body: sun, format: f),
        const SizedBox(height: 14),
        _Facts([
          _Fact(f.w('सूर्योदय', 'Sunrise'), time(rs.rise)),
          _Fact(f.w('सूर्यास्त', 'Sunset'), time(rs.set)),
          _Fact(
            f.w('मध्याह्न', 'Solar noon'),
            time(rs.transit),
            rs.transitAltitude == null
                ? null
                : f.w(
                    '${f.deg(rs.transitAltitude!)} उचाइमा',
                    'at ${f.deg(rs.transitAltitude!)}',
                  ),
          ),
          _Fact(f.w('दिनमान', 'Day length'), switch (rs.upFor) {
            final d? => f.duration(d),
            _ when rs.alwaysUp => f.w('दिनभर', 'All day'),
            _ => '—',
          }),
          _Fact(
            f.w('सूर्य राशि', 'Sidereal sign'),
            '${rashiNames[sun.rashi].$3} ${f.name((rashiNames[sun.rashi].$1, rashiNames[sun.rashi].$2))}',
            f.inSign(sun.siderealLongitude),
          ),
          _Fact(
            f.w('सायन देशान्तर', 'Tropical longitude'),
            f.deg(sun.eclipticLongitude, digits: 2),
          ),
          _Fact(
            f.w('विषुवांश', 'Right ascension'),
            f.rightAscension(sun.rightAscension),
          ),
          _Fact(f.w('क्रान्ति', 'Declination'), f.signedDeg(sun.declination)),
          _Fact(
            f.w('दूरी', 'Distance'),
            f.n('${(sun.distanceKm / 149597870.7).toStringAsFixed(4)} AU'),
            f.w(
              f.n('${(sun.distanceKm / 1e7).toStringAsFixed(2)} करोड किमी'),
              '${(sun.distanceKm / 1e6).toStringAsFixed(2)} million km',
            ),
          ),
          _Fact(
            f.w('घण्टा कोण', 'Hour angle'),
            f.signedDeg(sun.hourAngle),
            sun.hourAngle < 0
                ? f.w('मध्याह्न अघि', 'before noon')
                : f.w('मध्याह्न पछि', 'after noon'),
          ),
        ]),
      ],
    );
  }
}

class _MoonCard extends StatelessWidget {
  const _MoonCard({
    required this.snap,
    required this.day,
    required this.panchanga,
    required this.format,
  });

  final SkySnapshot snap;
  final SkyDay day;
  final Panchanga panchanga;
  final SkyFormat format;

  @override
  Widget build(BuildContext context) {
    final f = format;
    final moon = snap.moon;
    final rs = day.moon;
    String time(DateTime? t) => t == null ? '—' : f.when(t);
    final rashi = rashiNames[moon.rashi];
    return _Card(
      leading: MoonGlyph(phase: snap.phase, size: 22),
      title: f.w('चन्द्र', 'Moon'),
      trailing: f.name(moonPhaseNames[snap.phaseIndex]),
      children: [
        _Coordinates(body: moon, format: f),
        const SizedBox(height: 14),
        _Facts([
          _Fact(
            f.w('चन्द्रोदय', 'Moonrise'),
            time(rs.rise),
            rs.rise == null ? f.w('आज उदाउँदैन', 'none today') : null,
          ),
          _Fact(
            f.w('चन्द्रास्त', 'Moonset'),
            time(rs.set),
            rs.set == null ? f.w('आज अस्ताउँदैन', 'none today') : null,
          ),
          _Fact(
            f.w('उज्यालो भाग', 'Illumination'),
            f.n('${(snap.illumination * 100).toStringAsFixed(1)}%'),
            snap.waxing ? f.w('बढ्दो', 'waxing') : f.w('घट्दो', 'waning'),
          ),
          _Fact(
            f.w('चन्द्र उमेर', 'Age'),
            f.n('${snap.moonAgeDays.toStringAsFixed(1)} ${f.w('दिन', 'days')}'),
            f.w(
              'सूर्यबाट ${f.deg(snap.elongation)}',
              '${f.deg(snap.elongation)} from the Sun',
            ),
          ),
          _Fact(
            f.w('चन्द्र राशि', 'Sidereal sign'),
            '${rashi.$3} ${f.name((rashi.$1, rashi.$2))}',
            f.inSign(moon.siderealLongitude),
          ),
          _Fact(
            f.w('नक्षत्र', 'Nakshatra'),
            f.name(nakshatraNames[panchanga.nakshatra]),
            f.w(f.n('पाद ${panchanga.pada}'), 'pada ${panchanga.pada}'),
          ),
          _Fact(
            f.w('शिरोबिन्दु पार', 'Transit'),
            time(rs.transit),
            rs.transitAltitude == null
                ? null
                : f.w(
                    '${f.deg(rs.transitAltitude!)} उचाइमा',
                    'at ${f.deg(rs.transitAltitude!)}',
                  ),
          ),
          _Fact(
            f.w('दूरी', 'Distance'),
            f.n('${NumberFormat('#,##0').format(moon.distanceKm)} km'),
            f.w(
              'कोणीय व्यास ${f.n((moon.angularDiameter * 60).toStringAsFixed(1))}′',
              'appears ${(moon.angularDiameter * 60).toStringAsFixed(1)}′ wide',
            ),
          ),
          _Fact(
            f.w('विषुवांश', 'Right ascension'),
            f.rightAscension(moon.rightAscension),
          ),
          _Fact(f.w('क्रान्ति', 'Declination'), f.signedDeg(moon.declination)),
        ]),
      ],
    );
  }
}

class _PanchangaCard extends StatelessWidget {
  const _PanchangaCard({
    required this.panchanga,
    required this.bsDay,
    required this.format,
  });

  final Panchanga panchanga;
  final PatroDay bsDay;
  final SkyFormat format;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final f = format;
    final p = panchanga;
    String until(DateTime? t) =>
        t == null ? '' : f.w('${f.when(t)} सम्म', 'until ${f.when(t)}');
    String span((DateTime, DateTime)? r) =>
        r == null ? '—' : '${f.clock(r.$1)} – ${f.clock(r.$2)}';

    final bs = bsDay.bsDate;
    final bsLabel =
        '${s.digits(bs.day)} ${s.bsMonth(bs.month)} ${s.digits(bs.year)}';
    final tithiName = f.nepali
        ? Lunar.tithiName(p.tithi)
        : tithiEnglishName(p.tithi);

    return _Card(
      leading: Icon(Icons.auto_awesome_outlined, color: s.accent, size: 22),
      title: f.w('पञ्चाङ्ग', 'Panchanga'),
      trailing: bsLabel,
      children: [
        // Tithi with how far through it the Moon is.
        Row(
          children: [
            MoonGlyph(phase: (p.tithi + p.tithiProgress) / 30, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.w('तिथि', 'TITHI'), style: s.sectionLabel),
                  Text(
                    tithiName,
                    style: s.body.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(until(p.tithiEnds), style: s.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: p.tithiProgress,
            minHeight: 5,
            backgroundColor: s.hairline,
            color: s.accent,
          ),
        ),
        const SizedBox(height: 16),
        _Facts([
          _Fact(
            f.w('पक्ष', 'Paksha'),
            p.shukla
                ? f.w('शुक्ल पक्ष', 'Shukla · bright half')
                : f.w('कृष्ण पक्ष', 'Krishna · dark half'),
          ),
          _Fact(f.w('वार', 'Vara'), f.name(varaNames[p.weekday])),
          _Fact(
            f.w('नक्षत्र', 'Nakshatra'),
            '${f.name(nakshatraNames[p.nakshatra])} ${f.n('${p.pada}')}',
            until(p.nakshatraEnds),
          ),
          _Fact(
            f.w('योग', 'Yoga'),
            f.name(yogaNames[p.yoga]),
            until(p.yogaEnds),
          ),
          _Fact(
            f.w('करण', 'Karana'),
            f.name(karanaName(p.karana)),
            until(p.karanaEnds),
          ),
          _Fact(
            f.w('चन्द्र राशि', 'Moon sign'),
            f.name((rashiNames[p.moonRashi].$1, rashiNames[p.moonRashi].$2)),
            until(p.moonRashiEnds),
          ),
          _Fact(
            f.w('सूर्य राशि', 'Sun sign'),
            f.name((rashiNames[p.sunRashi].$1, rashiNames[p.sunRashi].$2)),
          ),
          _Fact(
            f.w('चान्द्र मास', 'Lunar month'),
            '${p.adhikaMasa ? f.w('अधिक ', 'Adhika ') : ''}'
            '${f.name(lunarMonthNames[p.lunarMonth])}',
            f.w('अमान्त', 'amanta'),
          ),
          _Fact(f.w('ऋतु', 'Ritu'), f.name(rituNames[p.ritu])),
          _Fact(
            f.w('अयन', 'Ayana'),
            p.uttarayana
                ? f.w('उत्तरायण', 'Uttarayana')
                : f.w('दक्षिणायन', 'Dakshinayana'),
            p.uttarayana
                ? f.w('सूर्य उत्तरतर्फ', 'Sun moving north')
                : f.w('सूर्य दक्षिणतर्फ', 'Sun moving south'),
          ),
          _Fact(f.w('राहु काल', 'Rahu Kaal'), span(p.rahuKaal)),
          _Fact(f.w('अभिजित् मुहूर्त', 'Abhijit muhurta'), span(p.abhijit)),
          _Fact(
            f.w('अयनांश', 'Ayanamsa'),
            f.degMin(p.ayanamsa),
            f.w('लाहिरी', 'Lahiri'),
          ),
        ]),
      ],
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.panchanga, required this.format});

  final Panchanga panchanga;
  final SkyFormat format;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final f = format;
    final p = panchanga;
    final rashi = rashiNames[p.nextSankrantiRashi];
    final rows = [
      (
        Icons.wb_sunny_outlined,
        f.w('${rashi.$1} संक्रान्ति', '${rashi.$2} Sankranti'),
        f.w('सूर्य ${rashi.$1} राशिमा', 'Sun enters ${rashi.$2} ${rashi.$3}'),
        p.nextSankranti,
      ),
      (
        Icons.brightness_1_outlined,
        f.w('पूर्णिमा', 'Purnima'),
        f.w('पूर्ण चन्द्र', 'Full moon'),
        p.nextPurnima,
      ),
      (
        Icons.brightness_1,
        f.w('औंसी', 'Aunsi'),
        f.w('नयाँ चन्द्र', 'New moon'),
        p.nextAunsi,
      ),
    ]..sort((a, b) => a.$4.compareTo(b.$4));

    return _Card(
      leading: Icon(Icons.event_note_outlined, color: s.accent, size: 22),
      title: f.w('आउँदै', 'Coming up'),
      children: [
        for (final (icon, title, sub, at) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: s.inkMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: s.body),
                      Text(sub, style: s.bodySmall),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(f.dateTime(at), style: s.mono),
                    Text(
                      f.relative(at),
                      style: s.bodySmall.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
