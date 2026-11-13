import 'dart:ui';

/// A launcher icon the user can pick on Android. The Android side declares a
/// matching launcher entry for each id (see AndroidManifest.xml).
class AppIconOption {
  const AppIconOption(this.id, this.name, this.background, this.foreground);

  final String id;
  final String name;
  final Color background;
  final Color foreground;
}

const appIcons = [
  AppIconOption('classic', 'Crimson', Color(0xFFC21D1D), Color(0xFFFFFFFF)),
  AppIconOption('obsidian', 'Obsidian', Color(0xFF121214), Color(0xFFFFD700)),
  AppIconOption('snow', 'Snow', Color(0xFFFFFFFF), Color(0xFF111113)),
  AppIconOption('midnight', 'Midnight', Color(0xFF0B1020), Color(0xFF8AB4FF)),
  AppIconOption(
    'chalkboard',
    'Chalkboard',
    Color(0xFF1F2A24),
    Color(0xFFF6E7A1),
  ),
  AppIconOption(
    'rhododendron',
    'Rhododendron',
    Color(0xFF1A0F12),
    Color(0xFFFF8FA3),
  ),
  AppIconOption('himalaya', 'Himalaya', Color(0xFF3A6E8F), Color(0xFFFFFFFF)),
];
