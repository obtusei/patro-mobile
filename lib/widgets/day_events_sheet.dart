import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patro_day.dart';
import '../providers/events_provider.dart';
import '../screens/day_detail_screen.dart';
import '../theme/patro_style.dart';
import 'common.dart';
import 'event_editor_sheet.dart';
import 'event_tile.dart';

/// Everything on [day], in a bottom sheet.
Future<void> showDayEventsSheet(BuildContext context, PatroDay day) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DayEventsSheet(day: day),
  );
}

class _DayEventsSheet extends ConsumerWidget {
  const _DayEventsSheet({required this.day});

  final PatroDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final events = ref.watch(eventsProvider).on(day);
    final observances = s.showObservances ? day.observances : const [];

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '${s.weekdayFull(day)} · ${s.primaryDayNumeral(day)} '
              '${s.bsMonthYear(day.bsDate)}',
              style: s.body.copyWith(fontSize: 20),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              children: [
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
                if (events.isNotEmpty) ...[
                  const SectionLabel('Events'),
                  for (final e in events) EventTile(event: e, day: day),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      final navigator = Navigator.of(context)..pop();
                      navigator.push(DayDetailScreen.route(day.adDate));
                    },
                    child: const Text('Open day'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => showEventEditor(context, date: day.adDate),
                    child: const Text('Add event'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
