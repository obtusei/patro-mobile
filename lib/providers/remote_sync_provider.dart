import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patro_day.dart';
import '../models/patro_event.dart';
import '../services/patro_api.dart';
import 'settings_provider.dart';
import 'storage_provider.dart';

enum RemoteStatus { idle, syncing, failed }

/// Holidays, festivals and events published on the Patro server, cached so
/// they show offline.
@immutable
class RemoteSyncState {
  factory RemoteSyncState({
    RemoteStatus status = RemoteStatus.idle,
    List<RemoteItem> items = const [],
    DateTime? lastSynced,
    String? error,
  }) => RemoteSyncState._(
    status: status,
    items: items,
    lastSynced: lastSynced,
    error: error,
    observances: _observancesOf(items),
    events: _eventsOf(items),
  );

  const RemoteSyncState._({
    required this.status,
    required this.items,
    required this.lastSynced,
    required this.error,
    required this.observances,
    required this.events,
  });

  final RemoteStatus status;
  final List<RemoteItem> items;
  final DateTime? lastSynced;
  final String? error;

  /// Published holidays and festivals by UTC-midnight date.
  final Map<DateTime, List<Observance>> observances;

  /// Published events and notices, as read-only events.
  final List<PatroEvent> events;

  static Map<DateTime, List<Observance>> _observancesOf(List<RemoteItem> all) {
    final map = <DateTime, List<Observance>>{};
    for (final item in all) {
      if (!item.kind.isObservance) continue;
      (map[item.date] ??= []).add(
        Observance(item.title, isHoliday: item.isHoliday),
      );
    }
    return map;
  }

  static List<PatroEvent> _eventsOf(List<RemoteItem> all) => [
    for (final item in all)
      if (!item.kind.isObservance)
        PatroEvent(
          id: 'patro:${item.id}:${item.date.toIso8601String().substring(0, 10)}',
          date: item.date,
          title: item.title,
          note: item.description,
          startMinutes: item.startMinutes,
          endMinutes: item.startMinutes == null ? null : item.endMinutes,
          color: item.color,
          location: item.location,
          url: item.url,
          calendarName: 'Patro',
        ),
  ];

  /// Keeps the derived maps, so status changes don't redraw every day.
  RemoteSyncState copyWith({RemoteStatus? status, String? Function()? error}) =>
      RemoteSyncState._(
        status: status ?? this.status,
        items: items,
        lastSynced: lastSynced,
        error: error != null ? error() : this.error,
        observances: observances,
        events: events,
      );
}

class RemoteSyncNotifier extends Notifier<RemoteSyncState> {
  static const storageKey = 'patro.remote.v1';

  /// Refetch when the cache is older than this.
  static const staleAfter = Duration(hours: 6);

  /// Skipped under `flutter test`, where there is no network.
  static bool enabled =
      kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST');

  late String _url;

  @override
  RemoteSyncState build() {
    final on = ref.watch(settingsProvider.select((s) => s.onlineEvents));
    _url = ref.watch(settingsProvider.select((s) => s.serverUrl));
    if (!on) return RemoteSyncState();

    final cached = _load();
    final fresh =
        cached != null &&
        cached.url == _url &&
        DateTime.now().difference(cached.state.lastSynced!) < staleAfter;
    if (!fresh) Future.microtask(refresh);
    return cached != null && cached.url == _url
        ? cached.state
        : RemoteSyncState();
  }

  ({String url, RemoteSyncState state})? _load() {
    final raw = ref.read(sharedPreferencesProvider).getString(storageKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final synced = DateTime.tryParse('${json['syncedAt']}');
      if (synced == null) return null;
      return (
        url: json['url'] as String? ?? '',
        state: RemoteSyncState(
          lastSynced: synced,
          items: [
            for (final item in json['items'] as List<dynamic>)
              ?RemoteItem.fromJson(item),
          ],
        ),
      );
    } on Object catch (e) {
      debugPrint('Patro: discarding unreadable server cache: $e');
      return null;
    }
  }

  /// Fetches a year back and two years ahead.
  Future<void> refresh() async {
    if (!enabled || !ref.read(settingsProvider).onlineEvents) return;
    if (state.status == RemoteStatus.syncing) return;
    final url = _url;
    state = state.copyWith(status: RemoteStatus.syncing, error: () => null);
    final now = DateTime.now();
    try {
      final items = await PatroApi.fetchEvents(
        url,
        from: DateTime.utc(now.year - 1, 1, 1),
        to: DateTime.utc(now.year + 2, 12, 31),
      );
      // Settings changed while fetching: that rebuild owns the state now.
      if (url != _url) return;
      final synced = DateTime.now();
      state = RemoteSyncState(items: items, lastSynced: synced);
      unawaited(
        ref
            .read(sharedPreferencesProvider)
            .setString(
              storageKey,
              jsonEncode({
                'url': url,
                'syncedAt': synced.toIso8601String(),
                'items': [for (final i in items) i.toJson()],
              }),
            ),
      );
    } on Object catch (e) {
      debugPrint('Patro: could not reach $url: $e');
      if (url != _url) return;
      state = state.copyWith(
        status: RemoteStatus.failed,
        error: () => e is PatroApiException
            ? e.message
            : 'Could not reach the Patro server',
      );
    }
  }
}

final remoteSyncProvider =
    NotifierProvider<RemoteSyncNotifier, RemoteSyncState>(
      RemoteSyncNotifier.new,
    );

/// Published holidays and festivals by date; feeds every [PatroDay].
final remoteObservancesProvider = Provider<Map<DateTime, List<Observance>>>(
  (ref) => ref.watch(remoteSyncProvider.select((s) => s.observances)),
);
