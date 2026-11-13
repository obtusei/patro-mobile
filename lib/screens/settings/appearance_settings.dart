import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/calendar_format.dart';
import '../../models/app_icon.dart';
import '../../models/app_settings.dart';
import '../../providers/settings_provider.dart';
import '../../services/system_bridge.dart';
import '../../theme/patro_style.dart';
import '../../widgets/color_picker_sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/select.dart';
import 'settings_parts.dart';

/// Theme, colours, shape, month marks and the launcher icon.
class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  /// Rename or delete a saved theme.
  Future<void> _editTheme(
    BuildContext context,
    WidgetRef ref,
    ThemePreset theme,
  ) async {
    final s = PatroStyle.of(context);
    final notifier = ref.read(settingsProvider.notifier);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(theme.name, style: s.body.copyWith(fontSize: 20)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: s.holiday),
              title: Text('Delete', style: TextStyle(color: s.holiday)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'rename':
        final name = await askText(
          context,
          title: 'Rename theme',
          initial: theme.name,
        );
        if (name != null) notifier.renameCustomTheme(theme.id, name);
      case 'delete':
        final ok = await confirmSetting(
          context,
          title: 'Delete “${theme.name}”?',
          body: 'The theme is removed. Colours in use now stay as they are.',
          action: 'Delete',
        );
        if (ok) notifier.deleteCustomTheme(theme.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSubpage(
      title: 'Appearance',
      children: [
        SectionLabel(
          'Theme',
          trailing: settings.customThemes.isEmpty
              ? null
              : Text('HOLD A SAVED THEME TO EDIT', style: s.sectionLabel),
        ),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: settings.allThemes.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              if (i == settings.allThemes.length) {
                return _NewThemeTile(
                  onTap: () async {
                    final name = await askText(
                      context,
                      title: 'Save theme',
                      initial: 'My theme ${settings.customThemes.length + 1}',
                    );
                    if (name != null) notifier.saveCustomTheme(name);
                  },
                );
              }
              final theme = settings.allThemes[i];
              return _PresetTile(
                preset: theme,
                selected: settings.presetId == theme.id,
                onTap: () => notifier.applyPreset(theme),
                onLongPress: theme.isCustom
                    ? () => _editTheme(context, ref, theme)
                    : null,
              );
            },
          ),
        ),
        SectionLabel(
          'Colours',
          trailing: switch (settings.presetId) {
            null => Text(
              'UNSAVED',
              style: s.sectionLabel.copyWith(color: s.accent),
            ),
            final id when id.startsWith(ThemePreset.customPrefix) => Text(
              'EDITING SAVED THEME',
              style: s.sectionLabel.copyWith(color: s.accent),
            ),
            _ => null,
          },
        ),
        for (final role in ColorRole.values)
          _ColorRow(
            role: role,
            color: settings.colors.of(role),
            onTap: () => showColorPickerSheet(
              context,
              title: role.label,
              initial: settings.colors.of(role),
              onChanged: (c) => notifier.setColor(role, c),
            ),
          ),
        const SectionLabel('Shape'),
        Row(
          children: [
            Expanded(child: Text('Corner roundness', style: s.body)),
            Text('${settings.cornerRadius.round()}', style: s.mono),
          ],
        ),
        Slider(
          value: settings.cornerRadius,
          max: AppSettings.maxCornerRadius,
          divisions: AppSettings.maxCornerRadius.toInt(),
          onChanged: (v) => notifier.update((x) => x.copyWith(cornerRadius: v)),
        ),
        const SectionLabel('Year view'),
        SelectRow<int>(
          title: 'Months per row',
          subtitle: settings.yearColumns == 2
              ? 'Larger months; scroll, pull past the end for the next year'
              : 'The whole year on one screen',
          value: settings.yearColumns,
          options: [for (final n in yearColumnChoices) SelectOption(n, '$n')],
          onChanged: (n) => notifier.update((x) => x.copyWith(yearColumns: n)),
        ),
        const SectionLabel('Month view'),
        SelectRow<DayIndicator>(
          title: 'Days with events',
          subtitle: switch (settings.dayIndicator) {
            DayIndicator.faded => 'A faint wash, the date in its colour',
            DayIndicator.background => 'Tinted for one, solid for several',
            DayIndicator.dots => 'Up to three dots under the date',
          },
          value: settings.dayIndicator,
          options: [
            for (final d in DayIndicator.values) SelectOption(d, d.label),
          ],
          onChanged: (d) => notifier.update((x) => x.copyWith(dayIndicator: d)),
        ),
        SettingsSwitchRow(
          title: settings.primaryCalendar == CalendarSystem.bs
              ? 'English dates'
              : 'Nepali dates',
          subtitle: settings.primaryCalendar == CalendarSystem.bs
              ? 'Small AD date under each day'
              : 'Small BS date under each day',
          value: settings.monthSecondaryDates,
          // With Gregorian dates off everywhere, BS calendars have none to show.
          onChanged:
              settings.primaryCalendar == CalendarSystem.bs &&
                  !settings.showAdDates
              ? null
              : (v) =>
                    notifier.update((x) => x.copyWith(monthSecondaryDates: v)),
        ),
        if (SystemBridge.isSupported) ...[
          const SectionLabel('App icon'),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: appIcons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) => _AppIconTile(
                icon: appIcons[i],
                selected: settings.appIcon == appIcons[i].id,
                onTap: () =>
                    notifier.update((x) => x.copyWith(appIcon: appIcons[i].id)),
              ),
            ),
          ),
          Text(
            'Your launcher may take a moment to show the new icon.',
            style: s.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final c = preset.colors;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 96,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: s.scaledRadius(0.8),
          border: Border.all(
            color: selected ? s.highlight : c.ink.withValues(alpha: 0.12),
            width: selected ? 2.2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              devanagariDigits('6'),
              style: TextStyle(
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w300,
                color: c.highlight,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                for (final dot in [c.accent, c.holiday, c.surface]) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.ink.withValues(alpha: 0.15)),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.role,
    required this.color,
    required this.onTap,
  });

  final ColorRole role;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Pressable(
      pressedScale: 0.98,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: s.inkFaint),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role.label, style: s.body),
                  Text(role.description, style: s.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: s.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// The last tile of the theme strip: saves the current colours.
class _NewThemeTile extends StatelessWidget {
  const _NewThemeTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: s.scaledRadius(0.8),
          border: Border.all(color: s.inkFaint),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.add_rounded, size: 30, color: s.highlight),
            const Spacer(),
            Text(
              'Save current',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: s.ink,
              ),
            ),
            Text(
              'as a theme',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: s.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A launcher icon choice, drawn from the same dot-grid mark.
class _AppIconTile extends StatelessWidget {
  const _AppIconTile({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final AppIconOption icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? s.highlight : Colors.transparent,
                  width: 2.2,
                ),
              ),
              child: Container(
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: icon.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: s.hairline),
                ),
                child: Image.asset(
                  'assets/images/foreground.png',
                  color: icon.foreground,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              icon.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: s.bodySmall.copyWith(
                fontSize: 11.5,
                color: selected ? s.ink : s.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
