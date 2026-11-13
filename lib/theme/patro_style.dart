import 'dart:ui' show FontFeature, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:nepali_utils/nepali_utils.dart';

import '../core/calendar_format.dart';
import '../models/app_settings.dart';
import '../models/patro_day.dart';

/// Every visual and display preference, derived from [AppSettings] and
/// reachable from any widget via [PatroStyle.of].
@immutable
class PatroStyle extends ThemeExtension<PatroStyle> {
  PatroStyle({
    required this.colors,
    required this.radius,
    required this.primary,
    required this.nepaliDigits,
    required this.weekStartsMonday,
    required this.showTithi,
    required this.showAdDates,
    required this.showObservances,
    this.weekendDays = const [7],
    this.dayIndicator = DayIndicator.faded,
    this.monthSecondaryDates = true,
  });

  factory PatroStyle.fromSettings(AppSettings s) => PatroStyle(
    colors: s.colors,
    radius: s.cornerRadius,
    primary: s.primaryCalendar,
    nepaliDigits: s.nepaliDigits,
    weekStartsMonday: s.weekStartsMonday,
    showTithi: s.showTithi,
    showAdDates: s.showAdDates,
    showObservances: s.showObservances,
    weekendDays: s.weekendDays,
    dayIndicator: s.dayIndicator,
    monthSecondaryDates: s.monthSecondaryDates,
  );

  static PatroStyle of(BuildContext context) =>
      Theme.of(context).extension<PatroStyle>()!;

  final PatroColorSet colors;
  final double radius;
  final CalendarSystem primary;
  final bool nepaliDigits;
  final bool weekStartsMonday;
  final bool showTithi;
  final bool showAdDates;
  final bool showObservances;

  /// Weekly days off; NepaliDateTime weekdays, Sunday = 1 … Saturday = 7.
  final List<int> weekendDays;
  final DayIndicator dayIndicator;
  final bool monthSecondaryDates;

  // Colours -----------------------------------------------------------------

  Color get background => colors.background;
  Color get surface => colors.surface;
  Color get ink => colors.ink;
  Color get accent => colors.accent;
  Color get highlight => colors.highlight;
  Color get holiday => colors.holiday;

  late final Color inkMuted = ink.withValues(alpha: 0.64);
  late final Color inkFaint = ink.withValues(alpha: 0.38);
  late final Color hairline = ink.withValues(alpha: 0.09);
  late final Color todaySurface = Color.alphaBlend(
    highlight.withValues(alpha: 0.16),
    surface,
  );

  /// The solid column behind each date in the day list.
  late final Color dateBlock = Color.alphaBlend(
    ink.withValues(alpha: 0.04),
    surface,
  );
  late final bool isDark =
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  late final Color onHighlight =
      ThemeData.estimateBrightnessForColor(highlight) == Brightness.dark
      ? Colors.white
      : Colors.black;

  BorderRadius get borderRadius => BorderRadius.circular(radius);
  BorderRadius scaledRadius(double factor) =>
      BorderRadius.circular(radius * factor);

  /// Whether [day] is one of the user's weekly days off.
  bool isWeekend(PatroDay day) => weekendDays.contains(day.bsDate.weekday);

  /// Text colour that reads on a solid [fill].
  static Color onColor(Color fill) =>
      ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
      ? Colors.white
      : Colors.black;

  /// Numeral colour for a day: today, rest day or ordinary.
  Color dayColor(PatroDay day) {
    if (day.isToday) return highlight;
    if (isWeekend(day) || (showObservances && day.isPublicHoliday)) {
      return holiday;
    }
    return ink;
  }

  // Text --------------------------------------------------------------------
  // The platform's system font throughout; Devanagari falls back to the
  // system's Noto/Devanagari face.

  static const _tabular = [FontFeature.tabularFigures()];

