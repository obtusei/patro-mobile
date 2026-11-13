import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:nepali_utils/nepali_utils.dart';

import 'patro_day.dart';

enum EventRepeat {
  none('Never'),
  daily('Daily'),
  weekly('Weekly'),
  monthlyBs('Monthly · BS'),
  monthlyAd('Monthly · AD'),
  yearlyBs('Yearly · BS'),
  yearlyAd('Yearly · AD');

  const EventRepeat(this.label);
  final String label;

  /// Repeats by the Bikram Sambat calendar, which phone calendars can't do.
  bool get followsBs => this == monthlyBs || this == yearlyBs;
}

/// Reminder lead times, in minutes before a timed event starts.
const timedReminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440, 10080];

/// Reminder lead times for all-day events, in minutes before the day's
/// midnight; negative is later on the day itself (-540 is 9 AM on the day).
const allDayReminderOptions = [-540, 900, 2340, 9540];

/// A user-created event pinned to a calendar day.
@immutable
class PatroEvent {
  PatroEvent({
    required this.id,
    required DateTime date,
    required this.title,
    this.note = '',
    this.startMinutes,
    this.endMinutes,
    this.repeat = EventRepeat.none,
    this.color,
    this.calendarName,
    this.location = '',
    this.url = '',
    this.reminders = const [],
    DateTime? repeatUntil,
    this.deviceEventId,
    this.deviceCalendarId,
  }) : date = BsCalendar.dateOnly(date),
       repeatUntil = repeatUntil == null
           ? null
           : BsCalendar.dateOnly(repeatUntil);

  factory PatroEvent.create({
    required DateTime date,
    required String title,
    String note = '',
    int? startMinutes,
    int? endMinutes,
    EventRepeat repeat = EventRepeat.none,
    Color? color,
    String location = '',
    String url = '',
    List<int> reminders = const [],
    DateTime? repeatUntil,
  }) {
    final id =
        DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        _random.nextInt(1 << 30).toRadixString(36);
    return PatroEvent(
      id: id,
      date: date,
      title: title,
      note: note,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      repeat: repeat,
      color: color,
      location: location,
      url: url,
      reminders: reminders,
      repeatUntil: repeatUntil,
    );
  }

  factory PatroEvent.fromJson(Map<String, dynamic> json) {
    final color = json['color'] as int?;
    final until = json['until'] as String?;
    return PatroEvent(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      title: json['title'] as String,
      note: json['note'] as String? ?? '',
      startMinutes: json['start'] as int?,
      endMinutes: json['end'] as int?,
      repeat:
          EventRepeat.values.asNameMap()[json['repeat']] ?? EventRepeat.none,
      color: color == null ? null : Color(color),
      location: json['location'] as String? ?? '',
      url: json['url'] as String? ?? '',
      reminders: [
        if (json['reminders'] case final List<dynamic> list)
          for (final m in list)
            if (m is int) m,
      ],
      repeatUntil: until == null ? null : DateTime.tryParse(until),
      deviceEventId: json['deviceEvent'] as String?,
      deviceCalendarId: json['deviceCalendar'] as String?,
    );
  }

  static final _random = math.Random();

  final String id;

  /// UTC-midnight date of the (first) occurrence.
  final DateTime date;
  final String title;
  final String note;

  /// Minutes after midnight; null for an all-day event.
  final int? startMinutes;
  final int? endMinutes;
  final EventRepeat repeat;

  /// Null means "use the theme accent".
  final Color? color;

  /// The phone calendar this came from; null for Patro's own events. These
  /// are read-only and never saved.
  final String? calendarName;

  final String location;
  final String url;

  /// Lead times in minutes; see [timedReminderOptions] and
  /// [allDayReminderOptions].
  final List<int> reminders;

  /// Last day a repeating event can fall on; null repeats forever.
  final DateTime? repeatUntil;

  /// The event's id in a phone calendar: the copy Patro saved there, or, for
  /// an [isExternal] event, the event it was read from.
  final String? deviceEventId;

  /// The phone calendar holding the copy in [deviceEventId].
  final String? deviceCalendarId;

  bool get isExternal => calendarName != null;

  bool get isAllDay => startMinutes == null;

  late final NepaliDateTimeParts _originBs = NepaliDateTimeParts.of(date);

