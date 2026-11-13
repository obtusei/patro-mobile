import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patro/core/astronomy.dart';
import 'package:patro/models/app_settings.dart';
import 'package:patro/providers/calendar_provider.dart';
import 'package:patro/providers/settings_provider.dart';
import 'package:patro/providers/storage_provider.dart';
import 'package:patro/screens/settings/sky_settings.dart';
import 'package:patro/screens/sky_page.dart';
import 'package:patro/theme/patro_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('astronomy', () {
    test('matches Meeus worked examples', () {
      // Example 47.a: Moon, 1992-04-12 0h TD.
      final m = Astro.moonEcliptic(2448724.5);
      expect(m.lon, closeTo(133.1627, 0.02));
      expect(m.lat, closeTo(-3.2291, 0.01));
      expect(m.distanceKm, closeTo(368409.7, 50));
      // Example 25.a: Sun, 1992-10-13 0h TD.
      expect(Astro.sunEcliptic(2448908.5).lon, closeTo(199.9099, 0.01));
    });

    test('Kathmandu sun times and panchanga are sensible', () {
      const npt = Duration(hours: 5, minutes: 45);
      final start = DateTime.utc(2026, 11, 13).subtract(npt);
      final sun = Astro.riseSet(Body.sun, start, GeoLocation.kathmandu);
      // Solar noon ~11:48 NPT; ~10h49m of daylight in mid-November.
      expect(sun.transit!.add(npt).hour, 11);
      expect(sun.upFor!.inMinutes, closeTo(649, 10));
      final p = Panchanga.at(DateTime.utc(2026, 11, 13, 6), sun: sun);
      expect(p.tithi, 3); // Shukla Chaturthi
      expect(p.sunRashi, 6); // Tula
      expect(p.lunarMonth, 7); // Kartik
      // Full moon 24 Nov 2026 ~14:53 UTC.
      expect(
        p.nextPurnima.difference(DateTime.utc(2026, 11, 24, 14, 53)).inMinutes,
        closeTo(0, 15),
      );
      expect(p.rahuKaal, isNotNull);
    });

    test('settings round-trip the sky page and location', () {
      final s = const AppSettings().copyWith(
        showSkyPage: false,
        skyLocation: const GeoLocation(28.2, 83.98, 'Pokhara'),
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.showSkyPage, isFalse);
      expect(back.skyLocation, s.skyLocation);
      expect(back.visiblePages, isNot(contains(ShellPage.sky)));
      expect(const AppSettings().visiblePages, contains(ShellPage.sky));
    });
  });

  Future<Widget> app(Widget home, {bool nepali = false}) async {
    SharedPreferences.setMockInitialValues({
      SettingsNotifier.storageKey: jsonEncode(
        AppSettings(nepaliDigits: nepali).toJson(),
      ),
    });
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        shellPageProvider.overrideWith((ref) => ShellPage.sky),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: buildPatroTheme(ref.watch(settingsProvider)),
          home: Scaffold(body: home),
        ),
      ),
    );
  }

  for (final nepali in [false, true]) {
    testWidgets('sky page renders at phone size (nepali: $nepali)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await app(const SkyPage(), nepali: nepali));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(find.text(nepali ? 'आकाश' : 'Sky'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sky settings toggles the page', (tester) async {
    await tester.pumpWidget(await app(const SkySettings()));
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SkySettings)),
    );
    expect(container.read(settingsProvider).showSkyPage, isFalse);
  });
}
