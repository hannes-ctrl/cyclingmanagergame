// Checks what keeps the world alive over the seasons: the other teams
// promote riders from their development teams, the intake is as strong as
// a real year, prize money follows the size of the race, and the winter has
// its own business.
import 'package:flutter_test/flutter_test.dart';
import 'package:game/game.dart';
import 'package:radmanager/app_state.dart';
import 'package:sim/sim.dart';

void main() {
  final dataDir = AppState.findDataDir();

  test(
    'Nachwuchs und Preisgeld',
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

      // The intake is as strong as a real year of young riders: the 30th
      // best of the 19-year-olds in the WorldDB rates 68.4.
      final before = {...c.riderById.keys};
      c.today = DateTime.utc(c.year + 1, 1, 1);
      c.startNextSeason();
      final intake = [
        for (final r in c.riderById.values)
          if (!before.contains(r.id)) r,
      ];
      expect(intake.length, greaterThanOrEqualTo(150));
      final ratings = intake.map(Economy.rating).toList()
        ..sort((a, b) => b.compareTo(a));
      expect(ratings.first, greaterThan(70));
      expect(ratings[29], inInclusiveRange(65.5, 70.5));

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
  test(
    'Winter: Nachwuchs im November, vereinslose Fahrer, Winterlager',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 10)),
    () {
      I18n.lang = Lang.de;
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
      final c = Career(world, teamId: team, seed: 4)
        ..delegation.lineups = true
        ..delegation.radio = RadioMode.off;
      final eco = c.economy;

      // A rider without a team signs in March and rides at once.
      c.today = DateTime.utc(c.year, 3, 2);
      final free =
          c.riderById.values
              .where(
                (r) =>
                    eco.isFreeAgent(r) && !eco.retiring(r) && eco.expiring(r),
              )
              .toList()
            ..sort((a, b) => eco.demand(a).compareTo(eco.demand(b)));
      expect(
        eco.offer(free.first.id, eco.demand(free.first) - 10000, 2),
        isNotNull,
      );
      // Room in the squad: one rider leaves first.
      final freeTeam = c.teams.values.firstWhere((t) => t.division == 'Free');
      eco.move(c.squads[team]!.last, freeTeam.id);
      final before = c.squads[team]!.length;
      eco.contracts[free.first.id]!.refusedUntil = null;
      expect(eco.offer(free.first.id, eco.demand(free.first), 2), isNull);
      expect(c.riderById[free.first.id]!.teamId, team);
      expect(c.squads[team]!.length, before + 1);
      expect(eco.contracts[free.first.id]!.endYear, c.year + 1);
      for (var i = 0; i < 3; i++) {
        c.advance();
      }

      // On 1 November the young riders arrive; the academy's talents sign
      // for next season.
      final known = {...c.riderById.keys};
      c.today = DateTime.utc(c.year, 11, 1);
      eco.daily(const []);
      final young = [
        for (final r in c.riderById.values)
          if (!known.contains(r.id)) r,
      ];
      expect(young.length, 150);
      expect(young.every(eco.isFreeAgent), isTrue);
      expect(young.where(eco.expiring).length, greaterThanOrEqualTo(146));
      final dev = c.devTeam.teamId;
      if (dev != null) {
        expect(
          young.where((r) => eco.contracts[r.id]!.nextTeam == dev),
          isNotEmpty,
        );
      }

      // Camps can now be booked for January, not for March.
      final squad = [for (final r in c.squads[team]!.take(4)) r.id];
      eco.balance = 1e7;
      expect(
        c.camps.book(CampType.base, DateTime.utc(c.year + 1, 3, 1), 7, squad),
        isNotNull,
      );
      expect(
        c.camps.book(CampType.base, DateTime.utc(c.year, 12, 28), 14, squad),
        isNull,
      );

      // The season turns: no second intake, the camp runs on into January.
      c.today = DateTime.utc(c.year + 1, 1, 1);
      final count = c.riderById.length;
      c.startNextSeason();
      expect(c.riderById.length, lessThan(count));
      expect(c.camps.all.where((k) => !k.closed), hasLength(1));
      c.today = DateTime.utc(c.year, 1, 11);
      c.camps.daily();
      expect(c.camps.all.single.closed, isTrue);
    },
  );
  test(
    'Scouting in Stufen, Mentoren, Vorlagen, Angebote und Sponsorwünsche',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 10)),
    () {
      I18n.lang = Lang.de;
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
      final c = Career(world, teamId: team, seed: 4)
        ..delegation.lineups = true
        ..delegation.radio = RadioMode.off;
      final book = c.staff;
      final eco = c.economy;

      // Scouting in stages: a rider of a small team becomes known step by
      // step, from a first impression to the test at the base.
      final unknown = c.riderById.values.firstWhere(
        (r) =>
            c.teams[r.teamId]?.division.startsWith('[3]') == true &&
            book.knowledge(r.id) < 0.5,
      );
      final k0 = book.knowledge(unknown.id);
      expect(book.test(unknown.id), isNotNull); // no report yet
      for (final stage in [1, 2]) {
        expect(book.scout(unknown.id), isNull);
        final job = book.jobs.single;
        expect(job.stage, stage);
        c.today = job.until;
        book.daily();
        expect(book.stageOf(unknown.id), stage);
      }
      expect(book.knowledge(unknown.id), greaterThan(k0 + 0.3));
      eco.balance = 1e7;
      expect(book.test(unknown.id), isNull);
      c.today = book.jobs.single.until;
      book.daily();
      expect(book.knowledge(unknown.id), 1);

      // An assignment brings first impressions of riders who fit it.
      final scout = book.idleScouts.first;
      expect(book.assign(scout.id, null, 23, 'mountain'), isNull);
      expect(book.idleScouts.contains(scout), isFalse);
      final before = book.reports.length;
      c.today = book.assignments.single.next;
      book.daily();
      expect(book.reports.length, greaterThan(before));
      expect(book.recall(scout.id), isNull);

      // Mentoring: an older rider looks after a young one, who develops a
      // little faster and takes on some of his professionalism.
      final squad = c.squads[team]!;
      final mentor = squad.firstWhere(
        (r) => c.people.mentorReason(r.id) == null,
      );
      final young = squad.firstWhere(
        (r) => c.year - r.born ~/ 10000 <= People.menteeAge,
      );
      expect(c.people.setMentor(young.id, mentor.id), isNull);
      expect(c.people.mentorOf(young.id), mentor.id);
      expect(c.people.mentorFactor(young.id), greaterThan(1));
      expect(c.people.setMentor(mentor.id, young.id), isNotNull);
      // The other teams have mentors too.
      expect(
        c.people.mentors.values.where((m) => c.riderById[m]?.teamId != team),
        isNotEmpty,
      );

      // Programme templates: built-in ones follow the calendar, own ones
      // keep the races.
      final rider = squad.first;
      final added = c.applyTemplate('Cobbled classics', rider.id);
      expect(added, greaterThan(0));
      expect(c.saveTemplate('Mine', rider.id), isNull);
      expect(c.templates.where((t) => !t.builtIn), hasLength(1));
      c.programWarnings();

      // Sponsors wish for something the races can bring.
      expect(eco.wishes, hasLength(eco.sponsors.length));

      // Competing offers: a rider of another team answers after a week,
      // for the player or for a rival.
      c.today = DateTime.utc(c.year, 8, 2);
      final limit = c.finances.wageLimit(team);
      final target =
          (eco
                  .market()
                  .where(
                    (r) =>
                        !eco.isFreeAgent(r) &&
                        eco.demand(r) * 1.1 +
                                eco.wageBill(team, nextSeason: true) <
                            limit,
                  )
                  .toList()
                ..sort((a, b) => eco.demand(b).compareTo(eco.demand(a))))
              .first;
      expect(
        eco.offer(target.id, (eco.demand(target) * 1.1).round(), 2),
        isNull,
      );
      expect(eco.pending.containsKey(target.id), isTrue);
      expect(eco.offer(target.id, eco.demand(target) * 2, 2), isNotNull);
      c.today = eco.pending[target.id]!.until;
      eco.daily(const []);
      expect(eco.pending, isEmpty);
      expect(eco.contracts[target.id]!.nextTeam, isNotNull);

      // Own riders can be renewed before August, with a running contract.
      c.today = DateTime.utc(c.year, 3, 1);
      final running = squad.firstWhere(
        (r) =>
            eco.contracts[r.id]!.endYear > c.year &&
            eco.contracts[r.id]!.nextTeam == null,
      );
      eco.contracts[running.id]!.refusedUntil = null;
      expect(eco.offer(running.id, eco.demand(running) + 100000, 3), isNull);
      expect(eco.contracts[running.id]!.nextTeam, team);
    },
  );
  test(
    'Gespräche im Postfach, Wechselwunsch und Eingewöhnung',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 10)),
    () {
      I18n.lang = Lang.de;
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
      final c = Career(world, teamId: team, seed: 4);
      final people = c.people;

      // A miserable, ambitious rider with a running contract asks to leave.
      final r = c.squads[team]!.firstWhere(
        (x) =>
            people.of(x.id).ambition >= 0.5 &&
            c.economy.contracts[x.id]!.endYear > c.year,
      );
      people.morale[r.id] = -2;
      people.weekly();
      final talk = c.inbox.last.talk;
      expect(talk?.kind, 'leave');
      expect(talk?.riderId, r.id);
      expect(talk!.choices, hasLength(3));
      // Let go: his contract ends with the season.
      expect(c.answerTalk('leave', r.id, 1), isNull);
      expect(talk.answer, 1);
      expect(c.economy.contracts[r.id]!.endYear, c.year);
      expect(people.letGo, contains(r.id));
      expect(c.answerTalk('leave', r.id, 0), isNotNull); // already answered
      people.weekly();
      expect(c.inbox.where((m) => m.talk?.kind == 'leave'), hasLength(1));

      // A rider who joins a team needs a while to settle, the less
      // adaptable the longer.
      final newcomer = c.riderById.values.firstWhere(
        (x) =>
            x.teamId != team &&
            people.of(x.id).adaptability < 0.6 &&
            c.teams[x.teamId]?.division.startsWith('[1]') == true,
      );
      c.economy.move(newcomer, team);
      expect(people.settlingDays(newcomer.id), greaterThan(0));
      expect(people.settling(newcomer.id), lessThan(1));
      c.today = c.today.add(const Duration(days: 130));
      expect(people.settling(newcomer.id), 1);
    },
  );
  test(
    'Klauseln, Straßenkapitän und Grand Tours',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 10)),
    () {
      I18n.lang = Lang.de;
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
      final c = Career(world, teamId: team, seed: 4);
      final eco = c.economy;

      // The three Grand Tours are told apart, although the WorldDB gives
      // the Giro and the Vuelta the same class.
      final giro = c.calendar.firstWhere((r) => r.info.name == "Giro d'Italia");
      final vuelta = c.calendar.firstWhere(
        (r) => r.info.name.contains('Vuelta Ciclista a España'),
      );
      expect(grandTourOf(giro.info), GrandTour.giro);
      expect(grandTourOf(vuelta.info), GrandTour.vuelta);
      expect(Prizes.overallWinner(giro), 265000);
      expect(jerseyNames(GrandTour.giro).general, 'pink jersey');

      // Clauses lower what a rider asks.
      final r = c.squads[team]!.firstWhere((x) => Economy.rating(x) >= 76);
      final plain = eco.askFor(r, 2);
      final bonus = eco.askFor(
        r,
        2,
        clauses: const Clauses(signing: 200000, winBonus: 10000, leader: true),
      );
      expect(bonus, lessThan(plain));
      expect(
        eco.askFor(r, 2, clauses: const Clauses(signing: 99000000)),
        greaterThanOrEqualTo((eco.demand(r) * 0.6).round() - 1000),
      );

      // A renewal with a signing bonus charges it and keeps the clauses for
      // the next contract.
      final own = c.squads[team]!.firstWhere(
        (x) =>
            eco.contracts[x.id]!.endYear > c.year &&
            eco.contracts[x.id]!.nextTeam == null,
      );
      eco.balance = 1e8;
      const clauses = Clauses(signing: 50000, release: 9000000);
      expect(
        eco.offer(
          own.id,
          eco.askFor(own, 2, clauses: clauses) + 1000,
          2,
          clauses: clauses,
        ),
        isNull,
      );
      expect(eco.contracts[own.id]!.nextClauses.release, 9000000);
      expect(eco.available, lessThan(1e8));

      // A road captain for every team in a race.
      final squad = c.squads[team]!;
      final best = c.people.bestCaptain(squad)!;
      expect(c.people.captainSkill(best.id), greaterThan(0));
      for (final x in squad) {
        expect(
          c.people.captainSkill(x.id),
          lessThanOrEqualTo(c.people.captainSkill(best.id)),
        );
      }
    },
  );

  test(
    'Managerkarriere: Ruf, Entlassung, Teamwechsel',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 10)),
    () {
      I18n.lang = Lang.de;
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
      final c = Career(world, teamId: team, seed: 4)
        ..delegation.jobMarket = true;
      final m = c.manager;
      final start = m.reputation;
      expect(start, greaterThan(60)); // a top team's manager is known

      // A season without a point: the board warns, a second one costs the
      // job, and weaker teams make offers.
      c.today = DateTime.utc(c.year, 11, 1);
      m.daily();
      expect(m.warned, isTrue);
      expect(m.dismissed, isFalse);
      expect(m.reputation, lessThan(start));
      m.daily();
      expect(m.dismissed, isTrue);
      expect(m.offers, isNotEmpty);
      final strength = c.teamStrength(team);
      for (final id in m.offers) {
        expect(c.teamStrength(id), lessThanOrEqualTo(strength));
      }
      final talks = c.inbox.where((x) => x.talk?.kind == 'job').toList();
      expect(talks, isNotEmpty);
      final to = talks.first.talk!.riderId;
      expect(c.answerTalk('job', to, 0), isNull);
      expect(m.nextTeam, to);

      // At the turn of the year the player takes over the new team; the
      // old one keeps books of its own.
      c.today = DateTime.utc(c.year + 1, 1, 1);
      c.startNextSeason();
      expect(c.teamId, to);
      expect(c.startTeam, team);
      expect(c.finances.books.containsKey(team), isTrue);
      expect(c.finances.books.containsKey(to), isFalse);
      expect(c.economy.sponsors, hasLength(3));
      expect(c.devTeam.teamId, c.devTeam.links[to]);
      expect(m.seasons[c.year - 1], team);
      expect(m.dismissed, isFalse);

      // A save loads into the same state, created for the first team.
      final saved = c.toJson();
      final copy = Career(world, teamId: c.startTeam, seed: 4)
        ..restore(saved, const []);
      expect(copy.delegation.jobMarket, isTrue);
      expect(copy.teamId, to);
      expect(copy.toJson().toString(), saved.toString());
    },
  );
}
