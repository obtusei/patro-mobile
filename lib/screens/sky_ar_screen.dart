import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/astronomy.dart';
import '../providers/settings_provider.dart';
import '../services/compass_sensor.dart';
import '../theme/patro_style.dart';
import '../widgets/sky_scene.dart';
import 'sky_page.dart';

/// Hold the phone up to the sky: the camera image with the horizon, compass,
/// ecliptic and today's Sun and Moon paths drawn over it where they really
/// are, and arrows toward whichever body is out of view.
class SkyArScreen extends ConsumerStatefulWidget {
  const SkyArScreen({super.key, this.at});

  /// A fixed moment to show; null follows the clock.
  final DateTime? at;

  @override
  ConsumerState<SkyArScreen> createState() => _SkyArScreenState();
}

class _SkyArScreenState extends ConsumerState<SkyArScreen> {
  final _compass = CompassSensor();

  CameraController? _camera;
  bool _cameraOn = true;
  String? _cameraError;

  Timer? _ticker;
  SkyDay? _day;
  Body _focus = Body.sun;

  @override
  void initState() {
    super.initState();
    // The projection assumes the phone is upright.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _compass
      ..error.addListener(() {
        if (mounted) setState(() {});
      })
      ..start();
    unawaited(_startCamera());
    if (widget.at == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _compass.dispose();
    unawaited(_camera?.dispose());
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', 'No camera found');
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } on CameraException catch (e) {
      if (mounted) {
        setState(
          () => _cameraError = e.code == 'CameraAccessDenied'
              ? 'Camera access is off; showing the sky without it.'
              : 'Camera unavailable; showing the sky without it.',
        );
      }
    } on Object {
      if (mounted) {
        setState(() => _cameraError = 'Camera unavailable.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = PatroStyle.of(context);
    final location = ref.watch(settingsProvider.select((x) => x.skyLocation));
    final time = widget.at ?? DateTime.now();
    final day = _day != null && _day!.covers(time, location)
        ? _day!
        : (_day = SkyDay(SkyDay.startOf(time), location));
    final snap = SkySnapshot.at(time, location);
    final f = SkyFormat(context, s, time);
    final scene = SkySceneData(
      snapshot: snap,
      sunPath: day.sunPath,
      moonPath: day.moonPath,
      nepali: s.nepaliDigits,
      timeLabel: f.hour,
      digits: f.n,
      focus: _focus,
    );
    final camera = _camera;
    final showCamera =
        _cameraOn && camera != null && camera.value.isInitialized;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (showCamera)
              ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    // The preview's aspect ratio is landscape; upright, the
                    // image is its inverse.
                    width: 100,
                    height: 100 * camera.value.aspectRatio,
                    child: CameraPreview(camera),
                  ),
                ),
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: SkyColors.sky(snap.sun.altitude),
                  ),
                ),
              ),
            ValueListenableBuilder<DeviceAxes?>(
              valueListenable: _compass.axes,
              builder: (context, axes, _) {
                if (axes == null) {
                  return Center(
                    child: Text(
                      _compass.error.value != null
                          ? f.w(
                              'यो फोनमा कम्पास वा गति सेन्सर छैन, त्यसैले '
                                  'दृश्यले फोनलाई पछ्याउन सक्दैन।',
                              'This phone has no compass or motion sensor, '
                                  'so the view cannot follow it.',
                            )
                          : f.w('सेन्सर पर्खँदै…', 'Waiting for the compass…'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: SkyScenePainter(
                        data: scene,
                        showPointer: true,
                        projectorFor: (size) => DeviceProjector(
                          size,
                          east: axes.east,
                          north: axes.north,
                          up: axes.up,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: _ArPanel(
                          snap: snap,
                          pointing: DeviceProjector(
                            Size.zero,
                            east: axes.east,
                            north: axes.north,
                            up: axes.up,
                          ).pointing,
                          focus: _focus,
                          format: f,
                          onFocus: (b) => setState(() => _focus = b),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: f.w('बन्द', 'Close'),
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              f.w('आकाश एआर', 'Sky AR'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${location.name.isEmpty ? f.coords(location) : location.name} · '
                              '${f.clock(time, seconds: widget.at == null)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: _cameraOn
                            ? f.w('क्यामेरा बन्द', 'Hide camera')
                            : f.w('क्यामेरा खोल्नुहोस्', 'Show camera'),
                        color: Colors.white,
                        icon: Icon(
                          _cameraOn
                              ? Icons.videocam_rounded
                              : Icons.videocam_off_rounded,
                        ),
                        onPressed: () => setState(() => _cameraOn = !_cameraOn),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_cameraError != null && _cameraOn)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 56),
                    child: Center(
                      child: Text(
                        _cameraError!,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where the phone points, and which way to turn to find each body.
class _ArPanel extends StatelessWidget {
  const _ArPanel({
    required this.snap,
    required this.pointing,
    required this.focus,
    required this.format,
    required this.onFocus,
  });

  final SkySnapshot snap;
  final Vec3 pointing;
  final Body focus;
  final SkyFormat format;
  final ValueChanged<Body> onFocus;

  @override
  Widget build(BuildContext context) {
    final f = format;
    const label = TextStyle(
      color: Colors.white60,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    );
    const value = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );

    String turn(BodyPosition b) {
      final dAz = wrap180(b.azimuth - pointing.azimuth);
      final dAlt = b.altitude - pointing.altitude;
      if (dAz.abs() < 3 && dAlt.abs() < 3) return f.w('सामुन्ने', 'dead ahead');
      final parts = [
        if (dAz.abs() >= 3)
          '${dAz > 0 ? '→' : '←'} ${f.deg(dAz.abs(), digits: 0)}',
        if (dAlt.abs() >= 3)
          '${dAlt > 0 ? '↑' : '↓'} ${f.deg(dAlt.abs(), digits: 0)}',
      ];
      return parts.join('  ');
    }

    Widget row(BodyPosition b, String name, Color color) {
      final on = focus == b.body;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onFocus(b.body),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: on ? Border.all(color: Colors.white, width: 2) : null,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 64,
                child: Text(name, style: value.copyWith(color: color)),
              ),
              Expanded(
                child: Text(
                  '${f.deg(b.altitude)} · ${f.deg(b.azimuth)} ${f.direction(b.azimuth)}',
                  style: value,
                ),
              ),
              Text(turn(b), style: value.copyWith(color: color)),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(f.w('फोन दिशा', 'PHONE POINTS'), style: label),
              const Spacer(),
              Text(
                '${f.deg(pointing.azimuth, digits: 0)} ${f.direction(pointing.azimuth)}'
                '  ·  ${f.w('उचाइ', 'alt')} ${f.deg(pointing.altitude, digits: 0)}',
                style: value,
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 14),
          row(snap.sun, f.w('सूर्य', 'Sun'), SkyColors.sun),
          row(snap.moon, f.w('चन्द्र', 'Moon'), SkyColors.moon),
          const SizedBox(height: 4),
          Text(
            f.w(
              'दिशा मिलेन भने फोनलाई ८ आकारमा घुमाएर कम्पास मिलाउनुहोस्।',
              'If directions look off, wave the phone in a figure 8 to '
                  'calibrate the compass.',
            ),
            style: const TextStyle(color: Colors.white54, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}
