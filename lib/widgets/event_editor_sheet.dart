import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/platform.dart';
import '../models/patro_event.dart';
import '../providers/calendar_provider.dart';
import '../providers/calendar_sync_provider.dart';
import '../providers/event_actions.dart';
import '../providers/settings_provider.dart';
import '../services/system_bridge.dart';
import '../theme/patro_style.dart';
import 'common.dart';
import 'event_qr_sheet.dart';
import 'select.dart';

const eventColors = [
  null, // theme accent
  Color(0xFF4A80F0),
  Color(0xFF5FBF7F),
  Color(0xFFFF6E61),
  Color(0xFFF6B73C),
  Color(0xFFB58CFF),
  Color(0xFFFF8FA3),
  Color(0xFF1592A6),
];

/// Opens the editor for a new event on [date], or for an existing [event].
/// A [draft] pre-fills a new event, such as one scanned from a QR code;
/// [startMinutes] pre-sets a new event's start, such as a tapped hour.
Future<void> showEventEditor(
  BuildContext context, {
  required DateTime date,
  PatroEvent? event,
  PatroEvent? draft,
  int? startMinutes,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EventEditorSheet(
      date: date,
      event: event,
      draft: draft,
      startMinutes: startMinutes,
    ),
  );
}

class EventEditorSheet extends ConsumerStatefulWidget {
  const EventEditorSheet({
    super.key,
    required this.date,
    this.event,
    this.draft,
    this.startMinutes,
  });

  final DateTime date;
  final PatroEvent? event;
  final PatroEvent? draft;
  final int? startMinutes;

