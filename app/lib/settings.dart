import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sim/sim.dart';

/// Version shown in the start menu; keep in step with pubspec.yaml.
const appVersion = '0.5.0 alpha';

/// How the interface adapts its colours for colour-blind players. The
/// colours are shifted so that red and green, or blue and yellow, can be
/// told apart again (daltonisation).
enum ColorVision {
  normal('Normal colours'),
  deuteranopia('Deuteranopia (green weakness)'),
  protanopia('Protanopia (red weakness)'),
  tritanopia('Tritanopia (blue weakness)');

  const ColorVision(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);

  /// Colour matrix for a [ColorFilter.matrix], or null for normal colours.
  List<double>? get matrix {
    final sim = switch (this) {
      ColorVision.normal => null,
      ColorVision.deuteranopia => const [
        [0.367322, 0.860646, -0.227968],
        [0.280085, 0.672501, 0.047413],
        [-0.011820, 0.042940, 0.968881],
      ],
      ColorVision.protanopia => const [
        [0.152286, 1.052583, -0.204868],
        [0.114503, 0.786281, 0.099216],
        [-0.003882, -0.048116, 1.051998],
      ],
      ColorVision.tritanopia => const [
        [1.255528, -0.076749, -0.178779],
        [-0.078411, 0.930809, 0.147602],
        [0.004733, 0.691367, 0.303900],
      ],
    };
    if (sim == null) return null;
    // What the eye misses is moved into the channels it still sees.
    final shift = this == ColorVision.tritanopia
        ? const [
            [1.0, 0.0, 0.7],
            [0.0, 1.0, 0.7],
            [0.0, 0.0, 0.0],
          ]
        : const [
            [0.0, 0.0, 0.0],
            [0.7, 1.0, 0.0],
            [0.7, 0.0, 1.0],
          ];
    final m = List.generate(3, (i) => List.filled(3, 0.0));
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        var sum = i == j ? 1.0 : 0.0;
        for (var k = 0; k < 3; k++) {
          final lost = (k == j ? 1.0 : 0.0) - sim[k][j];
          sum += shift[i][k] * lost;
        }
        m[i][j] = sum;
      }
    }
    return [
      for (var i = 0; i < 3; i++) ...[m[i][0], m[i][1], m[i][2], 0, 0],
      0,
      0,
      0,
      1,
      0,
    ];
  }
}

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
    if (!persist) return;
    I18n.lang = _lang;
    if (!_file.existsSync()) return;
    try {
      final j = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      _scale = (j['scale'] as num?)?.toDouble() ?? 1;
      _animations = j['animations'] as bool? ?? true;
      _fullScreen = j['fullScreen'] as bool? ?? false;
      _debug = j['debug'] as bool? ?? false;
      _vision = ColorVision.values
          .where((v) => v.name == j['vision'])
          .firstWhere((_) => true, orElse: () => ColorVision.normal);
      _lang = Lang.values
          .where((l) => l.name == j['lang'])
          .firstWhere((_) => true, orElse: () => Lang.en);
      I18n.lang = _lang;
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
  var _debug = false;
  var _vision = ColorVision.normal;

  /// Colours for colour-blind players.
  ColorVision get vision => _vision;
  set vision(ColorVision v) => _set(() => _vision = v);

  /// Debug mode: exact values for all riders, internal figures on the
  /// rider page, a debug page with test actions.
  bool get debug => _debug;
  set debug(bool v) => _set(() => _debug = v);
  var _lang = Lang.en;

  /// Language of the interface and of all texts the game writes.
  Lang get lang => _lang;
  set lang(Lang v) => _set(() {
    _lang = v;
    I18n.lang = v;
  });

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
          'debug': _debug,
          'lang': _lang.name,
          'vision': _vision.name,
        }),
      );
    }
    notifyListeners();
  }
}
