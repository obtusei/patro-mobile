import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/festival_notes.dart';
import '../data/nepal_history.dart';
import '../models/patro_day.dart';
import '../theme/patro_style.dart';

/// Fills a day that has no events: greetings on a festival, otherwise
/// something from Nepal's past.
class DayStory extends StatelessWidget {
  const DayStory({super.key, required this.day, required this.observances});

  final PatroDay day;
  final List<Observance> observances;

  @override
  Widget build(BuildContext context) {
    final notes = [
      for (final o in observances)
        if (festivalNotes[o.name] case final note?) (o.name, note),
    ];
    if (notes.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (name, note) in notes)
            _GreetingCard(name: name, note: note),
        ],
      );
    }
    return _HistoryCard(day: day);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: s.borderRadius,
      ),
      child: child,
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.name, required this.note});

  final String name;
  final FestivalNote note;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final greeting = note.greeting;
    final english = note.english;
    return _Card(
      color: greeting == null ? s.ink : s.holiday,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name.toUpperCase(), style: s.sectionLabel)),
              if (greeting != null)
                IconButton(
                  tooltip: 'Share greeting',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(text: '$greeting\n${english ?? ''}'.trim()),
                  ),
                ),
            ],
          ),
          if (greeting != null) ...[
            const SizedBox(height: 6),
            Text(
              greeting,
              style: s.nepali.copyWith(
                fontSize: 24,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (english != null) ...[
            const SizedBox(height: 2),
            Text(english, style: s.body.copyWith(color: s.inkMuted)),
          ],
          const SizedBox(height: 10),
          Text(note.about, style: s.bodySmall),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.day});

  final PatroDay day;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final entries = historyOn(day.adDate);
    return _Card(
      color: s.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (entries.isEmpty ? 'Did you know?' : 'What happened on this day?')
                .toUpperCase(),
            style: s.sectionLabel,
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Text(factFor(day.adDate), style: s.body.copyWith(fontSize: 16)),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 58,
                    child: Text(
                      s.digits(e.year),
                      style: s.mono.copyWith(color: s.accent, fontSize: 14),
                    ),
                  ),
                  Expanded(
                    child: Text(e.text, style: s.body.copyWith(fontSize: 15)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
