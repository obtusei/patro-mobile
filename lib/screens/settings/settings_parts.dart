import 'package:flutter/material.dart';

import '../../theme/patro_style.dart';
import '../../widgets/common.dart';

/// A pushed settings sub-page: a back button, a title and its rows.
class SettingsSubpage extends StatelessWidget {
  const SettingsSubpage({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  static Route<void> route(Widget page) =>
      MaterialPageRoute<void>(builder: (_) => page);

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(title, style: s.body.copyWith(fontSize: 20)),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: s.body),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, style: s.bodySmall),
      value: value,
      onChanged: onChanged,
    );
  }
}

class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Pressable(
      pressedScale: 0.98,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? s.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: s.body),
                  if (subtitle.isNotEmpty) Text(subtitle, style: s.bodySmall),
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

/// A row on the main settings page that opens a sub-page.
class SettingsGroupRow extends StatelessWidget {
  const SettingsGroupRow({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: s.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(s.radius.clamp(8, 20)),
              ),
              child: Icon(icon, color: s.accent, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: s.body),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: s.bodySmall,
                  ),
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

Future<bool> confirmSetting(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final s = PatroStyle.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: s.holiday),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for one line of text; null if cancelled or left empty.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String initial,
  String hint = 'Name',
  TextInputType? keyboardType,
  TextCapitalization capitalization = TextCapitalization.words,
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: keyboardType,
        textCapitalization: capitalization,
        autocorrect: false,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
