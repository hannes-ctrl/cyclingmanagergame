// Checks the riders as people: personality, season goals that steer the
// plan, promises that are kept or broken, and morale.
import 'package:flutter_test/flutter_test.dart';
import 'package:game/game.dart';
import 'package:radmanager/app_state.dart';
import 'package:sim/sim.dart';

void main() {
  final dataDir = AppState.findDataDir();

  test(
    'Ziele, Versprechen und Moral',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 15)),
    () {
      I18n.lang = Lang.de;
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
      final career = Career(world, teamId: team, seed: 11)
        ..delegation.lineups = true
        ..delegation.radio = RadioMode.off;
      final people = career.people;
      final squad = career.squads[team]!;

      // Personality: fixed per rider and career, inside its range.
      for (final r in squad) {
        final a = people.of(r.id), b = People(career).of(r.id);
        expect(a.ambition, b.ambition);
        for (final v in [
          a.professionalism,
          a.ambition,
          a.loyalty,
          a.consistency,
        ]) {
          expect(v, inInclusiveRange(0, 1));
        }
        expect(people.growthFactor(r.id), inInclusiveRange(0.9, 1.1));
      }

      // Good, balanced and difficult characters all exist, under a name.
      final tones = {
        for (final r in career.riderById.values) people.of(r.id).tone,
      };
      expect(tones, {-1, 0, 1});
      expect(people.of(squad.first.id).label, isNotEmpty);

      // Standing in the team: the strongest leads, and a step down hurts.
      final top = squad.reduce(
        (a, b) => Economy.rating(b) > Economy.rating(a) ? b : a,
      );
      expect(people.roleOf(top.id).leads, isTrue);
      people.setRole(top.id, TeamRole.helper);
      expect(people.moraleOf(top.id), lessThan(0));
      people.teamRoles.remove(top.id);
      people.morale.remove(top.id);

      // The season plan gives the riders goals, and only races they ride.
      career.ensureProgram();
      final best = squad.reduce(
        (a, b) => Economy.rating(b) > Economy.rating(a) ? b : a,
      );
      expect(people.goals[best.id], isNotEmpty);
      for (final e in people.goals.entries) {
        if (career.riderById[e.key]?.teamId != team) continue;
        expect(e.value.length, lessThanOrEqualTo(People.maxGoals));
        for (final raceId in e.value) {
          expect(career.program[raceId], contains(e.key));
        }
      }
      // The riders of the other teams have goals too.
      expect(
        people.goals.keys.where((id) => career.riderById[id]?.teamId != team),
        isNotEmpty,
      );
      // A goal race lifts the form, the others cost a little.
      final goal = people.goals[best.id]!.first;
      final other = career.ownRaces
          .firstWhere((r) => !people.goals[best.id]!.contains(r.info.id))
          .info
          .id;
      expect(people.formFactor(best, goal), greaterThan(1.0));
      expect(people.formFactor(best, other), lessThan(1.012));

      // A goal set by the player puts the rider into the race and survives
      // a new plan; a fourth goal is refused.
      final races = [
        for (final r in career.ownRaces)
          if (r.tier != RaceTier.championship && r.start.month >= 6) r,
      ];
      final quiet = squad.firstWhere(
        (r) => !(career.program[races.first.info.id]?.contains(r.id) ?? false),
      );
      people.goals.remove(quiet.id);
      expect(people.toggleGoal(quiet.id, races.first.info.id), isNull);
      expect(career.program[races.first.info.id], contains(quiet.id));
      career.planSeason(replace: true);
      expect(career.program[races.first.info.id], contains(quiet.id));
      expect(people.goals[quiet.id], {races.first.info.id});
      people.goals[quiet.id]!.addAll([-1, -2]);
      expect(people.toggleGoal(quiet.id, races[1].info.id), isNotNull);
      people.goals[quiet.id]!.removeAll([-1, -2]);

      // Two promises for the first race of the team: a start for a rider
      // who is planned, a leading role for the least suited of its riders.
      final first = career.ownRaces.firstWhere(
        (r) =>
            r.tier != RaceTier.championship &&
            (career.program[r.info.id]?.length ?? 0) >= 4,
      );
      final planned =
          [
            for (final id in career.program[first.info.id]!)
              career.riderById[id]!,
          ]..sort(
            (a, b) => career.planner
                .fit(first, b)
                .compareTo(career.planner.fit(first, a)),
          );
      final starter = planned[1], helper = planned.last;
      expect(
        people.promise(starter.id, first.info.id, PromiseKind.start),
        isNull,
      );
      expect(
        people.promise(helper.id, first.info.id, PromiseKind.leader),
        isNull,
      );
      // One promise per rider and season.
      expect(
        people.promise(starter.id, first.info.id, PromiseKind.leader),
        isNotNull,
      );
      expect(people.moraleOf(starter.id), greaterThan(0));
      final before = people.moraleOf(helper.id);
      // A third rider holds a promise but is out on race day: it lapses
      // without harm.
      final sick = planned[2];
      people.promises.add(
        RiderPromise(sick.id, first.info.id, PromiseKind.start, career.year),
      );
      people.morale.remove(sick.id);
      career.shapeOf(sick.id).injuredUntil = first.start.add(
        const Duration(days: 30),
      );

      while (!(career.progress[first.info.id]?.stagesDone == 1) &&
          career.today.isBefore(first.start.add(const Duration(days: 2)))) {
        career.advance();
      }
      expect(career.progress[first.info.id]?.stagesDone, greaterThan(0));
      expect(people.promises.where((p) => p.raceId == first.info.id), isEmpty);
      final started = career.progress[first.info.id]!.riders;
      expect(started.any((r) => r.id == sick.id), isFalse);
      expect(people.moraleOf(sick.id), 0);
      expect(
        people.notes[sick.id]!.map((n) => n[0]),
        contains(
          tr('Versprechen entfällt, er ist nicht fit: {0}', [first.info.name]),
        ),
      );
      if (started.any((r) => r.id == starter.id)) {
        expect(
          people.notes[starter.id]!.map((n) => n[0]),
          contains(tr('Versprechen gehalten: {0}', [first.info.name])),
        );
      }
      final role = started.any((r) => r.id == helper.id)
          ? career.planUsed(first.info.id, 0).roleOf(helper.id)
          : null;
      if (role != Role.leader &&
          role != Role.coLeader &&
          role != Role.sprinter) {
        expect(people.moraleOf(helper.id), lessThan(before));
        expect(
          career.inbox.map((m) => m.subject),
          contains(tr('{0} fühlt sich getäuscht', [helper.name])),
        );
      }

      // The other teams have a morale too: somebody has won by now.
      expect(
        people.morale.keys.where((id) => career.riderById[id]?.teamId != team),
        isNotEmpty,
      );

      // A promise made in contract talks counts for the next season.
      people.promiseSeason(best.id, PromiseKind.leader);
      expect(people.promiseOf(best.id, career.year + 1)?.raceId, 0);

      // An unhappy rider asks more to renew than a content one.
      people.morale[best.id] = -1.5;
      final sour = career.economy.demand(best);
      people.morale[best.id] = 1.5;
      expect(career.economy.demand(best), lessThan(sour));
    },
  );
}
