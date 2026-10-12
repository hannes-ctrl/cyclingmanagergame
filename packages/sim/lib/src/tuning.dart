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
    return SimTuning({
      for (final e in values.entries)
        if (e.value is num) e.key: (e.value as num).toDouble(),
    });
  }

  /// Values in the order of [params].
  final List<double> _a;

  /// @returns All values by parameter name.
  Map<String, double> toMap() => {
        for (var i = 0; i < params.length; i++) params[i].name: _a[i],
      };

  static const params = <TuningParam>[
    TuningParam('thresholdWkg', 5.3, 4.8, 6.6,
        'Schwellenleistung in W/kg bei Fahrerwert 70'),
    TuningParam('gainPerPoint', 0.013, 0.006, 0.02,
        'Leistungszuwachs je Punkt Fahrerwert'),
    TuningParam('dayFormSigma', 0.012, 0.004, 0.03, 'Streuung der Tagesform'),
    TuningParam('energyPerHour', 0.2, 0.08, 0.35,
        'Verbrauch der Ausdauerreserve je Stunde an der Schwelle'),
    TuningParam('fatigueLoss', 0.18, 0.05, 0.35,
        'Leistungsverlust bei leerer Ausdauerreserve'),
    TuningParam('reserveDrainS', 240, 45, 480,
        'Sekunden bis die Kurzzeitreserve bei 125 % Schwelle leer ist'),
    TuningParam('reserveRefillS', 600, 200, 1500,
        'Sekunden bis sie sich bei 70 % Schwelle füllt'),
    TuningParam('controlEffort', 0.76, 0.6, 0.96,
        'Anstrengung der Tempomacher im ruhigen Feld'),
    TuningParam('chaseEffort', 0.95, 0.85, 1.05,
        'Höchste Anstrengung des Feldes bei der Verfolgung'),
    TuningParam('breakEffort', 0.9, 0.8, 0.98, 'Anstrengung der Ausreißer'),
    TuningParam('secondsPerKmAllowed', 6, 2, 12,
        'Vorsprung je Restkilometer, den das Feld zulässt'),
    TuningParam(
        'sprintStageAllowed', 0.6, 0.2, 1.0, 'Faktor darauf an Sprintetappen'),
    TuningParam('attackRatePerKm', 0.15, 0.02, 0.5,
        'Grundrate für Angriffe im Finale je Kilometer'),
    TuningParam('attackEdgeGain', 20, 0, 60,
        'Wie stark ein Kraftvorsprung die Angriffslust erhöht'),
    TuningParam('followMargin', 0.012, 0.003, 0.03,
        'Kraftrückstand, bis zu dem ein Fahrer einem Angriff folgt'),
    TuningParam('surgeEffort', 1.1, 1.02, 1.25, 'Anstrengung im Antritt'),
    TuningParam('finaleRefShare', 0.15, 0.03, 0.4,
        'Welcher Anteil der Gruppe im Finale stärker ist als der Taktgeber'),
    TuningParam('finaleEaseEffort', 0.95, 0.8, 1.0,
        'Anstrengung der Spitze zwischen schweren Stellen'),
    TuningParam('chaseGroupEffort', 0.84, 0.7, 1.0,
        'Anstrengung größerer Verfolgergruppen im Finale'),
    TuningParam(
        'droppedEffort', 0.85, 0.7, 0.95, 'Anstrengung abgehängter Gruppen'),
    TuningParam('draftSmall', 0.72, 0.6, 0.9,
        'Restlicher Luftwiderstand im Windschatten, 2 bis 4 Fahrer'),
    TuningParam('draftMedium', 0.62, 0.5, 0.8, 'dito, 5 bis 15 Fahrer'),
    TuningParam('draftLarge', 0.55, 0.42, 0.7, 'dito, 16 bis 60 Fahrer'),
    TuningParam('draftPeloton', 0.5, 0.3, 0.65, 'dito, großes Feld'),
    TuningParam('cobbleDraftLoss', 0.17, 0.05, 0.2,
        'Verlust an Windschatten je Schwierigkeitsstufe Pflaster'),
    TuningParam('cobbleSqueeze', 30, 10, 80,
        'So viele Fahrer kommen geschlossen durch einen schweren Sektor'),
    TuningParam('kickGain', 0.2, 0.0, 0.5,
        'Mehrleistung im Schlussanstieg bei voller Kurzzeitreserve'),
    TuningParam('sprintNoise', 2.5, 0.8, 5, 'Streuung im Sprint in Punkten'),
    TuningParam('selectiveStageChase', 0.93, 0.8, 1.05,
        'Jagdeifer des Feldes an Etappen, die nicht im Sprint enden'),
    TuningParam('makeHardEffort', 0.9, 0.8, 1.0,
        'Anstrengung der Helfer, wenn ein Team das Rennen früh schwer macht'),
    TuningParam('letGoFactor', 2.5, 1.0, 6.0,
        'Wie viel mehr Vorsprung eine ungefährliche Gruppe an schweren Tagen bekommt'),
    TuningParam('easeEffort', 0.68, 0.5, 0.85,
        'Anstrengung des Feldes, solange es eine Gruppe ziehen lässt'),
    TuningParam('followChance', 0.66, 0.3, 0.8,
        'Grundwahrscheinlichkeit, dass ein Fahrer einem Angriff folgt'),
    TuningParam('gruppettoEffort', 0.7, 0.5, 0.9,
        'Anstrengung des Gruppettos an Bergetappen'),
    TuningParam('cobbleEffort', 1.0, 1.0, 1.2,
        'Anstrengung der Spitze auf Pflastersektoren im Rennen'),
    TuningParam('cobbleMishap', 0.0, 0.0, 0.02,
        'Defekt oder Sturz je Fahrer und Kilometer schweren Pflasters'),
    TuningParam('gruppettoLimit', 0.1, 0.05, 0.2,
        'Rückstand als Anteil der Fahrzeit, ab dem das Gruppetto Tempo macht'),
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

  /// Gap, as a share of the riding time, from which the gruppetto rides hard
  /// to stay inside the time limit.
  double get gruppettoLimit => _a[36];

  /// Effort of the front on cobbled sectors while the race is on.
  double get cobbleEffort => _a[34];

  /// Chance per rider and kilometre of hard cobbles of a puncture or crash
  /// that costs him the wheel.
  double get cobbleMishap => _a[35];
}
