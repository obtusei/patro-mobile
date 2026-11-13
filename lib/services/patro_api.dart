import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// What the Patro server publishes for a day. Holidays and festivals are
/// shown like Patro's built-in observances; events and notices like
/// read-only calendar events.
enum RemoteKind {
  holiday,
  festival,
  event,
  notice;

  bool get isObservance => this == holiday || this == festival;
}

/// One occurrence published on the Patro server (see the web app's
/// `src/server` and `GET /api/v1/events`).
@immutable
class RemoteItem {
  const RemoteItem({
    required this.id,
    required this.date,
    required this.title,
    required this.kind,
    this.isHoliday = false,
    this.startMinutes,
    this.endMinutes,
    this.color,
    this.description = '',
    this.location = '',
    this.url = '',
  });

  /// Null if [json] is not a usable item.
  static RemoteItem? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final title = json['title'];
    final date = DateTime.tryParse('${json['date']}');
    if (id is! String || title is! String || date == null) return null;
    final kind =
        RemoteKind.values.asNameMap()[json['kind']] ?? RemoteKind.event;
    return RemoteItem(
      id: id,
      date: DateTime.utc(date.year, date.month, date.day),
      title: title,
      kind: kind,
      isHoliday: json['isHoliday'] == true || kind == RemoteKind.holiday,
      startMinutes: (json['startMinutes'] as num?)?.toInt(),
      endMinutes: (json['endMinutes'] as num?)?.toInt(),
      color: _parseColor(json['color']),
      description: json['description'] as String? ?? '',
      location: json['location'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  final String id;

  /// UTC-midnight AD date of this occurrence.
  final DateTime date;
  final String title;
  final RemoteKind kind;
  final bool isHoliday;
  final int? startMinutes;
  final int? endMinutes;
  final Color? color;
  final String description;
  final String location;
  final String url;

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String().substring(0, 10),
    'title': title,
    'kind': kind.name,
    if (isHoliday) 'isHoliday': true,
    'startMinutes': ?startMinutes,
    'endMinutes': ?endMinutes,
    if (color case final c?)
      'color':
          '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
    if (description.isNotEmpty) 'description': description,
    if (location.isNotEmpty) 'location': location,
    if (url.isNotEmpty) 'url': url,
  };

  static Color? _parseColor(Object? v) {
    if (v is! String) return null;
    final hex = v.replaceFirst('#', '');
    final n = int.tryParse(hex, radix: 16);
    if (n == null || hex.length != 6) return null;
    return Color(0xFF000000 | n);
  }
}

/// Talks to the Patro server's public API.
abstract final class PatroApi {
  static const _timeout = Duration(seconds: 12);

  static String _date(DateTime d) => d.toIso8601String().substring(0, 10);

  /// Every published occurrence between [from] and [to], inclusive.
  static Future<List<RemoteItem>> fetchEvents(
    String baseUrl, {
    required DateTime from,
    required DateTime to,
    http.Client? client,
  }) async {
    final base = Uri.parse(baseUrl.trim());
    final uri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/api/v1/events',
      queryParameters: {'from': _date(from), 'to': _date(to)},
    );
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(_timeout);
      if (res.statusCode != 200) {
        throw PatroApiException('Server answered ${res.statusCode}');
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final list = body is Map<String, dynamic> ? body['events'] : null;
      if (list is! List<dynamic>) {
        throw const PatroApiException('Unexpected reply from the server');
      }
      return [for (final item in list) ?RemoteItem.fromJson(item)];
    } finally {
      if (client == null) c.close();
    }
  }
}

class PatroApiException implements Exception {
  const PatroApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
