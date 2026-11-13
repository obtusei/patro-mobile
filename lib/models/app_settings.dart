import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/astronomy.dart';
import '../core/platform.dart';

enum CalendarSystem { bs, ad }

/// How the month grid marks days that have events or festivals.
enum DayIndicator {
  /// A faint fill in the day's colour, with the numeral in that colour.
  faded('Faded'),

  /// A rounded fill: tinted for one item, solid for several.
  background('Background'),

  /// Small dots under the numeral.
  dots('Dots');

  const DayIndicator(this.label);
  final String label;
}

/// Months per row the year page offers.
const yearColumnChoices = [2, 3];

/// The Patro server new public holidays and events are fetched from.
const defaultServerUrl = 'https://patro.obtusei.com';

/// Weekly holiday choices offered in Settings. Weekdays follow
/// NepaliDateTime: Sunday = 1 … Saturday = 7.
const weekendPresets = <(String, List<int>)>[
  ('Saturday', [7]),
  ('Sunday', [1]),
  ('Saturday & Sunday', [1, 7]),
  ('Friday & Saturday', [6, 7]),
  ('None', []),
];

/// Places offered for the Sky page, before the user's own.
const skyPlaces = [
  GeoLocation.kathmandu,
  GeoLocation(28.2096, 83.9856, 'Pokhara'),
  GeoLocation(26.4525, 87.2718, 'Biratnagar'),
  GeoLocation(27.0104, 84.8770, 'Birgunj'),
  GeoLocation(26.7288, 85.9263, 'Janakpur'),
  GeoLocation(27.6766, 84.4309, 'Bharatpur'),
  GeoLocation(27.4840, 83.2760, 'Lumbini'),
  GeoLocation(28.0500, 81.6167, 'Nepalgunj'),
  GeoLocation(28.6852, 80.6216, 'Dhangadhi'),
  GeoLocation(29.2747, 82.1838, 'Jumla'),
  GeoLocation(27.9881, 86.9250, 'Everest'),
];

/// The pages of the home shell, left to right.
enum ShellPage {
  year('Year'),
  month('Month'),
  day('Days'),
  date('Date'),
  sky('Sky'),
  compass('Compass'),
  settings('Settings');

  const ShellPage(this.label);
  final String label;
}

enum ColorRole {
  background('Background', 'Page colour behind everything'),
  surface('Surface', 'Sheets, panels and month cells'),
  ink('Text', 'Numerals, names and events'),
  accent('Accent', 'Brand, month names and default event colour'),
  highlight('Today', 'Today\'s glow and selected controls'),
  holiday('Holiday', 'Saturdays and public holidays');

  const ColorRole(this.label, this.description);
  final String label;
  final String description;
}

@immutable
class PatroColorSet {
  const PatroColorSet({
    required this.background,
    required this.surface,
    required this.ink,
    required this.accent,
    required this.highlight,
    required this.holiday,
  });

  factory PatroColorSet.fromJson(
    Map<String, dynamic> json,
    PatroColorSet fallback,
  ) {
    Color read(ColorRole role) {
      final v = json[role.name];
      return v is int ? Color(v) : fallback.of(role);
    }

    return PatroColorSet(
      background: read(ColorRole.background),
      surface: read(ColorRole.surface),
      ink: read(ColorRole.ink),
      accent: read(ColorRole.accent),
      highlight: read(ColorRole.highlight),
      holiday: read(ColorRole.holiday),
    );
  }

  final Color background;
  final Color surface;
  final Color ink;
  final Color accent;
  final Color highlight;
  final Color holiday;

  Color of(ColorRole role) => switch (role) {
    ColorRole.background => background,
    ColorRole.surface => surface,
    ColorRole.ink => ink,
    ColorRole.accent => accent,
    ColorRole.highlight => highlight,
    ColorRole.holiday => holiday,
  };

  PatroColorSet withRole(ColorRole role, Color color) => PatroColorSet(
    background: role == ColorRole.background ? color : background,
    surface: role == ColorRole.surface ? color : surface,
    ink: role == ColorRole.ink ? color : ink,
    accent: role == ColorRole.accent ? color : accent,
    highlight: role == ColorRole.highlight ? color : highlight,
    holiday: role == ColorRole.holiday ? color : holiday,
  );

