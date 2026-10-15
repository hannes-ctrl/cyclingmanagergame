// Plays several seasons without a player and reports whether the world
// holds: squad strength per tier, squad sizes, ages, retirements and the
// intake, top riders, licence moves, morale, and the finances of the team
// the board runs. Every later balance change is judged by it.
//
//   dart run bin/world.dart [--seasons n] [--seed s] [--team ABBR] [--csv file]
//
// All decisions are delegated: line-ups, radio, training, scouting, season
// plan and contract renewals. The stages run on other isolates.
import 'dart:io';
import 'dart:math';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

/// Command-line entry point.
///
/// @param argv Options.
/// @returns A future that completes after the last season.
Future<void> main(List<String> argv) async {
  final args = [...argv];
  String? option(String name) {
    final i = args.indexOf(name);
    if (i < 0) return null;
    final v = args[i + 1];
    args.removeRange(i, i + 2);
    return v;
  }

  final seasons = int.parse(option('--seasons') ?? '10');
  final seed = int.parse(option('--seed') ?? '3');
  final abbr = option('--team') ?? 'RBH';
  final csv = option('--csv');
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
  c.economy.autoRenew = true;

  final rows = <List<Object>>[];
  const header = [
    'Saison',
    'Fahrer',
    'WT',
    'Pro',
    'Conti',
    'Kader WT',
    'Kader Pro',
    'unter 8',
    'Alter',
    'bis 23',
    'ab 33',
    'ab 84',
    'ab 80',
    'Bester',
    'Neu',
    'Rücktritt',
    'Auf/Ab',
    'Moral',
    'unzufrieden',
    'Platz',
    'Konto',
    'Budget',
    'Gehälter',
    'Talente',
    'bei Profis',
    'Talent bester',
    'Min',
  ];
  stdout.writeln(header.join('\t'));
  var known = {...c.riderById.keys};
  var licences = {
    for (final t in c.teams.values) t.id: c.licences.of(t.id),
  };
  for (var s = 0; s < seasons; s++) {
    final watch = Stopwatch()..start();
    while (!c.seasonOver) {
      await c.advanceAsync();
    }
    // The season as it ended, before the turn of the year.
    double mean(Iterable<double> x) =>
        x.isEmpty ? 0 : x.reduce((a, b) => a + b) / x.length;
    List<int> tier(String prefix) => [
          for (final t in c.teams.values)
            if (t.division.startsWith(prefix)) t.id,
        ];
    final wt = tier('[1]'), pro = tier('[2]'), conti = tier('[3]');
    final pros = [
      for (final id in [...wt, ...pro]) ...?c.squads[id],
    ];
    final ratings = [for (final r in pros) Economy.rating(r)]..sort();
    int age(SimRider r) => c.year - r.born ~/ 10000;
    final moods = [for (final r in pros) c.people.moraleOf(r.id)];
    final rank = c.economy.ownRank;
    final balance = c.economy.balance, budget = c.economy.budget;
    final wages = c.economy.wageBill(c.teamId);
    final year = c.year;
    // The exceptional talents of the intake: potential 6, up to 25.
    final talents = [
      for (final r in c.riderById.values)
        if (r.potential >= 6 && age(r) <= 25) r,
    ];
    final proIds = {...wt, ...pro};
    // Turn of the year: contracts, retirements, intake, licences.
    c.startNextSeason();
    final now = {...c.riderById.keys};
    final added = now.difference(known).length;
    final gone = known.difference(now).length;
    known = now;
    var moves = 0;
    for (final t in c.teams.values) {
      final l = c.licences.of(t.id);
      if (licences[t.id] != null && licences[t.id] != l) moves++;
      licences[t.id] = l;
    }
    final row = <Object>[
      year,
      pros.length,
      mean(wt.map(c.teamStrength)).toStringAsFixed(1),
      mean(pro.map(c.teamStrength)).toStringAsFixed(1),
      mean(conti.map(c.teamStrength)).toStringAsFixed(1),
      mean(wt.map((id) => (c.squads[id]?.length ?? 0).toDouble()))
          .toStringAsFixed(1),
      mean(pro.map((id) => (c.squads[id]?.length ?? 0).toDouble()))
          .toStringAsFixed(1),
      [...wt, ...pro].where((id) => (c.squads[id]?.length ?? 0) < 8).length,
      mean(pros.map((r) => age(r).toDouble())).toStringAsFixed(1),
      pros.where((r) => age(r) <= 23).length,
      pros.where((r) => age(r) >= 33).length,
      ratings.where((x) => x >= 84).length,
      ratings.where((x) => x >= 80).length,
      ratings.isEmpty ? 0 : ratings.last.toStringAsFixed(1),
      added,
      gone,
      moves,
      mean(moods).toStringAsFixed(2),
      moods.where((m) => m <= -0.4).length,
      rank,
      (balance / 1e6).toStringAsFixed(1),
      (budget / 1e6).toStringAsFixed(1),
      (wages / 1e6).toStringAsFixed(1),
      talents.length,
      talents.where((r) => proIds.contains(r.teamId)).length,
      talents.isEmpty
          ? 0
          : talents.map(Economy.rating).reduce(max).toStringAsFixed(1),
      watch.elapsed.inMinutes,
    ];
    rows.add(row);
    stdout.writeln(row.join('\t'));
    if (csv != null) {
      File(csv)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync([
          header.join(';'),
          for (final r in rows) r.join(';'),
        ].join('\n'));
    }
  }
  c.planner.saveWeights();
  world.close();
}
