import 'package:flutter_test/flutter_test.dart';
import 'package:patro/models/app_settings.dart';
import 'package:patro/services/compass_sensor.dart';
import 'package:patro/widgets/sky_scene.dart';

void main() {
  group('heading', () {
    test('flat, top edge north', () {
      const axes = (
        east: Vec3(1, 0, 0),
        north: Vec3(0, 1, 0),
        up: Vec3(0, 0, 1),
      );
      expect(headingOf(axes), closeTo(0, 1e-9));
      expect(levelOf(axes).x, 0);
      expect(levelOf(axes).y, 0);
    });

    test('flat, top edge east', () {
      // Right edge to the south, so north is to the left (−x).
      const axes = (
        east: Vec3(0, 1, 0),
        north: Vec3(-1, 0, 0),
        up: Vec3(0, 0, 1),
      );
      expect(headingOf(axes), closeTo(90, 1e-9));
    });

    test('upright, camera west', () {
      // Top edge up; the back camera (−z) looks west, so east is +z and the
      // right edge points north.
      const axes = (
        east: Vec3(0, 0, 1),
        north: Vec3(1, 0, 0),
        up: Vec3(0, 1, 0),
      );
      expect(headingOf(axes), closeTo(270, 1e-9));
    });

    test('settings round-trip the compass page', () {
      final off = AppSettings.fromJson(
        const AppSettings().copyWith(showCompassPage: false).toJson(),
      );
      expect(off.showCompassPage, isFalse);
      expect(off.visiblePages, isNot(contains(ShellPage.compass)));
      // Tests run as Android, so the page shows by default.
      expect(const AppSettings().visiblePages, contains(ShellPage.compass));
      expect(
        const AppSettings().visiblePages.last,
        ShellPage.settings,
        reason: 'Settings stays the last page',
      );
    });
  });
}
