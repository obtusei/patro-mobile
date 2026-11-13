import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/patro_day.dart';
import '../models/patro_event.dart';
import '../theme/patro_style.dart';
import 'common.dart';
import 'event_editor_sheet.dart';
import 'event_qr_sheet.dart';

/// Timed events on an hour-by-hour grid. Overlapping events share the width;
/// tapping an empty slot adds an event there.
class DayTimeline extends StatefulWidget {
  const DayTimeline({super.key, required this.day, required this.events});

  static const double hourHeight = 56;
  static const double _labelWidth = 56;

  final PatroDay day;

  /// Timed events only; all-day ones are listed above the grid.
  final List<PatroEvent> events;

  @override
  State<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<DayTimeline> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  @override
  void didUpdateWidget(DayTimeline old) {
    super.didUpdateWidget(old);
    if (old.day.isToday != widget.day.isToday) _syncClock();
  }

  /// Moves the now-line every minute, only while showing today.
  void _syncClock() {
    _clock?.cancel();
    _clock = widget.day.isToday
        ? Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}))
        : null;
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  static int _endOf(PatroEvent e) =>
      math.max(e.endMinutes ?? e.startMinutes! + 60, e.startMinutes! + 15);

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final events = [...widget.events]..sort(PatroEvent.compare);

    // Show the working day, stretched to fit every event and the time now.
    var firstHour = 7;
    var lastHour = 21;
    for (final e in events) {
      firstHour = math.min(firstHour, e.startMinutes! ~/ 60);
      lastHour = math.max(lastHour, (_endOf(e) / 60).ceil());
    }
    if (widget.day.isToday) {
      firstHour = math.min(firstHour, nowMinutes ~/ 60);
      lastHour = math.max(lastHour, nowMinutes ~/ 60 + 1);
    }
    firstHour = firstHour.clamp(0, 23);
    lastHour = lastHour.clamp(firstHour + 1, 24);

    const hourHeight = DayTimeline.hourHeight;
    double yOf(int minutes) => (minutes - firstHour * 60) / 60 * hourHeight;
    final height = (lastHour - firstHour) * hourHeight;
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    String hourLabel(int h) => use24h
        ? '${h.toString().padLeft(2, '0')}:00'
        : DateFormat.j().format(DateTime(2000, 1, 1, h));

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth - DayTimeline._labelWidth;
        final placed = _layOut(events);

        return SizedBox(
          height: height + 8,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var h = firstHour; h <= lastHour; h++)
                Positioned(
                  top: yOf(h * 60) - 7,
                  left: 0,
                  right: 0,
                  child: Row(
                    children: [
                      SizedBox(
                        width: DayTimeline._labelWidth,
                        child: Text(
                          hourLabel(h),
                          style: s.mono.copyWith(color: s.inkFaint),
                        ),
                      ),
                      Expanded(child: Container(height: 1, color: s.hairline)),
                    ],
                  ),
                ),
              // Empty space: tap to add an event on that half hour.
              Positioned(
                top: 0,
                left: DayTimeline._labelWidth,
                right: 0,
                height: height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final minutes =
                        firstHour * 60 +
                        (details.localPosition.dy / hourHeight * 2).floor() *
                            30;
                    showEventEditor(
                      context,
                      date: widget.day.adDate,
                      startMinutes: minutes.clamp(0, 24 * 60 - 30),
                    );
                  },
                ),
              ),
              for (final p in placed)
                Positioned(
                  top: yOf(p.event.startMinutes!) + 1,
                  height: math.max(
                    yOf(_endOf(p.event)) - yOf(p.event.startMinutes!) - 2,
                    26,
                  ),
                  left:
                      DayTimeline._labelWidth +
                      gridWidth * p.column / p.columns +
                      2,
                  width: gridWidth / p.columns - 4,
                  child: _TimelineBlock(event: p.event, day: widget.day),
                ),
              if (widget.day.isToday &&
                  nowMinutes >= firstHour * 60 &&
                  nowMinutes <= lastHour * 60)
                Positioned(
                  top: yOf(nowMinutes) - 4,
                  left: DayTimeline._labelWidth - 4,
                  right: 0,
                  child: IgnorePointer(
                    child: Row(
                      children: [
                        Dot(color: s.highlight, size: 8),
                        Expanded(
                          child: Container(height: 1.5, color: s.highlight),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Greedy column packing: each run of overlapping events splits the width
  /// into as many columns as it needs.
  static List<_Placed> _layOut(List<PatroEvent> events) {
    final out = <_Placed>[];
    var cluster = <_Placed>[];
    var columnEnds = <int>[];
    var clusterEnd = -1;

    void close() {
      for (final p in cluster) {
        out.add(_Placed(p.event, p.column, columnEnds.length));
      }
      cluster = [];
      columnEnds = [];
    }

    for (final e in events) {
      final start = e.startMinutes!;
      if (start >= clusterEnd) close();
      var column = columnEnds.indexWhere((end) => end <= start);
      if (column < 0) {
        column = columnEnds.length;
        columnEnds.add(_endOf(e));
      } else {
        columnEnds[column] = _endOf(e);
      }
      cluster.add(_Placed(e, column, 0));
      clusterEnd = math.max(clusterEnd, _endOf(e));
    }
    close();
    return out;
  }
}

class _Placed {
  const _Placed(this.event, this.column, this.columns);

  final PatroEvent event;
  final int column;
  final int columns;
}

class _TimelineBlock extends StatelessWidget {
  const _TimelineBlock({required this.event, required this.day});

  final PatroEvent event;
  final PatroDay day;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final color = event.color ?? s.accent;
    return Pressable(
      pressedScale: 0.97,
      onTap: () => event.isExternal
          ? showEventQr(context, event)
          : showEventEditor(context, date: day.adDate, event: event),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: 0.2), s.surface),
          borderRadius: s.scaledRadius(0.5),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: LayoutBuilder(
          builder: (context, box) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                maxLines: box.maxHeight > 52 ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: s.body.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              if (box.maxHeight > 38)
                Text(
                  [
                    eventTimeLabel(context, event),
                    if (event.location.isNotEmpty) event.location,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: s.mono.copyWith(fontSize: 10.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
