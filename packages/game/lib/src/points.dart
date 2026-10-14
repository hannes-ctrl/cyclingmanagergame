import 'package:sim/sim.dart';

/// Tier of a race, derived from the race class of the WorldDB.
enum RaceTier {
  grandTour('Grand Tour', 13),
  monument('Monument', 8),
  worldTour('WorldTour', 5),
  proSeries('ProSeries', 2),
  class1('Class 1', 1.25),
  class2('Class 2', 0.4),
  under23('U23', 0.3),
  championship('Championship', 0);

  const RaceTier(this._label, this.factor);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);

  /// Weight of the ranking points relative to a class 1 race.
  final double factor;

  /// @param raceClass Race class of the WorldDB, e.g. `CWTGTFrance`.
  /// @returns The tier.
  static RaceTier of(String raceClass) {
    if (raceClass.contains('Championship')) return championship;
    if (raceClass.startsWith('CWTGT')) return grandTour;
    if (raceClass.startsWith('CWTMaj')) return monument;
    if (raceClass.startsWith('CWT')) return worldTour;
    if (raceClass.endsWith('HC')) return proSeries;
    if (raceClass.endsWith('U')) return under23;
    if (raceClass.endsWith('1')) return class1;
    return class2;
  }
}

/// Points for the first ten of a one-day race or a general classification,
/// before the tier factor. A simplified scale modelled on the UCI ranking;
/// the real tables will come from the WorldDB later.
const _finalScale = [100, 80, 65, 55, 45, 35, 30, 25, 20, 15];

/// Points for the first three of a stage.
const _stageScale = [16, 8, 4];

/// @param tier Tier of the race.
/// @param place Zero-based place.
/// @returns Ranking points for the final result.
double finalPoints(RaceTier tier, int place) =>
    place < _finalScale.length ? _finalScale[place] * tier.factor : 0;

/// @param tier Tier of the race.
/// @param place Zero-based place.
/// @returns Ranking points for a stage.
double stagePoints(RaceTier tier, int place) =>
    place < _stageScale.length ? _stageScale[place] * tier.factor : 0;
