import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/patro_day.dart';
import '../providers/calendar_provider.dart';
import '../services/feedback_service.dart';
import '../theme/patro_style.dart';
import '../widgets/common.dart';
import '../widgets/day_swipe.dart';
import '../widgets/event_editor_sheet.dart';
import 'day_detail_screen.dart';

/// One date at a time, between the day list and Settings. Steps a day with
/// the arrows; tap the date to jump anywhere. Follows the last day picked on
/// the month page.
class DatePage extends ConsumerWidget {
  const DatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final today = ref.watch(calendarProvider);
    final date = ref.watch(datePageDayProvider) ?? today;
    final day = ref.read(calendarProvider.notifier).dayOn(date);
    final previous = date.subtract(const Duration(days: 1));
    final next = date.add(const Duration(days: 1));

    void go(DateTime next) {
      if (!BsCalendar.isSupportedAd(next)) return;
      ref.read(feedbackProvider).play(PatroSound.pageTurn);
      ref.read(datePageDayProvider.notifier).state = next == today
          ? null
          : next;
    }

    Future<void> pick() async {
      final picked = await pickAdDate(context, initial: date);
      if (picked != null) go(picked);
    }

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
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: pick,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.nepaliDigits ? 'मिति' : 'Date',
                            style: s.monthTitle.copyWith(fontSize: 28),
                          ),
                          Text(
                            DateFormat(
                              'EEE, d MMM yyyy',
                            ).format(day.adDate).toUpperCase(),
                            style: s.mono,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!day.isToday) ...[
                TodayButton(onPressed: () => go(today)),
                const SizedBox(width: 4),
              ],
              ChevronButton(
                tooltip: 'Previous day',
                icon: Icons.chevron_left_rounded,
                onPressed: () => go(previous),
              ),
              const SizedBox(width: 6),
              ChevronButton(
                tooltip: 'Next day',
                icon: Icons.chevron_right_rounded,
                onPressed: () => go(next),
              ),
              IconButton(
                tooltip: 'Add event',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => showEventEditor(context, date: date),
              ),
            ],
          ),
        ),
        Expanded(
          child: DaySwipe(
            previousLabel: dayLabel(context, previous),
            nextLabel: dayLabel(context, next),
            onPrevious: BsCalendar.isSupportedAd(previous)
                ? () => go(previous)
                : null,
            onNext: BsCalendar.isSupportedAd(next) ? () => go(next) : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              child: DayDetailBody(key: ValueKey(date), date: date),
            ),
          ),
        ),
      ],
    );
  }
}
