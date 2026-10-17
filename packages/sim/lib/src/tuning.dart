import 'dart:convert';
import 'dart:io';

/// One tuning parameter with its permitted range for the calibration.
class TuningParam {
  const TuningParam(this.name, this.standard, this.min, this.max, this.meaning);
  final String name;
  final double standard;
  final double min;
  final double max;
  final String meaning;
}

/// Tuning parameters of the model. The defaults are estimates; the
/// calibration writes better ones to `data/calibration/tuning.json`.
class SimTuning {
  SimTuning._(this._a);

  /// Creates the default set.
  ///
  /// @param overrides Values that differ from the defaults, by parameter name.
  /// @returns The tuning set.
  factory SimTuning([Map<String, double> overrides = const {}]) => SimTuning._([
        for (final p in params) overrides[p.name] ?? p.standard,
      ]);

  static final standard = SimTuning();

  /// Reads calibrated values.
  ///
  /// @param path Path of `tuning.json`.
  /// @returns The stored values, or the defaults if the file is missing.
  static SimTuning load(String path) {
    final file = File(path);
    if (!file.existsSync()) return SimTuning();
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final values = (json['values'] ?? json) as Map<String, dynamic>;
    // Values outside the permitted ranges (from a calibration before the
    // ranges were narrowed to physical values) are pulled into them.
    return SimTuning({
      for (final e in values.entries)
        if (e.value is num) e.key: (e.value as num).toDouble(),
    }).clamped();
  }

  /// The same values, each pulled into its permitted range. Values from an
  /// older calibration can lie outside ranges that have since been narrowed.
  ///
  /// @returns The clamped set.
  SimTuning clamped() => SimTuning._([
        for (var i = 0; i < params.length; i++)
          _a[i].clamp(params[i].min, params[i].max).toDouble(),
      ]);

  /// Values in the order of [params].
  final List<double> _a;

  /// @returns All values by parameter name.
  Map<String, double> toMap() => {
        for (var i = 0; i < params.length; i++) params[i].name: _a[i],
      };

