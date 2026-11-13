import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/event_qr.dart';
import '../models/patro_event.dart';
import '../theme/patro_style.dart';
import '../widgets/event_editor_sheet.dart';

/// Scans an event QR code, then opens it in the editor to review and save.
Future<void> scanEventQr(BuildContext context) async {
  final event = await Navigator.of(context).push<PatroEvent>(
    MaterialPageRoute(builder: (_) => const ScanEventScreen()),
  );
  if (event == null || !context.mounted) return;
  await showEventEditor(context, date: event.date, draft: event);
}

class ScanEventScreen extends StatefulWidget {
  const ScanEventScreen({super.key});

  @override
  State<ScanEventScreen> createState() => _ScanEventScreenState();
}

class _ScanEventScreenState extends State<ScanEventScreen> {
  bool _done = false;
  bool _unknownCode = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final event = eventFromQr(barcode.rawValue ?? '');
      if (event != null) {
        _done = true;
        Navigator.pop(context, event);
        return;
      }
    }
    if (capture.barcodes.isNotEmpty && !_unknownCode) {
      setState(() => _unknownCode = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan event')),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'The camera is not available. Check that Patro is allowed '
                    'to use it.',
                    textAlign: TextAlign.center,
                    style: s.body,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Text(
              _unknownCode
                  ? 'That code is not an event'
                  : 'Point the camera at an event QR code',
              textAlign: TextAlign.center,
              style: s.body.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
