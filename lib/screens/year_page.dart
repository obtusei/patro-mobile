import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nepali_utils/nepali_utils.dart';

import '../core/calendar_format.dart';
import '../models/patro_day.dart';
import '../providers/calendar_provider.dart';
import '../providers/events_provider.dart';
import '../providers/settings_provider.dart';
import '../services/feedback_service.dart';
import '../theme/patro_style.dart';
import '../widgets/common.dart';
import '../widgets/day_swipe.dart';

/// The BS years, one at a time. With three months per row a year fits one
/// screen and years page vertically; with two, the larger months scroll and
/// pulling past either end turns the year.
class YearPage extends ConsumerWidget {
  const YearPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns = ref.watch(settingsProvider.select((s) => s.yearColumns));
    final thisYear = bsMonthOf(ref.watch(calendarProvider)).year;
    final focusedYear = ref.watch(focusedMonthProvider.select((m) => m.year));

    return Stack(
      children: [
        Positioned.fill(
          child: columns == 3 ? const _PagedYears() : const _ScrolledYears(),
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingTodayButton(
            direction: thisYear.compareTo(focusedYear),
            onPressed: () => ref.read(focusedMonthProvider.notifier).state =
                bsMonthOf(ref.read(calendarProvider)),
          ),
        ),
      ],
    );
  }
}

/// Moves the focused month to [year], keeping its month.
void _focusYear(WidgetRef ref, int year) {
  final focused = ref.read(focusedMonthProvider);
  if (focused.year != year) {
    ref.read(focusedMonthProvider.notifier).state = NepaliDateTime(
      year,
      focused.month,
    );
  }
}

/// Three months per row: whole years stacked as vertical pages.
class _PagedYears extends ConsumerStatefulWidget {
  const _PagedYears();

  @override
  ConsumerState<_PagedYears> createState() => _PagedYearsState();
}

class _PagedYearsState extends ConsumerState<_PagedYears> {
  static const _yearCount = BsCalendar.maxYear - BsCalendar.minYear + 1;

  late final _pages = PageController(
    initialPage: ref.read(focusedMonthProvider).year - BsCalendar.minYear,
  );
  bool _syncing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _syncTo(int year) async {
    if (!_pages.hasClients) return;
    final target = year - BsCalendar.minYear;
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

  @override
  Widget build(BuildContext context) {
    ref.listen(focusedMonthProvider, (prev, next) {
      if (prev?.year != next.year) _syncTo(next.year);
    });

    return PageView.builder(
      controller: _pages,
      scrollDirection: Axis.vertical,
      itemCount: _yearCount,
      onPageChanged: (i) {
        _focusYear(ref, BsCalendar.minYear + i);
        if (!_syncing) ref.read(feedbackProvider).play(PatroSound.pageFlick);
      },
      itemBuilder: (context, i) =>
          _YearSheet(year: BsCalendar.minYear + i, columns: 3),
    );
  }
}

/// Two months per row: the focused year scrolls; pull past an end to turn it.
class _ScrolledYears extends ConsumerWidget {
  const _ScrolledYears();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final year = ref.watch(focusedMonthProvider.select((m) => m.year));

    void go(int next) {
      ref.read(feedbackProvider).play(PatroSound.pageFlick);
      _focusYear(ref, next);
    }

    return DaySwipe(
      previousLabel: s.digits(year - 1),
      nextLabel: s.digits(year + 1),
      onPrevious: year > BsCalendar.minYear ? () => go(year - 1) : null,
      onNext: year < BsCalendar.maxYear ? () => go(year + 1) : null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        child: _YearSheet(key: ValueKey(year), year: year, columns: 2),
      ),
    );
  }
}

class _YearSheet extends ConsumerWidget {
  const _YearSheet({super.key, required this.year, required this.columns});

  final int year;
  final int columns;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final scrolls = columns == 2;

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PatroLogo(),
          Text(
            s.digits(year),
            style: s.numeral.copyWith(
              fontSize: 64,
              fontWeight: FontWeight.w200,
              color: s.accent,
            ),
          ),
          Text(adSpanOfBsYear(year), style: s.mono),
        ],
      ),
    );
    final months = [
      for (var m = 1; m <= 12; m++)
        _MiniMonth(month: NepaliDateTime(year, m), large: scrolls),
    ];

    if (scrolls) {
      return ListView(
        physics: DaySwipe.physics,
        // Room at the end so the Today button never hides the last months.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        children: [
          header,
          const SizedBox(height: 18),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            crossAxisCount: 2,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
            childAspectRatio: 0.92,
            children: months,
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 18),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final width = (box.maxWidth - 2 * _gap) / 3;
                final height = (box.maxHeight - 3 * _gap) / 4;
                return GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: _gap,
                  crossAxisSpacing: _gap,
                  childAspectRatio: width / height,
                  children: months,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMonth extends ConsumerWidget {
  const _MiniMonth({required this.month, this.large = false});

  final NepaliDateTime month;

  /// Two months per row: bigger digits and name.
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final today = ref.watch(calendarProvider);
    final events = ref.watch(eventsProvider);
    final calendar = ref.read(calendarProvider.notifier);
    final todayMonth = bsMonthOf(today);
    final isCurrent =
        todayMonth.year == month.year && todayMonth.month == month.month;
    final leading = s.columnOf(month.weekday);
    final digitStyle = s.nepaliSmall.copyWith(
      fontSize: large ? 13 : 10,
      height: 1,
      color: s.inkMuted,
    );

    Widget cell(int index) {
      final d = index - leading + 1;
      if (d < 1 || d > month.totalDays) return const SizedBox.shrink();
      final PatroDay day = calendar.dayOnBs(month.year, month.month, d);
      final busy = events.on(day).isNotEmpty;
      final text = Text(
        s.digits(d),
        style: digitStyle.copyWith(
          color: day.isToday
              ? s.onHighlight
              : busy
              ? s.accent
              : s.dayColor(day),
          fontWeight: busy || day.isToday ? FontWeight.w700 : null,
        ),
      );
      return Center(
        child: day.isToday
            ? Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: s.highlight,
                  shape: BoxShape.circle,
                ),
                child: FittedBox(child: text),
              )
            : FittedBox(child: text),
      );
    }

    return Pressable(
      pressedScale: 0.95,
      onTap: () {
        ref.read(feedbackProvider).play(PatroSound.chalk);
        ref.read(focusedMonthProvider.notifier).state = month;
        ref.read(shellPageProvider.notifier).state = ShellPage.month;
      },
      // The current month is marked by its name and today's dot alone.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.bsMonth(month.month),
              style: s.nepali.copyWith(
                fontSize: large ? 16 : 13.5,
                fontWeight: FontWeight.w600,
                color: isCurrent ? s.highlight : s.ink,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Column(
                children: [
                  for (var r = 0; r < 6; r++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var c = 0; c < 7; c++)
                            Expanded(child: cell(r * 7 + c)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
