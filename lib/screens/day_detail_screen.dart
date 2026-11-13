import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/app_settings.dart';
import '../models/patro_day.dart';
import '../providers/calendar_provider.dart';
import '../providers/events_provider.dart';
import '../providers/settings_provider.dart';
import '../services/feedback_service.dart';
import '../theme/patro_style.dart';
import '../widgets/common.dart';
import '../widgets/day_sky.dart';
import '../widgets/day_story.dart';
import '../widgets/day_swipe.dart';
import '../widgets/day_timeline.dart';
import '../widgets/event_editor_sheet.dart';
import '../widgets/event_tile.dart';

/// One day per page, swiped sideways, with its events.
class DayDetailScreen extends ConsumerStatefulWidget {
  const DayDetailScreen({super.key, required this.date});

  final DateTime date;

  /// Opens at once, with no transition.
  static Route<void> route(DateTime date) {
    return PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => DayDetailScreen(date: date),
    );
  }

  @override
  ConsumerState<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends ConsumerState<DayDetailScreen> {
  static final int _pageCount =
      BsCalendar.lastSupportedAd
          .difference(BsCalendar.firstSupportedAd)
          .inDays +
      1;

  late final int _initialIndex = _indexOf(widget.date);
  late final _pager = PageController(initialPage: _initialIndex);
  late int _index = _initialIndex;

  static int _indexOf(DateTime date) => BsCalendar.dateOnly(
    date,
  ).difference(BsCalendar.firstSupportedAd).inDays.clamp(0, _pageCount - 1);

  static DateTime _dateAt(int index) =>
      BsCalendar.firstSupportedAd.add(Duration(days: index));

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _goToToday() {
    final target = _indexOf(ref.read(calendarProvider));
    if (target == _index) return;
    if ((target - _index).abs() <= 3) {
      _pager.animateToPage(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pager.jumpToPage(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const PatroLogo(),
        centerTitle: true,
        actions: [
          TodayButton(onPressed: _goToToday),
          const SizedBox(width: 12),
        ],
      ),
      body: DaySwipe(
        previousLabel: dayLabel(context, _dateAt(_index - 1)),
        nextLabel: dayLabel(context, _dateAt(_index + 1)),
        onPrevious: _index > 0 ? () => _pager.jumpToPage(_index - 1) : null,
        onNext: _index < _pageCount - 1
            ? () => _pager.jumpToPage(_index + 1)
            : null,
        child: PageView.builder(
          itemCount: _pageCount,
          controller: _pager,
          onPageChanged: (i) {
            setState(() => _index = i);
            ref.read(feedbackProvider).play(PatroSound.pageTurn);
          },
          itemBuilder: (context, i) => DayDetailBody(date: _dateAt(i)),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add event',
        onPressed: () => showEventEditor(context, date: _dateAt(_index)),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

/// "Tomorrow", "Yesterday", or "Sat, 14 कात्तिक", for the pull hint.
String dayLabel(BuildContext context, DateTime date) {
  final s = PatroStyle.of(context);
  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  switch (BsCalendar.dateOnly(date).difference(today).inDays) {
    case 0:
      return s.nepaliDigits ? 'आज' : 'Today';
    case 1:
      return s.nepaliDigits ? 'भोलि' : 'Tomorrow';
    case -1:
      return s.nepaliDigits ? 'हिजो' : 'Yesterday';
  }
  if (!BsCalendar.isSupportedAd(date)) return '';
  final bs = BsCalendar.fromAd(date);
  return s.primary == CalendarSystem.bs
      ? '${s.digits(bs.day)} ${s.bsMonth(bs.month)}'
      : DateFormat('EEE, d MMM').format(date);
}

/// Everything about one date: numerals, tithi, festivals and events. Shared
/// by the day screen and the date page.
class DayDetailBody extends ConsumerWidget {
  const DayDetailBody({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    ref.watch(calendarProvider);
    final day = ref.read(calendarProvider.notifier).dayOn(date);
    final events = ref.watch(eventsProvider).on(day);
    final timeline = ref.watch(settingsProvider.select((x) => x.showTimeline));
    final observances = s.showObservances
        ? day.observances
        : const <Observance>[];
    final bsPrimary = s.primary == CalendarSystem.bs;

    final numeral = Text(
      s.primaryDayNumeral(day),
      style: s.numeral.copyWith(
        fontSize: 116,
        height: 0.95,
        fontWeight: FontWeight.w200,
        color: s.dayColor(day),
      ),
    );

    return ListView(
      physics: DaySwipe.physics,
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 120),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            numeral,
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.weekdayFull(day),
                      style: s.nepali.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      bsPrimary
                          ? s.bsMonthYear(day.bsDate)
                          : DateFormat('MMMM yyyy').format(day.adDate),
                      style: s.nepaliSmall.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bsPrimary
                          ? DateFormat(
                              'EEE, d MMMM yyyy',
                            ).format(day.adDate).toUpperCase()
                          : '${s.bsMonth(day.bsDate.month)} '
                                '${s.digits(day.bsDate.day)}, '
                                '${s.digits(day.bsDate.year)}',
                      style: bsPrimary ? s.mono : s.nepaliSmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (day.isToday)
              _InfoChip(
                label: s.nepaliDigits ? 'आज' : 'Today',
                color: s.highlight,
              ),
            if (s.showTithi)
              _InfoChip(
                label: day.tithi,
                leading: MoonGlyph(phase: day.moonPhase, size: 12),
              ),
            if (s.isWeekend(day))
              _InfoChip(label: 'Weekly holiday', color: s.holiday),
            if (s.showObservances && day.isPublicHoliday)
              _InfoChip(label: 'Public holiday', color: s.holiday),
          ],
        ),
        DaySky(key: ValueKey(day.adDate), day: day),
        if (observances.isNotEmpty) ...[
          const SectionLabel('Festivals & holidays'),
          for (final o in observances)
            EventLine(
              title: o.name,
              color: o.isHoliday ? s.holiday : s.accent,
              titleStyle: s.body.copyWith(
                fontSize: 16,
                color: o.isHoliday ? s.holiday : s.ink,
              ),
            ),
        ],
        SectionLabel(
          'Events',
          trailing: Text(s.digits(events.length), style: s.sectionLabel),
        ),
        if (timeline) ...[
          for (final e in events)
            if (e.isAllDay) EventTile(event: e, day: day),
          const SizedBox(height: 8),
          DayTimeline(
            day: day,
            events: [
              for (final e in events)
                if (!e.isAllDay) e,
            ],
          ),
          if (events.isEmpty) DayStory(day: day, observances: [...observances]),
        ] else if (events.isEmpty) ...[
          _EmptyEvents(onAdd: () => showEventEditor(context, date: date)),
          DayStory(day: day, observances: [...observances]),
        ] else
          for (final e in events) EventTile(event: e, day: day),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, this.leading, this.color});

  final String label;
  final Widget? leading;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final tint = color ?? s.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(s.radius.clamp(4, 99)),
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Text(label, style: s.nepaliSmall.copyWith(color: tint, height: 1.2)),
        ],
      ),
    );
  }
}

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Pressable(
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          borderRadius: s.borderRadius,
          border: Border.all(color: s.hairline),
        ),
        child: Column(
          children: [
            Icon(Icons.edit_calendar_outlined, color: s.inkFaint),
            const SizedBox(height: 8),
            Text('Nothing planned', style: s.body.copyWith(color: s.inkMuted)),
            Text('Tap to add an event', style: s.bodySmall),
          ],
        ),
      ),
    );
  }
}