  @override
  ConsumerState<EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends ConsumerState<EventEditorSheet> {
  late final _source = widget.event ?? widget.draft;
  late final _settings = ref.read(settingsProvider);
  late final _title = TextEditingController(text: _source?.title);
  late final _note = TextEditingController(text: _source?.note);
  late final _location = TextEditingController(text: _source?.location);
  late final _url = TextEditingController(text: _source?.url);

  /// For an existing repeating event this is the series' first date.
  late DateTime _date = _source?.date ?? widget.date;
  late bool _allDay =
      widget.startMinutes == null && (_source?.isAllDay ?? false);
  late int _start =
      widget.startMinutes ?? _source?.startMinutes ?? _defaultStart();
  late int _end = _source?.endMinutes ?? (_start + 60).clamp(0, 24 * 60 - 1);
  late EventRepeat _repeat = _source?.repeat ?? EventRepeat.none;
  late DateTime? _until = _source?.repeatUntil;
  late Color? _color = _source?.color;

  /// Timed and all-day lead times mean different things, so each kind
  /// keeps its own set while the All day switch is flipped back and forth.
  late final Set<int> _timedReminders = {
    if (_source?.isAllDay != true) ...?widget.event?.reminders,
    if (widget.event == null) ?_settings.defaultReminder,
  };
  late final Set<int> _allDayReminders = {
    if (_source?.isAllDay == true) ...?widget.event?.reminders,
  };

  Set<int> get _reminders => _allDay ? _allDayReminders : _timedReminders;
  late String? _calendarId = widget.event != null
      ? widget.event!.deviceCalendarId
      : _settings.eventCalendarId;

  static int _defaultStart() {
    final now = TimeOfDay.now();
    return ((now.hour + 1) % 24) * 60;
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _location.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (start) {
        final length = _end - _start;
        _start = minutes;
        _end = (minutes + (length > 0 ? length : 60)).clamp(0, 24 * 60 - 1);
      } else {
        _end = minutes < _start ? _start : minutes;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await pickAdDate(context, initial: _date);
    if (picked == null) return;
    setState(() {
      _date = picked;
      if (_until case final until? when until.isBefore(picked)) _until = null;
    });
  }

  Future<void> _pickUntil() async {
    final picked = await pickAdDate(
      context,
      initial: _until ?? _date.add(const Duration(days: 30)),
      first: _date,
      helpText: 'Repeat until',
    );
    if (picked != null) setState(() => _until = picked);
  }

  /// The calendar to save to, once the phone's calendars are known. Until
  /// they load, an existing choice is kept rather than dropped.
  String? _resolvedCalendar(CalendarSyncState sync) {
    final id = _calendarId;
    if (id == null || !isPhone) return null;
    if (sync.calendars.isEmpty) return id;
    return sync.writable.any((c) => c.id == id) ? id : null;
  }

  /// Phone calendars count lead times before the start only.
  static bool _allowed(int minutes, bool toPhoneCalendar) =>
      !toPhoneCalendar || minutes >= 0;

  List<int> _reminderOptions(bool toPhoneCalendar) {
    final base = _allDay ? allDayReminderOptions : timedReminderOptions;
    return [
      for (final m in base)
        if (_allowed(m, toPhoneCalendar)) m,
    ];
  }

  Future<void> _addReminder(BuildContext anchor, bool toPhoneCalendar) async {
    final options = [
      for (final m in _reminderOptions(toPhoneCalendar))
        if (!_reminders.contains(m))
          SelectOption<int>(m, reminderLabel(context, m, allDay: _allDay)),
    ];
    final picked = await showSelectMenu<int>(
      anchor,
      options: options,
      selected: null,
      customLabel: 'Custom…',
    );
    if (picked == null || !mounted) return;
    var minutes = picked.value;
    if (picked.custom) {
      minutes = await pickCustomReminder(context, allDay: _allDay);
      if (minutes == null || !mounted) return;
      if (!_allowed(minutes, toPhoneCalendar)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone calendars remind before the start only.'),
          ),
        );
        return;
      }
    }
    if (minutes != null) setState(() => _reminders.add(minutes!));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final sync = ref.read(calendarSyncProvider);
    final calendarId = _resolvedCalendar(sync);
    final reminders = [
      for (final m in _reminders)
        if (_allowed(m, calendarId != null)) m,
    ]..sort();
    final existing = widget.event;
    final repeatUntil = _repeat == EventRepeat.none ? null : _until;

    final event = existing == null
        ? PatroEvent.create(
            date: _date,
            title: title,
            note: _note.text.trim(),
            startMinutes: _allDay ? null : _start,
            endMinutes: _allDay ? null : _end,
            repeat: _repeat,
            color: _color,
            location: _location.text.trim(),
            url: _url.text.trim(),
            reminders: reminders,
            repeatUntil: repeatUntil,
          ).copyWith(deviceCalendarId: () => calendarId)
        : existing.copyWith(
            date: _date,
            title: title,
            note: _note.text.trim(),
            startMinutes: () => _allDay ? null : _start,
            endMinutes: () => _allDay ? null : _end,
            repeat: _repeat,
            color: () => _color,
            location: _location.text.trim(),
            url: _url.text.trim(),
            reminders: reminders,
            repeatUntil: () => repeatUntil,
            deviceCalendarId: () => calendarId,
          );

    // New events start in the calendar picked last time.
    if (existing == null && calendarId != _settings.eventCalendarId) {
      ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(eventCalendarId: () => calendarId));
    }

