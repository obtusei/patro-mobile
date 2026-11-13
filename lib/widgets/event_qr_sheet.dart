import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/event_qr.dart';
import '../models/patro_event.dart';
import '../theme/patro_style.dart';
import 'common.dart';

/// Shows [event] with a QR code others can scan to add it.
Future<void> showEventQr(BuildContext context, PatroEvent event) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EventQrSheet(event: event),
  );
}

class _EventQrSheet extends StatelessWidget {
  const _EventQrSheet({required this.event});

  final PatroEvent event;

  /// Renders the code on white with a quiet zone, whatever the theme.
  Future<void> _share(String data) async {
    const size = 1024.0;
    const margin = 72.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, size, size),
        Paint()..color = Colors.white,
      )
      ..translate(margin, margin);
    QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
    ).paint(canvas, const Size.square(size - 2 * margin));
    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text: event.title,
        files: [
          XFile.fromData(bytes.buffer.asUint8List(), mimeType: 'image/png'),
        ],
        fileNameOverrides: const ['patro-event.png'],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final data = eventToQr(event);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(event.title, style: s.body.copyWith(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            '${DateFormat('d MMMM yyyy').format(event.date).toUpperCase()}'
            '  ·  ${eventTimeLabel(context, event).toUpperCase()}',
            style: s.mono,
          ),
          if (event.calendarName != null) ...[
            const SizedBox(height: 4),
            Text(event.calendarName!, style: s.bodySmall),
          ],
          if (event.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(event.note, style: s.bodySmall),
          ],
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: s.borderRadius,
              ),
              child: QrImageView(
                data: data,
                size: 228,
                padding: EdgeInsets.zero,
                gapless: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Scan with Patro or a phone camera to add this event',
            textAlign: TextAlign.center,
            style: s.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _share(data),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Share QR code'),
          ),
        ],
      ),
    );
  }
}
