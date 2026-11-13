import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nepali_utils/nepali_utils.dart';

import '../core/calendar_format.dart';
import '../core/platform.dart';
import '../models/app_settings.dart';
import '../models/patro_day.dart';
import '../providers/calendar_provider.dart';
import '../providers/events_provider.dart';
import '../services/feedback_service.dart';
import '../theme/patro_style.dart';
import '../widgets/common.dart';
import '../widgets/event_editor_sheet.dart';
import 'day_detail_screen.dart';
import 'scan_event_screen.dart';

/// The default page: an endless list of days, past above and future below.
class DayListPage extends ConsumerStatefulWidget {
  const DayListPage({super.key});

  @override
  ConsumerState<DayListPage> createState() => _DayListPageState();
}

class _DayListPageState extends ConsumerState<DayListPage>
    with SingleTickerProviderStateMixin {
  static const double _prefetchThreshold = 400;
  static const _centerKey = ValueKey('day-list-center');

  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();

  /// Date of the row under the header, for the month title.
  final _topDate = ValueNotifier<DateTime?>(null);

  /// Where today's row is: 0 on screen, -1 above it, 1 below it.
  final _todayDirection = ValueNotifier<int>(0);
  final _todayKey = GlobalKey();

  late final _fade = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 260),
  );
  bool _prefetchPending = false;

  @override
  void dispose() {
    _scroll.dispose();
    _topDate.dispose();
    _todayDirection.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// Rows have variable height, so find the top one by hit-testing for the
  /// [MetaData] each row carries.
  void _syncTopRow() {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _syncToday(box);
    final result = BoxHitTestResult();
    box.hitTest(result, position: const Offset(32, 2));
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is DateTime) {
        _topDate.value = target.metaData as DateTime;
        return;
      }
    }
  }

  /// Shows the Today button whenever today's row is off screen.
  void _syncToday(RenderBox viewport) {
    final row = _todayKey.currentContext?.findRenderObject() as RenderBox?;
    if (row == null || !row.attached || !row.hasSize) {
      // Not built at all: it is beyond the cache extent on one side.
      final today = ref.read(calendarProvider);
      final top = _topDate.value ?? ref.read(timelineProvider).anchor;
      _todayDirection.value = today.isBefore(top) ? -1 : 1;
      return;
    }
    final top = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
    _todayDirection.value = top + row.size.height <= 0
        ? -1
        : top >= viewport.size.height
        ? 1
        : 0;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    _syncTopRow();
    if (_prefetchPending) return false;

    final m = notification.metrics;
    final timeline = ref.read(timelineProvider.notifier);
    var requested = false;
    if (m.pixels - m.minScrollExtent < _prefetchThreshold &&
        timeline.canLoadPast) {
      timeline.loadPast();
      requested = true;
    }
    if (m.maxScrollExtent - m.pixels < _prefetchThreshold &&
        timeline.canLoadFuture) {
      timeline.loadFuture();
      requested = true;
    }
    if (requested) {
      // Extents only update after the next layout.
      _prefetchPending = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _prefetchPending = false,
      );
    }
    return false;
  }

  void _goToToday() {
    final today = ref.read(calendarProvider);
    final anchor = ref.read(timelineProvider).anchor;
    if (anchor == today && _scroll.hasClients && _scroll.offset.abs() < 4000) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 560),
        curve: Curves.easeOutCubic,
      );
    } else {
      _reanchor(today);
    }
  }

  /// Cross-fades to a list re-centred on [date].
  Future<void> _reanchor(DateTime date) async {
    await _fade.animateTo(0, duration: const Duration(milliseconds: 120));
    if (!mounted) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    ref.read(timelineProvider.notifier).reanchor(date);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _syncTopRow();
    await _fade.animateTo(1, curve: Curves.easeOutCubic);
  }

  void _openMonth() {
    final date = _topDate.value ?? ref.read(timelineProvider).anchor;
    ref.read(focusedMonthProvider.notifier).state = bsMonthOf(date);
    ref.read(shellPageProvider.notifier).state = ShellPage.month;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTopRow();
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(calendarProvider);
    final timeline = ref.watch(timelineProvider);
    final calendar = ref.read(calendarProvider.notifier);

    Widget row(int offset) {
      final date = timeline.dateAt(offset);
      return MetaData(
        key: date == today ? _todayKey : null,
        metaData: date,
        behavior: HitTestBehavior.translucent,
        child: DayRow(key: ValueKey(date), day: calendar.dayOn(date)),
      );
    }

    return Column(
      children: [
        _DayListHeader(
          topDate: _topDate,
          fallbackDate: timeline.anchor,
          onTitleTap: _openMonth,
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: FadeTransition(
                  opacity: _fade,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: CustomScrollView(
                      key: _viewportKey,
                      controller: _scroll,
                      center: _centerKey,
                      slivers: [
                        // Grows upward from the anchor: index 0 is the day before.
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => row(-1 - i),
                            childCount: timeline.pastCount,
                          ),
                        ),
                        SliverList(
                          key: _centerKey,
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => row(i),
                            childCount: timeline.futureCount,
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 96)),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                bottom: 20,
                child: ValueListenableBuilder<int>(
                  valueListenable: _todayDirection,
                  builder: (context, direction, _) => FloatingTodayButton(
                    direction: direction,
                    onPressed: _goToToday,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayListHeader extends ConsumerWidget {
  const _DayListHeader({
    required this.topDate,
    required this.fallbackDate,
    required this.onTitleTap,
  });

  final ValueNotifier<DateTime?> topDate;
  final DateTime fallbackDate;
  final VoidCallback onTitleTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final calendar = ref.read(calendarProvider.notifier);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: s.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTitleTap,
              child: ValueListenableBuilder<DateTime?>(
                valueListenable: topDate,
                builder: (context, date, _) {
                  final day = calendar.dayOn(date ?? fallbackDate);
                  final bsMonth = NepaliDateTime(
                    day.bsDate.year,
                    day.bsDate.month,
                  );
                  final title = s.primary == CalendarSystem.bs
                      ? s.bsMonth(day.bsDate.month)
                      : DateFormat('MMMM').format(day.adDate);
                  final subtitle = s.primary == CalendarSystem.bs
                      ? '${s.digits(day.bsDate.year)}  ·  '
                            '${adSpanOfBsMonth(bsMonth)}'
                      : '${day.adDate.year}  ·  ${s.bsMonthYear(bsMonth)}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PatroLogo(),
                      const SizedBox(height: 4),
                      _SlidingText(
                        title,
                        style: s.monthTitle.copyWith(fontSize: 28),
                      ),
                      _SlidingText(subtitle, style: s.mono),
                    ],
                  );
                },
              ),
            ),
          ),
          if (isPhone)
            IconButton(
              tooltip: 'Scan event QR code',
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: () => scanEventQr(context),
            ),
          IconButton(
            tooltip: 'Add event today',
            icon: const Icon(Icons.add_rounded),
            onPressed: () =>
                showEventEditor(context, date: ref.read(calendarProvider)),
          ),
        ],
      ),
    );
  }
}

