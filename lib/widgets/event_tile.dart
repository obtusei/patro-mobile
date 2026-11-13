import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/patro_day.dart';
import '../models/patro_event.dart';
import '../providers/calendar_sync_provider.dart';
import '../providers/event_actions.dart';
import '../theme/patro_style.dart';
import 'common.dart';
import 'event_editor_sheet.dart';
import 'event_qr_sheet.dart';

/// Opens [event]'s location in a maps app.
Future<void> openLocation(String location) => _open(
  Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': location}),
);

/// Opens a link typed into an event, adding https:// if it has no scheme.
Future<void> openLink(String link) {
  final uri = Uri.tryParse(link.contains('://') ? link : 'https://$link');
  return uri == null ? Future.value() : _open(uri);
}

Future<void> _open(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object catch (e) {
    debugPrint('Patro: could not open $uri: $e');
  }
}

/// A full event card. Patro's own events can be edited or swiped away;
/// events from a phone calendar are read-only.
class EventTile extends ConsumerWidget {
  const EventTile({super.key, required this.event, required this.day});

  final PatroEvent event;
  final PatroDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final color = event.color ?? s.accent;
    // Read-only events name their calendar; Patro's own name the one they
    // are copied to.
    final calendar =
        event.calendarName ??
        (event.deviceEventId == null
            ? null
            : ref.watch(
                calendarSyncProvider.select(
                  (sync) => sync.calendarById(event.deviceCalendarId)?.name,
                ),
              ));

    final card = Pressable(
      pressedScale: 0.98,
      onTap: () => event.isExternal
          ? showEventQr(context, event)
          : showEventEditor(context, date: day.adDate, event: event),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: s.borderRadius,
          border: Border.all(color: s.hairline),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title, style: s.body.copyWith(fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(
                      eventTimeLabel(context, event).toUpperCase(),
                      style: s.mono,
                    ),
                    if (event.location.isNotEmpty)
                      _LinkLine(
                        icon: Icons.place_outlined,
                        text: event.location,
                        onTap: () => openLocation(event.location),
                      ),
                    if (event.url.isNotEmpty)
                      _LinkLine(
                        icon: Icons.link_rounded,
                        text: event.url,
                        onTap: () => openLink(event.url),
                      ),
                    if (calendar != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        event.isExternal ? calendar : 'Also in $calendar',
                        style: s.bodySmall,
                      ),
                    ],
                    if (event.note.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        event.note,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: s.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: [
                  if (event.repeat != EventRepeat.none)
                    Tooltip(
                      message: event.repeat.label,
                      child: Icon(
                        Icons.repeat_rounded,
                        size: 18,
                        color: s.inkFaint,
                      ),
                    ),
                  if (event.reminders.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Tooltip(
                      message: event.reminders.length == 1
                          ? '1 reminder'
                          : '${event.reminders.length} reminders',
                      child: Icon(
                        Icons.notifications_none_rounded,
                        size: 18,
                        color: s.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: event.isExternal
          ? card
          : Dismissible(
              key: ValueKey('${event.id}-${day.adDate}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(
                  color: s.holiday.withValues(alpha: 0.18),
                  borderRadius: s.borderRadius,
                ),
                child: Icon(Icons.delete_outline_rounded, color: s.holiday),
              ),
              onDismissed: (_) {
                final actions = ref.read(eventActionsProvider);
                // Removes any phone-calendar copy too; Undo puts it back.
                actions.delete(event);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        event.repeat == EventRepeat.none
                            ? 'Deleted “${event.title}”'
                            : 'Deleted every “${event.title}”',
                      ),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () => actions.save(event),
                      ),
                    ),
                  );
              },
              child: card,
            ),
    );
  }
}

/// A tappable line under an event title: its place or link.
class _LinkLine extends StatelessWidget {
  const _LinkLine({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(icon, size: 14, color: s.highlight),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: s.bodySmall.copyWith(color: s.highlight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