  Map<String, int> toJson() => {
    for (final role in ColorRole.values) role.name: of(role).toARGB32(),
  };

  @override
  bool operator ==(Object other) =>
      other is PatroColorSet &&
      ColorRole.values.every((r) => of(r) == other.of(r));

  @override
  int get hashCode => Object.hashAll(ColorRole.values.map(of));
}

@immutable
class ThemePreset {
  const ThemePreset(this.id, this.name, this.colors);

  /// A theme the user saved; null if [json] is not one.
  static ThemePreset? fromJson(Object? json, PatroColorSet fallback) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final name = json['name'];
    final colors = json['colors'];
    if (id is! String || name is! String || colors is! Map<String, dynamic>) {
      return null;
    }
    return ThemePreset(id, name, PatroColorSet.fromJson(colors, fallback));
  }

  static const customPrefix = 'custom-';

  final String id;
  final String name;
  final PatroColorSet colors;

  bool get isCustom => id.startsWith(customPrefix);

  ThemePreset copyWith({String? name, PatroColorSet? colors}) =>
      ThemePreset(id, name ?? this.name, colors ?? this.colors);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colors': colors.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ThemePreset &&
      other.id == id &&
      other.name == name &&
      other.colors == colors;

  @override
  int get hashCode => Object.hash(id, name, colors);
}

const themePresets = [
  ThemePreset(
    'obsidian',
    'Obsidian',
    PatroColorSet(
      background: Color(0xFF121214),
      surface: Color(0xFF1B1B1F),
      ink: Color(0xFFEFECE6),
      accent: Color(0xFFFFD700),
      highlight: Color(0xFF4A80F0),
      holiday: Color(0xFFFF6E61),
    ),
  ),
  ThemePreset(
    'chalkboard',
    'Chalkboard',
    PatroColorSet(
      background: Color(0xFF1F2A24),
      surface: Color(0xFF26332C),
      ink: Color(0xFFF2F0E6),
      accent: Color(0xFFF6E7A1),
      highlight: Color(0xFF8FD3C1),
      holiday: Color(0xFFFF9C8A),
    ),
  ),
  ThemePreset(
    'midnight',
    'Midnight',
    PatroColorSet(
      background: Color(0xFF0B1020),
      surface: Color(0xFF141B30),
      ink: Color(0xFFE6EAF5),
      accent: Color(0xFF8AB4FF),
      highlight: Color(0xFF5B8CFF),
      holiday: Color(0xFFFF7A85),
    ),
  ),
  ThemePreset(
    'rhododendron',
    'Rhododendron',
    PatroColorSet(
      background: Color(0xFF1A0F12),
      surface: Color(0xFF26161B),
      ink: Color(0xFFF6E9EC),
      accent: Color(0xFFFF8FA3),
      highlight: Color(0xFFFF2E63),
      holiday: Color(0xFFFFB347),
    ),
  ),
  ThemePreset(
    'himalaya',
    'Himalaya',
    PatroColorSet(
      background: Color(0xFFEFF3F6),
      surface: Color(0xFFFFFFFF),
      ink: Color(0xFF16212B),
      accent: Color(0xFF3A6E8F),
      highlight: Color(0xFF1592A6),
      holiday: Color(0xFFD9534F),
    ),
  ),
  ThemePreset(
    'snow',
    'Snow',
    PatroColorSet(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF4F4F5),
      ink: Color(0xFF111113),
      accent: Color(0xFF111113),
      highlight: Color(0xFF111113),
      holiday: Color(0xFFE5484D),
    ),
  ),
];

