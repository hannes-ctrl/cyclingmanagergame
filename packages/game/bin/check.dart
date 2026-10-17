// Plays a season and its turn of the year and checks every day what must
// always hold. Prints each broken rule once with the first day it broke,
// and how often.
//
//   dart run bin/check.dart [--seed s] [--team ABBR] [--switch ABBR]
//                           [--seasons n] [--job-market]
//
// With --switch the player takes over that team at the turn of the year;
// the check then plays on into January and compares a save and its load.
// With --seasons it goes on over several seasons and turns of the year;
// with --job-market the board may dismiss the manager, who then takes the
// first offer at the turn of the year.
import 'dart:io';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

/// What must hold on every day beyond the races: every rider in one squad
/// only, books that are numbers, valid mentors, programmes without riders
/// of other teams or overlaps, and the player's staff within its limits.
///
/// @param c The career.
/// @param check Records a broken rule.
void checkWorld(Career c, void Function(bool, String, [String]) check) {
  final seen = <int>{};
  for (final e in c.squads.entries) {
    for (final r in e.value) {
      check(seen.add(r.id), 'rider in two squads', r.name);
    }
  }
  for (final id in c.teams.keys) {
    final budget = c.finances.budgetOf(id), balance = c.finances.balanceOf(id);
    check(budget.isFinite && balance.isFinite, 'books not finite',
        '${c.teams[id]?.abbr}');
    check(budget >= 0, 'negative budget', '${c.teams[id]?.abbr}');
  }
  for (final young in c.people.mentors.keys) {
    final m = c.people.mentorOf(young);
    if (m == null) continue;
    check(m != young, 'rider mentors himself');
  }
  for (final e in c.program.entries) {
    for (final id in e.value) {
      check(
          c.riderById[id]?.teamId == c.teamId || c.devTeam.has(id),
          'programme holds a rider of another team',
          '${c.riderById[id]?.name}');
    }
  }
  final races = {for (final r in c.calendar) r.info.id: r};
  for (final team in c.teamPrograms.entries) {
    final byRider = <int, List<RaceEntry>>{};
    for (final e in team.value.entries) {
      final race = races[e.key];
      if (race == null || c.progress.containsKey(e.key)) continue;
      for (final id in e.value) {
        byRider.putIfAbsent(id, () => []).add(race);
      }
    }
    for (final e in byRider.entries) {
      final list = e.value..sort((a, b) => a.start.compareTo(b.start));
      for (var i = 1; i < list.length; i++) {
        check(
            list[i].start.isAfter(list[i - 1].end),
            'rider of another team planned for overlapping races',
            '${c.riderById[e.key]?.name}: ${list[i - 1].info.name} / ${list[i].info.name}');
      }
    }
  }
  for (final role in StaffRole.values) {
    check(c.staff.of(c.teamId, role).length <= StaffBook.limits[role]!,
        'more staff than allowed', role.name);
  }
  for (final o in c.economy.pending.values) {
    check(!o.until.isAfter(c.today.add(const Duration(days: 7))),
        'offer waits too long');
  }
}

