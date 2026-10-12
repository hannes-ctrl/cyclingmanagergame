import 'model.dart';

/// Points, mountain points and bonus seconds a race awards, by the "sprint
/// type" names of the WorldDB's classification files (`finish_flat`,
/// `mountain_hc`, `sprint_bonif`, …).
class PointsScheme {
  /// Creates a scheme.
  ///
  /// @param points Points classification: sprint type to points by place.
  /// @param mountain Mountain classification: sprint type to points by place.
  /// @param seconds Bonus seconds: sprint type to seconds by place.
  const PointsScheme({
    this.points = const {},
    this.mountain = const {},
    this.seconds = const {},
  });

  final Map<String, List<int>> points;
  final Map<String, List<int>> mountain;
  final Map<String, List<int>> seconds;

  /// Fallback modelled on the Grand Tours, used when a race has no
  /// classification file or the file lacks a sprint type.
  static const standard = PointsScheme(
    points: {
      'finish_flat': [50, 30, 20, 18, 16, 14, 12, 10, 8, 7, 6, 5, 4, 3, 2],
      'finish_hill': [30, 25, 22, 19, 17, 15, 13, 11, 9, 7, 6, 5, 4, 3, 2],
      'finish_mountainstage': [
        20,
        17,
        15,
        13,
        11,
        10,
        9,
        8,
        7,
        6,
        5,
        4,
        3,
        2,
        1
      ],
      'finish_itt': [20, 17, 15, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
      'finish_classic': [20, 17, 15, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
      'sprint_bonif': [20, 17, 15, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
    },
    mountain: {
      'mountain_hc': [20, 15, 12, 10, 8, 6, 4, 2],
      'mountain_1': [10, 8, 6, 4, 2, 1],
      'mountain_2': [5, 3, 2, 1],
      'mountain_3': [2, 1],
      'mountain_4': [1],
    },
    seconds: {
      'finish_flat': [10, 6, 4],
      'finish_hill': [10, 6, 4],
      'finish_mountainstage': [10, 6, 4],
      'finish_classic': [10, 6, 4],
    },
  );

  static const _categories = ['hc', 'hc', '1', '2', '3', '4'];

  /// @param category Climb category, 1 = HC … 5 = fourth category.
  /// @returns The suffix used in sprint type names.
  static String categoryName(int category) => _categories[category.clamp(1, 5)];

  /// Works out which finish type a stage has.
  ///
  /// @param route The stage.
  /// @param oneDay Whether the race is a one-day race.
  /// @returns A sprint type name such as `finish_flat` or `finish_mountain_1`.
  static String finishType(SimRoute route, {required bool oneDay}) {
    if (route.kind == StageKind.teamTimeTrial) return 'finish_ttt';
    if (route.kind == StageKind.timeTrial) return 'finish_itt';
    if (oneDay) return 'finish_classic';
    if (route.sprintStage) return 'finish_flat';
    // Summit finish: a categorised climb tops out at the line.
    final summit = route.climbTops
        .where((p) => p.km >= route.raceKm - 0.6 && p.category > 0)
        .firstOrNull;
    if (summit != null)
      return 'finish_mountain_${categoryName(summit.category)}';
    return route.selectivity < 1500 ? 'finish_hill' : 'finish_mountainstage';
  }

  /// Looks up a scale with fallbacks: a summit finish falls back to a
  /// mountain stage, and anything missing to [standard].
  ///
  /// @param table One of [points], [mountain] or [seconds].
  /// @param fallback The same table of [standard].
  /// @param type Sprint type name.
  /// @returns Values by place, possibly empty.
  static List<int> _lookup(Map<String, List<int>> table,
      Map<String, List<int>> fallback, String type) {
    final generic =
        type.startsWith('finish_mountain_') ? 'finish_mountainstage' : type;
    return table[type] ??
        table[generic] ??
        (table.isEmpty ? fallback[type] ?? fallback[generic] : null) ??
        const [];
  }

  /// @param type Sprint type name.
  /// @returns Points for the points classification by place.
  List<int> pointsFor(String type) => _lookup(points, standard.points, type);

  /// @param type Sprint type name.
  /// @returns Points for the mountain classification by place.
  List<int> mountainFor(String type) =>
      _lookup(mountain, standard.mountain, type);

  /// @param type Sprint type name.
  /// @returns Bonus seconds by place.
  List<int> secondsFor(String type) => _lookup(seconds, standard.seconds, type);
}