@immutable
class AppSettings {
  const AppSettings({
    this.presetId = 'obsidian',
    this.colors = _defaultColors,
    this.cornerRadius = 16,
    this.primaryCalendar = CalendarSystem.bs,
    this.nepaliDigits = true,
    this.weekStartsMonday = false,
    this.showTithi = true,
    this.showAdDates = true,
    this.showObservances = true,
    this.soundEffects = false,
    this.haptics = false,
    this.stickyNotification = true,
    this.customThemes = const [],
    this.startPage = ShellPage.day,
    this.showDatePage = true,
    this.showTimeline = true,
    this.defaultReminder,
    this.eventCalendarId,
    this.appIcon = 'classic',
    this.dayIndicator = DayIndicator.faded,
    this.monthSecondaryDates = true,
    this.yearColumns = 2,
    this.weekendDays = const [7],
    this.onlineEvents = true,
    this.serverUrl = defaultServerUrl,
    this.showSkyPage = true,
    this.showCompassPage = true,
    this.skyLocation = GeoLocation.kathmandu,
    this.statusBarDate = true,
    this.statusBarCalendar = CalendarSystem.bs,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    const d = AppSettings();
    final colors = json['colors'];
    final customThemes = [
      if (json['customThemes'] case final List<dynamic> list)
        for (final t in list) ?ThemePreset.fromJson(t, d.colors),
    ];
    // A preset that no longer exists, such as the retired Moleskine theme,
    // leaves its colours behind as an unsaved custom set.
    final presetId = json.containsKey('presetId')
        ? json['presetId'] as String?
        : d.presetId;
    final knownPreset = [
      ...themePresets,
      ...customThemes,
    ].any((t) => t.id == presetId);
    final defaultReminder = json['defaultReminder'];
    return AppSettings(
      presetId: knownPreset ? presetId : null,
      colors: colors is Map<String, dynamic>
          ? PatroColorSet.fromJson(colors, d.colors)
          : d.colors,
      cornerRadius:
          (json['cornerRadius'] as num?)?.toDouble() ?? d.cornerRadius,
      primaryCalendar:
          CalendarSystem.values.asNameMap()[json['primaryCalendar']] ??
          d.primaryCalendar,
      nepaliDigits: json['nepaliDigits'] as bool? ?? d.nepaliDigits,
      weekStartsMonday: json['weekStartsMonday'] as bool? ?? d.weekStartsMonday,
      showTithi: json['showTithi'] as bool? ?? d.showTithi,
      showAdDates: json['showAdDates'] as bool? ?? d.showAdDates,
      showObservances: json['showObservances'] as bool? ?? d.showObservances,
      soundEffects: json['soundEffects'] as bool? ?? d.soundEffects,
      haptics: json['haptics'] as bool? ?? d.haptics,
      stickyNotification:
          json['stickyNotification'] as bool? ?? d.stickyNotification,
      customThemes: customThemes,
      startPage: ShellPage.values.asNameMap()[json['startPage']] ?? d.startPage,
      showDatePage: json['showDatePage'] as bool? ?? d.showDatePage,
      showTimeline: json['showTimeline'] as bool? ?? d.showTimeline,
      defaultReminder: defaultReminder is int ? defaultReminder : null,
      eventCalendarId: json['eventCalendarId'] as String?,
      appIcon: json['appIcon'] as String? ?? d.appIcon,
      dayIndicator:
          DayIndicator.values.asNameMap()[json['dayIndicator']] ??
          d.dayIndicator,
      monthSecondaryDates:
          json['monthSecondaryDates'] as bool? ?? d.monthSecondaryDates,
      yearColumns: switch (json['yearColumns']) {
        final int n when yearColumnChoices.contains(n) => n,
        _ => d.yearColumns,
      },
      weekendDays: switch (json['weekendDays']) {
        final List<dynamic> list => _normalizeWeekdays([
          for (final w in list)
            if (w is int) w,
        ]),
        _ => d.weekendDays,
      },
      onlineEvents: json['onlineEvents'] as bool? ?? d.onlineEvents,
      serverUrl: switch (json['serverUrl']) {
        final String url when url.trim().isNotEmpty => url.trim(),
        _ => d.serverUrl,
      },
      showSkyPage: json['showSkyPage'] as bool? ?? d.showSkyPage,
      showCompassPage: json['showCompassPage'] as bool? ?? d.showCompassPage,
      statusBarDate: json['statusBarDate'] as bool? ?? d.statusBarDate,
      statusBarCalendar:
          CalendarSystem.values.asNameMap()[json['statusBarCalendar']] ??
          d.statusBarCalendar,
      skyLocation: switch (json['skyLocation']) {
        {'lat': final num lat, 'lon': final num lon} &&
                final Map<String, dynamic> m
            when lat.abs() <= 90 && lon.abs() <= 180 =>
          GeoLocation(
            lat.toDouble(),
            lon.toDouble(),
            m['name'] as String? ?? '',
          ),
        _ => d.skyLocation,
      },
    );
  }

  /// Distinct weekdays 1–7, ascending.
  static List<int> _normalizeWeekdays(Iterable<int> days) => [
    for (var w = 1; w <= 7; w++)
      if (days.contains(w)) w,
  ];

  static const _defaultColors = PatroColorSet(
    background: Color(0xFF121214),
    surface: Color(0xFF1B1B1F),
    ink: Color(0xFFEFECE6),
    accent: Color(0xFFFFD700),
    highlight: Color(0xFF4A80F0),
    holiday: Color(0xFFFF6E61),
  );

  static const double maxCornerRadius = 28;

  /// The preset the colours came from; null once any colour is customised.
  final String? presetId;
  final PatroColorSet colors;
  final double cornerRadius;
  final CalendarSystem primaryCalendar;
  final bool nepaliDigits;
  final bool weekStartsMonday;
  final bool showTithi;
  final bool showAdDates;
  final bool showObservances;
  final bool soundEffects;
  final bool haptics;

  /// Android: today's date and events pinned in the notification shade.
  final bool stickyNotification;

  /// Colour sets the user saved, shown after the built-in presets.
  final List<ThemePreset> customThemes;

  /// The page the app opens on.
  final ShellPage startPage;

  /// The single-date page between the day list and Settings.
  final bool showDatePage;

  /// Lays timed events out on an hour-by-hour timeline in day views.
  final bool showTimeline;

  /// Minutes before a new timed event to remind; null for none.
  final int? defaultReminder;

  /// The phone calendar new events are also saved to; null keeps them in
  /// Patro only.
  final String? eventCalendarId;

  /// Android launcher icon; see `appIcons`.
  final String appIcon;

  /// How the month grid marks busy days.
  final DayIndicator dayIndicator;

  /// The small other-calendar date under each day in the month grid.
  final bool monthSecondaryDates;

  /// Months per row on the year page; see [yearColumnChoices].
  final int yearColumns;

  /// Weekly days off, shown in the holiday colour. NepaliDateTime weekdays:
  /// Sunday = 1 … Saturday = 7. Nepal's default is Saturday.
  final List<int> weekendDays;

  /// Shows public holidays and events published on the Patro server.
  final bool onlineEvents;

  /// Base URL of the Patro server, such as `https://patro.obtusei.com`.
  final String serverUrl;

  /// The Sun & Moon page between the date page and Settings.
  final bool showSkyPage;

  /// The compass page after the Sky page. Phones only: other devices have no
  /// compass to read.
  final bool showCompassPage;

  /// Where the Sky page computes positions, rise and set times for.
  final GeoLocation skyLocation;

  /// Android: the sticky notification's status-bar icon is today's date
  /// rather than the Patro mark.
  final bool statusBarDate;

  /// Which date the status bar shows: BS in Nepali numerals, or AD.
  final CalendarSystem statusBarCalendar;

  /// The preset matching [weekendDays], or null for a custom choice.
  String? get weekendPresetLabel {
    for (final (label, days) in weekendPresets) {
      if (listEquals(days, weekendDays)) return label;
    }
    return null;
  }

  /// Every theme the picker shows: built-in presets, then saved ones.
  List<ThemePreset> get allThemes => [...themePresets, ...customThemes];

  /// The pages the shell shows, in order.
  List<ShellPage> get visiblePages => [
    for (final page in ShellPage.values)
      if ((page != ShellPage.date || showDatePage) &&
          (page != ShellPage.sky || showSkyPage) &&
          (page != ShellPage.compass || (showCompassPage && isPhone)))
        page,
  ];

  /// [startPage], or the day list if that page is hidden.
  ShellPage get effectiveStartPage =>
      visiblePages.contains(startPage) ? startPage : ShellPage.day;

  AppSettings copyWith({
    String? Function()? presetId,
    PatroColorSet? colors,
    double? cornerRadius,
    CalendarSystem? primaryCalendar,
    bool? nepaliDigits,
    bool? weekStartsMonday,
    bool? showTithi,
    bool? showAdDates,
    bool? showObservances,
    bool? soundEffects,
    bool? haptics,
    bool? stickyNotification,
    List<ThemePreset>? customThemes,
    ShellPage? startPage,
    bool? showDatePage,
    bool? showTimeline,
    int? Function()? defaultReminder,
    String? Function()? eventCalendarId,
    String? appIcon,
    DayIndicator? dayIndicator,
    bool? monthSecondaryDates,
    int? yearColumns,
    List<int>? weekendDays,
    bool? onlineEvents,
    String? serverUrl,
    bool? showSkyPage,
    bool? showCompassPage,
    GeoLocation? skyLocation,
    bool? statusBarDate,
    CalendarSystem? statusBarCalendar,
  }) {
    return AppSettings(
      presetId: presetId != null ? presetId() : this.presetId,
      colors: colors ?? this.colors,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      primaryCalendar: primaryCalendar ?? this.primaryCalendar,
      nepaliDigits: nepaliDigits ?? this.nepaliDigits,
      weekStartsMonday: weekStartsMonday ?? this.weekStartsMonday,
      showTithi: showTithi ?? this.showTithi,
      showAdDates: showAdDates ?? this.showAdDates,
      showObservances: showObservances ?? this.showObservances,
      soundEffects: soundEffects ?? this.soundEffects,
      haptics: haptics ?? this.haptics,
      stickyNotification: stickyNotification ?? this.stickyNotification,
      customThemes: customThemes ?? this.customThemes,
      startPage: startPage ?? this.startPage,
      showDatePage: showDatePage ?? this.showDatePage,
      showTimeline: showTimeline ?? this.showTimeline,
      defaultReminder: defaultReminder != null
          ? defaultReminder()
          : this.defaultReminder,
      eventCalendarId: eventCalendarId != null
          ? eventCalendarId()
          : this.eventCalendarId,
      appIcon: appIcon ?? this.appIcon,
      dayIndicator: dayIndicator ?? this.dayIndicator,
      monthSecondaryDates: monthSecondaryDates ?? this.monthSecondaryDates,
      yearColumns: yearColumns ?? this.yearColumns,
      weekendDays: weekendDays != null
          ? _normalizeWeekdays(weekendDays)
          : this.weekendDays,
      onlineEvents: onlineEvents ?? this.onlineEvents,
      serverUrl: serverUrl ?? this.serverUrl,
      showSkyPage: showSkyPage ?? this.showSkyPage,
      showCompassPage: showCompassPage ?? this.showCompassPage,
      skyLocation: skyLocation ?? this.skyLocation,
      statusBarDate: statusBarDate ?? this.statusBarDate,
      statusBarCalendar: statusBarCalendar ?? this.statusBarCalendar,
    );
  }

  Map<String, dynamic> toJson() => {
    'presetId': presetId,
    'colors': colors.toJson(),
    'cornerRadius': cornerRadius,
    'primaryCalendar': primaryCalendar.name,
    'nepaliDigits': nepaliDigits,
    'weekStartsMonday': weekStartsMonday,
    'showTithi': showTithi,
    'showAdDates': showAdDates,
    'showObservances': showObservances,
    'soundEffects': soundEffects,
    'haptics': haptics,
    'stickyNotification': stickyNotification,
    'customThemes': [for (final t in customThemes) t.toJson()],
    'startPage': startPage.name,
    'showDatePage': showDatePage,
    'showTimeline': showTimeline,
    'defaultReminder': ?defaultReminder,
    'eventCalendarId': ?eventCalendarId,
    'appIcon': appIcon,
    'dayIndicator': dayIndicator.name,
    'monthSecondaryDates': monthSecondaryDates,
    'yearColumns': yearColumns,
    'weekendDays': weekendDays,
    'onlineEvents': onlineEvents,
    'serverUrl': serverUrl,
    'showSkyPage': showSkyPage,
    'showCompassPage': showCompassPage,
    'statusBarDate': statusBarDate,
    'statusBarCalendar': statusBarCalendar.name,
    'skyLocation': {
      'lat': skyLocation.latitude,
      'lon': skyLocation.longitude,
      'name': skyLocation.name,
    },
  };
}
