import 'package:flutter_test/flutter_test.dart';
import 'package:game/game.dart';
import 'package:radmanager/app_state.dart';
import 'package:sim/sim.dart';

void main() {
  final dataDir = AppState.findDataDir();

  test(
    'Tracks for the 3D view are kept only for the running race of the player',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 8)),
    () {
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
      final c = Career(world, teamId: team, seed: 4)
        ..delegation.lineups = true
        ..delegation.radio = RadioMode.off;
      c.planSeason(replace: true);
      final own = c.ownRaces
          .where(
            (r) =>
                r.tier != RaceTier.championship &&
                (c.program[r.info.id]?.length ?? 0) >= 1,
          )
          .toList();
      void rideFirstStage(RaceEntry race) {
        while (!((c.progress[race.info.id]?.stagesDone ?? 0) >= 1) &&
            c.today.isBefore(race.start.add(const Duration(days: 2)))) {
          c.advance();
        }
      }

      final first = own[0];
      rideFirstStage(first);
      expect(c.progress[first.info.id]!.run.results.first.track, isNotNull);
      // Races without the player's team keep none.
      for (final p in c.progress.values) {
        if (p.run.riders.any((r) => r.teamId == team)) continue;
        for (final r in p.run.results) {
          expect(r.track, isNull, reason: p.race.info.name);
        }
      }
      // The next race of the team drops the tracks of the last one.
      final second = own.firstWhere((r) => r.start.isAfter(first.end));
      rideFirstStage(second);
      expect(c.progress[second.info.id]!.run.results.first.track, isNotNull);
      expect(
        c.progress[first.info.id]!.run.results.every((r) => r.track == null),
        isTrue,
      );
    },
  );
}
