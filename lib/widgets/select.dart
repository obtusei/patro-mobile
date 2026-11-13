import 'package:flutter/material.dart';

import '../theme/patro_style.dart';
import 'common.dart';

@immutable
class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.detail});

  final T value;
  final String label;

  /// A second, quieter line in the menu.
  final String? detail;
}

/// Wraps a picked value so a nullable [T] can still mean "picked null".
class _Picked<T> {
  const _Picked(this.value, {this.custom = false});
  final T? value;
  final bool custom;
}

/// Opens a dropdown of [options] under the widget at [context]. Returns the
/// picked option, `(custom: true)` for the "Custom…" entry, or null when the
/// menu was dismissed.
Future<({T? value, bool custom})?> showSelectMenu<T>(
  BuildContext context, {
  required List<SelectOption<T>> options,
  required T? selected,
  String? customLabel,
}) async {
  final s = PatroStyle.of(context);
  final box = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final rect = Rect.fromLTWH(
    topLeft.dx,
    topLeft.dy + box.size.height,
    box.size.width,
    0,
  );

  final picked = await showMenu<_Picked<T>>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    constraints: BoxConstraints(
      minWidth: box.size.width.clamp(180, 320),
      maxWidth: 320,
    ),
    items: [
      for (final o in options)
        PopupMenuItem<_Picked<T>>(
          value: _Picked(o.value),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.label, style: s.body),
                    if (o.detail case final d?) Text(d, style: s.bodySmall),
                  ],
                ),
              ),
              if (o.value == selected)
                Icon(Icons.check_rounded, size: 18, color: s.highlight),
            ],
          ),
        ),
      if (customLabel != null) ...[
        const PopupMenuDivider(),
        PopupMenuItem<_Picked<T>>(
          value: const _Picked(null, custom: true),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: s.accent),
              const SizedBox(width: 10),
              Text(customLabel, style: s.body),
            ],
          ),
        ),
      ],
    ],
  );
  if (picked == null) return null;
  return (value: picked.value, custom: picked.custom);
}

/// A settings-style row showing the current choice; tapping it opens a
/// dropdown of [options]. With [onCustom], the menu ends with "Custom…".
class SelectRow<T> extends StatelessWidget {
  const SelectRow({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
    this.valueLabel,
    this.onCustom,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final T value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;

  /// Shown instead of the matching option's label, e.g. for a custom value.
  final String? valueLabel;
  final VoidCallback? onCustom;
  final IconData? icon;

  String get _currentLabel {
    if (valueLabel case final label?) return label;
    for (final o in options) {
      if (o.value == value) return o.label;
    }
    return 'Custom';
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Builder(
      builder: (anchor) => Pressable(
        pressedScale: 0.98,
        onTap: () async {
          final picked = await showSelectMenu<T>(
            anchor,
            options: options,
            selected: value,
            customLabel: onCustom == null ? null : 'Custom…',
          );
          if (picked == null) return;
          if (picked.custom) {
            onCustom?.call();
          } else {
            onChanged(picked.value as T);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: s.accent, size: 22),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: s.body),
                    if (subtitle case final sub? when sub.isNotEmpty)
                      Text(sub, style: s.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                constraints: const BoxConstraints(maxWidth: 180),
                padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
                decoration: BoxDecoration(
                  color: s.surface,
                  borderRadius: BorderRadius.circular(s.radius.clamp(6, 99)),
                  border: Border.all(color: s.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _currentLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: s.bodySmall.copyWith(color: s.ink),
                      ),
                    ),
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 18,
                      color: s.inkFaint,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _LeadUnit {
  minutes('minutes', 1),
  hours('hours', 60),
  days('days', 1440),
  weeks('weeks', 10080);

  const _LeadUnit(this.label, this.size);
  final String label;

  /// Minutes in one of this unit.
  final int size;
}

/// Asks for a reminder lead time of the user's choosing.
///
/// For timed events this is "N minutes/hours/days/weeks before"; for all-day
/// events it is "N days before, at a time", returned in the same encoding as
/// [allDayReminderOptions] (minutes before the day's midnight).
Future<int?> pickCustomReminder(
  BuildContext context, {
  required bool allDay,
  int? initial,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _CustomReminderDialog(allDay: allDay, initial: initial),
  );
}

class _CustomReminderDialog extends StatefulWidget {
  const _CustomReminderDialog({required this.allDay, this.initial});

  final bool allDay;
  final int? initial;

  @override
  State<_CustomReminderDialog> createState() => _CustomReminderDialogState();
}

class _CustomReminderDialogState extends State<_CustomReminderDialog> {
  late final TextEditingController _amount;
  var _unit = _LeadUnit.minutes;

  /// All-day: time of day the reminder fires, in minutes after midnight.
  var _at = 9 * 60;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    var amount = widget.allDay ? 1 : 30;
    if (initial != null) {
      if (widget.allDay) {
        final days = (initial / 1440).ceil();
        amount = days;
        _at = days * 1440 - initial;
      } else {
        _unit = _LeadUnit.values.lastWhere(
          (u) => initial % u.size == 0 && initial >= u.size,
          orElse: () => _LeadUnit.minutes,
        );
        amount = initial ~/ _unit.size;
      }
    }
    _amount = TextEditingController(text: '$amount');
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _value {
    final n = int.tryParse(_amount.text.trim());
    if (n == null || n < 0) return null;
    if (widget.allDay) return n > 365 ? null : n * 1440 - _at;
    final minutes = n * _unit.size;
    return minutes > 365 * 1440 ? null : minutes;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _at ~/ 60, minute: _at % 60),
    );
    if (picked != null) setState(() => _at = picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final value = _value;
    final amountField = SizedBox(
      width: 84,
      child: TextField(
        controller: _amount,
        autofocus: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: s.body.copyWith(fontSize: 18),
      ),
    );

    return AlertDialog(
      title: const Text('Custom reminder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.allDay) ...[
            Row(
              children: [
                amountField,
                const SizedBox(width: 12),
                Expanded(child: Text('days before', style: s.body)),
              ],
            ),
            const SizedBox(height: 12),
            Pressable(
              onTap: _pickTime,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: s.background,
                  borderRadius: s.borderRadius,
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: s.accent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text('At', style: s.bodySmall)),
                    Text(formatMinutes(context, _at), style: s.body),
                  ],
                ),
              ),
            ),
          ] else
            Row(
              children: [
                amountField,
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<_LeadUnit>(
                    initialValue: _unit,
                    isExpanded: true,
                    items: [
                      for (final u in _LeadUnit.values)
                        DropdownMenuItem(value: u, child: Text(u.label)),
                    ],
                    onChanged: (u) => setState(() => _unit = u ?? _unit),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          Text(
            value == null
                ? 'Enter a number up to a year'
                : reminderLabel(context, value, allDay: widget.allDay),
            style: s.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: value == null ? null : () => Navigator.pop(context, value),
          child: const Text('Set'),
        ),
      ],
    );
  }
}
