import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/astronomy.dart';
import '../models/patro_day.dart';
import '../providers/settings_provider.dart';
import '../screens/sky_page.dart' show SkyFormat;
import '../theme/patro_style.dart';
import 'common.dart';
import 'sky_scene.dart' show SkyColors;

/// Sunrise, sunset, moonrise and moonset for a day, and where the Moon is:
/// now for today, or at the same clock time on other days. Computed for the
/// place set in Settings → Sun & Moon.
class DaySky extends ConsumerStatefulWidget {
  const DaySky({super.key, required this.day});

  final PatroDay day;

  @override
  ConsumerState<DaySky> createState() => _DaySkyState();
}

class _DaySkyState extends ConsumerState<DaySky> {
  Timer? _ticker;
  (DateTime, GeoLocation)? _key;
  late RiseSet _sun;
  late RiseSet _moon;

  @override
  void initState() {
    super.initState();
    // Today's Moon moves; refresh its position every minute.
    if (widget.day.isToday) {
      _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final location = ref.watch(settingsProvider.select((x) => x.skyLocation));
    final ad = widget.day.adDate;
    final start = DateTime(ad.year, ad.month, ad.day);
    if (_key != (start, location)) {
      _key = (start, location);
      _sun = Astro.riseSet(Body.sun, start, location);
      _moon = Astro.riseSet(Body.moon, start, location);
    }

    final now = DateTime.now();
    final at = widget.day.isToday
        ? now
        : start.add(Duration(hours: now.hour, minutes: now.minute));
    final snap = SkySnapshot.at(at, location);
    final moon = snap.moon;
    final f = SkyFormat(context, s, at);
    String time(DateTime? t) => t == null ? '—' : f.when(t);

    final label = s.mono.copyWith(color: s.inkFaint);
    Widget pair(String name, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name.toUpperCase(), style: label),
          Text(value, style: s.body),
        ],
      ),
    );

    Widget row(Widget icon, List<Widget> cells) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Padding(padding: const EdgeInsets.only(top: 4), child: icon),
          ),
          ...cells,
        ],
      ),
    );

    final rashi = rashiNames[moon.rashi];
    const nakSpan = 360 / 27;
    final nakshatra = nakshatraNames[moon.siderealLongitude ~/ nakSpan];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(f.w('सूर्य र चन्द्र', 'Sun & Moon')),
        row(const Dot(color: SkyColors.sunPath, size: 12), [
          pair(f.w('सूर्योदय', 'Sunrise'), time(_sun.rise)),
          pair(f.w('सूर्यास्त', 'Sunset'), time(_sun.set)),
          pair(
            f.w('दिनमान', 'Day'),
            _sun.upFor == null ? '—' : f.duration(_sun.upFor!),
          ),
        ]),
        row(MoonGlyph(phase: snap.phase, size: 12), [
          pair(f.w('चन्द्रोदय', 'Moonrise'), time(_moon.rise)),
          pair(f.w('चन्द्रास्त', 'Moonset'), time(_moon.set)),
          pair(
            f.w('उज्यालो', 'Lit'),
            f.n('${(snap.illumination * 100).round()}%'),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 28, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.day.isToday
                    ? f.w('चन्द्र अहिले', 'MOON NOW')
                    : f.w('${f.clock(at)} मा चन्द्र', 'MOON AT ${f.clock(at)}'),
                style: label,
              ),
              Text(
                moon.isUp
                    ? f.w(
                        '${f.deg(moon.altitude)} माथि · ${f.direction(moon.azimuth)} ${f.deg(moon.azimuth, digits: 0)}',
                        '${f.deg(moon.altitude)} up · ${f.direction(moon.azimuth)} ${f.deg(moon.azimuth, digits: 0)}',
                      )
                    : f.w(
                        'क्षितिजमुनि (${f.deg(moon.altitude)}) · ${f.direction(moon.azimuth)} ${f.deg(moon.azimuth, digits: 0)}',
                        'Below horizon (${f.deg(moon.altitude)}) · ${f.direction(moon.azimuth)} ${f.deg(moon.azimuth, digits: 0)}',
                      ),
                style: s.body,
              ),
              Text(
                '${rashi.$3} ${f.name((rashi.$1, rashi.$2))} · ${f.name(nakshatra)}',
                style: s.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
