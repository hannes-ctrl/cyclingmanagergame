import 'dart:math';

import 'model.dart';
import 'physics.dart';
import 'tactics.dart';
import 'weather.dart';

/// Tyres a team chooses for a race day.
enum Tyres {
  /// Narrow and hard: the least rolling resistance on smooth roads, more
  /// punctures and more vibration on bad ones.
  narrow,

  /// What most teams ride on most days.
  standard,

  /// Wide at low pressure: rolls better over cobbles and gravel, punctures
  /// less there, and is a little slower on smooth tarmac.
  wide;

  /// Factor on the rolling resistance.
  ///
  /// @param rough Difficulty of the surface, 0 for tarmac.
  /// @param wet Whether the road is wet.
  /// @returns E.g. 0.92 for wide tyres on cobbles.
  double rolling(int rough, {bool wet = false}) => switch (this) {
        Tyres.narrow => rough > 0 ? 1.12 : 0.97,
        Tyres.standard => 1.0,
        Tyres.wide => rough > 0 ? 0.9 : (wet ? 1.0 : 1.02),
      };

  /// Factor on the rate of punctures.
  ///
  /// @param rough Difficulty of the surface, 0 for tarmac.
  /// @returns E.g. 0.65 for wide tyres on cobbles.
  double punctures(int rough) => switch (this) {
        Tyres.narrow => rough > 0 ? 1.45 : 1.1,
        Tyres.standard => 1.0,
        Tyres.wide => rough > 0 ? 0.65 : 0.92,
      };
}

/// What a team brings to a stage besides its riders: the material of its
/// suppliers, the choices of the day, the quality of its mechanics and
/// soigneurs, and the style its sports directors race in.
///
/// The defaults are an average team on average material; every effect is
/// measured against them, so a race without kits rides as before.
class TeamKit {
  const TeamKit({
    this.aero = 1,
    this.bikeKg = 0,
    this.rolling = 1,
    this.punctures = 1,
    this.tyres = Tyres.standard,
    this.timeTrialBike = true,
    this.mechanics = 0.5,
    this.physios = 0.5,
    this.style = TeamStyle.balanced,
  });

  /// Factor on the drag area from frame, wheels and clothing, about 0.98
  /// to 1.02.
  final double aero;

  /// Weight of the bike above or below the average, in kg.
  final double bikeKg;

  /// Factor on the rolling resistance of the tyre brand.
  final double rolling;

  /// Factor on the puncture rate of the tyre brand.
  final double punctures;

  /// Tyres chosen for the day.
  final Tyres tyres;

  /// Whether the team rides time trials on the time trial bike. On a hilly
  /// course the road bike can be faster: lighter, but less aerodynamic.
  final bool timeTrialBike;

  /// Quality of the mechanics, 0 to 1: a quick wheel change, fewer
  /// mechanical problems.
  final double mechanics;

  /// Quality of the soigneurs and physiotherapists, 0 to 1: recovery
  /// overnight in stage races.
  final double physios;

  /// How the team's sports directors like to race.
  final TeamStyle style;

  /// Neutral material and staff.
  static const average = TeamKit();

  /// @returns A copy with other choices of the day.
  TeamKit withChoices({Tyres? tyres, bool? timeTrialBike}) => TeamKit(
        aero: aero,
        bikeKg: bikeKg,
        rolling: rolling,
        punctures: punctures,
        tyres: tyres ?? this.tyres,
        timeTrialBike: timeTrialBike ?? this.timeTrialBike,
        mechanics: mechanics,
        physios: physios,
        style: style,
      );

  /// Factor on the time a rider loses with a puncture or a broken bike.
  double get serviceLoss => 1 - 0.6 * (mechanics - 0.5);

  /// Factor on the rate of mechanical problems.
  double get mechanicalRate => 1 - 0.3 * (mechanics - 0.5);

  /// Factor on the share of fatigue won back overnight.
  double get recovery => 1 + 0.25 * (physios - 0.5);

  /// @returns The kit as a compact list.
  List<Object> toJson() => [
        aero,
        bikeKg,
        rolling,
        punctures,
        tyres.index,
        timeTrialBike ? 1 : 0,
        mechanics,
        physios,
        style.index,
      ];

  /// @param j A list written by [toJson].
  /// @returns The kit.
  static TeamKit fromJson(List<dynamic> j) => TeamKit(
        aero: (j[0] as num).toDouble(),
        bikeKg: (j[1] as num).toDouble(),
        rolling: (j[2] as num).toDouble(),
        punctures: (j[3] as num).toDouble(),
        tyres: Tyres.values[j[4] as int],
        timeTrialBike: j[5] == 1,
        mechanics: (j[6] as num).toDouble(),
        physios: (j[7] as num).toDouble(),
        style: TeamStyle.values[j[8] as int],
      );
}

/// The tyres a sports director picks for a stage: wide where cobbles or
/// gravel matter, or on a wet day with descents; narrow for a short time
/// trial on dry roads; otherwise the standard tyre.
///
/// @param route The stage.
/// @param weather Its weather, or the forecast.
/// @returns The choice.
Tyres suggestTyres(SimRoute route, Weather weather) {
  var roughKm = 0.0, descentKm = 0.0;
  for (final s in route.segments) {
    if (s.rough > 0) roughKm += s.lengthM / 1000;
    if (s.grade < -0.05) descentKm += s.lengthM / 1000;
  }
  if (roughKm >= 3 || roughKm >= 0.02 * route.raceKm) return Tyres.wide;
  if (weather.rain && descentKm >= 10) return Tyres.wide;
  if (route.kind != StageKind.road && !weather.rain && route.raceKm < 30) {
    return Tyres.narrow;
  }
  return Tyres.standard;
}

/// Whether the time trial bike is faster than the road bike on a course:
/// both are ridden by an average rider at the same power, the faster one
/// wins. On a mountain time trial the lighter road bike comes out ahead.
///
/// @param route The time trial.
/// @returns true for the time trial bike.
bool suggestTimeTrialBike(SimRoute route) {
  const power = 330.0, rider = 68.0;
  double time(double cda, double bike) {
    var t = 0.0;
    for (final s in route.segments) {
      final v = speedFor(power, s.grade, cda, rollingResistance(s),
          mass: rider + bike, rho: airDensity(s.altitudeM));
      t += s.lengthM / max(1.0, v);
    }
    return t;
  }

  return time(timeTrialCda, bikeMassKg) <=
      time(roadBikeTimeTrialCda, bikeMassKg - timeTrialBikeExtraKg);
}

/// How much heavier a time trial bike is than a road bike, in kg. The bike
/// mass of the model is that of the time trial bike.
const timeTrialBikeExtraKg = 1.2;

/// Drag area on a road bike in a time trial, low on the drops.
const roadBikeTimeTrialCda = 0.255;
