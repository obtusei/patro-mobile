import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../widgets/sky_scene.dart';

/// The world axes in device coordinates, from gravity and the magnetic
/// field. Device coordinates: x right, y toward the top of the screen, z out
/// of the screen.
typedef DeviceAxes = ({Vec3 east, Vec3 north, Vec3 up});

/// Reads the accelerometer and magnetometer and works out which way the
/// phone faces. Shared by the compass, the sky dome and the AR view.
///
/// Call [start] while the reading is on screen and [stop] when it is not;
/// sensors left running drain the battery.
class CompassSensor {
  /// The latest axes; null until both sensors have reported.
  final axes = ValueNotifier<DeviceAxes?>(null);

  /// Set when the phone has no compass or motion sensor.
  final error = ValueNotifier<String?>(null);

  final _subscriptions = <StreamSubscription<Object>>[];
  Vec3? _gravity;
  Vec3? _magnetic;

  bool get running => _subscriptions.isNotEmpty;

  void start() {
    if (running) return;
    // Cleared first so a repeat failure notifies listeners again.
    error.value = null;
    void fail(Object _) => error.value = 'no-sensor';
    try {
      _subscriptions
        ..add(
          accelerometerEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ).listen((e) {
            _gravity = _smooth(_gravity, Vec3(e.x, e.y, e.z));
            _update();
          }, onError: fail),
        )
        ..add(
          magnetometerEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ).listen((e) {
            _magnetic = _smooth(_magnetic, Vec3(e.x, e.y, e.z));
            _update();
          }, onError: fail),
        );
    } on Object catch (e) {
      // No sensor plugin on this platform (desktop, tests).
      fail(e);
    }
  }

  void stop() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
  }

  void dispose() {
    stop();
    axes.dispose();
    error.dispose();
  }

  /// Low-pass filter: steadies the jitter of raw sensor readings.
  static Vec3 _smooth(Vec3? previous, Vec3 next) =>
      previous == null ? next : previous + (next - previous) * 0.12;

  void _update() {
    final g = _gravity, m = _magnetic;
    if (g == null || m == null) return;
    // As Android's SensorManager.getRotationMatrix: east is the magnetic
    // field crossed with gravity, north completes the frame.
    final h = m.cross(g);
    if (h.length < 1e-3 || g.length < 1e-3) return;
    final east = h.normalized;
    final up = g.normalized;
    axes.value = (east: east, north: up.cross(east), up: up);
  }
}

/// Which way the phone faces, degrees east of magnetic north.
///
/// Lying flat, that is where the top of the phone points; held upright,
/// where the back camera looks. The two are added so the reading stays
/// steady as the phone tilts from one to the other.
double headingOf(DeviceAxes a) {
  // Device +y (top edge) and −z (back camera) in world coordinates.
  final topEast = a.east.y, topNorth = a.north.y;
  final backEast = -a.east.z, backNorth = -a.north.z;
  final e = topEast + backEast, n = topNorth + backNorth;
  if (e.abs() < 1e-6 && n.abs() < 1e-6) return 0;
  return (math.atan2(e, n) * 180 / math.pi) % 360;
}

/// How far the phone leans from flat, as the spirit-level bubble sees it:
/// x positive when the right edge is up, y positive when the top edge is
/// up. Each in −1…1 (the sine of the tilt).
({double x, double y}) levelOf(DeviceAxes a) => (x: a.up.x, y: a.up.y);
