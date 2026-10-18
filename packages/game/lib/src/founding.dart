import 'dart:math';

import 'package:sim/sim.dart';

/// Rules for a newly founded team: the licence depends on how strong the
/// chosen squad is compared with the existing teams.
class FoundingRules {
  /// Measures the existing teams.
  ///
  /// @param teams All teams of the world database.
  /// @param riders All riders with their current team.
  FoundingRules(List<TeamInfo> teams, List<SimRider> riders) {
    final squads = <int, List<SimRider>>{};
    for (final r in riders) {
      squads.putIfAbsent(r.teamId, () => []).add(r);
    }
    double weakest(String prefix) => teams
        .where((t) => t.division.startsWith(prefix))
        .map((t) => strength(squads[t.id] ?? const []))
        .where((s) => s > 0)
        .fold(double.infinity, min);
    worldTour = weakest('[1]');
    pro = weakest('[2]');
  }

  static const minRiders = 16, maxRiders = 30;

  /// Fewest riders a WorldTeam and a ProTeam must have, as in the UCI rules.
  static const minWorldTour = 27, minPro = 20;

  /// @param division A WorldDB division string.
  /// @returns The fewest riders a team of that division must have.
  static int minFor(String division) => division.startsWith('[1]')
      ? minWorldTour
      : division.startsWith('[2]')
          ? minPro
          : minRiders;

  /// @param division A WorldDB division string.
  /// @returns The fewest and the most riders a founded team of that
  ///   division may have.
  static (int, int) rangeFor(String division) => (minFor(division), maxRiders);

  /// Strength of the weakest WorldTeam and of the weakest ProTeam.
  late final double worldTour, pro;

  /// Mean of the eight best riders, each with his highest main attribute. The
  /// same number organisers use to judge teams.
  ///
  /// @param squad Riders of a team.
  /// @returns The strength, 0 for an empty squad.
  static double strength(Iterable<SimRider> squad) {
    final best = [
      for (final r in squad)
        [
          r.attributes.flat,
          r.attributes.mountain,
          r.attributes.hill,
          r.attributes.timeTrial,
          r.attributes.sprint,
          r.attributes.cobble,
        ].reduce(max),
    ]..sort((a, b) => b.compareTo(a));
    if (best.isEmpty) return 0;
    final top = best.take(8);
    return top.reduce((a, b) => a + b) / top.length;
  }

  /// @param squad A chosen squad.
  /// @returns The WorldDB division a squad of that strength belongs in:
  ///   the strength of its eight best riders decides; the licence then sets
  ///   how many riders the squad needs ([rangeFor]).
  String divisionFor(Iterable<SimRider> squad) {
    final s = strength(squad);
    return s >= worldTour
        ? '[1] World Tour'
        : s >= pro
            ? '[2] Pro Tour'
            : '[3] Continental Tour';
  }

  /// @param division A WorldDB division string.
  /// @returns The licence name shown to the player.
  static String label(String division) => division.startsWith('[1]')
      ? 'WorldTeam'
      : division.startsWith('[2]')
          ? 'ProTeam'
          : tr('Continental team');
}
