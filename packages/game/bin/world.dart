// Plays several seasons without a player and reports whether the world
// holds: squad strength per tier, squad sizes, ages, retirements and the
// intake, top riders, licence moves, morale, and the finances of the team
// the board runs. Every later balance change is judged by it.
//
//   dart run bin/world.dart [--seasons n] [--seed s] [--team ABBR] [--csv file]
//                           [--roundtrip]
//   dart run bin/world.dart --bands file.csv
//
// At the end the figures of every season are checked against the bands
// below, written down before the beta: a balance change that leaves them
// is a regression. --bands checks a CSV of an earlier run.
//
// With --roundtrip every season is saved on 1 July, in the middle of the
// racing, loaded into a new career and compared with the original.
//
// All decisions are delegated: line-ups, radio, training, scouting, season
// plan, contract renewals and facilities. The stages run on other isolates.
import 'dart:io';
import 'dart:math';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

/// Command-line entry point.
///
/// @param argv Options.
/// @returns A future that completes after the last season.
/// The range every season of a run must stay in, by column: what a world
/// in balance looks like (strength per tier, ages, top riders, money of the
/// WorldTeams, facilities). Written down for the beta; see ROADMAP.md.
const bands = <String, (double, double)>{
  'WT': (76.5, 79.0),
  'Pro': (72.5, 76.5),
  'Conti': (65.5, 70.0),
  'Squad WT': (27.0, 30.0),
  'Age': (27.5, 29.5),
  'from 33': (100, 250),
  'from 80': (8, 28),
  'from 84': (0, 5),
  'Balance WT': (0, 15),
  'in debt': (0, 6),
  'Facilities WT': (2.8, 4.2),
  'Morale': (-0.3, 0.4),
};

/// Checks the seasons of a run against [bands].
///
/// @param header The column names.
/// @param rows One row per season, the season in the first column.
/// @returns Lines naming each band left, empty if all held.
List<String> checkBands(List<String> header, List<List<Object>> rows) {
  final out = <String>[];
  for (final e in bands.entries) {
    final col = header.indexOf(e.key);
    if (col < 0) continue;
    final (low, high) = e.value;
    final off = [
      for (final r in rows)
        if (double.tryParse('${r[col]}') case final v? when v < low || v > high)
          '${r[0]}: $v',
    ];
    if (off.isNotEmpty) {
      out.add('${e.key} outside $low to $high in ${off.length} season(s), '
          'first ${off.first}');
    }
  }
  return out;
}

/// @returns The data folder of the repository.
String root0() => Platform.script.resolve('../../../data/').toFilePath();

Future<void> main(List<String> argv) async {
  final args = [...argv];
  String? option(String name) {
    final i = args.indexOf(name);
    if (i < 0) return null;
    final v = args[i + 1];
    args.removeRange(i, i + 2);
    return v;
  }

  // Only the bands of an earlier run.
  if (option('--bands') case final file?) {
    final lines = File(file).readAsLinesSync();
    final head = lines.first.split(';');
    final broken = checkBands(head, [
      for (final l in lines.skip(1))
        if (l.isNotEmpty) l.split(';'),
    ]);
    stdout.writeln(broken.isEmpty ? 'All bands held.' : broken.join('\n'));
    return;
  }
  final seasons = int.parse(option('--seasons') ?? '10');
  final seed = int.parse(option('--seed') ?? '3');
  final abbr = option('--team') ?? 'RBH';
  final csv = option('--csv');
  final roundtrip = args.remove('--roundtrip');
  final tuning = SimTuning.load('${root0()}calibration/tuning.json');
  I18n.lang = Lang.en;
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final team = world.teams().firstWhere((t) => t.abbr == abbr);
  final c = Career(world, teamId: team.id, seed: seed, tuning: tuning)
    ..delegation.lineups = true
    ..delegation.radio = RadioMode.off
    ..delegation.training = true
    ..delegation.scouting = true
    ..delegation.planning = true
    ..delegation.facilities = true;
  c.economy.autoRenew = true;

  final rows = <List<Object>>[];
  const header = [
    'Season',
    'Riders',
    'in teams',
    'WT',
    'Pro',
    'Conti',
    'Squad WT',
    'Squad Pro',
    'under 8',
    'Age',
    'to 23',
    'from 33',
    'from 84',
    'from 80',
    'Best',
    'New',
    'Retired',
    'Up/down',
    'Morale',
    'unhappy',
    'Place',
    'Balance',
    'Budget',
    'Wages',
    'Talents',
    'with pros',
    'Best talent',
    'Budget WT',
    'Balance WT',
    'Budget Pro',
    'in debt',
    'Facilities WT',
    'Winter from',
    'Min',
  ];
  stdout.writeln(header.join('\t'));
  var known = {...c.riderById.keys};
  var licences = {
    for (final t in c.teams.values) t.id: c.licences.of(t.id),
  };
  for (var s = 0; s < seasons; s++) {
    final watch = Stopwatch()..start();
    // The day the last race is ridden and the winter begins.
    var winter = '-';
    while (!c.seasonOver) {
      await c.advanceAsync();
      if (roundtrip && c.today.month == 7 && c.today.day == 1) {
        final saved = c.toJson();
        final copy = Career(world,
            teamId: c.startTeam, seed: seed, tuning: tuning)
          ..restore(saved, [for (final p in c.progress.values) c.raceJson(p)]);
        final a = saved.toString(), b = copy.toJson().toString();
        if (a != b) {
          var at = 0;
          while (at < a.length && at < b.length && a[at] == b[at]) {
            at++;
          }
          stderr.writeln('${c.year}: save and load differ at $at: '
              '…${a.substring(max(0, at - 80), min(a.length, at + 80))}…');
        }
      }
      if (c.racingOver && winter == '-') {
        winter = '${c.today.day}.${c.today.month}.';
      }
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
    // The money of the other teams, as the season ended.
    final fin = c.finances;
    double median(List<double> x) {
      if (x.isEmpty) return 0;
      x.sort();
      return x[x.length ~/ 2];
    }

    final budgetWt = mean(wt.map(fin.budgetOf));
    final balanceWt = median([for (final id in wt) fin.balanceOf(id)]);
    final budgetPro = mean(pro.map(fin.budgetOf));
    final inDebt = [...wt, ...pro].where((id) => fin.balanceOf(id) < 0).length;
    final facilitiesWt = mean([
      for (final id in wt)
        mean(Facility.values.map((f) => c.facilities.level(id, f).toDouble())),
    ]);
    // Riders under contract in every division, development teams included.
    final inTeams = c.riderById.values
        .where((r) => (c.teams[r.teamId]?.division ?? 'Free') != 'Free')
        .length;
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
      inTeams,
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
      (budgetWt / 1e6).toStringAsFixed(1),
      (balanceWt / 1e6).toStringAsFixed(1),
      (budgetPro / 1e6).toStringAsFixed(1),
      inDebt,
      facilitiesWt.toStringAsFixed(2),
      winter,
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
  final broken = checkBands(header, rows);
  stdout.writeln(broken.isEmpty ? 'All bands held.' : broken.join('\n'));
}
