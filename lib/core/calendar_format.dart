import 'package:intl/intl.dart';
import 'package:nepali_utils/nepali_utils.dart';

import '../models/patro_day.dart';

const _devanagariDigits = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];

String devanagariDigits(String input) => input.replaceAllMapped(
  RegExp('[0-9]'),
  (m) => _devanagariDigits[m[0]!.codeUnitAt(0) - 0x30],
);

/// Indexed by NepaliDateTime.weekday - 1 (Sunday first).
const nepaliWeekdaysShort = [
  'आइत',
  'सोम',
  'मंगल',
  'बुध',
  'बिही',
  'शुक्र',
  'शनि',
];
const englishWeekdaysShort = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

/// BS month name in Devanagari ("कार्तिक") or romanised ("Kartik").
String bsMonthName(int month, {bool nepali = true}) => NepaliDateTime(
  2080,
  month,
).format('MMMM', nepali ? Language.nepali : Language.english);

/// First day of the BS month at [index] months after Baishakh [BsCalendar.minYear].
NepaliDateTime bsMonthAt(int index) =>
    NepaliDateTime(BsCalendar.minYear + index ~/ 12, index % 12 + 1);

int bsMonthIndex(NepaliDateTime month) =>
    (month.year - BsCalendar.minYear) * 12 + month.month - 1;

const int bsMonthCount = (BsCalendar.maxYear - BsCalendar.minYear + 1) * 12;

NepaliDateTime bsMonthOf(DateTime ad) {
  final bs = BsCalendar.fromAd(ad);
  return NepaliDateTime(bs.year, bs.month);
}

String _span(DateTime start, DateTime end) {
  final mmm = DateFormat('MMM');
  final label = start.year == end.year
      ? '${mmm.format(start)} – ${mmm.format(end)} ${end.year}'
      : '${mmm.format(start)} ${start.year} – ${mmm.format(end)} ${end.year}';
  return label.toUpperCase();
}

/// "OCT – NOV 2026": the Gregorian months a BS month straddles.
String adSpanOfBsMonth(NepaliDateTime month) => _span(
  BsCalendar.toAd(NepaliDateTime(month.year, month.month)),
  BsCalendar.toAd(NepaliDateTime(month.year, month.month, month.totalDays)),
);

/// "APR 2026 – APR 2027": the Gregorian span of a BS year.
String adSpanOfBsYear(int year) => _span(
  BsCalendar.toAd(NepaliDateTime(year)),
  BsCalendar.toAd(NepaliDateTime(year, 12, NepaliDateTime(year, 12).totalDays)),
);
