import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patro_event.dart';
import 'calendar_sync_provider.dart';
import 'events_provider.dart';

/// Saves and deletes Patro's events, keeping any copy in a phone calendar
/// (such as Google Calendar) in step. The Patro event is always saved first;
/// the phone calendar follows.
class EventActions {
  const EventActions(this._ref);

  final Ref _ref;

  EventsNotifier get _events => _ref.read(eventsProvider.notifier);
  CalendarSyncNotifier get _sync => _ref.read(calendarSyncProvider.notifier);

  /// Saves [event] and its phone-calendar copy. Returns a message if the
  /// phone calendar refused it; the event is still saved in Patro.
  Future<String?> save(PatroEvent event, {PatroEvent? previous}) async {
    _events.upsert(event);
    final hadCopy = previous?.deviceEventId != null;
    if (event.deviceCalendarId == null && !hadCopy) return null;
    try {
      // A copy in a calendar the user switched away from goes first.
      final staleCopy =
          previous != null &&
          previous.deviceCalendarId != event.deviceCalendarId;
      if (staleCopy) await _sync.unpush(previous);
      final pushed = await _sync.push(
        staleCopy ? event.copyWith(deviceEventId: () => null) : event,
      );
      if (_stillSaved(event.id)) _events.upsert(pushed);
      return null;
    } on Object catch (e) {
      debugPrint('Patro: could not save to the phone calendar: $e');
      if (_stillSaved(event.id)) {
        _events.upsert(
          event.copyWith(
            deviceEventId: () => null,
            deviceCalendarId: () => null,
          ),
        );
      }
      return 'Saved in Patro, but the phone calendar would not take it.';
    }
  }

  /// Deletes [event] and its phone-calendar copy.
  Future<void> delete(PatroEvent event) async {
    _events.remove(event.id);
    try {
      await _sync.unpush(event);
    } on Object catch (e) {
      debugPrint('Patro: could not delete the phone calendar copy: $e');
    }
  }

  bool _stillSaved(String id) =>
      _ref.read(eventsProvider).all.any((e) => e.id == id);
}

final eventActionsProvider = Provider<EventActions>(EventActions.new);
