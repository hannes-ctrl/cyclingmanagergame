import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Settings of the app that do not belong to a career: how big the interface
/// is drawn, whether pages fade in and whether the window starts in full
/// screen. Stored as `settings.json` in the data folder.
class AppSettings extends ChangeNotifier {
  /// Reads the settings, or starts with the defaults.
  ///
  /// @param dataDir The data folder of the app.
  /// @param persist Whether changes are written to disk (off in tests).
  AppSettings(String dataDir, {this.persist = true})
    : _file = File('$dataDir/settings.json') {
    if (!persist || !_file.existsSync()) return;
    try {
      final j = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      _scale = (j['scale'] as num?)?.toDouble() ?? 1;
      _animations = j['animations'] as bool? ?? true;
      _fullScreen = j['fullScreen'] as bool? ?? false;
    } on Object {
      // A broken file must not keep the app from starting.
    }
  }

  final File _file;
  final bool persist;

  /// Sizes the interface can be drawn at.
  static const scales = [0.9, 1.0, 1.1, 1.25];

  var _scale = 1.0;
  var _animations = true;
  var _fullScreen = false;

  /// Factor on the size of the whole interface.
  double get scale => _scale;
  set scale(double v) => _set(() => _scale = v);

  /// Whether pages fade in when the player switches between them.
  bool get animations => _animations;
  set animations(bool v) => _set(() => _animations = v);

  /// Whether the window opens in full screen.
  bool get fullScreen => _fullScreen;
  set fullScreen(bool v) => _set(() => _fullScreen = v);

  void _set(void Function() change) {
    change();
    if (persist) {
      _file.writeAsStringSync(
        jsonEncode({
          'scale': _scale,
          'animations': _animations,
          'fullScreen': _fullScreen,
        }),
      );
    }
    notifyListeners();
  }
}