  late final TextStyle brand = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 4,
    color: accent,
  );

  /// Thin display numerals.
  late final TextStyle numeral = TextStyle(
    fontSize: 34,
    height: 1.05,
    fontWeight: FontWeight.w300,
    fontFeatures: _tabular,
    color: ink,
  );

  late final TextStyle monthTitle = TextStyle(
    fontSize: 32,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: ink,
  );

  late final TextStyle nepali = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: ink,
  );

  late final TextStyle nepaliSmall = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: inkMuted,
  );

  /// Small caption for dates and counts.
  late final TextStyle mono = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    fontFeatures: _tabular,
    color: inkMuted,
  );

  late final TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: ink,
  );

  late final TextStyle bodySmall = TextStyle(
    fontSize: 13,
    height: 1.35,
    color: inkMuted,
  );

  late final TextStyle sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.6,
    color: inkFaint,
  );

  // Calendar presentation --------------------------------------------------

  String digits(int n) => nepaliDigits ? devanagariDigits('$n') : '$n';

  /// BS month name in the display language: Nepali or English.
  String bsMonth(int month) => bsMonthName(month, nepali: nepaliDigits);

  String primaryDayNumeral(PatroDay day) =>
      digits(primary == CalendarSystem.bs ? day.bsDate.day : day.adDate.day);

  /// The other calendar's date, shown as a secondary label.
  String secondaryDate(PatroDay day) => primary == CalendarSystem.bs
      ? DateFormat('d MMM').format(day.adDate).toUpperCase()
      : '${bsMonth(day.bsDate.month)} ${digits(day.bsDate.day)}';

  String weekdayShort(PatroDay day) => nepaliDigits
      ? nepaliWeekdaysShort[day.bsDate.weekday - 1]
      : englishWeekdaysShort[day.bsDate.weekday - 1];

  String weekdayFull(PatroDay day) =>
      nepaliDigits ? day.weekdayName : DateFormat('EEEE').format(day.adDate);

  String bsMonthYear(NepaliDateTime month) =>
      '${bsMonth(month.month)} ${digits(month.year)}';

  int get _firstWeekdayIndex => weekStartsMonday ? 1 : 0;

  /// Column headers, ordered by the week-start preference.
  List<String> get weekdayHeaders {
    final names = nepaliDigits ? nepaliWeekdaysShort : englishWeekdaysShort;
    return [for (var i = 0; i < 7; i++) names[(i + _firstWeekdayIndex) % 7]];
  }

  /// Grid column (0–6) of a day whose NepaliDateTime.weekday is [weekday].
  int columnOf(int weekday) => (weekday - 1 - _firstWeekdayIndex) % 7;

  /// Whether grid column [column] (0–6) is a weekly day off.
  bool isWeekendColumn(int column) =>
      weekendDays.any((w) => columnOf(w) == column);

  // ThemeExtension ---------------------------------------------------------

  @override
  PatroStyle copyWith({PatroColorSet? colors, double? radius}) => PatroStyle(
    colors: colors ?? this.colors,
    radius: radius ?? this.radius,
    primary: primary,
    nepaliDigits: nepaliDigits,
    weekStartsMonday: weekStartsMonday,
    showTithi: showTithi,
    showAdDates: showAdDates,
    showObservances: showObservances,
    weekendDays: weekendDays,
    dayIndicator: dayIndicator,
    monthSecondaryDates: monthSecondaryDates,
  );

  @override
  PatroStyle lerp(PatroStyle? other, double t) {
    if (other == null) return this;
    Color c(ColorRole r) => Color.lerp(colors.of(r), other.colors.of(r), t)!;
    final next = t < 0.5 ? this : other;
    return PatroStyle(
      colors: PatroColorSet(
        background: c(ColorRole.background),
        surface: c(ColorRole.surface),
        ink: c(ColorRole.ink),
        accent: c(ColorRole.accent),
        highlight: c(ColorRole.highlight),
        holiday: c(ColorRole.holiday),
      ),
      radius: lerpDouble(radius, other.radius, t)!,
      primary: next.primary,
      nepaliDigits: next.nepaliDigits,
      weekStartsMonday: next.weekStartsMonday,
      showTithi: next.showTithi,
      showAdDates: next.showAdDates,
      showObservances: next.showObservances,
      weekendDays: next.weekendDays,
      dayIndicator: next.dayIndicator,
      monthSecondaryDates: next.monthSecondaryDates,
    );
  }
}

ThemeData buildPatroTheme(AppSettings settings) {
  final s = PatroStyle.fromSettings(settings);
  final brightness = s.isDark ? Brightness.dark : Brightness.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: s.highlight,
        brightness: brightness,
      ).copyWith(
        primary: s.highlight,
        onPrimary: s.onHighlight,
        secondary: s.accent,
        surface: s.background,
        onSurface: s.ink,
        onSurfaceVariant: s.inkMuted,
        surfaceContainerLowest: s.background,
        surfaceContainerLow: s.surface,
        surfaceContainer: s.surface,
        surfaceContainerHigh: s.surface,
        surfaceContainerHighest: s.surface,
        outline: s.inkFaint,
        outlineVariant: s.hairline,
        error: s.holiday,
      );
  final shape = RoundedRectangleBorder(borderRadius: s.borderRadius);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: s.background,
    canvasColor: s.background,
    splashFactory: InkSparkle.splashFactory,
    extensions: [s],
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: s.ink, displayColor: s.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: s.background,
      foregroundColor: s.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: s.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.surface,
      modalBackgroundColor: s.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: s.inkFaint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(s.radius + 8)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: s.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(s.radius.clamp(8, 20)),
        side: BorderSide(color: s.hairline),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surface,
      surfaceTintColor: Colors.transparent,
      shape: shape,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: s.highlight,
      foregroundColor: s.onHighlight,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(s.radius.clamp(6, 28)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        minimumSize: const Size.fromHeight(50),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        side: BorderSide(color: s.hairline),
        foregroundColor: s.ink,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: shape,
        side: BorderSide(color: s.hairline),
        selectedBackgroundColor: s.highlight.withValues(alpha: 0.18),
        selectedForegroundColor: s.ink,
        foregroundColor: s.inkMuted,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.background,
      hintStyle: TextStyle(color: s.inkFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: s.borderRadius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: s.borderRadius,
        borderSide: BorderSide(color: s.highlight, width: 1.4),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: s.ink,
      contentTextStyle: TextStyle(color: s.background),
      actionTextColor: s.highlight,
      shape: shape,
    ),
    dividerTheme: DividerThemeData(color: s.hairline, thickness: 1, space: 1),
    sliderTheme: SliderThemeData(
      activeTrackColor: s.highlight,
      inactiveTrackColor: s.hairline,
      thumbColor: s.highlight,
    ),
  );
}
