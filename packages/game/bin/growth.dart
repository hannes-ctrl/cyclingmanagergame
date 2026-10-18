import 'dart:io';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

/// Plays several seasons and prints how the strength of the riders moves:
/// the level of the best riders must stay about the same from year to year,
/// or development and decline are out of balance.
///
/// Usage: dart run bin/growth.dart [seasons] [rider id to follow]
void main(List<String> args) {
  final seasons = args.isEmpty ? 5 : int.parse(args[0]);
  final follow = args.length > 1 ? int.parse(args[1]) : 9396;
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final team = world.teams().firstWhere((t) => t.abbr == 'RBH');
  final c = Career(world,
      teamId: team.id,
      seed: 3,
      tuning: SimTuning.load('${root}calibration/tuning.json'))
    ..delegation.lineups = true
    ..delegation.radio = RadioMode.off
    ..delegation.training = true;
  void line() {
    final pros = [
      for (final t in c.teams.values)
        if (t.division.startsWith('[1]') || t.division.startsWith('[2]'))
          ...?c.squads[t.id],
    ];
    final ratings = pros.map(Economy.rating).toList()
      ..sort((a, b) => b.compareTo(a));
    double mean(Iterable<double> x) => x.reduce((a, b) => a + b) / x.length;
    double best(SimRider r) {
      var m = 0.0;
      r.attributes.adjusted((_, v) {
        if (v > m) m = v;
        return v;
      });
      return m;
    }

    final ages = pros.map((r) => (c.year - r.born ~/ 10000).toDouble());
    final r = c.riderById[follow];
    stdout.writeln('${c.year}  pros ${pros.length}  '
        'Top 20 ${mean(ratings.take(20)).toStringAsFixed(2)}  '
        'Top 100 ${mean(ratings.take(100)).toStringAsFixed(2)}  '
        'all ${mean(ratings).toStringAsFixed(2)}  '
        'best value >= 84: ${pros.where((r) => best(r) >= 84).length}  '
        '>= 80: ${pros.where((r) => best(r) >= 80).length}  '
        'age ${mean(ages).toStringAsFixed(1)}'
        '${r == null ? '' : '  | ${r.name}: mountain ${r.attributes.mountain.toStringAsFixed(1)} '
            'hill ${r.attributes.hill.toStringAsFixed(1)} flat ${r.attributes.flat.toStringAsFixed(1)} '
            'TT ${r.attributes.timeTrial.toStringAsFixed(1)} sprint ${r.attributes.sprint.toStringAsFixed(1)}'}');
  }

  line();
  for (var y = 0; y < seasons; y++) {
    while (!c.seasonOver) {
      c.advance();
    }
    c.startNextSeason();
    line();
  }
}