  static const params = <TuningParam>[
    TuningParam('thresholdWkg', 5.4, 5.0, 6.0,
        'Threshold power in W/kg at a rider value of 70'),
    TuningParam('gainPerPoint', 0.012, 0.008, 0.016,
        'Gain in power per point of rider value'),
    TuningParam(
        'dayFormSigma', 0.008, 0.003, 0.03, 'Spread of the form of the day'),
    TuningParam('energyPerHour', 0.2, 0.08, 0.35,
        'Stamina reserve used per hour at threshold'),
    TuningParam('fatigueLoss', 0.18, 0.05, 0.35,
        'Loss of power with an empty stamina reserve'),
    TuningParam('reserveDrainS', 240, 45, 480,
        'Seconds until the short-term reserve is empty at 125 % of threshold'),
    TuningParam('reserveRefillS', 600, 200, 1500,
        'Seconds until it refills at 70 % of threshold'),
    TuningParam('controlEffort', 0.76, 0.6, 0.96,
        'Effort of the pace-setters in a quiet peloton'),
    TuningParam('chaseEffort', 0.95, 0.85, 1.05,
        'Highest effort of the peloton in the chase'),
    TuningParam('breakEffort', 0.9, 0.8, 0.98, 'Effort of the breakaway'),
    TuningParam('secondsPerKmAllowed', 6, 2, 12,
        'Lead per remaining kilometre the peloton allows'),
    TuningParam(
        'sprintStageAllowed', 0.6, 0.2, 1.0, 'Factor on it on sprint stages'),
    TuningParam('attackRatePerKm', 0.15, 0.02, 0.5,
        'Base rate of attacks in the finale per kilometre'),
    TuningParam('attackEdgeGain', 20, 0, 60,
        'How much an edge in strength raises the will to attack'),
    TuningParam('followMargin', 0.012, 0.003, 0.03,
        'Deficit in strength up to which a rider follows an attack'),
    TuningParam('surgeEffort', 1.1, 1.02, 1.25, 'Effort in the surge'),
    TuningParam('finaleRefShare', 0.15, 0.03, 0.4,
        'Share of the group that is stronger than the pace-setter in the finale'),
    TuningParam('finaleEaseEffort', 0.95, 0.8, 1.0,
        'Effort of the front between hard sections'),
    TuningParam('chaseGroupEffort', 0.84, 0.7, 1.0,
        'Effort of larger chasing groups in the finale'),
    TuningParam('droppedEffort', 0.85, 0.7, 0.95, 'Effort of dropped groups'),
    TuningParam('draftSmall', 0.7, 0.6, 0.8,
        'Remaining air resistance in the slipstream, 2 to 4 riders'),
    TuningParam('draftMedium', 0.6, 0.5, 0.7, 'the same, 5 to 15 riders'),
    TuningParam('draftLarge', 0.5, 0.4, 0.6, 'the same, 16 to 60 riders'),
    TuningParam('draftPeloton', 0.42, 0.3, 0.5, 'the same, large peloton'),
    TuningParam('cobbleDraftLoss', 0.17, 0.05, 0.2,
        'Loss of slipstream per level of cobble difficulty'),
    TuningParam('cobbleSqueeze', 30, 10, 80,
        'Position from which a rider has the full disadvantage of the rear rows in a sector'),
    TuningParam('kickGain', 0.2, 0.0, 0.5,
        'Extra power on the final climb with a full short-term reserve'),
    TuningParam('sprintNoise', 2.5, 0.8, 5, 'Spread in the sprint, in points'),
    TuningParam('selectiveStageChase', 0.93, 0.8, 1.05,
        'Eagerness of the peloton to chase on stages that do not end in a sprint'),
    TuningParam('makeHardEffort', 0.9, 0.8, 1.0,
        'Effort of the helpers when a team makes the race hard early'),
    TuningParam('letGoFactor', 2.5, 1.0, 6.0,
        'How much more lead a harmless group gets on hard days'),
    TuningParam('easeEffort', 0.68, 0.5, 0.85,
        'Effort of the peloton while it lets a group go'),
    TuningParam('followChance', 0.66, 0.3, 0.8,
        'Base probability that a rider follows an attack'),
    TuningParam('gruppettoEffort', 0.7, 0.5, 0.9,
        'Effort of the gruppetto on mountain stages'),
    TuningParam('cobbleEffort', 1.0, 1.0, 1.2,
        'Effort of the front on cobbled sectors in the race'),
    TuningParam('cobbleMishap', 0.0, 0.0, 0.02,
        'Punctures and crashes per rider and kilometre of level 3 cobbles'),
    TuningParam('gruppettoCutShare', 0.7, 0.4, 0.95,
        'Share of the time limit from which the gruppetto sets a pace'),
    TuningParam('fightEffort', 0.95, 0.85, 1.02,
        'Effort of the peloton while the fight for the break is on'),
    TuningParam('breakStickRate', 0.06, 0.02, 0.25,
        'Chance per kilometre that a group gets away on hard days'),
    TuningParam('helperEmpty', 0.2, 0.05, 0.4,
        'Stamina reserve at which a helper can no longer lead'),
    TuningParam('positionCost', 0.08, 0.0, 0.2,
        'Extra effort in the fight for position before key points'),
    TuningParam('echelonSize', 20, 10, 35,
        'This many riders find shelter in an echelon'),
    TuningParam('echelonEffort', 1.0, 0.9, 1.1,
        'Effort of the team that forces the pace in the crosswind'),
    TuningParam('crashRate', 0.001, 0.0, 0.003,
        'Crashes per kilometre in a group of 50 riders'),
    TuningParam('punctureRate', 0.0002, 0.0, 0.001,
        'Punctures per rider and kilometre on tarmac'),
    TuningParam('longAttackRate', 0.03, 0.0, 0.15,
        'Attacks per kilometre on climbs before the finale'),
    TuningParam('flatAttackRate', 0.25, 0.0, 1.0,
        'Factor on the will to attack away from the climbs'),
    TuningParam('tttDraft', 0.7, 0.55, 0.85,
        'Remaining air resistance in the line of a team time trial'),
    TuningParam('sitUpEffort', 0.85, 0.7, 1.0,
        'Effort above which a rider with nothing to ride for lets the group go'),
    TuningParam('aimlessEffort', 0.72, 0.6, 0.88,
        'Effort of a group in which nobody races any more on a hard day'),
  ];

  /// Threshold power in W/kg at attribute 70.
  double get thresholdWkg => _a[0];

  /// Power gain per attribute point.
  double get gainPerPoint => _a[1];

  /// Spread of the daily form.
  double get dayFormSigma => _a[2];

  /// Share of the endurance reserve used per hour at threshold.
  double get energyPerHour => _a[3];

  /// Power loss with an empty endurance reserve.
  double get fatigueLoss => _a[4];

