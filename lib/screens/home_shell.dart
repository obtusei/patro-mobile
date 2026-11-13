import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/calendar_provider.dart';
import '../providers/settings_provider.dart';
import '../services/feedback_service.dart';
import '../services/widget_bridge.dart';
import 'date_page.dart';
import 'day_detail_screen.dart';
import 'day_list_page.dart';
import 'compass_page.dart';
import 'month_page.dart';
import 'settings_page.dart';
import 'sky_page.dart';
import 'year_page.dart';

/// Year · Month · Days · Date · Sky · Compass · Settings, side by side;
/// swipe to move between them. The date, sky and compass pages can be turned
/// off in Settings.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late List<ShellPage> _visible = ref.read(settingsProvider).visiblePages;
  late final _pages = PageController(
    initialPage: _indexOf(ref.read(shellPageProvider)),
  );

  int _indexOf(ShellPage page) {
    final i = _visible.indexOf(page);
    return i >= 0 ? i : _visible.indexOf(ShellPage.day);
  }

  /// Pages were shown or hidden: stay on the same page, or fall back to the
  /// day list if it was the one hidden.
  void _onVisibleChanged(List<ShellPage> visible) {
    final current = ref.read(shellPageProvider);
    _visible = visible;
    final target = visible.contains(current) ? current : ShellPage.day;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (target != current) {
        ref.read(shellPageProvider.notifier).state = target;
      }
      if (_pages.hasClients) _pages.jumpToPage(_indexOf(target));
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(feedbackProvider).warmUp();
      WidgetBridge.listenForDays(_openDay);
    });
  }

  /// A home-screen widget asked for [day]: show its page over the shell,
  /// replacing any page or sheet already open.
  void _openDay(DateTime day) {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    navigator.push(DayDetailScreen.route(day));
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _page(ShellPage page) => switch (page) {
    ShellPage.year => const YearPage(),
    ShellPage.month => const MonthPage(),
    ShellPage.day => const DayListPage(),
    ShellPage.date => const DatePage(),
    ShellPage.sky => const SkyPage(),
    ShellPage.compass => const CompassPage(),
    ShellPage.settings => const SettingsPage(),
  };

  @override
  Widget build(BuildContext context) {
    // A record compares by value, so only these switches rebuild the shell.
    ref.watch(
      settingsProvider.select(
        (s) => (s.showDatePage, s.showSkyPage, s.showCompassPage),
      ),
    );
    final visible = ref.read(settingsProvider).visiblePages;
    if (!listEquals(visible, _visible)) {
      _onVisibleChanged(visible);
    }

    ref.listen(shellPageProvider, (_, next) {
      final index = _indexOf(next);
      if (_pages.hasClients && _pages.page?.round() != index) {
        _pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Phone-width pages on tablets and desktop.
            constraints: const BoxConstraints(maxWidth: 640),
            child: PageView(
              controller: _pages,
              onPageChanged: (i) {
                ref.read(shellPageProvider.notifier).state = _visible[i];
                ref.read(feedbackProvider).play(PatroSound.pageTurn);
              },
              children: [
                // Keyed, so pages keep their state when one is shown or
                // hidden between them.
                for (final page in _visible)
                  _KeepAlive(_page(page), key: ValueKey(page)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps an off-screen page mounted so it keeps its scroll position.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive(this.child, {super.key});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