/// Command-line entry point.
///
/// @param argv Options.
/// @returns A future that completes after the season.
Future<void> main(List<String> argv) async {
  final args = [...argv];
  String? option(String name) {
    final i = args.indexOf(name);
    if (i < 0) return null;
    final v = args[i + 1];
    args.removeRange(i, i + 2);
    return v;
  }

  final seed = int.parse(option('--seed') ?? '5');
  final abbr = option('--team') ?? 'TVL';
  final switchTo = option('--switch');
  final seasons = int.parse(option('--seasons') ?? '1');
  final jobMarket = args.remove('--job-market');
  I18n.lang = Lang.de;
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final team = world.teams().firstWhere((t) => t.abbr == abbr);
  final c = Career(world,
      teamId: team.id,
      seed: seed,
      tuning: SimTuning.load('${root}calibration/tuning.json'))
    ..delegation.lineups = true
    ..delegation.radio = RadioMode.off
    ..delegation.training = true
    ..delegation.scouting = true
    ..delegation.planning = true
    ..delegation.jobMarket = jobMarket;

  final broken = <String, (String, int)>{};
  void check(bool ok, String rule, [String detail = '']) {
    if (ok) return;
    final day = c.today.toIso8601String().substring(0, 10);
    final seen = broken[rule];
    broken[rule] = seen == null ? ('$day $detail', 1) : (seen.$1, seen.$2 + 1);
  }

  // Highest average power per kind of stage, to judge the limits.
  final strongest = <StageKind, (double, String)>{};
  for (var round = 0; round < seasons; round++) {
    var balance = c.economy.balance;
    var ledger = c.economy.ledger.length;
    while (!c.seasonOver) {
      // Who was out before the day began: none of them may start.
      final out = {
        for (final e in c.shape.entries)
          if (e.value.injuredUntil?.isAfter(c.today) ?? false) e.key,
      };
      final day = await c.advanceAsync();
      // Every stage: a result for everyone at the start, in time order,
      // without impossible times.
      final started = <int, String>{};
      for (final r in day.stages) {
        final res = r.result;
        final name = r.race.race.info.name;
        check(res.placings.isNotEmpty, 'stage without finishers', name);
        for (var i = 1; i < res.placings.length; i++) {
          check(res.placings[i].timeS >= res.placings[i - 1].timeS,
              'placings out of order', name);
        }
        for (final p in res.placings) {
          check(p.timeS.isFinite && p.timeS > 0, 'impossible time', name);
          final other = started[p.rider.id];
          check(other == null || other == name, 'rider in two races on one day',
              '${p.rider.name}: $other / $name');
          started[p.rider.id] = name;
        }
        final route = c.world.route(r.race.race.stages[r.stageIndex].id);
        if (res.placings.isNotEmpty) {
          final kmh = route.raceKm / (res.winnerTimeS / 3600);
          check(kmh > 20 && kmh < 65, 'implausible winner speed',
              '$name ${kmh.toStringAsFixed(1)} km/h');
        }
        // Average power over the stage: a long road stage stays well below
        // 400 W even for heavy riders; a short time trial of a quarter of an
        // hour reaches 600 W at the very top, a prologue more.
        final limit = route.kind == StageKind.road
            ? 450
            : route.raceKm < 10
                ? 750
                : route.raceKm < 20
                    ? 620
                    : 560;
        for (final p in res.placings) {
          final e = res.power[p.rider.id];
          if (e == null) continue;
          check(e.averageW > 50 && e.averageW < limit, 'implausible power',
              '$name ${p.rider.name} ${(p.rider.massKg).round()} kg ${e.averageW.round()} W');
          if (e.averageW > (strongest[route.kind]?.$1 ?? 0)) {
            strongest[route.kind] = (
              e.averageW,
              '$name ${route.raceKm.toStringAsFixed(1)} km, ${p.rider.name} ${p.rider.massKg.round()} kg'
            );
          }
        }
        // The general classification: the leader's total is the sum of his
        // stage times less his bonus seconds, never more.
        if (r.race.race.isStageRace && r.race.run.standings.isNotEmpty) {
          final gc = r.race.run.standings.last.general;
          for (var i = 1; i < gc.length; i++) {
            check(gc[i].timeS >= gc[i - 1].timeS,
                'general classification out of order', name);
          }
        }
      }
      // Nobody starts injured.
      for (final r in day.stages) {
        if (r.stageIndex != 0) continue;
        for (final x in r.race.riders) {
          check(!out.contains(x.id), 'injured rider at the start',
              '${x.name} ${r.race.race.info.name}');
        }
      }
      // Money: the balance moves only by the monthly statements and bookings
      // of the day.
      if (c.economy.ledger.length > ledger) {
        final line = c.economy.ledger.last;
        check(
            (c.economy.balance - balance - line.result).abs() < 1,
            'balance does not follow the statement',
            '${(c.economy.balance - balance - line.result).round()} €');
        check(line.prize >= 0 && line.wages >= 0 && line.costs >= 0,
            'negative item in the statement');
        ledger = c.economy.ledger.length;
      }
      balance = c.economy.balance;
      // Points: a team has what its riders have.
      final byTeam = <int, double>{};
      for (final e in c.riderPoints.entries) {
        final t = c.riderById[e.key]?.teamId;
        if (t != null) byTeam[t] = (byTeam[t] ?? 0) + e.value;
      }
      for (final e in c.teamPoints.entries) {
        check(
            ((byTeam[e.key] ?? 0) - e.value).abs() < 0.01,
            'team points differ from rider points',
            '${c.teams[e.key]?.abbr} ${e.value.round()} / ${(byTeam[e.key] ?? 0).round()}');
      }
      // Squads and contracts.
      for (final e in c.squads.entries) {
        final t = c.teams[e.key];
        if (t == null || t.division == 'Free') continue;
        check(e.value.length <= 32, 'squad too large',
            '${t.abbr} ${e.value.length}');
        for (final r in e.value) {
          check(c.riderById[r.id]?.teamId == e.key, 'rider in the wrong squad',
              '${r.name} ${t.abbr}');
          final k = c.economy.contracts[r.id];
          check(k != null && k.wage >= 0, 'rider without a contract', r.name);
        }
      }
      // Form and fatigue within their range.
      for (final s in c.shape.values) {
        check(s.form > 0.9 && s.form < 1.1, 'form out of range',
            s.form.toStringAsFixed(3));
        check(s.fitness.isFinite && s.fatigue.isFinite, 'fitness not finite');
      }
      checkWorld(c, check);
    }
    stdout.writeln('Reputation ${c.manager.reputation.round()} '
        '(${c.manager.standing}), offers: '
        '${c.manager.offers.map((id) => c.teams[id]?.abbr).join(', ')}, '
        'warned ${c.manager.warned}, dismissed ${c.manager.dismissed}');
    if (switchTo != null && round == 0) {
      final to = world.teams().firstWhere((t) => t.abbr == switchTo).id;
      c.manager.offers.add(to);
      check(c.manager.answer(to, 0) == null, 'job offer not accepted');
    }
    // The turn of the year: transfers, retirements, licences.
    final before = c.teamId;
    c.startNextSeason();
    if (c.teamId != before) {
      stdout.writeln('Turn of ${c.year - 1}: the manager moves from '
          '${c.teams[before]?.abbr} to ${c.teams[c.teamId]?.abbr}');
    }
    if (switchTo != null && round == 0) {
      check(c.teams[c.teamId]?.abbr == switchTo, 'team not switched');
      check(c.finances.books[team.id] != null, 'old team without books');
      check(!c.finances.books.containsKey(c.teamId), 'new team keeps books');
      for (var i = 0; i < 45; i++) {
        await c.advanceAsync();
        checkWorld(c, check);
      }
      final saved = c.toJson();
      final copy = Career(world,
          teamId: c.startTeam,
          seed: seed,
          tuning: SimTuning.load('${root}calibration/tuning.json'))
        ..restore(saved, [for (final p in c.progress.values) c.raceJson(p)]);
      check(copy.teamId == c.teamId, 'load lost the team');
      final a = saved.toString(), b = copy.toJson().toString();
      check(a == b, 'save and load differ',
          'first difference at ${Iterable.generate(a.length).firstWhere((i) => i >= b.length || a[i] != b[i], orElse: () => -1)}');
      stdout.writeln('Now with ${c.teams[c.teamId]?.name}: budget '
          '${c.economy.budget.round()}, balance ${c.economy.balance.round()}, '
          'squad ${c.squads[c.teamId]?.length}, staff ${c.staff.of(c.teamId).length}, '
          'sponsors ${c.economy.sponsors.map((x) => x.name).join(' / ')}');
    }
    checkWorld(c, check);
    for (final t in c.teams.values) {
      final n = c.squads[t.id]?.length ?? 0;
      final l = c.licences.of(t.id);
      if (l == Licence.worldTour) {
        check(n >= 27 && n <= 30, 'WorldTeam squad out of 27 to 30',
            '${t.abbr} $n');
      }
      if (l == Licence.pro && t.id != c.teamId) {
        check(n >= 20 && n <= 30, 'ProTeam squad out of 20 to 30',
            '${t.abbr} $n');
      }
    }
    check(c.licences.teamsWith(Licence.pro).length <= c.licences.proPlaces,
        'more ProTeams than places');
    for (final k in c.economy.contracts.entries) {
      final r = c.riderById[k.key];
      if (r == null || c.teams[r.teamId]?.division == 'Free') continue;
      check(k.value.endYear >= c.year, 'contract ended but still in a team',
          '${r.name} ${k.value.endYear}');
    }
  }
  stdout.writeln(
      '$seasons season(s) up to ${c.year - 1} and the turns of the year, '
      'started with ${team.name}, seed $seed');
  if (broken.isEmpty) {
    stdout.writeln('Nothing broken.');
  } else {
    for (final e in broken.entries) {
      stdout.writeln('${e.key}: ${e.value.$2}× (first ${e.value.$1})');
    }
  }
  for (final e in strongest.entries) {
    stdout.writeln(
        'Highest average power, ${e.key.name}: ${e.value.$1.round()} W (${e.value.$2})');
  }
  world.close();
}
