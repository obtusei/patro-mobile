import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

enum PatroSound {
  /// Sideways turn between Year, Month, Day and Settings, and between days:
  /// one soft chalk touch, kept quiet so swiping stays calm.
  pageTurn('sounds/chalk.mp3', 0.45),

  /// The same touch when paging months and years vertically.
  pageFlick('sounds/chalk.mp3', 0.4),

  /// The same chalk touch, fuller, when a date is tapped.
  chalk('sounds/chalk.mp3', 0.8);

  const PatroSound(this.asset, this.volume);
  final String asset;
  final double volume;
}

/// Plays UI sound effects and haptics, honouring the user's settings.
///
/// Pools are created lazily so startup never waits on audio, and every
/// failure is swallowed: feedback must never break the calendar.
class FeedbackService {
  FeedbackService(this._ref);

  final Ref _ref;
  final Map<PatroSound, Future<AudioPool?>> _pools = {};

  static final _context = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
    respectSilence: true,
  ).build();

  /// Set false in tests, where no audio platform exists.
  static bool enabled = true;

  void play(PatroSound sound) {
    final settings = _ref.read(settingsProvider);
    if (settings.haptics) {
      unawaited(
        sound == PatroSound.chalk
            ? HapticFeedback.lightImpact()
            : HapticFeedback.selectionClick(),
      );
    }
    if (!enabled || !settings.soundEffects) return;
    unawaited(_start(sound));
  }

  Future<void> _start(PatroSound sound) async {
    try {
      final pool = await (_pools[sound] ??= _createPool(sound));
      await pool?.start(volume: sound.volume);
    } on Object catch (e) {
      debugPrint('Patro: sound ${sound.name} failed: $e');
    }
  }

  Future<AudioPool?> _createPool(PatroSound sound) async {
    try {
      return await AudioPool.create(
        source: AssetSource(sound.asset),
        maxPlayers: 3,
        audioContext: _context,
      );
    } on Object catch (e) {
      debugPrint('Patro: could not load ${sound.asset}: $e');
      return null;
    }
  }

  /// Decodes the sounds ahead of first use so the first tap isn't silent.
  void warmUp() {
    if (!enabled) return;
    for (final sound in PatroSound.values) {
      _pools[sound] ??= _createPool(sound);
    }
  }
}

final feedbackProvider = Provider<FeedbackService>(FeedbackService.new);
