import 'package:flutter/material.dart';

import '../theme/patro_style.dart';
import 'common.dart';

const _swatches = [
  // Darks for backgrounds and surfaces.
  Color(0xFF000000), Color(0xFF121214), Color(0xFF1B1B1F), Color(0xFF0B1020),
  Color(0xFF1F2A24), Color(0xFF1A0F12), Color(0xFF2B2522), Color(0xFF3A3A40),
  // Lights.
  Color(0xFFFFFFFF), Color(0xFFF4F4F5), Color(0xFFF3EEE3), Color(0xFFFBF8F1),
  Color(0xFFEFF3F6), Color(0xFFEFECE6), Color(0xFFE6EAF5), Color(0xFFF6E9EC),
  // Accents.
  Color(0xFFFFD700), Color(0xFFF6B73C), Color(0xFFFF6E61), Color(0xFFE5484D),
  Color(0xFFFF2E63), Color(0xFFFF8FA3), Color(0xFFB58CFF), Color(0xFF5B8CFF),
  Color(0xFF4A80F0), Color(0xFF2D6CDF), Color(0xFF1592A6), Color(0xFF8FD3C1),
  Color(0xFF5FBF7F), Color(0xFFB5D99C), Color(0xFF9A6B12), Color(0xFF111113),
];

/// Bottom sheet that edits a colour live: [onChanged] fires on every change.
Future<void> showColorPickerSheet(
  BuildContext context, {
  required String title,
  required Color initial,
  required ValueChanged<Color> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _ColorPickerSheet(title: title, initial: initial, onChanged: onChanged),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({
    required this.title,
    required this.initial,
    required this.onChanged,
  });

  final String title;
  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  void _set(HSVColor hsv) {
    setState(() => _hsv = hsv);
    widget.onChanged(hsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final color = _hsv.toColor();
    final hex = color.toARGB32().toRadixString(16).substring(2).toUpperCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: s.scaledRadius(0.7),
                  border: Border.all(color: s.hairline),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: s.body.copyWith(fontSize: 17)),
                    Text('#$hex', style: s.mono),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _set(HSVColor.fromColor(widget.initial)),
                child: const Text('Revert'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final swatch in _swatches)
                Pressable(
                  onTap: () => _set(HSVColor.fromColor(swatch)),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: swatch.toARGB32() == color.toARGB32()
                            ? s.highlight
                            : s.hairline,
                        width: swatch.toARGB32() == color.toARGB32() ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _GradientSlider(
            label: 'Hue',
            value: _hsv.hue / 360,
            colors: [
              for (var h = 0; h <= 360; h += 60)
                HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
            ],
            onChanged: (v) => _set(_hsv.withHue(v * 360)),
          ),
          _GradientSlider(
            label: 'Saturation',
            value: _hsv.saturation,
            colors: [
              _hsv.withSaturation(0).toColor(),
              _hsv.withSaturation(1).toColor(),
            ],
            onChanged: (v) => _set(_hsv.withSaturation(v)),
          ),
          _GradientSlider(
            label: 'Brightness',
            value: _hsv.value,
            colors: [Colors.black, _hsv.withValue(1).toColor()],
            onChanged: (v) => _set(_hsv.withValue(v)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  final String label;
  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: s.sectionLabel),
          SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: LinearGradient(colors: colors),
                      border: Border.all(color: s.hairline),
                    ),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 0,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: s.ink,
                    overlayColor: s.ink.withValues(alpha: 0.12),
                  ),
                  child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
