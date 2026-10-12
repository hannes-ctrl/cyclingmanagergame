// Exercises the building blocks of step 7 without a user interface: radio,
// "what if", forecast, licences, development team and delegation.
//
// Usage: dart run bin/step7.dart [team abbreviation] [years]
import 'dart:io';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

void main(List<String> args) {
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final abbr = args.isEmpty ? 'RBH' : args[0];
  final years = args.length > 1 ? int.parse(args[1]) : 1;
  final team = world.teams().firstWhere((t) => t.abbr == abbr);
  final tuning = SimTuning.load('${root}calibration/tuning.json');

  /// @returns A fresh career with the chosen team and a fixed seed.
  Career start() => Career(world, teamId: team.id, seed: 5, tuning: tuning);

  // 1. Radio: answering "stick to the plan" every time gives the same race as
  //    no radio at all. Other answers change it.
  final silent = start()..delegation.radio = RadioMode.off;
  final plain = start(), active = start();
  final calls = <RadioKind, int>{};
  final options = <RadioKind, int>{};
  var changed = 0, same = 0, asked = 0;

  /// @param r A stage result.
  /// @returns The ids of the first twenty finishers, as a comparable string.
  String top(StageResult r) =>
      r.placings.take(20).map((p) => p.rider.id).join(',');
  Forecast? forecast;
  var forecastMs = 0;
  String? whatIf;
  while (silent.today.month < 4) {
    for (var call = plain.nextRadioCall();
        call != null;
        call = plain.nextRadioCall()) {
      plain.answerRadio(call.race.race.info.id, call.call.kind, 0);
    }
    for (var call = active.nextRadioCall();
        call != null;
        call = active.nextRadioCall()) {
      asked++;
      calls[call.call.kind] = (calls[call.call.kind] ?? 0) + 1;
      options[call.call.kind] = call.call.options.length;
      if (asked <= 3) {
        print('  Funk ${call.race.race.info.name}: ${call.call.text}');
        for (final o in call.call.options) {
          print('     - $o');
        }
      }
      // Always the last option: the one furthest from the plan.
      active.answerRadio(
          call.race.race.info.id, call.call.kind, call.call.options.length - 1);
    }
    final pending = active.needsDecision;
    if (pending != null && forecast == null && pending.race.isStageRace) {
      final watch = Stopwatch()..start();
      forecast = forecastRace(
          pending.routes, [...pending.others, ...pending.suggestedLineup],
          tuning: tuning, seed: pending.race.info.id);
      forecastMs = watch.elapsedMilliseconds;
      print(
          '\nPrognose ${pending.race.info.name} (${pending.routes.length} Etappen, '
          '${forecast.runs} Läufe, $forecastMs ms)');
      for (final row in forecast.rows.take(5)) {
        print('  ${row.rider.name.padRight(22)} ${row.rider.team.padRight(4)} '
            'Siege ${row.wins}  Podium ${row.podiums}  Schnitt ${row.meanRank.toStringAsFixed(1)}');
      }
    }
    final a = silent.advance(), b = plain.advance(), c = active.advance();
    for (var i = 0; i < a.stages.length; i++) {
      if (top(a.stages[i].result) != top(b.stages[i].result)) {
        throw StateError(
            'Funk mit Antwort 0 ändert ${a.stages[i].race.race.info.name}');
      }
    }
    for (var i = 0; i < c.stages.length && i < a.stages.length; i++) {
      final s = c.stages[i];
      if (!s.result.placings.any((p) => p.rider.teamId == team.id)) continue;
      top(a.stages[i].result) == top(s.result) ? same++ : changed++;
      // 2. What if: the same stage without interventions must equal the silent
      //    run as long as the history before it is the same (first stage).
      if (whatIf == null &&
          s.stageIndex == 0 &&
          top(a.stages[i].result) != top(s.result)) {
        final again = active.whatIf(s.race.race.info.id, 0, radio: const {});
        final replay = active.whatIf(s.race.race.info.id, 0);
        whatIf = '${s.race.race.info.name}: ohne Funk wie stiller Lauf '
            '${top(again) == top(a.stages[i].result)}, Wiederholung gleich '
            '${top(replay) == top(s.result)}; gefahren Platz '
            '${s.result.placings.indexWhere((p) => p.rider.teamId == team.id) + 1}, '
            'ohne Funk Platz ${again.placings.indexWhere((p) => p.rider.teamId == team.id) + 1}';
      }
    }
  }
  print(
      '\nFunk Januar–März: $asked Rückfragen $calls (Möglichkeiten $options), '
      'eigene Renntage verändert $changed, gleich $same');
  print('Was wäre wenn: $whatIf');

  // 3. Licences, development team and delegation over whole seasons.
  final career = start()
    ..delegation.radio = RadioMode.off
    ..delegation.training = true
    ..delegation.scouting = true;
  final dev = career.devTeam;
  print('\nNachwuchsteam: ${dev.team?.name} (${dev.squad.length} Fahrer); '
      '${dev.links.length} Partnerschaften');
  for (var y = 0; y < years; y++) {
    final watch = Stopwatch()..start();
    var promoted = false;
    while (!career.seasonOver) {
      career.advance();
      if (!promoted && career.economy.windowOpen && dev.squad.isNotEmpty) {
        promoted = true;
        final best = dev.squad
          ..sort((a, b) => Economy.rating(b).compareTo(Economy.rating(a)));
        print(
            '  Hochziehen ${best.first.name}: ${dev.promote(best.first.id) ?? 'ok'}');
      }
    }
    final loads = <TrainingLoad, int>{};
    for (final r in career.squads[team.id]!) {
      final l = career.shapeOf(r.id).load;
      loads[l] = (loads[l] ?? 0) + 1;
    }
    final rows = career.licences.ranking();
    print(
        '\n${career.year} in ${watch.elapsed.inSeconds} s · Trainer: $loads · '
        'beobachtet: ${career.staff.scouted.length} · Zyklus '
        '${career.licences.cycleStart}–${career.licences.cycleEnd}');
    for (final (i, r) in rows.indexed) {
      if (i < 3 || (i >= 15 && i < 21) || r.teamId == team.id) {
        print(
            '  ${(i + 1).toString().padLeft(2)} ${career.teams[r.teamId]!.name.padRight(34)} '
            '${r.licence.label.padRight(10)} ${r.perYear.map((p) => p.round()).join(' + ')} = ${r.total.round()}');
      }
    }
    final before = career.inbox.length;
    career.startNextSeason();
    for (final m in career.inbox.skip(before)) {
      if (m.from == 'UCI' || m.from == 'Nachwuchsteam')
        print('  [${m.from}] ${m.subject}: ${m.body}');
    }
    print(
        '  Einladungen: ${career.licences.wildcards.map((id) => career.teams[id]!.abbr).join(', ')} · '
        'eigene Rennen ${career.ownRaces.length} · Nachwuchs ${dev.squad.length}');
  }
  world.close();
}
