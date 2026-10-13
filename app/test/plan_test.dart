// Checks the season plan the sports director draws up: complete, without
// clashes, spread over the squad, and repaired when a rider drops out.
import 'package:flutter_test/flutter_test.dart';
import 'package:game/game.dart';
import 'package:radmanager/app_state.dart';
import 'package:sim/sim.dart';

void main() {
  final dataDir = AppState.findDataDir();

  test('Saisonplan des Sportlichen Leiters', skip: dataDir == null, () {
    final world = World('$dataDir/world.sqlite');
    addTearDown(world.close);
    final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
    final career = Career(world, teamId: team, seed: 5);
    expect(career.program, isEmpty);
    career.ensureProgram();
    final squad = career.squads[team]!;
    final races = [
      for (final r in career.ownRaces)
        if (r.tier != RaceTier.championship) r,
    ];

    // Every race is planned, with a full line-up and nobody twice.
    for (final race in races) {
      final riders = career.program[race.info.id];
      expect(riders, isNotNull, reason: race.info.name);
      expect(
        riders!.length,
        career.planner.sizeOf(race),
        reason: race.info.name,
      );
    }
    expect(career.programClashes(), isEmpty);
    // The sports director reports it.
    expect(
      career.inbox.map((m) => m.subject),
      contains(tr('Der Saisonplan steht')),
    );

    // Spread over the squad: nobody idle, nobody overloaded.
    final days = {for (final r in squad) r.id: 0};
    for (final race in races) {
      for (final id in career.program[race.info.id]!) {
        days[id] = days[id]! + race.stages.length;
      }
    }
    final sorted = days.values.toList()..sort();
    expect(sorted.first, greaterThan(20));
    expect(sorted.last, lessThanOrEqualTo(90));
    expect(sorted.last - sorted.first, lessThan(50));

    // The leaders are split over the Grand Tours, the best rider leads at
    // the Tour, and nobody under 22 rides a Grand Tour.
    final best = squad.reduce(
      (a, b) => Economy.rating(b) > Economy.rating(a) ? b : a,
    );
    final grandTours = races
        .where((r) => r.tier == RaceTier.grandTour)
        .toList();
    expect(grandTours.length, 3);
    final tour = grandTours.firstWhere(
      (r) => r.info.raceClass == 'CWTGTFrance',
    );
    expect(career.program[tour.info.id], contains(best.id));
    for (final race in grandTours) {
      for (final id in career.program[race.info.id]!) {
        final r = career.riderById[id]!;
        expect(career.year - r.born ~/ 10000, greaterThan(21));
      }
    }

    // The best rider drops out for the Tour: he is taken out and replaced.
    final before = career.program[tour.info.id]!.length;
    career.shapeOf(best.id).injuredUntil = tour.end;
    career.replaceInProgram(best, tour.end);
    expect(career.program[tour.info.id], isNot(contains(best.id)));
    expect(career.program[tour.info.id]!.length, before);
    expect(career.programClashes(), isEmpty);
    expect(career.inbox.last.subject, tr('Ersatz für {0}', [best.name]));

    // A plan made by hand is kept; planning anew replaces it.
    final first = races.firstWhere((r) => r.start.isAfter(career.today));
    career.program[first.info.id] = {squad.last.id};
    expect(career.planSeason(), 0);
    expect(career.program[first.info.id], {squad.last.id});
    expect(career.planSeason(replace: true), greaterThan(50));
    expect(career.program[first.info.id]!.length, career.planner.sizeOf(first));
  });
}