    final actions = ref.read(eventActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    final problem = await actions.save(event, previous: existing);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  void _delete() {
    final actions = ref.read(eventActionsProvider);
    Navigator.pop(context);
    actions.delete(widget.event!);
  }

  Future<void> _chooseCalendar(CalendarSyncState sync) async {
    final picked = await showModalBottomSheet<_CalendarChoice>(
      context: context,
      useSafeArea: true,
      builder: (_) =>
          _CalendarSheet(sync: sync, selected: _resolvedCalendar(sync)),
    );
    if (picked == null || !mounted) return;
    if (picked.connect) {
      await ref.read(calendarSyncProvider.notifier).connect();
      return;
    }
    setState(() => _calendarId = picked.calendarId);
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final sync = ref.watch(calendarSyncProvider);
    final day = ref.read(calendarProvider.notifier).dayOn(_date);
    final canSave = _title.text.trim().isNotEmpty;
    final calendarId = _resolvedCalendar(sync);
    final calendar = sync.calendarById(calendarId);
    final reminders = [..._reminders]..sort();

    final String? reminderHint;
    if (calendarId != null) {
      reminderHint = 'Your phone calendar will send these reminders.';
    } else if (!SystemBridge.isSupported && _reminders.isNotEmpty) {
      reminderHint = isPhone
          ? 'Patro sends reminders on Android. Save to a phone calendar '
                'to be reminded on this device.'
          : 'Reminders are sent on Android phones.';
    } else {
      reminderHint = null;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.event == null ? 'New event' : 'Edit event',
                    style: s.body.copyWith(fontSize: 20),
                  ),
                ),
                if (widget.event case final event?)
                  IconButton(
                    tooltip: 'Share as QR code',
                    icon: const Icon(Icons.qr_code_rounded),
                    onPressed: () => showEventQr(context, event),
                  ),
                if (widget.event != null)
                  IconButton(
                    tooltip: 'Delete event',
                    color: s.holiday,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _delete,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: _source == null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              style: s.body.copyWith(fontSize: 18),
              decoration: const InputDecoration(hintText: 'Title'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            _Tile(
              icon: Icons.calendar_today_rounded,
              label: _repeat == EventRepeat.none ? 'Date' : 'First date',
              value:
                  '${s.weekdayFull(day)} · ${s.bsMonthYear(day.bsDate)} '
                  '${s.digits(day.bsDate.day)}',
              detail: DateFormat('d MMMM yyyy').format(day.adDate),
              onTap: _pickDate,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('All day', style: s.body),
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: _allDay
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: _TimeTile(
                              label: 'Starts',
                              value: formatMinutes(context, _start),
                              onTap: () => _pickTime(start: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TimeTile(
                              label: 'Ends',
                              value: formatMinutes(context, _end),
                              onTap: () => _pickTime(start: false),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            TextField(
              controller: _location,
              textCapitalization: TextCapitalization.words,
              style: s.body,
              decoration: const InputDecoration(
                hintText: 'Location',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            SelectRow<EventRepeat>(
              icon: Icons.repeat_rounded,
              title: 'Repeat',
              value: _repeat,
              options: [
                for (final r in EventRepeat.values) SelectOption(r, r.label),
              ],
              onChanged: (r) => setState(() => _repeat = r),
            ),
            if (_repeat != EventRepeat.none) ...[
              const SizedBox(height: 12),
              _Tile(
                icon: Icons.event_repeat_rounded,
                label: 'Repeat until',
                value: _until == null
                    ? 'Never'
                    : DateFormat('d MMMM yyyy').format(_until!),
                onTap: _pickUntil,
                trailing: _until == null
                    ? null
                    : IconButton(
                        tooltip: 'Repeat forever',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _until = null),
                      ),
              ),
            ],
            const SectionLabel('Reminders'),
            for (final m in reminders)
              _ReminderLine(
                label: reminderLabel(context, m, allDay: _allDay),
                faded: !_allowed(m, calendarId != null),
                onRemove: () => setState(() => _reminders.remove(m)),
              ),
            Builder(
              builder: (anchor) => Pressable(
                pressedScale: 0.98,
                onTap: () => _addReminder(anchor, calendarId != null),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_alert_outlined,
                        color: s.highlight,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Add reminder',
                          style: s.body.copyWith(color: s.highlight),
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
              ),
            ),
            if (reminderHint != null) ...[
              const SizedBox(height: 8),
              Text(reminderHint, style: s.bodySmall),
            ],
            if (isPhone) ...[
              const SectionLabel('Save to'),
              _Tile(
                icon: calendarId == null
                    ? Icons.phone_android_rounded
                    : Icons.event_available_rounded,
                iconColor: calendar?.color,
                label: calendarId == null ? 'Patro only' : 'Patro and',
                value: calendarId == null
                    ? 'This phone'
                    : calendar?.name ?? 'Phone calendar',
                detail: calendarId == null
                    ? 'Pick Google or another calendar to copy it there'
                    : calendar?.accountName,
                onTap: () => _chooseCalendar(sync),
              ),
              if (calendarId != null && _repeat.followsBs) ...[
                const SizedBox(height: 8),
                Text(
                  'Phone calendars can\'t repeat by Bikram Sambat, so only '
                  'the first date is copied there.',
                  style: s.bodySmall,
                ),
              ],
            ],
            const SectionLabel('Colour'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in eventColors)
                  Pressable(
                    onTap: () => setState(() => _color = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c ?? s.accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c ? s.ink : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: s.body,
              decoration: const InputDecoration(
                hintText: 'Link',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: s.body,
              decoration: const InputDecoration(hintText: 'Notes'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: canSave ? _save : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One chosen reminder, with a button to remove it.
class _ReminderLine extends StatelessWidget {
  const _ReminderLine({
    required this.label,
    required this.onRemove,
    this.faded = false,
  });

  final String label;
  final VoidCallback onRemove;

  /// Not kept on save, e.g. a same-day time for a phone calendar.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: s.borderRadius,
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_active_rounded,
            size: 18,
            color: faded ? s.inkFaint : s.highlight,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: s.body.copyWith(color: faded ? s.inkFaint : s.ink),
            ),
          ),
          IconButton(
            tooltip: 'Remove reminder',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: s.inkMuted),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.detail,
    this.trailing,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Pressable(
      pressedScale: 0.98,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: s.background,
          borderRadius: s.borderRadius,
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? s.accent, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.toUpperCase(), style: s.sectionLabel),
                  const SizedBox(height: 3),
                  Text(value, style: s.body),
                  if (detail case final d? when d.isNotEmpty)
                    Text(d, style: s.bodySmall),
                ],
              ),
            ),
            trailing ?? Icon(Icons.chevron_right_rounded, color: s.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _CalendarChoice {
  const _CalendarChoice(this.calendarId, {this.connect = false});

  final String? calendarId;
  final bool connect;
}

/// Patro only, or a phone calendar that takes new events.
class _CalendarSheet extends StatelessWidget {
  const _CalendarSheet({required this.sync, required this.selected});

  final CalendarSyncState sync;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);

    Widget option({
      required Widget leading,
      required String title,
      String? subtitle,
      required _CalendarChoice choice,
      bool checked = false,
    }) => ListTile(
      leading: leading,
      title: Text(title, style: s.body),
      subtitle: subtitle == null || subtitle.isEmpty
          ? null
          : Text(subtitle, style: s.bodySmall),
      trailing: checked ? Icon(Icons.check_rounded, color: s.highlight) : null,
      onTap: () => Navigator.pop(context, choice),
    );

    final calendars = [...sync.writable]
      ..sort((a, b) => (a.accountName ?? '').compareTo(b.accountName ?? ''));

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Save to', style: s.body.copyWith(fontSize: 20)),
          ),
          option(
            leading: Icon(Icons.phone_android_rounded, color: s.accent),
            title: 'Patro only',
            subtitle: 'Kept on this phone, inside Patro',
            choice: const _CalendarChoice(null),
            checked: selected == null,
          ),
          if (!sync.connected)
            option(
              leading: Icon(Icons.add_link_rounded, color: s.highlight),
              title: 'Connect phone calendars',
              subtitle: 'Google, Outlook and other accounts on this phone',
              choice: const _CalendarChoice(null, connect: true),
            )
          else if (calendars.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text(
                'None of this phone\'s calendars take new events.',
                style: s.bodySmall,
              ),
            )
          else
            for (final Calendar c in calendars)
              option(
                leading: Dot(color: c.color ?? s.accent, size: 14),
                title: c.name,
                subtitle: c.accountName,
                choice: _CalendarChoice(c.id),
                checked: selected == c.id,
              ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: s.background,
          borderRadius: s.borderRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: s.sectionLabel),
            const SizedBox(height: 4),
            Text(value, style: s.body.copyWith(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
