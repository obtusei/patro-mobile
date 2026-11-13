import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nepali_utils/nepali_utils.dart';

import '../core/calendar_format.dart';
import '../models/app_settings.dart';
import '../models/patro_day.dart';
import 'remote_sync_provider.dart';
import 'settings_provider.dart';

export '../models/app_settings.dart' show ShellPage;

/// Today's date (UTC midnight of the device's local day), rolling over at
/// midnight, plus a bounded cache of materialised [PatroDay]s.
class CalendarNotifier extends Notifier<DateTime> {
  static const int _cacheCapacity = 1024;

  final Map<DateTime, PatroDay> _cache = {};
  Map<DateTime, List<Observance>> _published = const {};
  Timer? _midnightTimer;

  @override
  DateTime build() {
    ref.onDispose(() => _midnightTimer?.cancel());
    // Rebuilt, with a fresh cache, when the server publishes new holidays.
    _published = ref.watch(remoteObservancesProvider);
    _cache.clear();
    _scheduleRollover();
    return _localToday();
  }

  /// The day for [ad]. Widgets that call this should watch [calendarProvider]
  /// so they rebuild when "today" changes.
  PatroDay dayOn(DateTime ad) {
    final date = BsCalendar.dateOnly(ad);
    final cached = _cache.remove(date);
    if (cached != null) return _cache[date] = cached;

    final day = PatroDay.fromAd(
      date,
      today: state,
      extra: _published[date] ?? const [],
    );
    _cache[date] = day;
    if (_cache.length > _cacheCapacity) _cache.remove(_cache.keys.first);
    return day;
  }

  PatroDay dayOnBs(int year, int month, int day) =>
      dayOn(BsCalendar.toAd(NepaliDateTime(year, month, day)));

  static DateTime _localToday() {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }

  void _scheduleRollover() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(
      next.difference(now) + const Duration(seconds: 1),
      () {
        final today = _localToday();
        if (today != state) {
          _cache.clear();
          state = today;
        }
        _scheduleRollover();
      },
    );
  }
}

final calendarProvider = NotifierProvider<CalendarNotifier, DateTime>(
  CalendarNotifier.new,
);

/// The loaded window of the bidirectional day list.
///
/// Days are addressed by offset from [anchor] (0 = anchor, negative = past).
/// Rows have variable height, so jumping to a far date re-anchors the list
/// on that date instead of computing a pixel offset.
@immutable
class TimelineState {
  const TimelineState({
    required this.anchor,
    required this.firstOffset,
    required this.lastOffset,
  });

  final DateTime anchor;
  final int firstOffset;
  final int lastOffset;

  int get pastCount => -firstOffset;
  int get futureCount => lastOffset + 1;

  DateTime dateAt(int offset) => anchor.add(Duration(days: offset));

  int offsetOf(DateTime ad) =>
      BsCalendar.dateOnly(ad).difference(anchor).inDays;
}

class TimelineNotifier extends Notifier<TimelineState> {
  static const int initialPastDays = 30;
  static const int initialFutureDays = 60;
  static const int chunkSize = 45;

  @override
  TimelineState build() => _windowAround(ref.read(calendarProvider));

  int get _minOffset =>
      BsCalendar.firstSupportedAd.difference(state.anchor).inDays;
  int get _maxOffset =>
      BsCalendar.lastSupportedAd.difference(state.anchor).inDays;

  bool get canLoadPast => state.firstOffset > _minOffset;
  bool get canLoadFuture => state.lastOffset < _maxOffset;

  void loadPast() {
    if (!canLoadPast) return;
    state = TimelineState(
      anchor: state.anchor,
      firstOffset: math.max(state.firstOffset - chunkSize, _minOffset),
      lastOffset: state.lastOffset,
    );
  }

  void loadFuture() {
    if (!canLoadFuture) return;
    state = TimelineState(
      anchor: state.anchor,
      firstOffset: state.firstOffset,
      lastOffset: math.min(state.lastOffset + chunkSize, _maxOffset),
    );
  }

  void reanchor(DateTime date) => state = _windowAround(date);

  static TimelineState _windowAround(DateTime date) {
    var anchor = BsCalendar.dateOnly(date);
    if (anchor.isBefore(BsCalendar.firstSupportedAd)) {
      anchor = BsCalendar.firstSupportedAd;
    } else if (anchor.isAfter(BsCalendar.lastSupportedAd)) {
      anchor = BsCalendar.lastSupportedAd;
    }
    final minOffset = BsCalendar.firstSupportedAd.difference(anchor).inDays;
    final maxOffset = BsCalendar.lastSupportedAd.difference(anchor).inDays;
    return TimelineState(
      anchor: anchor,
      firstOffset: math.max(-initialPastDays, minOffset),
      lastOffset: math.min(initialFutureDays - 1, maxOffset),
    );
  }
}

final timelineProvider = NotifierProvider<TimelineNotifier, TimelineState>(
  TimelineNotifier.new,
);

/// The page on screen; starts on the one picked in Settings.
final shellPageProvider = StateProvider<ShellPage>(
  (ref) => ref.read(settingsProvider).effectiveStartPage,
);

/// The day shown on the date page; null is today.
final datePageDayProvider = StateProvider<DateTime?>((ref) => null);

/// Day picked on the month page; null falls back to today or the 1st.
final selectedDayProvider = StateProvider<DateTime?>((ref) => null);

/// First day of the BS month shown on the month page; its year drives the
/// year page.
final focusedMonthProvider = StateProvider<NepaliDateTime>(
  (ref) => bsMonthOf(ref.read(calendarProvider)),
);
