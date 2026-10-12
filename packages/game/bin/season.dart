// Plays a whole season without a user interface and prints a summary.
//
// Usage: dart run bin/season.dart [team abbreviation] [seed]
import 'dart:io';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

void main(List<String> args) {
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final abbr = args.isEmpty ? 'RBH' : args[0];
  final team = world.teams().firstWhere((t) => t.abbr == abbr);
  final career = Career(
    world,
    teamId: team.id,
    seed: args.length > 1 ? int.parse(args[1]) : 1,
    tuning: SimTuning.load('${root}calibration/tuning.json'),
  );
  final watch = Stopwatch()..start();
  var stages = 0, slowestMs = 0, busiest = 0;
  while (!career.seasonOver) {
    final dayWatch = Stopwatch()..start();
    final day = career.advance();
    stages += day.stages.length;
    if (dayWatch.elapsedMilliseconds > slowestMs) {
      slowestMs = dayWatch.elapsedMilliseconds;
      busiest = day.stages.length;
    }
  }
  final started = career.progress.values;
  print('Saison ${career.year} mit ${team.name}: '
      '${started.length} von ${career.calendar.length} Rennen, $stages Renntage '
      'in ${watch.elapsed.inSeconds} s '
      '(längster Tag ${slowestMs / 1000} s bei $busiest Rennen)');

  final names = {for (final r in world.riders()) r.id: r};
  print('\nGroße Rennen');
  for (final p in started.where((p) => p.race.tier.factor >= 8)) {
    final winner = p.race.isStageRace
        ? p.run.standings.last.general.first.rider
        : p.run.results.last.placings.first.rider;
    print('  ${p.race.info.name.padRight(34)} ${winner.name} (${winner.team})');
  }
  print('\nFahrerrangliste');
  final riders = career.riderPoints.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in riders.take(12)) {
    final r = names[e.key]!;
    print('  ${e.value.round().toString().padLeft(6)}  ${r.name} (${r.team})');
  }
  print('\nTeamrangliste');
  final teams = career.teamPoints.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in teams.take(8)) {
    print(
        '  ${e.value.round().toString().padLeft(6)}  ${career.teams[e.key]!.name}');
  }
  final place = teams.indexWhere((e) => e.key == team.id);
  print('\n${team.name}: Platz ${place + 1}, '
      '${career.inbox.length} Nachrichten im Postfach, davon '
      '${career.inbox.where((m) => m.subject.endsWith('Sieg')).length} Siege');
  world.close();
}
