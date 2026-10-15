// Plays a season and checks every day what must always hold. Prints each
// broken rule once with the first day it broke, and how often.
//
//   dart run bin/check.dart [--seed s] [--team ABBR]
import 'dart:io';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

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
    ..delegation.planning = true;

  final broken = <String, (String, int)>{};
  void check(bool ok, String rule, [String detail = '']) {
    if (ok) return;
    final day = c.today.toIso8601String().substring(0, 10);
    final seen = broken[rule];
    broken[rule] = seen == null ? ('$day $detail', 1) : (seen.$1, seen.$2 + 1);
  }

  // Highest average power per kind of stage, to judge the limits.
  final strongest = <StageKind, (double, String)>{};
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
  }
  stdout.writeln('Season ${c.year} with ${team.name}, seed $seed');
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
