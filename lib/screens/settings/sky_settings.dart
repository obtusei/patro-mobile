import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/astronomy.dart';
import '../../core/platform.dart';
import '../../models/app_settings.dart';
import '../../providers/settings_provider.dart';
import '../../theme/patro_style.dart';
import '../../widgets/common.dart';
import '../../widgets/select.dart';
import 'settings_parts.dart';

void _set(WidgetRef ref, AppSettings Function(AppSettings) change) =>
    ref.read(settingsProvider.notifier).update(change);

String placeLabel(GeoLocation at) => at.name.isNotEmpty
    ? at.name
    : '${at.latitude.toStringAsFixed(2)}°, ${at.longitude.toStringAsFixed(2)}°';

/// The Sky page switch and the place its positions are computed for.
class SkySettings extends ConsumerWidget {
  const SkySettings({super.key});

  Future<void> _locate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        say('Turn on location services first.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        say('Location access is off. Pick a place instead.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 20),
        ),
      );
      // Two decimals (~1 km) is plenty for the sky, and keeps less of the
      // user's whereabouts on the phone.
      double round(double v) => (v * 100).roundToDouble() / 100;
      _set(
        ref,
        (x) => x.copyWith(
          skyLocation: GeoLocation(
            round(pos.latitude),
            round(pos.longitude),
            'My location',
          ),
        ),
      );
      say('Using your location.');
    } on Object {
      say('Could not get your location.');
    }
  }

  Future<void> _custom(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<GeoLocation>(
      context: context,
      builder: (_) =>
          _CoordinatesDialog(initial: ref.read(settingsProvider).skyLocation),
    );
    if (picked != null) _set(ref, (x) => x.copyWith(skyLocation: picked));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = PatroStyle.of(context);
    final settings = ref.watch(settingsProvider);
    final location = settings.skyLocation;
    final preset = skyPlaces.where((p) => p == location).firstOrNull;

    return SettingsSubpage(
      title: 'Sun & Moon',
      children: [
        const SectionLabel('Page'),
        SettingsSwitchRow(
          title: 'Sky page',
          subtitle:
              'Live Sun and Moon positions in 3D and AR, with the panchanga',
          value: settings.showSkyPage,
          onChanged: (v) => _set(ref, (x) => x.copyWith(showSkyPage: v)),
        ),
        const SectionLabel('Location'),
        SelectRow<GeoLocation?>(
          title: 'Place',
          subtitle:
              '${location.latitude.toStringAsFixed(4)}°, '
              '${location.longitude.toStringAsFixed(4)}°',
          value: preset,
          valueLabel: placeLabel(location),
          options: [for (final p in skyPlaces) SelectOption(p, p.name)],
          onChanged: (p) {
            if (p != null) _set(ref, (x) => x.copyWith(skyLocation: p));
          },
          onCustom: () => _custom(context, ref),
        ),
        if (isPhone)
          SettingsActionRow(
            icon: Icons.my_location_rounded,
            title: 'Use my location',
            subtitle: 'Approximate, read once from this phone',
            onTap: () => _locate(context, ref),
          ),
        const SizedBox(height: 8),
        Text(
          'Positions, rise and set times and the panchanga are computed on '
          'your phone; nothing is sent anywhere. Times show in your phone\'s '
          'time zone.',
          style: s.bodySmall,
        ),
      ],
    );
  }
}

class _CoordinatesDialog extends StatefulWidget {
  const _CoordinatesDialog({required this.initial});

  final GeoLocation initial;

  @override
  State<_CoordinatesDialog> createState() => _CoordinatesDialogState();
}

class _CoordinatesDialogState extends State<_CoordinatesDialog> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _lat = TextEditingController(
    text: widget.initial.latitude.toString(),
  );
  late final _lon = TextEditingController(
    text: widget.initial.longitude.toString(),
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  void _save() {
    final lat = double.tryParse(_lat.text.trim());
    final lon = double.tryParse(_lon.text.trim());
    if (lat == null || lat.abs() > 90) {
      setState(() => _error = 'Latitude is between −90 and 90');
      return;
    }
    if (lon == null || lon.abs() > 180) {
      setState(() => _error = 'Longitude is between −180 and 180');
      return;
    }
    Navigator.pop(context, GeoLocation(lat, lon, _name.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    const numeric = TextInputType.numberWithOptions(
      signed: true,
      decimal: true,
    );
    return AlertDialog(
      title: const Text('Coordinates'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Name (optional)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lat,
            keyboardType: numeric,
            decoration: const InputDecoration(
              hintText: 'Latitude, north positive',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lon,
            keyboardType: numeric,
            decoration: const InputDecoration(
              hintText: 'Longitude, east positive',
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: s.bodySmall.copyWith(color: s.holiday)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
