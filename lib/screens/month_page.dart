import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nepali_utils/nepali_utils.dart';

import '../core/calendar_format.dart';
import '../models/app_settings.dart';
import '../models/patro_day.dart';
import '../models/patro_event.dart';
import '../providers/calendar_provider.dart';
import '../providers/events_provider.dart';
import '../services/feedback_service.dart';
import '../theme/patro_style.dart';
import '../widgets/common.dart';
import '../widgets/day_events_sheet.dart';
import '../widgets/event_editor_sheet.dart';
import 'day_detail_screen.dart';

bool _sameMonth(NepaliDateTime a, NepaliDateTime b) =>
    a.year == b.year && a.month == b.month;

/// BS months stacked vertically; each page is a month grid over the selected
/// day's details.
class MonthPage extends ConsumerStatefulWidget {
  const MonthPage({super.key});

  @override
  ConsumerState<MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends ConsumerState<MonthPage> {
  late final _pages = PageController(
    initialPage: bsMonthIndex(ref.read(focusedMonthProvider)),
  );
  bool _syncing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _syncTo(NepaliDateTime month) async {
    if (!_pages.hasClients) return;
    final target = bsMonthIndex(month);
    final current = _pages.page?.round();
    if (current == target) return;
    _syncing = true;
    if (current == null || (target - current).abs() > 2) {
      _pages.jumpToPage(target);
    } else {
      await _pages.animateToPage(
        target,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
      );
    }
    _syncing = false;
  }

  /// Steps one month up or down; paging plays the flick like a swipe does.
  void _step(int delta) {
    if (!_pages.hasClients) return;
    final from =
        _pages.page?.round() ?? bsMonthIndex(ref.read(focusedMonthProvider));
    final to = (from + delta).clamp(0, bsMonthCount - 1);
    if (to == from) return;
    _pages.animateToPage(
      to,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(focusedMonthProvider, (_, next) => _syncTo(next));
    final thisMonth = bsMonthIndex(bsMonthOf(ref.watch(calendarProvider)));
    final focused = bsMonthIndex(ref.watch(focusedMonthProvider));

    final pages = PageView.builder(
      controller: _pages,
      scrollDirection: Axis.vertical,
      itemCount: bsMonthCount,
      onPageChanged: (i) {
        final month = bsMonthAt(i);
        if (!_sameMonth(ref.read(focusedMonthProvider), month)) {
          ref.read(focusedMonthProvider.notifier).state = month;
        }
        if (!_syncing) ref.read(feedbackProvider).play(PatroSound.pageFlick);
      },
      itemBuilder: (context, i) => _DepthPage(
        controller: _pages,
        index: i,
        child: _MonthSheet(month: bsMonthAt(i)),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(child: pages),
        Positioned(
          top: 18,
          right: 24,
          child: Row(
            children: [
              ChevronButton(
                tooltip: 'Previous month',
                icon: Icons.keyboard_arrow_up_rounded,
                onPressed: focused > 0 ? () => _step(-1) : null,
              ),
              const SizedBox(width: 8),
              ChevronButton(
                tooltip: 'Next month',
                icon: Icons.keyboard_arrow_down_rounded,
                onPressed: focused < bsMonthCount - 1 ? () => _step(1) : null,
              ),
            ],
          ),
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingTodayButton(
            direction: thisMonth.compareTo(focused),
            onPressed: () {
              ref.read(selectedDayProvider.notifier).state = null;
              ref.read(focusedMonthProvider.notifier).state = bsMonthOf(
                ref.read(calendarProvider),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Pages recede and fade as they leave, so vertical paging feels layered.
class _DepthPage extends StatelessWidget {
  const _DepthPage({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        var delta = 0.0;
        if (controller.hasClients && controller.position.haveDimensions) {
          delta = (controller.page! - index).clamp(-1.0, 1.0);
        }
        final t = delta.abs();
        return Opacity(
          opacity: 1 - 0.55 * t,
          child: Transform.scale(scale: 1 - 0.08 * t, child: child),
        );
      },
    );
  }
}

class _MonthSheet extends ConsumerWidget {
  const _MonthSheet({required this.month});

  final NepaliDateTime month;

  /// Cells never squeeze the day panel below this.
  static const _minPanelHeight = 132.0;
  static const _weekdayRowHeight = 28.0;
  static const _panelGap = 10.0;

  /// Cells grow taller than wide by at most this much.
  static const _maxCellAspect = 1.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final today = ref.watch(calendarProvider);
    final picked = ref.watch(selectedDayProvider);
    final events = ref.watch(eventsProvider);
    final calendar = ref.read(calendarProvider.notifier);

    final days = [
      for (var d = 1; d <= month.totalDays; d++)
        calendar.dayOnBs(month.year, month.month, d),
    ];
    final leading = s.columnOf(month.weekday);
    final rows = ((leading + days.length) / 7).ceil();

    bool inMonth(DateTime date) => _sameMonth(bsMonthOf(date), month);
    final selectedDate = picked != null && inMonth(picked)
        ? picked
        : inMonth(today)
        ? today
        : days.first.adDate;
    final selected = days.firstWhere((d) => d.adDate == selectedDate);
    final selectedItems =
        (s.showObservances ? selected.observances.length : 0) +
        events.on(selected).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PatroLogo(),
                const SizedBox(height: 6),
                Text(
                  s.bsMonth(month.month),
                  style: s.monthTitle.copyWith(fontSize: 36),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      s.digits(month.year),
                      style: s.numeral.copyWith(
                        fontSize: 24,
                        color: s.inkMuted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        adSpanOfBsMonth(month),
                        style: s.mono,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // The grid takes the screen and gives the day panel just
                // enough room for the selected day's events, animating as
                // that need changes.
                final cellWidth = box.maxWidth / 7;
                final room = box.maxHeight - _weekdayRowHeight - _panelGap;
                final floor = math.max(
                  0.0,
                  math.min(cellWidth, (room - _minPanelHeight) / rows),
                );
                final target =
                    ((room - _DayPanel.heightFor(selectedItems)) / rows)
                        .clamp(
                          floor,
                          math.max(floor, cellWidth * _maxCellAspect),
                        )
                        .toDouble();
                return TweenAnimationBuilder<double>(
                  tween: Tween(end: target),
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  builder: (context, cell, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: _weekdayRowHeight,
                        child: Row(
                          children: [
                            for (final (i, label) in s.weekdayHeaders.indexed)
                              Expanded(
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: s.nepaliDigits
                                      ? s.nepaliSmall.copyWith(
                                          color: s.isWeekendColumn(i)
                                              ? s.holiday
                                              : s.inkFaint,
                                        )
                                      : s.sectionLabel.copyWith(
                                          letterSpacing: 1,
                                          color: s.isWeekendColumn(i)
                                              ? s.holiday
                                              : s.inkFaint,
                                        ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      for (var r = 0; r < rows; r++)
                        SizedBox(
                          height: cell,
                          child: Row(
                            children: [
                              for (var c = 0; c < 7; c++)
                                Expanded(
                                  child: switch (r * 7 + c - leading) {
                                    final i when i >= 0 && i < days.length =>
                                      _MonthCell(
                                        day: days[i],
                                        selected: days[i] == selected,
                                        events: events.on(days[i]),
                                      ),
                                    _ => const SizedBox.shrink(),
                                  },
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: _panelGap),
                      Expanded(child: _DayPanel(day: selected)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthCell extends ConsumerWidget {
  const _MonthCell({
    required this.day,
    required this.selected,
    required this.events,
  });

  final PatroDay day;
  final bool selected;
  final List<PatroEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final observances = s.showObservances
        ? day.observances
        : const <Observance>[];
    final showSecondary =
        s.monthSecondaryDates &&
        (s.primary == CalendarSystem.ad || s.showAdDates);
    final count = observances.length + events.length;

    // One colour stands for the day: a holiday wins, then a festival, then
    // the first event's own colour.
    final Color tone;
    if (s.showObservances && day.isPublicHoliday) {
      tone = s.holiday;
    } else if (observances.isNotEmpty) {
      tone = s.accent;
    } else if (events.isNotEmpty) {
      tone = events.first.color ?? s.accent;
    } else {
      tone = s.ink;
    }

    final marked = count > 0;
    // Faded: a faint wash with the numeral in the day's colour.
    final faded = s.dayIndicator == DayIndicator.faded && marked;
    // Background: one item is tinted, two or more are solid.
    final useFill = s.dayIndicator == DayIndicator.background && marked;
    final solid = useFill && count > 1;
    final Color fill = faded
        ? tone.withValues(alpha: 0.16)
        : !useFill
        ? tone.withValues(alpha: 0)
        : solid
        ? tone
        : tone.withValues(alpha: 0.2);
    final onFill = PatroStyle.onColor(tone);

    final numeralColor = solid
        ? onFill
        : faded
        ? tone
        : s.dayColor(day);
    final secondaryColor = solid
        ? onFill.withValues(alpha: 0.7)
        : faded
        ? tone.withValues(alpha: 0.7)
        : s.inkFaint;
    // Today keeps an underline when the day's colour takes its numeral.
    final recoloured = solid || faded;

    return Pressable(
      pressedScale: 0.92,
      onTap: () {
        ref.read(feedbackProvider).play(PatroSound.chalk);
        if (selected) {
          Navigator.of(context).push(DayDetailScreen.route(day.adDate));
        } else {
          ref.read(selectedDayProvider.notifier).state = day.adDate;
          // The date page follows the last day picked here.
          ref.read(datePageDayProvider.notifier).state = day.adDate;
        }
      },
      // Rows stretch to fill the screen; the dates stay round in the middle.
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          // The selection ring sits outside the fill with a hairline gap.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.all(1.5),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? s.highlight
                    : s.highlight.withValues(alpha: 0),
                width: 1.6,
              ),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: FittedBox(
                      child: Text(
                        s.primaryDayNumeral(day),
                        style: s.numeral.copyWith(
                          fontSize: 25,
                          fontWeight: day.isToday || solid
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: numeralColor,
                          decoration: day.isToday && recoloured
                              ? TextDecoration.underline
                              : null,
                          decorationColor: numeralColor,
                        ),
                      ),
                    ),
                  ),
                  if (showSecondary)
                    Flexible(
                      child: FittedBox(
                        child: Text(
                          s.primary == CalendarSystem.bs
                              ? '${day.adDate.day}'
                              : s.digits(day.bsDate.day),
                          style: s.mono.copyWith(
                            fontSize: 11,
                            color: secondaryColor,
                          ),
                        ),
                      ),
                    ),
                  if (s.dayIndicator == DayIndicator.dots)
                    SizedBox(
                      height: 5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (observances.isNotEmpty)
                            Dot(
                              size: 5,
                              color: day.isPublicHoliday ? s.holiday : s.accent,
                            ),
                          for (final e in events.take(3)) ...[
                            const SizedBox(width: 2),
                            Dot(
                              size: 5,
                              color: e.color ?? s.ink.withValues(alpha: 0.7),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The selected day's date and as many of its events as fit. Tapping it opens
/// the full list in a sheet.
class _DayPanel extends ConsumerWidget {
  const _DayPanel({required this.day});

  final PatroDay day;

  static const _lineHeight = 26.0;
  static const _headerHeight = 70.0;
  static const _moreHeight = 22.0;

  /// Height that shows a day with [items] events in full (or "No events").
  static double heightFor(int items) =>
      _headerHeight + math.max(items, 1) * _lineHeight + 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final events = ref.watch(eventsProvider).on(day);
    final bsPrimary = s.primary == CalendarSystem.bs;
    final items = <Widget>[
      if (s.showObservances)
        for (final o in day.observances)
          EventLine(
            title: o.name,
            color: o.isHoliday ? s.holiday : s.accent,
            titleStyle: s.body.copyWith(color: o.isHoliday ? s.holiday : s.ink),
          ),
      for (final e in events)
        EventLine(
          title: e.title,
          color: e.color ?? s.accent,
          time: e.isAllDay ? null : formatMinutes(context, e.startMinutes!),
        ),
    ];

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${s.weekdayFull(day)}, ${s.primaryDayNumeral(day)} '
                '${bsPrimary ? s.bsMonth(day.bsDate.month) : DateFormat('MMMM').format(day.adDate)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: s.nepali.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                [
                  s.secondaryDate(day),
                  if (s.showTithi) day.tithi,
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: s.nepaliSmall.copyWith(fontSize: 14.5),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Add event',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_rounded),
          onPressed: () => showEventEditor(context, date: day.adDate),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final room = box.maxHeight - _headerHeight;
          final fits = (room / _lineHeight).floor();
          final shown = items.length <= fits
              ? items.length
              : math.max(((room - _moreHeight) / _lineHeight).floor(), 0);
          final hidden = items.length - shown;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: items.isEmpty
                ? null
                : () => showDayEventsSheet(context, day),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 4),
                  if (items.isEmpty)
                    Text('No events', style: s.bodySmall)
                  else
                    ...items.take(shown),
                  if (hidden > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+$hidden MORE',
                        style: s.mono.copyWith(color: s.accent),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
