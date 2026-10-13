import 'tactics.dart';

/// State of the race at one kilometre, for the chart of the race report.
class RaceSample {
  RaceSample(
      this.km, this.frontGapS, this.frontSize, this.mainSize, this.lastGapS);

  /// Race kilometre.
  final double km;

  /// Seconds the head of the race is ahead of the favourites' group; 0 if
  /// the favourites lead.
  final double frontGapS;

  /// Riders at the head of the race.
  final int frontSize;

  /// Riders in the favourites' group.
  final int mainSize;

  /// Seconds the rider in the middle of the field is behind the favourites;
  /// 0 while he rides with them or ahead of them.
  final double lastGapS;

  /// @returns The sample as a compact list.
  List<Object> toJson() => [km, frontGapS, frontSize, mainSize, lastGapS];

  /// @param j A list written by [toJson].
  /// @returns The sample.
  static RaceSample fromJson(List<dynamic> j) => RaceSample(
      (j[0] as num).toDouble(),
      (j[1] as num).toDouble(),
      j[2] as int,
      j[3] as int,
      (j[4] as num).toDouble());
}

/// What one rider did during a stage, for the race report.
class RiderTrace {
  RiderTrace(this.role, this.inBreak, this.lostKm, this.frontKm, this.energy,
      this.gruppetto,
      [this.incident = RiderIncident.none]);

  /// His role in the team's plan.
  final Role role;

  /// Whether he was in the break of the day.
  final bool inBreak;

  /// Kilometre at which he lost contact with the favourites' group for good;
  /// null if he finished in it or ahead of it.
  final double? lostKm;

  /// Kilometres he spent setting the pace.
  final double frontKm;

  /// Endurance reserve left at the finish, 0 to 1.
  final double energy;

  /// Whether he finished in the gruppetto.
  final bool gruppetto;

  /// Worst mishap of his day.
  final RiderIncident incident;

  /// @returns The trace as a compact list.
  List<Object?> toJson() =>
      [role.index, inBreak, lostKm, frontKm, energy, gruppetto, incident.index];

  /// @param j A list written by [toJson].
  /// @returns The trace.
  static RiderTrace fromJson(List<dynamic> j) => RiderTrace(
      Role.values[j[0] as int],
      j[1] as bool,
      (j[2] as num?)?.toDouble(),
      (j[3] as num).toDouble(),
      (j[4] as num).toDouble(),
      j[5] as bool,
      j.length > 6 ? RiderIncident.values[j[6] as int] : RiderIncident.none);
}

/// Mishaps a rider can have during a stage, mildest first.
enum RiderIncident { none, puncture, crash }
