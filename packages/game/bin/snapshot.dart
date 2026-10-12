// Checks the snapshot: a career that is saved, restored into a fresh object
// and played on must match the original played on without interruption.
//
// Usage: dart run bin/snapshot.dart [team abbreviation] [days before] [days after]
import 'dart:convert';
import 'dart:io';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

/// @param c A career.
/// @returns A text that changes whenever the observable state changes.
String fingerprint(Career c) {
  final attrs = c.riderById.values
      .fold(0.0, (sum, r) => sum + r.attributes.mountain + r.attributes.sprint);
  final gc = c.progress.values
      .where((p) => p.stagesDone > 0)
      .map((p) =>
          '${p.race.info.id}:${p.run.standings.last.general.first.rider.id}:'
          '${p.run.standings.last.points.firstOrNull?.points}')
      .join(',');
  return [
    c.today,
    c.year,
    c.teamPoints.entries.map((e) => '${e.key}=${e.value}').join(','),
    c.riderPoints.length,
    c.riderPoints.values.fold(0.0, (a, b) => a + b),
    c.inbox.map((m) => m.subject).join('|'),
    c.economy.balance,
    c.economy.budget,
    c.economy.wageBill(c.teamId),
    attrs,
    c.riderById.length,
    c.staff.all.where((s) => s.busyUntil != null).length,
    c.palmares.length,
    c.titles.length,
    gc,
    c.squads[c.teamId]!.map((r) => r.id).join(','),
  ].join('\n');
}

void main(List<String> args) {
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final abbr = args.isEmpty ? 'RBH' : args[0];
  final before = args.length > 1 ? int.parse(args[1]) : 150;
  final after = args.length > 2 ? int.parse(args[2]) : 60;
  final team = world.teams().firstWhere((t) => t.abbr == abbr);
  final tuning = SimTuning.load('${root}calibration/tuning.json');
  Career start() => Career(world, teamId: team.id, seed: 9, tuning: tuning)
    ..delegation.radio = RadioMode.off
    ..delegation.training = true
    ..delegation.scouting = true;

  /// Plays days, starting a new season when one ends.
  void play(Career c, int days) {
    for (var i = 0; i < days; i++) {
      if (c.seasonOver) c.startNextSeason();
      c.advance();
    }
  }

  final a = start();
  play(a, before);
  var watch = Stopwatch()..start();
  final text = jsonEncode(a.toJson());
  final races = [for (final p in a.progress.values) jsonEncode(a.raceJson(p))];
  final raceBytes = races.fold(0, (sum, r) => sum + r.length);
  print('Stand am ${a.today.toIso8601String().substring(0, 10)}: '
      '${(text.length / 1048576).toStringAsFixed(1)} MB und '
      '${races.length} Rennen mit ${(raceBytes / 1048576).toStringAsFixed(1)} MB, '
      'geschrieben in ${watch.elapsedMilliseconds} ms');

  watch = Stopwatch()..start();
  final b = start()
    ..restore(jsonDecode(text) as Map<String, dynamic>,
        [for (final r in races) jsonDecode(r) as Map<String, dynamic>]);
  print('geladen in ${watch.elapsedMilliseconds} ms');
  final same = fingerprint(a) == fingerprint(b);
  print('gleich nach dem Laden: $same');
  // A second round trip must give the identical text.
  print('zweites Speichern identisch: ${jsonEncode(b.toJson()) == text && [
        for (final p in b.progress.values) jsonEncode(b.raceJson(p))
      ].join() == races.join()}');
  watch = Stopwatch()..start();
  jsonEncode(a.toJson());
  print('nur der Zustand ohne Rennen: ${watch.elapsedMilliseconds} ms');

  play(a, after);
  play(b, after);
  final fa = fingerprint(a).split('\n'), fb = fingerprint(b).split('\n');
  var equal = true;
  for (var i = 0; i < fa.length; i++) {
    if (fa[i] != fb[i]) {
      equal = false;
      print(
          'Abweichung in Zeile $i:\n  ${fa[i].length > 160 ? '${fa[i].substring(0, 160)}…' : fa[i]}'
          '\n  ${fb[i].length > 160 ? '${fb[i].substring(0, 160)}…' : fb[i]}');
    }
  }
  print(
      'gleich nach $after weiteren Tagen (${a.today.toIso8601String().substring(0, 10)}): $equal');
  world.close();
  if (!same || !equal) exitCode = 1;
}