/// Text that slides and fades when its content changes.
class _SlidingText extends StatelessWidget {
  const _SlidingText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.35),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Text(
        text,
        key: ValueKey(text),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// One row of the day list. Also used as the live preview in Settings.
class DayRow extends ConsumerWidget {
  const DayRow({super.key, required this.day});

  static const _dateColumnWidth = 84.0;

  final PatroDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final events = ref.watch(eventsProvider).on(day);
    final observances = s.showObservances ? day.observances : const [];
    final monthStart = s.primary == CalendarSystem.bs
        ? day.isFirstOfMonth
        : day.adDate.day == 1;
    final showSecondary = s.primary == CalendarSystem.ad || s.showAdDates;

    // Today is a full-bleed band; other days are separated by hairlines.
    final decoration = BoxDecoration(
      color: day.isToday ? s.todaySurface : null,
      border: Border(bottom: BorderSide(color: s.hairline)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (monthStart) _MonthMarker(day: day),
        Pressable(
          pressedScale: 0.98,
          onTap: () {
            ref.read(feedbackProvider).play(PatroSound.chalk);
            Navigator.of(context).push(DayDetailScreen.route(day.adDate));
          },
          child: Container(
            decoration: decoration,
            child: Stack(
              children: [
                // The date sits on a solid column, filled with the highlight
                // colour on today.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _dateColumnWidth,
                  child: ColoredBox(
                    color: day.isToday ? s.highlight : s.dateBlock,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 20, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _dateColumnWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.primaryDayNumeral(day),
                                style: s.numeral.copyWith(
                                  color: day.isToday
                                      ? s.onHighlight
                                      : s.dayColor(day),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                s.weekdayShort(day),
                                style:
                                    (s.nepaliDigits
                                            ? s.nepaliSmall
                                            : s.mono.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ))
                                        .copyWith(
                                          color: day.isToday
                                              ? s.onHighlight
                                              : null,
                                        ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (s.showTithi) ...[
                                  MoonGlyph(phase: day.moonPhase, size: 10),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      day.tithi,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: s.nepaliSmall.copyWith(
                                        color: s.inkFaint,
                                      ),
                                    ),
                                  ),
                                ] else
                                  const Spacer(),
                                if (showSecondary)
                                  Text(
                                    s.secondaryDate(day),
                                    style: s.primary == CalendarSystem.bs
                                        ? s.mono
                                        : s.nepaliSmall,
                                  ),
                              ],
                            ),
                            if (observances.isNotEmpty || events.isNotEmpty)
                              const SizedBox(height: 6),
                            for (final o in observances)
                              EventLine(
                                title: o.name,
                                color: o.isHoliday ? s.holiday : s.accent,
                                titleStyle: s.body.copyWith(
                                  color: o.isHoliday ? s.holiday : s.ink,
                                ),
                              ),
                            for (final e in events)
                              EventLine(
                                title: e.title,
                                color: e.color ?? s.accent,
                                time: e.isAllDay
                                    ? null
                                    : formatMinutes(context, e.startMinutes!),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthMarker extends StatelessWidget {
  const _MonthMarker({required this.day});

  final PatroDay day;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final bs = s.primary == CalendarSystem.bs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            bs
                ? s.bsMonth(day.bsDate.month)
                : DateFormat('MMMM').format(day.adDate),
            style: s.monthTitle.copyWith(fontSize: 30, color: s.accent),
          ),
          const SizedBox(width: 10),
          Text(
            bs ? s.digits(day.bsDate.year) : '${day.adDate.year}',
            style: s.numeral.copyWith(fontSize: 22, color: s.inkFaint),
          ),
          const SizedBox(width: 10),
          if (bs)
            Expanded(
              child: Text(
                adSpanOfBsMonth(bsMonthOf(day.adDate)),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: s.mono.copyWith(color: s.inkFaint),
              ),
            )
          else
            const Spacer(),
        ],
      ),
    );
  }
}