  /// Seconds until the short-term reserve is empty at 125 % of threshold.
  double get reserveDrainS => _a[5];

  /// Seconds until it refills at 70 % of threshold.
  double get reserveRefillS => _a[6];

  /// Effort of the pace-makers in a calm field.
  double get controlEffort => _a[7];

  /// Highest effort of the field in a chase.
  double get chaseEffort => _a[8];

  /// Effort of the breakaway.
  double get breakEffort => _a[9];

  /// Gap per remaining kilometre that the field tolerates.
  double get secondsPerKmAllowed => _a[10];

  /// Factor on that gap on sprint stages.
  double get sprintStageAllowed => _a[11];

  /// Base rate of attacks in the finale per kilometre.
  double get attackRatePerKm => _a[12];

  /// How much a strength advantage raises the urge to attack.
  double get attackEdgeGain => _a[13];

  /// Strength deficit up to which a rider follows an attack.
  double get followMargin => _a[14];

  /// Effort during an acceleration.
  double get surgeEffort => _a[15];

  /// Share of the group that is stronger than the pace-setter in the finale.
  double get finaleRefShare => _a[16];

  /// Effort of the front between hard sections.
  double get finaleEaseEffort => _a[17];

  /// Effort of larger chase groups in the finale.
  double get chaseGroupEffort => _a[18];

  /// Effort of dropped groups.
  double get droppedEffort => _a[19];

  /// Remaining drag in the slipstream, 2 to 4 riders.
  double get draftSmall => _a[20];

  /// Remaining drag in the slipstream, 5 to 15 riders.
  double get draftMedium => _a[21];

  /// Remaining drag in the slipstream, 16 to 60 riders.
  double get draftLarge => _a[22];

  /// Remaining drag in the slipstream of a large field.
  double get draftPeloton => _a[23];

  /// Loss of shelter per difficulty level of cobbles.
  double get cobbleDraftLoss => _a[24];

  /// Number of riders who get through a hard sector together.
  double get cobbleSqueeze => _a[25];

  /// Extra power on a finishing climb with a full short-term reserve.
  double get kickGain => _a[26];

  /// Spread in the sprint, in attribute points.
  double get sprintNoise => _a[27];

  /// Chasing zeal of the field on stages that do not end in a sprint.
  double get selectiveStageChase => _a[28];

  /// Effort of the helpers when a team makes the race hard early.
  double get makeHardEffort => _a[29];

  /// How much more gap a harmless group gets on hard days.
  double get letGoFactor => _a[30];

  /// Effort of the field while it lets a group go.
  double get easeEffort => _a[31];

  /// Base probability that a rider who is strong enough follows an attack.
  double get followChance => _a[32];

  /// Effort of the gruppetto on mountain stages.
  double get gruppettoEffort => _a[33];

  /// Share of the time limit from which the gruppetto rides hard to stay
  /// inside it.
  double get gruppettoCutShare => _a[36];

  /// Effort of the field while the break of the day is being fought for.
  double get fightEffort => _a[37];

  /// Chance per kilometre that a move sticks on a hard day.
  double get breakStickRate => _a[38];

  /// Endurance reserve below which a helper can no longer ride on the front.
  double get helperEmpty => _a[39];

  /// Extra effort of the fight for position before key points.
  double get positionCost => _a[40];

  /// Number of riders who find shelter in an echelon.
  double get echelonSize => _a[41];

  /// Effort of the team that splits the field in the crosswind.
  double get echelonEffort => _a[42];

  /// Crashes per kilometre in a group of 50 riders.
  double get crashRate => _a[43];

  /// Punctures per rider and kilometre on tarmac.
  double get punctureRate => _a[44];

  /// Attacks per kilometre on climbs before the finale.
  double get longAttackRate => _a[45];

  /// Factor on the urge to attack away from the climbs.
  double get flatAttackRate => _a[46];

  /// Remaining drag in the line of a team time trial.
  double get tttDraft => _a[47];

  /// Effort, relative to his threshold, above which a rider with nothing
  /// left to ride for lets the group go on a selective day.
  double get sitUpEffort => _a[48];

  /// Effort of a group in which nobody races any more on a hard day: it
  /// rolls to the finish.
  double get aimlessEffort => _a[49];

  /// Effort of the front on cobbled sectors while the race is on.
  double get cobbleEffort => _a[34];

  /// Chance per rider and kilometre of hard cobbles of a puncture or crash
  /// that costs him the wheel.
  double get cobbleMishap => _a[35];
}
