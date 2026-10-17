import 'package:sim/sim.dart';

import 'career.dart';
import 'points.dart';

/// Prize money of the races, after the orders of magnitude the UCI sets
/// and the big organisers pay: a stage of the Tour pays its winner
/// 11,000 €, the Tour itself 500,000 €, a monument 30,000 €, a race of
/// class 2 1,500 €. The first twenty are paid, on a falling scale.
///
/// The WorldDB has prize tables for only a handful of races, so the game
/// uses these amounts for all of them.
class Prizes {
  /// Share of the winner's prize for places 1 to 20.
  static const shares = [
    1.0, 0.5, 0.25, 0.14, 0.11, 0.09, 0.07, 0.06, 0.05, 0.045, //
    0.04, 0.035, 0.03, 0.025, 0.02, 0.02, 0.015, 0.015, 0.01, 0.01,
  ];

  /// What the winner of a one-day race or a stage earns.
  ///
  /// @param race The race.
  /// @returns Euros.
  static double stageWinner(RaceEntry race) {
    if (!race.isStageRace) {
      return switch (race.tier) {
        RaceTier.monument => 30000,
        RaceTier.worldTour => 16000,
        RaceTier.proSeries => 6000,
        RaceTier.class1 => 3000,
        RaceTier.class2 || RaceTier.under23 => 1500,
        RaceTier.championship || RaceTier.grandTour => 0,
      };
    }
    return switch (race.tier) {
      RaceTier.grandTour => 11000,
      RaceTier.worldTour || RaceTier.monument => 5000,
      RaceTier.proSeries => 2500,
      RaceTier.class1 => 1500,
      RaceTier.class2 || RaceTier.under23 => 800,
      RaceTier.championship => 0,
    };
  }

  /// What the winner of the general classification of a stage race earns;
  /// the points, mountains and youth jerseys pay a twentieth of it to their
  /// winner.
  ///
  /// @param race The race.
  /// @returns Euros.
  static double overallWinner(RaceEntry race) {
    if (!race.isStageRace) return 0;
    if (race.tier == RaceTier.grandTour) {
      return switch (grandTourOf(race.info)) {
        GrandTour.tour => 500000,
        GrandTour.giro => 265000,
        _ => 150000,
      };
    }
    return switch (race.tier) {
      RaceTier.worldTour || RaceTier.monument => 16000,
      RaceTier.proSeries => 6000,
      RaceTier.class1 => 3000,
      RaceTier.class2 || RaceTier.under23 => 1500,
      _ => 0,
    };
  }

  /// @param winner Prize of the winner.
  /// @param place Zero-based place.
  /// @returns The prize for that place.
  static double forPlace(double winner, int place) =>
      place < shares.length ? winner * shares[place] : 0;

  /// Share of the prize money a team keeps. As in real cycling the riders
  /// share most of it among themselves and the staff; the team keeps a
  /// quarter for its books.
  static const teamShare = 0.25;

  /// What a team keeps of the prize money of a stage.
  ///
  /// @param p The race.
  /// @param result The stage just ridden.
  /// @param teamId The team.
  /// @returns Euros.
  static double kept(RaceProgress p, StageResult result, int teamId) =>
      earned(p, result, teamId) * teamShare;

  /// What a team earns on a stage: its riders' prizes, and when the race
  /// ends, those of the final classifications.
  ///
  /// @param p The race.
  /// @param result The stage just ridden.
  /// @param teamId The team.
  /// @returns Euros.
  static double earned(RaceProgress p, StageResult result, int teamId) {
    final race = p.race;
    var sum = 0.0;
    final stage = stageWinner(race);
    for (var i = 0; i < result.placings.length && i < shares.length; i++) {
      if (result.placings[i].rider.teamId == teamId) {
        sum += forPlace(stage, i);
      }
    }
    if (!p.finished || !race.isStageRace) return sum;
    final s = p.run.standings.last;
    final overall = overallWinner(race);
    for (var i = 0; i < s.general.length && i < shares.length; i++) {
      if (s.general[i].rider.teamId == teamId) sum += forPlace(overall, i);
    }
    // The other jerseys pay their first three.
    for (final table in [s.points, s.mountains]) {
      for (var i = 0; i < table.length && i < 3; i++) {
        if (table[i].rider.teamId == teamId) {
          sum += forPlace(overall / 20, i);
        }
      }
    }
    for (var i = 0; i < s.youth.length && i < 3; i++) {
      if (s.youth[i].rider.teamId == teamId) sum += forPlace(overall / 20, i);
    }
    for (var i = 0; i < s.teams.length && i < 3; i++) {
      if (s.teams[i].teamId == teamId) sum += forPlace(overall / 20, i);
    }
    return sum;
  }
}
