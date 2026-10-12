import 'package:sim/sim.dart';

/// How a rider fared in the trial runs.
class ForecastRow {
  ForecastRow(this.rider);
  final SimRider rider;
  int wins = 0;
  int podiums = 0;
  int topTen = 0;
  int best = 1 << 20;
  double _sum = 0;
  int _runs = 0;

  /// Mean place over all runs.
  double get meanRank => _runs == 0 ? 999 : _sum / _runs;
}

/// Pre-race forecast from a few quick runs.
class Forecast {
  Forecast(this.runs, this.rows);
  final int runs;

  /// Sorted by mean place, best first.
  final List<ForecastRow> rows;
}

/// Simulates a race several times with different randomness than the race
/// that counts later, and tallies who finishes at the front. For stage
/// races the general classification counts.
///
/// Form, fatigue and the sports directors are left out; the forecast shows
/// what the riders' attributes and the route suggest.
///
/// @param routes Stages of the race.
/// @param riders Start list.
/// @param plans Tactics of teams that do not follow the automatic plan.
/// @param tuning Tuning values.
/// @param runs Number of runs.
/// @param seed Base seed; must differ from the seed of the real race.
/// @returns The tally.
Forecast forecastRace(
  List<SimRoute> routes,
  List<SimRider> riders, {
  Map<int, TeamPlan> plans = const {},
  SimTuning? tuning,
  int runs = 6,
  int seed = 1,
}) {
  final rows = {for (final r in riders) r.id: ForecastRow(r)};
  for (var k = 0; k < runs; k++) {
    final result = simulateStageRace(
      routes,
      riders,
      seed: seed * 7907 + k * 104723 + 13,
      plansFor: (_) => plans,
      tuning: tuning,
    );
    final order = routes.length > 1
        ? [for (final e in result.gc) e.rider.id]
        : [for (final p in result.stages.first.placings) p.rider.id];
    for (var i = 0; i < order.length; i++) {
      final row = rows[order[i]]!;
      if (i == 0) row.wins++;
      if (i < 3) row.podiums++;
      if (i < 10) row.topTen++;
      if (i + 1 < row.best) row.best = i + 1;
      row
        .._sum += i + 1
        .._runs += 1;
    }
  }
  return Forecast(
    runs,
    rows.values.toList()..sort((a, b) => a.meanRank.compareTo(b.meanRank)),
  );
}
