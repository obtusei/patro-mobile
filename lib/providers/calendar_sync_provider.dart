import 'dart:async';
import 'dart:math' as math;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patro_event.dart';
import '../core/platform.dart';
import 'events_provider.dart';
import 'storage_provider.dart';

enum SyncStatus { idle, syncing, denied, failed }

@immutable
class CalendarSyncState {
  const CalendarSyncState({
    this.connected = false,
    this.status = SyncStatus.idle,
    this.calendars = const [],
    this.selected = const {},
    this.lastSynced,
  });

  final bool connected;
  final SyncStatus status;
  final List<Calendar> calendars;
  final Set<String> selected;
  final DateTime? lastSynced;

  /// Calendars Patro can save events to, such as a Google account's.
  List<Calendar> get writable => [
    for (final c in calendars)
      if (!c.readOnly && !c.hidden) c,
  ];

  Calendar? calendarById(String? id) {
    for (final c in calendars) {
      if (c.id == id) return c;
    }
    return null;
  }

  CalendarSyncState copyWith({
    bool? connected,
    SyncStatus? status,
    List<Calendar>? calendars,
    Set<String>? selected,
    DateTime? lastSynced,
  }) {
    return CalendarSyncState(
      connected: connected ?? this.connected,
      status: status ?? this.status,
      calendars: calendars ?? this.calendars,
      selected: selected ?? this.selected,
      lastSynced: lastSynced ?? this.lastSynced,
    );
  }
}

/// Reads the calendars of the accounts on this phone (Google, Outlook, Samsung
/// and so on) and shows their events alongside Patro's. Their events are not
/// stored. Patro writes only copies of its own events, when the user picks a
/// calendar for them, and never touches anything else.
class CalendarSyncNotifier extends Notifier<CalendarSyncState> {
  static const storageKey = 'patro.calendars.v1';
  static const _pastDays = 90;
  static const _futureDays = 400;
  static const _maxSpanDays = 31;

  bool _running = false;

  @override
  CalendarSyncState build() {
    final saved = ref.read(sharedPreferencesProvider).getStringList(storageKey);
    final listener = AppLifecycleListener(onResume: () => unawaited(refresh()));
    ref.onDispose(listener.dispose);
    if (saved != null && isPhone) Future.microtask(refresh);
    return CalendarSyncState(
      connected: saved != null,
      selected: saved?.toSet() ?? const {},
    );
  }

  /// Asks for access, then turns on every calendar the phone shows.
  Future<void> connect() async {
    final plugin = DeviceCalendar.instance;
    try {
      final access = await plugin.requestPermissions();
      if (access != CalendarPermissionStatus.granted) {
        state = state.copyWith(status: SyncStatus.denied);
        return;
      }
      final calendars = await plugin.listCalendars();
      state = state.copyWith(
        connected: true,
        calendars: calendars,
        selected: {
          for (final c in calendars)
            if (!c.hidden) c.id,
        },
      );
      _save();
      await _pull();
    } on Object catch (e) {
      debugPrint('Patro: could not connect calendars: $e');
      state = state.copyWith(status: SyncStatus.failed);
    }
  }

  void disconnect() {
    unawaited(ref.read(sharedPreferencesProvider).remove(storageKey));
    ref.read(externalEventsProvider.notifier).state = const [];
    state = const CalendarSyncState();
  }

  void toggle(String calendarId, {required bool on}) {
    state = state.copyWith(
      selected: {
        for (final id in state.selected)
          if (id != calendarId) id,
        if (on) calendarId,
      },
    );
    _save();
    unawaited(_pull());
  }

  Future<void> refresh() async {
    if (!state.connected || !isPhone) return;
    final plugin = DeviceCalendar.instance;
    try {
      final access = await plugin.hasPermissions();
      if (access != CalendarPermissionStatus.granted) {
        ref.read(externalEventsProvider.notifier).state = const [];
        state = state.copyWith(status: SyncStatus.denied);
        return;
      }
      state = state.copyWith(calendars: await plugin.listCalendars());
      await _pull();
    } on Object catch (e) {
      debugPrint('Patro: could not read calendars: $e');
      state = state.copyWith(status: SyncStatus.failed);
    }
  }

  Future<void> _pull() async {
    if (_running) return;
    _running = true;
    state = state.copyWith(status: SyncStatus.syncing);
    try {
      final now = DateTime.now();
      final selected = state.selected.toList();
      final events = selected.isEmpty
          ? const <Event>[]
          : await DeviceCalendar.instance.listEvents(
              now.subtract(const Duration(days: _pastDays)),
              now.add(const Duration(days: _futureDays)),
              calendarIds: selected,
            );
      final calendars = {for (final c in state.calendars) c.id: c};
      ref.read(externalEventsProvider.notifier).state = [
        for (final e in events)
          if (e.status != EventStatus.canceled)
            ..._daysOf(e, calendars[e.calendarId]),
      ];
      state = state.copyWith(status: SyncStatus.idle, lastSynced: now);
    } on Object catch (e) {
      debugPrint('Patro: could not read calendar events: $e');
      state = state.copyWith(status: SyncStatus.failed);
    } finally {
      _running = false;
    }
  }

