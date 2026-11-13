import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patro/models/app_settings.dart';
import 'package:patro/models/patro_event.dart';
import 'package:patro/providers/events_provider.dart';
import 'package:patro/providers/settings_provider.dart';
import 'package:patro/providers/storage_provider.dart';
import 'package:patro/screens/home_shell.dart';
import 'package:patro/screens/settings_page.dart';
import 'package:patro/screens/year_page.dart';
import 'package:patro/theme/patro_style.dart';
import 'package:patro/widgets/day_timeline.dart';
import 'package:patro/widgets/event_editor_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders the new screens at phone size, so overflows and layout errors
/// fail here rather than on a device.
void main() {
  Future<Widget> app(
    Widget home, {
    AppSettings settings = const AppSettings(),
    List<PatroEvent> events = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      SettingsNotifier.storageKey: jsonEncode(settings.toJson()),
      EventsNotifier.storageKey: jsonEncode([
        for (final e in events) e.toJson(),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: buildPatroTheme(ref.watch(settingsProvider)),
          home: home,
        ),
      ),
    );
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);

  testWidgets('opens on the chosen start page, the date page', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      await app(
        const HomeShell(),
        settings: const AppSettings(startPage: ShellPage.date),
        events: [
          PatroEvent.create(date: today, title: 'Standup', startMinutes: 600),
          PatroEvent.create(
            date: today,
            title: 'Overlap',
            startMinutes: 630,
            endMinutes: 720,
            location: 'Room 2',
          ),
          PatroEvent.create(date: today, title: 'Holiday'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('मिति'), findsOneWidget);
    expect(find.byType(DayTimeline), findsOneWidget);
    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('Holiday'), findsOneWidget);

    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    expect(find.text('Standup'), findsNothing);
  });

  testWidgets('hiding the date page falls back to the day list', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      await app(
        const HomeShell(),
        settings: const AppSettings(
          startPage: ShellPage.date,
          showDatePage: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('मिति'), findsNothing);
  });

  testWidgets('the event editor lays out every option', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      await app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showEventEditor(context, date: today),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        settings: const AppSettings(defaultReminder: 10),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Repeat is a dropdown: open it and pick Weekly.
    expect(find.text('Repeat'), findsOneWidget);
    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();
    expect(find.text('Monthly · BS'), findsOneWidget);
    await tester.tap(find.text('Weekly').last);
    await tester.pumpAndSettle();
    // The select now reads Weekly, and "Repeat until" appears.
    expect(find.text('REPEAT UNTIL'), findsOneWidget);
    expect(find.text('Never'), findsOneWidget);

    final sheet = find
        .descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('REMINDERS'),
      200,
      scrollable: sheet,
    );
    expect(find.text('10 min before'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Yoga');
    await tester.enterText(find.widgetWithText(TextField, 'Location'), 'Park');
    // Let go of the keyboard, or the focused field scrolls back into view.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.text('open')),
    );
    final saved = container.read(eventsProvider).all.single;
    expect(saved.title, 'Yoga');
    expect(saved.location, 'Park');
    expect(saved.repeat, EventRepeat.weekly);
    expect(saved.reminders, [10]);
  });

  for (final columns in yearColumnChoices) {
    testWidgets('the year page lays out $columns months per row', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        await app(
          const Scaffold(body: YearPage()),
          settings: AppSettings(yearColumns: columns, nepaliDigits: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Baishakh'), findsOneWidget);
      if (columns == 2) {
        // The later months are below the fold and scroll into view.
        await tester.scrollUntilVisible(
          find.text('Chaitra'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
      }
      expect(find.text('Chaitra'), findsOneWidget);
    });
  }

  testWidgets('settings shows saved themes, pages and icons', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      await app(
        const Scaffold(body: SettingsPage()),
        settings: AppSettings(
          customThemes: [
            ThemePreset(
              '${ThemePreset.customPrefix}a',
              'Dusk',
              themePresets.first.colors,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The main page is a short list of groups, with no preview.
    expect(find.text('Preview'), findsNothing);
    expect(find.text('PREVIEW'), findsNothing);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    // Saved themes follow the built-in ones in the horizontal strip.
    await tester.dragUntilVisible(
      find.text('Dusk'),
      find.byType(ListView).at(1),
      const Offset(-200, 0),
    );
    expect(find.text('Dusk'), findsOneWidget);
    expect(find.text('Moleskine'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Days with events'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Faded'), findsWidgets);
    expect(find.text('Months per row'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pages'));
    await tester.pumpAndSettle();
    expect(find.text('Date page'), findsOneWidget);
    expect(find.text('Open the app on'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Events & reminders'));
    await tester.pumpAndSettle();
    expect(find.text('Default reminder'), findsOneWidget);
    // A dropdown with a custom option, not chips.
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '45');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Default reminder')),
    );
    expect(container.read(settingsProvider).defaultReminder, 45);
    expect(find.text('45 min before'), findsOneWidget);
  });

  testWidgets('pulling past the end of a day opens the next one', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      await app(
        const HomeShell(),
        settings: const AppSettings(startPage: ShellPage.date),
        events: [
          PatroEvent.create(date: today, title: 'Standup', startMinutes: 600),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Standup'), findsOneWidget);

    // A short pull springs back.
    await tester.drag(find.byType(HomeShell), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(find.text('Standup'), findsOneWidget);

    // Scroll to the bottom, then keep pulling against the resistance.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HomeShell)),
    );
    for (var i = 0; i < 80; i++) {
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Standup'), findsNothing);
  });
}
