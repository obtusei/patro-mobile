import 'package:flutter/foundation.dart';

/// Phone calendars and the camera scanner exist only on Android and iOS.
final bool isPhone =
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
