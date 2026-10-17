import 'dart:convert';
// Checks that loading a saved game yields the same state: same date, same
// rankings, same messages.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game/game.dart';
import 'package:radmanager/app_state.dart';
import 'package:sim/sim.dart';

void main() {
  seasonTest();
  customTest();
  namedTest();
  final dataDir = AppState.findDataDir();
  const saveName = 'savegame_test.json';

  test(
    'Spielstand laden ergibt denselben Stand',
    skip: dataDir == null,
    () async {
      final file = File('$dataDir/$saveName');
      if (file.existsSync()) file.deleteSync();
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      final a = AppState(dataDir!, saveName: saveName)..watchLive = false;
      // Make decisions of every kind so that loading has to replay them.
      a.setLoad(a.squad[0].id, TrainingLoad.high);
      a.setFocus(a.squad[1].id, TrainingFocus.timeTrial);
      // Shortlist and a note have to survive the save as well.
      a.toggleWatch(a.career.economy.market().first.id);
      a.setNote(a.squad[2].id, 'Für die Klassiker einplanen');
      a.toggleProgram(a.career.ownRaces[3].info.id, a.squad[2].id);
      // Staff and scouting: hire, dismiss, have a rider watched.
      final staff = a.career.staff;
      expect(
        a.hire(staff.free.firstWhere((s) => s.role == StaffRole.coach).id),
        isNull,
      );
      expect(a.fire(staff.of(a.team.id, StaffRole.doctor).last.id), isNull);
      final unknown = a.career.economy.market().firstWhere(
        (r) => staff.knowledge(r.id) < 0.5,
      );
      expect(a.scout(unknown.id), isNull);
      // Delegate tasks and choose another development team.
      a.delegate('training', true);
      a.delegate('scouting', true);
      // The development team is tied to the team and cannot be switched.
      expect(a.chooseDevTeam(1), isNotNull);
      // Red Bull's development team is the one of the real world.
      expect(a.career.devTeam.team?.abbr, 'RBC');
      // Training camp in three weeks for four riders.
      expect(
        a.bookCamp(
          CampType.base,
          a.career.today.add(const Duration(days: 21)),
          7,
          a.squad.skip(20).take(4).map((r) => r.id).toList(),
        ),
        isNull,
      );
      var customLineups = 0, radioCalls = 0;
      for (var i = 0; i < 40; i++) {
        // Radio: pick each option in turn.
        if (a.radio case final r?) {
          await a.answerRadio(radioCalls++ % r.call.options.length);
          continue;
        }
        final p = a.pending;
        if (p == null) {
          await a.next();
          continue;
        }
        // Every second line-up differs from the suggestion and has its own tactics.
        if (customLineups++ % 2 == 0 && p.available.length > p.size) {
          final lineup = p.available.reversed.take(p.size).toList();
          await a.confirmLineup(
            p,
            lineup,
            // In turn: pin a leader and the approach and leave the rest to
            // the sports director, or fix the complete plan.
            wish: customLineups % 4 == 1
                ? PlanWish(
                    roles: {lineup.first.id: Role.leader},
                    approach: Approach.control,
                  )
                : null,
            plan: customLineups % 4 == 3
                ? a.career.suggestPlan(p.routes.first, lineup, p.others)
                : null,
            // Not the suggested director but the last free one.
            directorId: p.directors.lastOrNull?.id,
          );
        } else {
          await a.confirmLineup(p, p.suggestedLineup);
        }
      }
      expect(customLineups, greaterThan(0));
      expect(radioCalls, greaterThan(3));
      expect(a.career.inbox, isNotEmpty);

      a.flush();

      final b = AppState(dataDir, saveName: saveName)..watchLive = false;
      expect(b.team.id, a.team.id);
      await b.restore();

      // The whole state must be the same, key by key.
      final ja = a.career.toJson(), jb = b.career.toJson();
      for (final k in ja.keys) {
        expect(
          jsonEncode(jb[k]),
          jsonEncode(ja[k]),
          reason: 'Zustand "$k" weicht ab (Seed ${a.career.seed})',
        );
      }
      expect(b.career.today, a.career.today);
      expect(
        b.career.inbox.map((m) => m.subject).toList(),
        a.career.inbox.map((m) => m.subject).toList(),
      );
      expect(b.career.riderPoints, a.career.riderPoints);
      expect(b.career.teamPoints, a.career.teamPoints);
      expect(
        b.career.shapeOf(a.squad[0].id).load,
        a.career.shapeOf(a.squad[0].id).load,
      );
      expect(
        b.career.shapeOf(a.squad[0].id).fitness,
        a.career.shapeOf(a.squad[0].id).fitness,
      );
      expect(b.career.program, a.career.program);
      // The loaded game looks for an open radio question at once; the
      // original only does so on the next step, so ask its career directly.
      expect(
        b.radio?.call.text,
        a.career.needsDecision != null
            ? null
            : a.career.nextRadioCall()?.call.text,
      );
      expect(b.career.delegation.training, isTrue);
      expect(b.career.delegation.scouting, isTrue);
      expect(b.career.devTeam.teamId, a.career.devTeam.teamId);
      expect(
        b.career.camps.all.single.riders,
        a.career.camps.all.single.riders,
      );
      expect(b.career.titles.length, a.career.titles.length);
      expect(
        b.squad.map((r) => b.career.shapeOf(r.id).load).toList(),
        a.squad.map((r) => a.career.shapeOf(r.id).load).toList(),
      );

      // Both play on: the loaded career must take the same course.
      for (final x in [a, b]) {
        x.delegate('radio', RadioMode.off.name);
        x.delegate('lineups', true);
        for (var i = 0; i < 6; i++) {
          await x.next();
        }
      }
      // The complete state must still be the same after playing on. This
      // caught riders starting in two races on one day: line-ups drawn up
      // before the first race started were stale for the second.
      final pa = a.career.toJson(), pb = b.career.toJson();
      for (final k in pa.keys) {
        expect(
          jsonEncode(pb[k]),
          jsonEncode(pa[k]),
          reason:
              'Zustand "$k" weicht nach dem Weiterspielen ab '
              '(Seed ${a.career.seed})',
        );
      }
      expect(b.career.today, a.career.today);
      expect(b.career.teamPoints, a.career.teamPoints);
      expect(
        b.career.inbox.map((m) => m.subject).toList(),
        a.career.inbox.map((m) => m.subject).toList(),
      );
      expect(
        b.career.staff.of(b.team.id).map((s) => s.id).toList(),
        a.career.staff.of(a.team.id).map((s) => s.id).toList(),
      );
      expect(b.career.staff.scouted, a.career.staff.scouted);
      expect(
        b.career.staff.jobs.map((j) => j.riderId).toList(),
        a.career.staff.jobs.map((j) => j.riderId).toList(),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

// Named saves: save, play on, load gives the state at the time of saving
// again. With a hand-picked squad and race entries.
void namedTest() {
  final dataDir = AppState.findDataDir();
  const saveName = 'savegame_test_named.json';

  test(
    'Benannter Spielstand mit gewähltem Kader',
    skip: dataDir == null,
    () async {
      final file = File('$dataDir/$saveName');
      if (file.existsSync()) file.deleteSync();
      final a = AppState(dataDir!, saveName: saveName)..watchLive = false;
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
        for (final s in a.saves().where((s) => s.name == 'Test benannt')) {
          a.deleteSave(s);
        }
      });
      // Every third of the 81 strongest riders: 27, enough for a WorldTeam.
      final best = a.world.riders()
        ..sort((x, y) => Economy.rating(y).compareTo(Economy.rating(x)));
      final picked = [for (var i = 0; i < 81; i += 3) best[i]];
      a.foundTeam(
        name: 'Auswahl Test',
        abbr: 'AWT',
        country: 'GER',
        color: '0B4FA8',
        color2: 'F0C000',
        riders: picked,
      );
      expect(a.squad.map((r) => r.id).toSet(), {for (final r in picked) r.id});
      expect(a.career.licences.of(a.team.id), Licence.worldTour);
      // The riders' old teams have been filled up again.
      final donor = picked.first.teamId;
      expect(a.career.squads[donor]!.length, greaterThan(15));
      a.delegate('radio', RadioMode.off.name);
      a.delegate('lineups', true);
      final e = a.career.entries;
      final declinable = a.career.calendar.firstWhere(
        (r) => e.status(r) == EntryStatus.entered && r.start.month >= 3,
      );
      expect(a.entry(declinable.info.id, 'decline'), isNull);
      for (var i = 0; i < 6; i++) {
        await a.next();
      }
      expect(a.saveAs('Test benannt'), isNull);
      final date = a.career.today;
      final points = {...a.career.teamPoints};
      for (var i = 0; i < 6; i++) {
        await a.next();
      }
      expect(a.career.today.isAfter(date), isTrue);

      final saved = a.saves().firstWhere((s) => s.name == 'Test benannt');
      expect(saved.team, 'Auswahl Test');
      expect(saved.gameDate, date);
      expect(await a.loadSave(saved), isNull);
      expect(a.team.name, 'Auswahl Test');
      expect(a.career.today, date);
      expect(a.career.teamPoints, points);
      expect(a.squad.map((r) => r.id).toSet(), {for (final r in picked) r.id});
      expect(
        a.career.entries.status(
          a.career.calendar.firstWhere((r) => r.info.id == declinable.info.id),
        ),
        EntryStatus.declined,
      );
      expect(a.career.delegation.lineups, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

// A founded team does not exist in the WorldDB; it has to come back from
// the save with its squad and race programme.
void customTest() {
  final dataDir = AppState.findDataDir();
  const saveName = 'savegame_test_custom.json';

  test(
    'Urlaub, Lesezeichen und gehaltene Delegation',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 15)),
    () async {
      const name = 'savegame_vacation_test.json';
      final file = File('$dataDir/$name');
      if (file.existsSync()) file.deleteSync();
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      final a = AppState(dataDir!, saveName: name)..watchLive = false;

      // A bookmark comes and goes; the list belongs to the player.
      const place = {'page': 'debug', 'sub': 'test-bookmark'};
      final had = a.isBookmarked(place);
      a.toggleBookmark(place);
      expect(a.isBookmarked(place), !had);
      a.toggleBookmark(place);
      expect(a.isBookmarked(place), had);

      // Two weeks of vacation: the staff decide, the player's own
      // settings come back afterwards.
      a.delegate('training', false);
      a.delegate('lineups', false);
      final start = a.career.today;
      await a.simulateUntil(
        start.add(const Duration(days: 14)),
        vacation: true,
        answerTalks: true,
      );
      expect(a.career.today.isAfter(start), isTrue);
      expect(a.career.delegation.training, isFalse);
      expect(a.career.delegation.lineups, isFalse);
      expect(a.career.heldDelegation, isNull);

      // A save made while the staff were in charge loads with the
      // player's settings.
      a.career.heldDelegation = a.career.delegation.toJson();
      a.career.delegation.training = true;
      final copy =
          Career(a.world, teamId: a.career.startTeam, seed: a.career.seed)
            ..restore(a.career.toJson(), [
              for (final p in a.career.progress.values) a.career.raceJson(p),
            ]);
      expect(copy.delegation.training, isFalse);
      expect(copy.heldDelegation, isNull);
    },
  );

  test('Gegründetes Team übersteht das Laden', skip: dataDir == null, () async {
    final file = File('$dataDir/$saveName');
    if (file.existsSync()) file.deleteSync();
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final a = AppState(dataDir!, saveName: saveName)..watchLive = false;
    a.foundTeam(
      name: 'RSV Leipzig',
      abbr: 'RSL',
      country: 'GER',
      color: '0B4FA8',
      color2: 'F0C000',
      pro: true,
    );
    a.delegate('radio', RadioMode.off.name);
    expect(a.squad.length, 22);
    // A founded team has no development team until it founds one. Trainees
    // are only possible from August.
    expect(a.career.devTeam.teamId, isNull);
    expect(a.foundDevTeam(), isNull);
    expect(a.career.devTeam.squad.length, 8);
    expect(a.foundDevTeam(), isNotNull);
    expect(a.takeStagiaire(a.career.devTeam.squad.first.id), isNotNull);
    for (var i = 0; i < 12; i++) {
      final p = a.pending;
      if (p != null) {
        await a.confirmLineup(p, p.suggestedLineup);
      } else {
        await a.next();
      }
    }
    expect(
      a.career.progress.values.any(
        (p) => p.riders.any((r) => r.teamId == a.team.id),
      ),
      isTrue,
    );

    a.flush();

    final b = AppState(dataDir, saveName: saveName)..watchLive = false;
    expect(b.team.name, 'RSV Leipzig');
    await b.restore();
    expect(b.career.today, a.career.today);
    expect(
      b.squad.map((r) => r.id).toList(),
      a.squad.map((r) => r.id).toList(),
    );
    expect(b.career.teamPoints, a.career.teamPoints);
    expect(b.career.economy.balance, a.career.economy.balance);
    // The founded development team is part of the save.
    expect(b.career.devTeam.team?.name, a.career.devTeam.team?.name);
    expect(
      b.career.devTeam.squad.map((r) => r.id).toSet(),
      a.career.devTeam.squad.map((r) => r.id).toSet(),
    );

    // From August a trainee can be taken and starts for the professional
    // team in races below the WorldTour.
    await a.simulateUntil(DateTime.utc(a.career.year, 8, 2), auto: true);
    final trainee = a.career.devTeam.squad.first;
    expect(a.takeStagiaire(trainee.id), isNull);
    await a.simulateUntil(DateTime.utc(a.career.year, 10, 20), auto: true);
    final rides = [
      for (final p in a.career.progress.values)
        if (p.riders.any((r) => r.id == trainee.id && r.teamId == a.team.id))
          p.race.tier,
    ];
    expect(rides.every(DevTeam.allows), isTrue);
    // No rider starts twice in a race.
    for (final p in a.career.progress.values) {
      final ids = [for (final r in p.riders) r.id];
      expect(ids.toSet().length, ids.length, reason: p.race.info.name);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}

// A whole year with contract offers and a change of season: the loaded
// state must have the same squads, contracts and balances.
void seasonTest() {
  final dataDir = AppState.findDataDir();
  const saveName = 'savegame_test_season.json';

  test('Angebote und Saisonwechsel überstehen das Laden', skip: dataDir == null, () async {
    final file = File('$dataDir/$saveName');
    if (file.existsSync()) file.deleteSync();
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    final a = AppState(dataDir!, saveName: saveName)..watchLive = false;
    a.setAutoRenew(false);
    // Without radio, and from summer on the sports director picks the line-ups.
    a.delegate('radio', RadioMode.off.name);
    var offered = false, searched = false, sponsored = false;
    String? signedName;
    for (var i = 0; i < 400 && !a.career.seasonOver; i++) {
      final p = a.pending;
      if (p != null) {
        await a.confirmLineup(p, p.suggestedLineup);
      } else {
        await a.next();
      }
      final eco = a.career.economy;
      // Sponsor search: have the board look further first, then take the new offer.
      if (eco.offers.isNotEmpty) {
        final slot = eco.offers.keys.first;
        if (!searched) {
          searched = true;
          expect(a.searchSponsor(slot), isNull);
        } else if (!sponsored && !eco.searches.containsKey(slot)) {
          sponsored = true;
          expect(a.acceptSponsor(slot, eco.offers[slot]!.length - 1), isNull);
        }
      }
      if (!offered && eco.windowOpen) {
        offered = true;
        // One offer that is too low (refusal) and one that fits (acceptance).
        final own = a.squad.firstWhere(eco.expiring);
        expect(a.offer(own.id, 1000, 2), isNotNull);
        final target = eco.market().firstWhere(
          (r) => eco.demand(r) < 150000 && Economy.rating(r) > 70,
        );
        expect(a.offer(target.id, eco.demand(target), 2), isNull);
        signedName = a.career.fullName(target.id);
        // Promote a rider from the development team.
        expect(a.promote(a.career.devTeam.squad.first.id), isNull);
        a.delegate('lineups', true);
      }
    }
    expect(offered, isTrue);
    expect(sponsored, isTrue);
    expect(a.career.seasonOver, isTrue);
    // The Tour de France rides another course in the second season.
    List<int> tour() => [
      for (final s
          in a.career.calendar
              .firstWhere((r) => r.info.name.startsWith('Tour de France'))
              .stages)
        s.id,
    ];
    final tour2026 = tour();
    a.nextSeason();
    expect(a.career.year, 2027);
    expect(tour(), hasLength(tour2026.length));
    expect(tour().first, isNot(tour2026.first));
    // A little way into the second season, with our own line-ups.
    for (var i = 0; i < 8; i++) {
      final p = a.pending;
      if (p != null) {
        await a.confirmLineup(p, p.suggestedLineup.reversed.toList());
      } else {
        await a.next();
      }
    }
    expect(a.squad.map((r) => a.career.fullName(r.id)), contains(signedName));

    a.flush();

    final b = AppState(dataDir, saveName: saveName)..watchLive = false;
    await b.restore();
    expect(b.career.year, 2027);
    expect(b.career.today, a.career.today);
    expect(
      b.career.calendar.map((r) => r.stages.map((s) => s.id).join(',')),
      a.career.calendar.map((r) => r.stages.map((s) => s.id).join(',')),
    );
    expect(
      b.career.inbox.map((m) => m.subject).toList(),
      a.career.inbox.map((m) => m.subject).toList(),
    );
    expect(
      b.squad.map((r) => r.id).toList(),
      a.squad.map((r) => r.id).toList(),
    );
    expect(b.career.economy.balance, a.career.economy.balance);
    expect(b.career.economy.budget, a.career.economy.budget);
    expect(
      b.career.economy.sponsors.map((s) => s.name).toList(),
      a.career.economy.sponsors.map((s) => s.name).toList(),
    );
    expect(b.career.titles.length, a.career.titles.length);
    expect(
      b.career.economy.wageBill(b.team.id),
      a.career.economy.wageBill(a.team.id),
    );
    expect(b.career.riderById.length, a.career.riderById.length);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
