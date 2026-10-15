import 'package:sim/sim.dart';

import 'career.dart';

/// A race on its own, outside the season: the field as the season would
/// send it, fresh riders, average sports directors, and the same
/// simulation as in the career. The player leads one team; the others race
/// as every team does. Nothing of it reaches a career.
class SingleRace {
  /// Prepares the race.
  ///
  /// @param career A career that only serves this race; its team is the
  ///   player's team here.
  /// @param race The race.
  /// @param seed Seed of the race; the same seed gives the same race.
  /// @param wish What the player sets for his team; the sports director
  ///   plans the rest stage by stage.
  /// @param lineup The player's riders; null takes the sports director's
  ///   suggestion.
  SingleRace(this.career, this.race,
      {required this.seed,
      this.wish = const PlanWish(),
      List<SimRider>? lineup}) {
    final pending = career.prepareSingle(race);
    routes = pending.routes;
    riders = [...pending.others, ...(lineup ?? pending.suggestedLineup)];
    run = StageRaceRun(riders,
        seed: seed,
        year: career.year,
        tuning: career.tuning,
        scheme: career.world.scheme(race.info.id),
        oneDay: !race.isStageRace,
        month: race.start.month,
        country: race.info.country);
  }

  final Career career;
  final RaceEntry race;
  final int seed;
  final PlanWish wish;
  late final List<SimRoute> routes;
  late final List<SimRider> riders;
  late final StageRaceRun run;

  /// Stages ridden so far.
  int get stagesDone => run.results.length;

  /// Whether every stage has been ridden.
  bool get finished => stagesDone >= routes.length;

  /// The next stage as a job, to be run here or on another isolate.
  ///
  /// @returns The job.
  StageJob nextJob() {
    final route = routes[stagesDone];
    final team = career.teamId;
    final weather = run.nextWeather;
    final kits = {
      for (final t in {for (final r in run.riders) r.teamId})
        t: career.kitFor(t, race.info.id, route, weather),
    };
    final plans = <int, TeamPlan>{};
    if (!wish.isEmpty && run.riders.any((r) => r.teamId == team)) {
      final auto = autoPlans(route, run.riders,
          gcGaps: run.gcGaps,
          styles: {for (final e in kits.entries) e.key: e.value.style});
      final own = auto[team];
      if (own != null) {
        plans[team] = wish.applyTo(own, route, {
          for (final r in run.riders)
            if (r.teamId == team) r.id,
        });
      }
    }
    return run.begin(route, plans: plans, kits: kits);
  }

  /// Takes the result of a job into the race, with a rest day if the next
  /// stage is not on the following day.
  ///
  /// @param job The job from [nextJob].
  /// @param result Its result.
  /// @returns The stage result.
  StageResult take(StageJob job, StageResult result) {
    final done = run.finish(job, result);
    final i = stagesDone;
    if (i < race.stages.length) {
      final before = race.stages[i - 1], next = race.stages[i];
      final gap = DateTime.utc(career.year, next.month, next.day)
          .difference(DateTime.utc(career.year, before.month, before.day))
          .inDays;
      if (gap > 1) {
        run.restDay({
          for (final t in {for (final r in run.riders) r.teamId})
            t: TeamKit(physios: career.recoveryQuality(t)),
        });
      }
    }
    return done;
  }
}
