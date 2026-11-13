import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/patro_day.dart';
import '../models/patro_event.dart';
import '../theme/patro_style.dart';

String formatMinutes(BuildContext context, int minutes) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

String eventTimeLabel(BuildContext context, PatroEvent e) {
  final start = e.startMinutes;
  if (start == null) return 'All day';
  final end = e.endMinutes;
  return end == null
      ? formatMinutes(context, start)
      : '${formatMinutes(context, start)} – ${formatMinutes(context, end)}';
}

/// "10 min before", or for all-day events "1 day before, 9:00 AM".
String reminderLabel(
  BuildContext context,
  int minutes, {
  required bool allDay,
}) {
  if (allDay) {
    final days = (minutes / 1440).ceil();
    final at = formatMinutes(context, days * 1440 - minutes);
    final when = switch (days) {
      0 => 'On the day',
      1 => '1 day before',
      7 => '1 week before',
      _ => '$days days before',
    };
    return '$when, $at';
  }
  if (minutes == 0) return 'At start';
  if (minutes < 60) return '$minutes min before';
  if (minutes == 10080) return '1 week before';
  if (minutes % 1440 == 0) {
    final days = minutes ~/ 1440;
    return days == 1 ? '1 day before' : '$days days before';
  }
  if (minutes % 60 == 0) {
    final hours = minutes ~/ 60;
    return hours == 1 ? '1 hr before' : '$hours hr before';
  }
  if (minutes > 1440) {
    final days = minutes ~/ 1440;
    final rest = minutes % 1440;
    return '${days}d ${rest ~/ 60}h ${rest % 60}m before'
        .replaceAll(' 0h', '')
        .replaceAll(' 0m', '');
  }
  return '${minutes ~/ 60} hr ${minutes % 60} min before';
}

/// A Gregorian date picker limited to the dates Patro can convert. Returns
/// the picked date at UTC midnight.
Future<DateTime?> pickAdDate(
  BuildContext context, {
  required DateTime initial,
  DateTime? first,
  String? helpText,
}) async {
  DateTime local(DateTime d) => DateTime(d.year, d.month, d.day);
  final firstDate = first ?? BsCalendar.firstSupportedAd;
  final picked = await showDatePicker(
    context: context,
    initialDate: local(initial.isBefore(firstDate) ? firstDate : initial),
    firstDate: local(firstDate),
    lastDate: local(BsCalendar.lastSupportedAd),
    helpText: helpText,
  );
  return picked == null
      ? null
      : DateTime.utc(picked.year, picked.month, picked.day);
}

/// Shrinks slightly under the finger and springs back on release, for a
/// tactile, fluid tap.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.965,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: Duration(milliseconds: _pressed ? 90 : 260),
        curve: _pressed ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: s.sectionLabel)),
          ?trailing,
        ],
      ),
    );
  }
}

/// A round icon button on a faint wash, for stepping between days and months.
class ChevronButton extends StatelessWidget {
  const ChevronButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 36,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Pressable(
        pressedScale: 0.88,
        onTap: onPressed,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.35,
          duration: const Duration(milliseconds: 160),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: s.ink.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: size * 0.62, color: s.ink),
          ),
        ),
      ),
    );
  }
}

/// Small rounded "आज / TODAY" button.
class TodayButton extends StatelessWidget {
  const TodayButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Pressable(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: s.highlight.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(math.max(s.radius, 6)),
          border: Border.all(color: s.highlight.withValues(alpha: 0.5)),
        ),
        child: Text(
          s.nepaliDigits ? 'आज' : 'TODAY',
          style: s.nepaliDigits
              ? s.nepaliSmall.copyWith(color: s.highlight, height: 1.2)
              : s.mono.copyWith(
                  color: s.highlight,
                  fontWeight: FontWeight.w700,
                ),
        ),
      ),
    );
  }
}

/// A pill that slides in while today is out of view. [direction] says where
/// today is: 0 in view, negative above, positive below.
class FloatingTodayButton extends StatelessWidget {
  const FloatingTodayButton({
    super.key,
    required this.direction,
    required this.onPressed,
  });

  final int direction;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final visible = direction != 0;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.6),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Pressable(
            onTap: onPressed,
            child: Material(
              color: s.highlight,
              elevation: 4,
              shadowColor: Colors.black54,
              borderRadius: BorderRadius.circular(math.max(s.radius, 22)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 18, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      direction < 0
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 18,
                      color: s.onHighlight,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.nepaliDigits ? 'आज' : 'TODAY',
                      style: s.nepaliDigits
                          ? s.nepaliSmall.copyWith(
                              color: s.onHighlight,
                              height: 1.2,
                            )
                          : s.mono.copyWith(
                              color: s.onHighlight,
                              fontWeight: FontWeight.w700,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app mark: white on dark backgrounds, black on light ones.
class PatroLogo extends StatelessWidget {
  const PatroLogo({super.key, this.height = 22});

  final double height;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Image.asset(
      s.isDark
          ? 'assets/images/foreground.png'
          : 'assets/images/foreground_black.png',
      height: height,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Patro',
      gaplessPlayback: true,
    );
  }
}

class Dot extends StatelessWidget {
  const Dot({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// One line of the day list: a coloured stripe, optional time, title.
class EventLine extends StatelessWidget {
  const EventLine({
    super.key,
    required this.title,
    required this.color,
    this.time,
    this.titleStyle,
  });

  final String title;
  final Color color;
  final String? time;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          if (time != null) ...[
            Text(time!, style: s.mono.copyWith(color: s.inkMuted)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle ?? s.body,
            ),
          ),
        ],
      ),
    );
  }
}

/// Moon phase disc: [phase] 0 is new, 0.5 full, waxing lit from the right.
class MoonGlyph extends StatelessWidget {
  const MoonGlyph({super.key, required this.phase, this.size = 12});

  final double phase;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _MoonPainter(phase, lit: s.ink, dark: s.hairline),
    );
  }
}

class _MoonPainter extends CustomPainter {
  const _MoonPainter(this.phase, {required this.lit, required this.dark});

  final double phase;
  final Color lit;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) => paintMoonPhase(
    canvas,
    size.center(Offset.zero),
    size.shortestSide / 2,
    phase,
    lit: lit,
    dark: dark,
  );

  @override
  bool shouldRepaint(_MoonPainter old) =>
      old.phase != phase || old.lit != lit || old.dark != dark;
}

/// Paints a moon disc of radius [r] at [c]: [phase] 0 is new, 0.5 full,
/// waxing lit from the right.
void paintMoonPhase(
  Canvas canvas,
  Offset c,
  double r,
  double phase, {
  required Color lit,
  required Color dark,
  double litAlpha = 0.85,
}) {
  canvas.drawCircle(c, r, Paint()..color = dark.withValues(alpha: 0.35));

  // Terminator x-radius runs r (new) → 0 (half) → -r (full).
  final k = math.cos(phase * 2 * math.pi);
  canvas.save();
  if (phase >= 0.5) {
    canvas
      ..translate(c.dx * 2, 0)
      ..scale(-1, 1);
  }
  final top = Offset(c.dx, c.dy - r);
  final bottom = Offset(c.dx, c.dy + r);
  final path = Path()
    ..moveTo(top.dx, top.dy)
    ..arcToPoint(bottom, radius: Radius.circular(r))
    ..arcToPoint(
      top,
      radius: Radius.elliptical(math.max(r * k.abs(), 0.01), r),
      clockwise: k < 0,
    );
  canvas.drawPath(path, Paint()..color = lit.withValues(alpha: litAlpha));
  canvas.restore();
}