  bool occursOn(PatroDay day) => occursOnAd(day.adDate, day.bsDate);

  /// Whether an occurrence falls on the UTC-midnight date [ad]. Pass [bs] if
  /// it is already known.
  bool occursOnAd(DateTime ad, [NepaliDateTime? bs]) {
    if (ad.isBefore(date)) return false;
    if (repeat == EventRepeat.none) return ad == date;
    if (repeatUntil case final until? when ad.isAfter(until)) return false;
    switch (repeat) {
      case EventRepeat.none:
        return false;
      case EventRepeat.daily:
        return true;
      case EventRepeat.weekly:
        return ad.difference(date).inDays % 7 == 0;
      case EventRepeat.monthlyAd:
        final length = DateTime.utc(ad.year, ad.month + 1, 0).day;
        return ad.day == math.min(date.day, length);
      case EventRepeat.yearlyAd:
        return ad.month == date.month && ad.day == date.day;
      case EventRepeat.monthlyBs:
        final b = bs ?? BsCalendar.fromAd(ad);
        // A day-32 origin falls on the last day in shorter months.
        return b.day == math.min(_originBs.day, b.totalDays);
      case EventRepeat.yearlyBs:
        final b = bs ?? BsCalendar.fromAd(ad);
        return b.month == _originBs.month &&
            b.day == math.min(_originBs.day, b.totalDays);
    }
  }

  /// When a reminder [minutesBefore] the occurrence on [day] should fire,
  /// in the device's local time.
  DateTime reminderTime(DateTime day, int minutesBefore) => DateTime(
    day.year,
    day.month,
    day.day,
  ).add(Duration(minutes: (startMinutes ?? 0) - minutesBefore));

  static int compare(PatroEvent a, PatroEvent b) {
    final byStart = (a.startMinutes ?? -1).compareTo(b.startMinutes ?? -1);
    return byStart != 0 ? byStart : a.title.compareTo(b.title);
  }

  PatroEvent copyWith({
    DateTime? date,
    String? title,
    String? note,
    int? Function()? startMinutes,
    int? Function()? endMinutes,
    EventRepeat? repeat,
    Color? Function()? color,
    String? location,
    String? url,
    List<int>? reminders,
    DateTime? Function()? repeatUntil,
    String? Function()? deviceEventId,
    String? Function()? deviceCalendarId,
  }) {
    return PatroEvent(
      id: id,
      date: date ?? this.date,
      title: title ?? this.title,
      note: note ?? this.note,
      startMinutes: startMinutes != null ? startMinutes() : this.startMinutes,
      endMinutes: endMinutes != null ? endMinutes() : this.endMinutes,
      repeat: repeat ?? this.repeat,
      color: color != null ? color() : this.color,
      calendarName: calendarName,
      location: location ?? this.location,
      url: url ?? this.url,
      reminders: reminders ?? this.reminders,
      repeatUntil: repeatUntil != null ? repeatUntil() : this.repeatUntil,
      deviceEventId: deviceEventId != null
          ? deviceEventId()
          : this.deviceEventId,
      deviceCalendarId: deviceCalendarId != null
          ? deviceCalendarId()
          : this.deviceCalendarId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String().substring(0, 10),
    'title': title,
    if (note.isNotEmpty) 'note': note,
    'start': ?startMinutes,
    'end': ?endMinutes,
    if (repeat != EventRepeat.none) 'repeat': repeat.name,
    'color': ?color?.toARGB32(),
    if (location.isNotEmpty) 'location': location,
    if (url.isNotEmpty) 'url': url,
    if (reminders.isNotEmpty) 'reminders': reminders,
    'until': ?repeatUntil?.toIso8601String().substring(0, 10),
    'deviceEvent': ?deviceEventId,
    'deviceCalendar': ?deviceCalendarId,
  };
}

/// BS year/month/day of an AD date, without keeping a NepaliDateTime around.
@immutable
class NepaliDateTimeParts {
  const NepaliDateTimeParts(this.year, this.month, this.day);

  factory NepaliDateTimeParts.of(DateTime ad) {
    final bs = BsCalendar.fromAd(ad);
    return NepaliDateTimeParts(bs.year, bs.month, bs.day);
  }

  final int year;
  final int month;
  final int day;
}
