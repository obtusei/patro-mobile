import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/patro_day.dart';
import '../models/patro_event.dart';
import '../services/system_bridge.dart';
import 'calendar_provider.dart';
import 'events_provider.dart';

/// One reminder notification, due at [at] in the device's local time.
@immutable
class PendingReminder {
  const PendingReminder({
    required this.key,
    required this.at,
    required this.title,
    required this.text,
  });

  final String key;
  final DateTime at;
  final String title;
  final String text;

  Map<String, dynamic> toJson() => {
    'key': key,
    'at': at.millisecondsSinceEpoch,
    'title': title,
    'text': text,
  };
}

/// The next reminders for Patro's own events, soonest first. Events saved to
/// a phone calendar are left to that calendar, which reminds on its own.
List<PendingReminder> upcomingReminders(
  Iterable<PatroEvent> events,
  DateTime now, {
  int horizonDays = 60,
  int limit = 64,
}) {
  final today = BsCalendar.dateOnly(now);
  final horizon = now.add(Duration(days: horizonDays));
  final time = DateFormat.jm();
  final weekday = DateFormat('EEE, d MMM');
  final out = <PendingReminder>[];

  String whenLabel(DateTime day, DateTime firesAt) {
    final firesOn = DateTime.utc(firesAt.year, firesAt.month, firesAt.day);
    return switch (day.difference(firesOn).inDays) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => weekday.format(day),
    };
  }

  for (final e in events) {
    if (e.isExternal || e.deviceEventId != null || e.reminders.isEmpty) {
      continue;
    }
    if (!BsCalendar.isSupportedAd(e.date)) continue;
    // Reminders can fire days before the event; look that far past the
    // horizon, and a day back for same-day reminders on all-day events.
    final leadDays = (e.reminders.reduce(math.max) / 1440).ceil() + 1;
    final first = today.subtract(const Duration(days: 1));
    var last = today.add(Duration(days: horizonDays + math.max(leadDays, 0)));
    if (e.repeatUntil case final until? when until.isBefore(last)) last = until;
    if (last.isAfter(BsCalendar.lastSupportedAd)) {
      last = BsCalendar.lastSupportedAd;
    }

    final days = e.repeat == EventRepeat.none
        ? [e.date]
        : [
            for (
              var d = e.date.isAfter(first) ? e.date : first;
              !d.isAfter(last);
              d = d.add(const Duration(days: 1))
            )
              if (e.occursOnAd(d)) d,
          ];

    for (final day in days) {
      for (final lead in e.reminders) {
        final at = e.reminderTime(day, lead);
        if (!at.isAfter(now) || at.isAfter(horizon)) continue;
        final start = e.startMinutes;
        final parts = [
          whenLabel(day, at),
          if (start == null)
            'All day'
          else
            time.format(DateTime(2000, 1, 1, 0, start)),
          if (e.location.isNotEmpty) e.location,
        ];
        out.add(
          PendingReminder(
            key: '${e.id}|${day.toIso8601String().substring(0, 10)}|$lead',
            at: at,
            title: e.title,
            text: parts.join(' · '),
          ),
        );
      }
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// Keeps Android's scheduled reminder notifications in step with the events.
/// Watch it once from the app root.
final reminderSyncProvider = Provider<void>((ref) {
  if (!SystemBridge.isSupported) return;
  final events = ref.watch(eventsProvider.select((s) => s.all));
  // Re-plan each day so the 60-day window keeps moving.
  ref.watch(calendarProvider);

  final timer = Timer(const Duration(milliseconds: 600), () {
    unawaited(
      SystemBridge.scheduleReminders([
        for (final r in upcomingReminders(events, DateTime.now())) r.toJson(),
      ]),
    );
  });
  ref.onDispose(timer.cancel);
});
