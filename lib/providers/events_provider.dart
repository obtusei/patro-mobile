import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patro_day.dart';
import '../models/patro_event.dart';
import 'remote_sync_provider.dart';
import 'storage_provider.dart';

/// Read-only events from the phone's calendars; see `CalendarSyncNotifier`.
final externalEventsProvider = StateProvider<List<PatroEvent>>(
  (ref) => const [],
);

/// All user events, indexed for per-day lookups.
@immutable
class EventsState {
  factory EventsState(
    List<PatroEvent> all, {
    List<PatroEvent> external = const [],
  }) {
    // Patro's own events saved to a phone calendar come back when that
    // calendar is read; show them once, as Patro's.
    final copies = {for (final e in all) ?e.deviceEventId};
    return EventsState._(all, [
      for (final e in external)
        if (!copies.contains(e.deviceEventId)) e,
    ]);
  }

  EventsState._(this.all, this.external)
    : _byDate = _index([...all, ...external]),
      _recurring = [
        for (final e in all)
          if (e.repeat != EventRepeat.none) e,
      ];

  final List<PatroEvent> all;
  final List<PatroEvent> external;
  final Map<DateTime, List<PatroEvent>> _byDate;
  final List<PatroEvent> _recurring;

  static Map<DateTime, List<PatroEvent>> _index(List<PatroEvent> events) {
    final map = <DateTime, List<PatroEvent>>{};
    for (final e in events) {
      if (e.repeat == EventRepeat.none) (map[e.date] ??= []).add(e);
    }
    return map;
  }

  List<PatroEvent> on(PatroDay day) {
    final exact = _byDate[day.adDate];
    if (exact == null && _recurring.isEmpty) return const [];
    return [...?exact, ..._recurring.where((e) => e.occursOn(day))]
      ..sort(PatroEvent.compare);
  }
}

class EventsNotifier extends Notifier<EventsState> {
  static const storageKey = 'patro.events.v1';

  /// Read-only events: the phone's calendars and the Patro server.
  List<PatroEvent> _external({bool watch = false}) => watch
      ? [
          ...ref.watch(externalEventsProvider),
          ...ref.watch(remoteSyncProvider.select((s) => s.events)),
        ]
      : [
          ...ref.read(externalEventsProvider),
          ...ref.read(remoteSyncProvider).events,
        ];

  @override
  EventsState build() {
    final external = _external(watch: true);
    final raw = ref.read(sharedPreferencesProvider).getString(storageKey);
    if (raw == null) return EventsState(const [], external: external);
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return EventsState([
        for (final e in list) PatroEvent.fromJson(e as Map<String, dynamic>),
      ], external: external);
    } on Object catch (e) {
      debugPrint('Patro: could not read saved events: $e');
      return EventsState(const [], external: external);
    }
  }

  void upsert(PatroEvent event) => _set([
    for (final e in state.all)
      if (e.id != event.id) e,
    event,
  ]);

  void remove(String id) => _set([
    for (final e in state.all)
      if (e.id != id) e,
  ]);

  void clear() => _set(const []);

  void _set(List<PatroEvent> events) {
    state = EventsState(events, external: _external());
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(
            storageKey,
            jsonEncode([for (final e in events) e.toJson()]),
          ),
    );
  }
}

final eventsProvider = NotifierProvider<EventsNotifier, EventsState>(
  EventsNotifier.new,
);