  /// One [PatroEvent] for each day [e] touches.
  Iterable<PatroEvent> _daysOf(Event e, Calendar? calendar) sync* {
    final first = DateTime.utc(
      e.startDate.year,
      e.startDate.month,
      e.startDate.day,
    );
    // End dates are exclusive.
    final last = e.endDate.subtract(const Duration(seconds: 1));
    final lastDay = DateTime.utc(last.year, last.month, last.day);
    final span = math.min(
      math.max(lastDay.difference(first).inDays, 0),
      _maxSpanDays,
    );
    final startMinutes = e.startDate.hour * 60 + e.startDate.minute;
    final endMinutes = e.endDate.hour * 60 + e.endDate.minute;

    for (var i = 0; i <= span; i++) {
      yield PatroEvent(
        id: 'calendar-${e.instanceId}-$i',
        date: first.add(Duration(days: i)),
        title: e.title.isEmpty ? '(No title)' : e.title,
        note: e.description ?? '',
        startMinutes: e.isAllDay || i > 0 ? null : startMinutes,
        endMinutes: e.isAllDay || span > 0 ? null : endMinutes,
        color: calendar?.color,
        calendarName: calendar?.name ?? 'Calendar',
        location: e.location ?? '',
        url: e.url ?? '',
        deviceEventId: e.eventId,
        deviceCalendarId: e.calendarId,
      );
    }
  }

  /// Saves a copy of [event] to its [PatroEvent.deviceCalendarId] calendar,
  /// replacing any earlier copy, and returns the event with the new copy's
  /// id. With no calendar, removes the copy. Throws if the calendar refuses.
  Future<PatroEvent> push(PatroEvent event) async {
    await unpush(event);
    final calendarId = event.deviceCalendarId;
    if (calendarId == null || !isPhone) {
      return event.copyWith(deviceEventId: () => null);
    }

    final d = event.date;
    final DateTime start;
    final DateTime end;
    if (event.startMinutes case final minutes?) {
      start = DateTime(d.year, d.month, d.day, 0, minutes);
      final endMinutes = event.endMinutes ?? minutes + 60;
      end = DateTime(d.year, d.month, d.day, 0, math.max(endMinutes, minutes));
    } else {
      start = DateTime(d.year, d.month, d.day);
      end = DateTime(d.year, d.month, d.day + 1);
    }

    final id = await DeviceCalendar.instance.createEvent(
      calendarId: calendarId,
      title: event.title,
      startDate: start,
      endDate: end,
      isAllDay: event.isAllDay,
      description: event.note.isEmpty ? null : event.note,
      location: event.location.isEmpty ? null : event.location,
      url: event.url.isEmpty ? null : event.url,
      recurrenceRule: _ruleFor(event),
      // Phone calendars count only lead times before the start.
      reminders: [
        for (final m in event.reminders)
          if (m >= 0) Duration(minutes: m),
      ],
    );
    unawaited(_pull());
    return event.copyWith(deviceEventId: () => id);
  }

  /// Deletes the phone-calendar copy of [event], if it has one. A copy the
  /// user already deleted there is not an error.
  Future<void> unpush(PatroEvent event) async {
    final id = event.deviceEventId;
    if (id == null || !isPhone) return;
    try {
      final existing = await DeviceCalendar.instance.getEvent(id);
      if (existing == null) return;
      if (existing.isRecurring) {
        await DeviceCalendar.instance.deleteRecurring(
          existing.eventId,
          EventSpan.allEvents,
        );
      } else {
        await DeviceCalendar.instance.deleteEvent(instanceId: id);
      }
      unawaited(_pull());
    } on DeviceCalendarException catch (e) {
      if (e.errorCode != DeviceCalendarError.notFound) rethrow;
    }
  }

  /// Phone calendars repeat by the Gregorian calendar only, so a BS repeat
  /// is saved there as its first date alone.
  static RecurrenceRule? _ruleFor(PatroEvent event) {
    final until = event.repeatUntil;
    final end = until == null
        ? null
        : UntilEnd(DateTime(until.year, until.month, until.day, 23, 59));
    return switch (event.repeat) {
      EventRepeat.none || EventRepeat.monthlyBs || EventRepeat.yearlyBs => null,
      EventRepeat.daily => DailyRecurrence(end: end),
      EventRepeat.weekly => WeeklyRecurrence(end: end),
      EventRepeat.monthlyAd => MonthlyByDate(end: end),
      EventRepeat.yearlyAd => YearlyByDate(end: end),
    };
  }

  void _save() => unawaited(
    ref
        .read(sharedPreferencesProvider)
        .setStringList(storageKey, state.selected.toList()),
  );
}

final calendarSyncProvider =
    NotifierProvider<CalendarSyncNotifier, CalendarSyncState>(
      CalendarSyncNotifier.new,
    );
