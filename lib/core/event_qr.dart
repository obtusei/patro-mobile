import 'package:flutter/widgets.dart';

import '../models/patro_day.dart';
import '../models/patro_event.dart';

const _maxTitle = 200;
const _maxNote = 300;

/// RRULE frequencies for the repeats phone calendars understand.
const _rrules = {
  EventRepeat.daily: 'DAILY',
  EventRepeat.weekly: 'WEEKLY',
  EventRepeat.monthlyAd: 'MONTHLY',
  EventRepeat.yearlyAd: 'YEARLY',
};

String _escape(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\n', r'\n');

String _unescape(String value) => value.replaceAllMapped(
  RegExp(r'\\(.)'),
  (m) => m[1] == 'n' || m[1] == 'N' ? '\n' : m[1]!,
);

/// [event] as an iCalendar VEVENT, which phone cameras can also add to a
/// calendar. Long text is cut so the code stays scannable.
String eventToQr(PatroEvent event) {
  String two(int v) => v.toString().padLeft(2, '0');
  final d = event.date;
  final day =
      '${d.year.toString().padLeft(4, '0')}${two(d.month)}${two(d.day)}';
  String at(int minutes) =>
      '${day}T${two(minutes ~/ 60)}${two(minutes % 60)}00';

  final start = event.startMinutes;
  final end = event.endMinutes;
  final note = event.note.characters.take(_maxNote).toString();
  final u = event.repeatUntil;
  final until = u == null
      ? null
      : '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}';
  return [
    'BEGIN:VEVENT',
    'SUMMARY:${_escape(event.title.characters.take(_maxTitle).toString())}',
    if (start == null) 'DTSTART;VALUE=DATE:$day' else 'DTSTART:${at(start)}',
    if (end != null) 'DTEND:${at(end)}',
    if (note.isNotEmpty) 'DESCRIPTION:${_escape(note)}',
    if (event.location.isNotEmpty)
      'LOCATION:${_escape(event.location.characters.take(_maxTitle).toString())}',
    if (event.url.isNotEmpty) 'URL:${event.url}',
    if (_rrules[event.repeat] case final freq?)
      'RRULE:FREQ=$freq${until == null ? '' : ';UNTIL=$until'}',
    if (event.repeat.followsBs) 'X-PATRO-REPEAT:${event.repeat.name}',
    if (event.repeat.followsBs && until != null) 'X-PATRO-UNTIL:$until',
    'END:VEVENT',
  ].join('\n');
}

DateTime? _parseStamp(String value) {
  final m = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?',
  ).firstMatch(value);
  if (m == null) return null;
  int part(int i) => int.parse(m[i] ?? '0');
  final parts = [part(1), part(2), part(3), part(4), part(5), part(6)];
  final utc = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (m[7] == null) return utc;
  // Keep the wall-clock reading of a UTC stamp in this device's zone.
  final local = utc.toLocal();
  return DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
  );
}

/// The event in a scanned code, or null if the code isn't one.
PatroEvent? eventFromQr(String raw) {
  if (!raw.contains('BEGIN:VEVENT')) return null;

  final lines = <String>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final folded = line.startsWith(' ') || line.startsWith('\t');
    if (folded && lines.isNotEmpty) {
      lines.last += line.substring(1);
    } else {
      lines.add(line);
    }
  }

  final fields = <String, String>{};
  final allDayFields = <String>{};
  for (final line in lines) {
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final head = line.substring(0, colon).toUpperCase().split(';');
    if (fields.containsKey(head.first)) continue;
    fields[head.first] = line.substring(colon + 1);
    if (head.contains('VALUE=DATE')) allDayFields.add(head.first);
  }

  final title = _unescape(fields['SUMMARY'] ?? '').trim();
  final start = _parseStamp(fields['DTSTART'] ?? '');
  if (title.isEmpty || start == null || !BsCalendar.isSupportedAd(start)) {
    return null;
  }
  final allDay =
      allDayFields.contains('DTSTART') || !fields['DTSTART']!.contains('T');
  final end = _parseStamp(fields['DTEND'] ?? '');
  final sameDayEnd =
      end != null && BsCalendar.dateOnly(end) == BsCalendar.dateOnly(start);

  final rrule = fields['RRULE'] ?? '';
  final bsRepeat = EventRepeat.values.asNameMap()[fields['X-PATRO-REPEAT']];
  final repeat = bsRepeat != null && bsRepeat.followsBs
      ? bsRepeat
      : _rrules.entries
                .where((r) => rrule.contains('FREQ=${r.value}'))
                .firstOrNull
                ?.key ??
            EventRepeat.none;
  final untilStamp =
      RegExp(r'UNTIL=(\w+)').firstMatch(rrule)?[1] ?? fields['X-PATRO-UNTIL'];
  final until = untilStamp == null ? null : _parseStamp(untilStamp);

  return PatroEvent.create(
    date: start,
    title: title,
    note: _unescape(fields['DESCRIPTION'] ?? '').trim(),
    startMinutes: allDay ? null : start.hour * 60 + start.minute,
    endMinutes: allDay || !sameDayEnd ? null : end.hour * 60 + end.minute,
    repeat: repeat,
    repeatUntil: repeat == EventRepeat.none ? null : until,
    location: _unescape(fields['LOCATION'] ?? '').trim(),
    url: (fields['URL'] ?? '').trim(),
  );
}
