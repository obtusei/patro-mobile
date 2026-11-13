import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nepali_utils/nepali_utils.dart';

import '../models/patro_day.dart';
import '../providers/calendar_provider.dart';
import '../screens/day_detail_screen.dart';
import '../theme/patro_style.dart';
import 'common.dart';

Future<void> showDateConverter(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _DateConverterSheet(),
  );
}

/// BS and AD side by side; changing either one updates the other.
class _DateConverterSheet extends ConsumerStatefulWidget {
  const _DateConverterSheet();

  @override
  ConsumerState<_DateConverterSheet> createState() =>
      _DateConverterSheetState();
}

class _DateConverterSheetState extends ConsumerState<_DateConverterSheet> {
  late DateTime _ad = ref.read(calendarProvider);

  void _setBs(int year, int month, int day) {
    final length = NepaliDateTime(year, month).totalDays;
    setState(() {
      _ad = BsCalendar.toAd(NepaliDateTime(year, month, math.min(day, length)));
    });
  }

  void _setAd(int year, int month, int day) {
    final length = DateUtils.getDaysInMonth(year, month);
    var next = DateTime.utc(year, month, math.min(day, length));
    if (next.isBefore(BsCalendar.firstSupportedAd)) {
      next = BsCalendar.firstSupportedAd;
    }
    if (next.isAfter(BsCalendar.lastSupportedAd)) {
      next = BsCalendar.lastSupportedAd;
    }
    setState(() => _ad = next);
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final day = ref.read(calendarProvider.notifier).dayOn(_ad);
    final bs = day.bsDate;
    final months = DateFormat('MMM');
    final observances = s.showObservances ? day.observances : const [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Date converter', style: s.body.copyWith(fontSize: 20)),
          const SectionLabel('Bikram Sambat'),
          _DateRow(
            year: bs.year,
            month: bs.month,
            day: bs.day,
            years: [
              for (var y = BsCalendar.minYear; y <= BsCalendar.maxYear; y++)
                (y, s.digits(y)),
            ],
            months: [for (var m = 1; m <= 12; m++) (m, s.bsMonth(m))],
            days: [for (var d = 1; d <= bs.totalDays; d++) (d, s.digits(d))],
            onChanged: _setBs,
          ),
          const SectionLabel('Gregorian'),
          _DateRow(
            year: _ad.year,
            month: _ad.month,
            day: _ad.day,
            years: [
              for (
                var y = BsCalendar.firstSupportedAd.year;
                y <= BsCalendar.lastSupportedAd.year;
                y++
              )
                (y, '$y'),
            ],
            months: [
              for (var m = 1; m <= 12; m++)
                (m, months.format(DateTime.utc(2000, m))),
            ],
            days: [
              for (
                var d = 1;
                d <= DateUtils.getDaysInMonth(_ad.year, _ad.month);
                d++
              )
                (d, '$d'),
            ],
            onChanged: _setAd,
          ),
          const SizedBox(height: 20),
          Text(
            s.weekdayFull(day),
            style: s.nepali.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          if (s.showTithi) Text(day.tithi, style: s.nepaliSmall),
          for (final o in observances)
            EventLine(title: o.name, color: o.isHoliday ? s.holiday : s.accent),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      setState(() => _ad = ref.read(calendarProvider)),
                  child: const Text('Today'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final navigator = Navigator.of(context)..pop();
                    navigator.push(DayDetailScreen.route(_ad));
                  },
                  child: const Text('Open day'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.year,
    required this.month,
    required this.day,
    required this.years,
    required this.months,
    required this.days,
    required this.onChanged,
  });

  final int year;
  final int month;
  final int day;
  final List<(int, String)> years;
  final List<(int, String)> months;
  final List<(int, String)> days;
  final void Function(int year, int month, int day) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _Picker(
            value: year,
            items: years,
            onChanged: (y) => onChanged(y, month, day),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: _Picker(
            value: month,
            items: months,
            onChanged: (m) => onChanged(year, m, day),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _Picker(
            value: day,
            items: days,
            onChanged: (d) => onChanged(year, month, d),
          ),
        ),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final int value;
  final List<(int, String)> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: s.scaledRadius(0.7),
      ),
      child: DropdownButton<int>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        menuMaxHeight: 320,
        style: s.body.copyWith(fontSize: 16),
        items: [
          for (final (id, label) in items)
            DropdownMenuItem(
              value: id,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
