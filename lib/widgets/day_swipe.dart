import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../theme/patro_style.dart';

/// Pull a day past its top to go to the day before, or past its bottom for
/// the day after.
///
/// The day scrolls normally (its timeline can be long); only a drag that
/// keeps going once the list has hit an edge counts. That drag meets growing
/// resistance, so a flick never changes the date by accident; it has to be
/// pulled most of the way and released.
///
/// [child] must contain the day's vertical scrollable. It is given
/// [DaySwipe.physics] so both edges always report overscroll.
class DaySwipe extends ConsumerStatefulWidget {
  const DaySwipe({
    super.key,
    required this.child,
    required this.onPrevious,
    required this.onNext,
    required this.previousLabel,
    required this.nextLabel,
  });

  /// Lets a short day still be pulled, on every platform.
  static const physics = AlwaysScrollableScrollPhysics(
    parent: ClampingScrollPhysics(),
  );

  final Widget child;

  /// Null at the first supported date.
  final VoidCallback? onPrevious;

  /// Null at the last supported date.
  final VoidCallback? onNext;
  final String previousLabel;
  final String nextLabel;

  @override
  ConsumerState<DaySwipe> createState() => _DaySwipeState();
}

class _DaySwipeState extends ConsumerState<DaySwipe>
    with SingleTickerProviderStateMixin {
  /// The furthest the page moves; the pull approaches it asymptotically.
  static const _maxPull = 150.0;

  /// How far the page must move before a release changes the date.
  static const _trigger = 84.0;

  /// Distance a new day slides in from.
  static const _enterFrom = 56.0;

  /// Finger travel past the edge: positive pulls down (previous day).
  double _raw = 0;
  bool _armed = false;
  bool _entering = false;

  late final _offset = AnimationController.unbounded(vsync: this);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  /// Rubber band: the page follows the finger less and less.
  static double _resisted(double raw) =>
      raw.sign * _maxPull * (1 - math.exp(-raw.abs() / _maxPull));

  void _setRaw(double raw) {
    // Only edges with a day beyond them can be pulled.
    if (raw > 0 && widget.onPrevious == null) raw = 0;
    if (raw < 0 && widget.onNext == null) raw = 0;
    _raw = raw;
    _offset.value = _resisted(raw);
    final armed = _offset.value.abs() >= _trigger;
    if (armed != _armed) {
      _armed = armed;
      if (armed && ref.read(settingsProvider).haptics) {
        HapticFeedback.selectionClick();
      }
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || _entering) return false;

    if (n is OverscrollNotification && n.dragDetails != null) {
      // Overscroll is negative past the top, positive past the bottom.
      _setRaw(_raw - n.overscroll);
    } else if (n is ScrollUpdateNotification &&
        n.dragDetails != null &&
        _raw != 0) {
      // Dragging back toward the content first undoes the pull.
      final delta = n.scrollDelta ?? 0;
      final next = _raw - delta;
      _setRaw(_raw.sign == next.sign ? next : 0);
    } else if (n is ScrollEndNotification ||
        (n is UserScrollNotification && n.direction == ScrollDirection.idle)) {
      _release();
    }
    return false;
  }

  void _release() {
    if (_raw == 0 && _offset.value == 0) return;
    final pulledDown = _offset.value > 0;
    final go = _armed;
    _raw = 0;
    _armed = false;
    if (!go) {
      _offset.animateTo(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
      );
      return;
    }
    (pulledDown ? widget.onPrevious : widget.onNext)?.call();
    // The new day slides in from the side the old one left by.
    _entering = true;
    _offset.value = pulledDown ? -_enterFrom : _enterFrom;
    _offset
        .animateTo(
          0,
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
        )
        .whenCompleteOrCancel(() {
          if (mounted) setState(() => _entering = false);
        });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ScrollConfiguration(
        // The page itself moves; no stretch or glow on top of that.
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: AnimatedBuilder(
          animation: _offset,
          child: widget.child,
          builder: (context, child) {
            final y = _offset.value;
            final progress = (y.abs() / _trigger).clamp(0.0, 1.0);
            final page = Transform.translate(
              offset: Offset(0, y),
              child: _entering
                  ? Opacity(
                      opacity: (1 - y.abs() / _enterFrom).clamp(0.0, 1.0),
                      child: child,
                    )
                  : child,
            );
            final down = y > 0;
            // The tree keeps one shape throughout: re-parenting the page
            // would rebuild its list and cancel the drag.
            return Stack(
              children: [
                Positioned.fill(child: page),
                if (!_entering && y != 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: down ? 8 : null,
                    bottom: down ? null : 8,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: progress,
                        child: _PullHint(
                          up: down,
                          armed: progress >= 1,
                          label: down ? widget.previousLabel : widget.nextLabel,
                          style: s,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PullHint extends StatelessWidget {
  const _PullHint({
    required this.up,
    required this.armed,
    required this.label,
    required this.style,
  });

  final bool up;
  final bool armed;
  final String label;
  final PatroStyle style;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final color = armed ? s.highlight : s.inkMuted;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: armed ? s.highlight.withValues(alpha: 0.14) : s.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: armed ? s.highlight : s.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedRotation(
              turns: armed ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                up
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              armed ? 'Release for $label' : label,
              style: s.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
