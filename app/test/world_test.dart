// Checks what keeps the world alive over the seasons: the other teams
// promote riders from their development teams, the intake brings a few
// exceptional talents, and prize money follows the size of the race.
import 'package:flutter_test/flutter_test.dart';
import 'package:game/game.dart';
import 'package:radmanager/app_state.dart';
import 'package:sim/sim.dart';

void main() {
  final dataDir = AppState.findDataDir();

  test(
    'Nachwuchs, Ausnahmetalente und Preisgeld',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 10)),
    () {
      I18n.lang = Lang.de;
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
      final c = Career(world, teamId: team, seed: 4);

      // A young rider of another team can be signed for the development
      // team.
      c.today = DateTime.utc(c.year, 8, 2);
      final young = c.economy.market().firstWhere(
        (r) =>
            c.economy.devReason(r) == null &&
            c.economy.contracts[r.id]!.nextTeam == null,
      );
      expect(c.economy.offerDev(young.id, 2), isNull);
      expect(c.economy.contracts[young.id]!.nextTeam, c.devTeam.teamId);
      final old = c.economy.market().firstWhere(
        (r) => c.year + 1 - r.born ~/ 10000 > Economy.devMaxAge,
      );
      expect(c.economy.offerDev(old.id, 1), isNotNull);

      // The market waves of the autumn: teams with a development team
      // promote from it.
      for (final month in [8, 9, 10, 11]) {
        c.today = DateTime.utc(c.year, month, 15);
        c.economy.daily(const []);
      }
      var promoted = 0;
      for (final e in c.devTeam.links.entries) {
        if (e.key == team) continue;
        for (final r in c.squads[e.value] ?? const <SimRider>[]) {
          if (c.economy.contracts[r.id]?.nextTeam == e.key) promoted++;
        }
      }
      expect(promoted, greaterThan(5));

      // The intake brings three exceptional talents.
      final before = {...c.riderById.keys};
      c.today = DateTime.utc(c.year + 1, 1, 1);
      c.startNextSeason();
      final intake = [
        for (final r in c.riderById.values)
          if (!before.contains(r.id)) r,
      ];
      expect(intake.length, greaterThanOrEqualTo(150));
      final stars = intake.where((r) => r.potential >= 6).toList();
      expect(stars.length, greaterThanOrEqualTo(3));
      final best = intake.map(Economy.rating).reduce((a, b) => a > b ? a : b);
      expect(best, greaterThan(70));

      // Prize money: a Tour stage pays more than a class 2 race, and the
      // Tour itself most.
      final tour = c.calendar.firstWhere(
        (r) => r.info.raceClass == 'CWTGTFrance',
      );
      final small = c.calendar.firstWhere(
        (r) => r.tier == RaceTier.class2 && !r.isStageRace,
      );
      expect(Prizes.stageWinner(tour), 11000);
      expect(Prizes.overallWinner(tour), 500000);
      expect(Prizes.stageWinner(small), lessThan(Prizes.stageWinner(tour)));
      expect(Prizes.forPlace(1000, 0), 1000);
      expect(Prizes.forPlace(1000, 25), 0);

      // Facilities: the stronger the team, the better they are at the start;
      // a level more is bought, built and then counts.
      final fac = c.facilities;
      final strongest = c.teams.values
          .where((t) => t.division.startsWith('[1]'))
          .reduce(
            (a, b) => c.teamStrength(a.id) >= c.teamStrength(b.id) ? a : b,
          );
      final weakest = c.teams.values
          .where((t) => t.division.startsWith('[3]'))
          .reduce(
            (a, b) => c.teamStrength(a.id) <= c.teamStrength(b.id) ? a : b,
          );
      expect(
        fac.level(strongest.id, Facility.training),
        greaterThan(fac.level(weakest.id, Facility.training)),
      );
      expect(
        fac.development(strongest.id),
        greaterThan(fac.development(weakest.id)),
      );
      final medical = fac.level(team, Facility.medical);
      if (medical < Facilities.maxLevel) {
        c.economy.balance = 1e8;
        expect(fac.upgrade(Facility.medical), isNull);
        expect(fac.upgrade(Facility.training), isNotNull); // one at a time
        c.today = fac.building!.ready;
        fac.daily();
        expect(fac.level(team, Facility.medical), medical + 1);
      }

      // The sports director gives climbing domestiques only where there is
      // something to climb.
      Set<Role> roles(String name) {
        final race = c.calendar.firstWhere((r) => r.info.name == name);
        final route = world.route(race.stages.first.id);
        final riders = [
          for (final t in c.teams.values)
            if (t.division.startsWith('[1]')) ...?c.squads[t.id]?.take(7),
        ];
        return {
          for (final p in autoPlans(route, riders).values) ...p.roles.values,
        };
      }

      expect(roles('Paris-Roubaix'), isNot(contains(Role.climbDomestique)));
      expect(roles('Liège-Bastogne-Liège'), contains(Role.climbDomestique));
    },
  );
}
