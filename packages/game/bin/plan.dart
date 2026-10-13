// Prints the season plan the sports director draws up for a team.
//
// Usage: dart run bin/plan.dart [team abbreviation] [seed]
//
// Shows the line-ups of the most important races and, per rider, the race
// days and the races he is planned for, to judge whether the programme is
// sensible and evenly spread.
import 'dart:io';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

void main(List<String> args) {
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final abbr = args.isEmpty ? 'RBH' : args[0];
  final team = world.teams().firstWhere((t) => t.abbr == abbr);
  final career = Career(world,
      teamId: team.id, seed: args.length > 1 ? int.parse(args[1]) : 1);
  final watch = Stopwatch()..start();
  final planned = career.planSeason();
  stdout.writeln('${team.name}: $planned Rennen geplant in '
      '${watch.elapsedMilliseconds} ms');
  final sum = career.programSummary();
  stdout.writeln('${sum.races} Rennen, ${sum.days} Renntage, im Schnitt '
      '${sum.mean.toStringAsFixed(1)} je Fahrer, höchstens ${sum.most}\n');

  final races = [...career.ownRaces]..sort((a, b) =>
      career.planner.importance(b).compareTo(career.planner.importance(a)));
  stdout.writeln('Die wichtigsten Rennen:');
  for (final race in races.take(14)) {
    final riders = [
      for (final id in career.program[race.info.id] ?? const <int>{})
        career.riderById[id]!,
    ]..sort((a, b) =>
        career.planner.fit(race, b).compareTo(career.planner.fit(race, a)));
    stdout.writeln('  ${race.info.name.padRight(34)} '
        '${riders.map((r) => r.lastName).join(', ')}');
  }

  stdout.writeln('\nJe Fahrer (Alter, Stärke, Renntage, Rennen):');
  final squad = [...?career.squads[team.id]]
    ..sort((a, b) => Economy.rating(b).compareTo(Economy.rating(a)));
  for (final r in squad) {
    final mine = [
      for (final race in career.ownRaces)
        if (career.program[race.info.id]?.contains(r.id) ?? false) race,
    ];
    final days = mine.fold(0, (n, x) => n + x.stages.length);
    final big = [
      for (final x in mine)
        if (x.tier.factor >= 8) x.info.abbr.isEmpty ? x.info.name : x.info.abbr,
    ];
    stdout.writeln('  ${r.name.padRight(22)} ${career.year - r.born ~/ 10000}  '
        '${Economy.rating(r).round()}  ${'$days'.padLeft(3)} Tage  '
        '${'${mine.length}'.padLeft(2)} Rennen  ${big.join(', ')}');
  }
  world.close();
}
