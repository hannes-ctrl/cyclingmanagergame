// Compares the riders of the WorldDB with the riders the game creates:
// rating, potential and the share of top riders by age, for the real
// riders at the start of a career and for a simulated intake that develops
// by the game's rules. If an intake cohort ends up stronger than the real
// riders of the same age, the field grows from year to year.
//
//   dart run bin/cohorts.dart [--factor f]
//
// --factor is the product of coach, training load, facilities and morale
// on development (1.0 is an average team).
import 'dart:io';
import 'dart:math';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

/// Command-line entry point.
///
/// @param argv Options.
void main(List<String> argv) {
  final at = argv.indexOf('--factor');
  final factor = at < 0 ? 1.0 : double.parse(argv[at + 1]);
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final team = world.teams().firstWhere((t) => t.abbr == 'RBH');
  final c = Career(world,
      teamId: team.id,
      seed: 3,
      tuning: SimTuning.load('${root}calibration/tuning.json'));
  final free = c.teams.values.firstWhere((t) => t.division == 'Free').id;
  final riders = [
    for (final r in c.riderById.values)
      if (r.teamId != free) r,
  ];
  stdout.writeln('WorldDB ${c.year}, riders in teams: ${riders.length}');
  _table(riders, (r) => c.year - r.born ~/ 10000);

  // The real young riders, developed by the game's rules: if they end up
  // stronger than the real riders who are that old now, development is
  // too fast.
  final grown = <int, List<SimRider>>{};
  for (final r in riders) {
    final age = c.year - r.born ~/ 10000;
    if (age < 19 || age > 22) continue;
    var x = r;
    for (var a = age; a < 28; a++) {
      for (var m = 0; m < 12; m++) {
        x = _month(x, a, factor);
      }
      // The four cohorts 19 to 22 at the age of 28, as four cohorts.
    }
    grown.putIfAbsent(age, () => []).add(x);
  }
  stdout.writeln('\nWorldDB riders aged 19 to 22, developed to 28 '
      '(factor $factor), by their age now:');
  _table(const [], (r) => 0, byAge: grown, per: 1);

  // A simulated intake: ten years of 150 riders, made as Economy._intake
  // makes them, at 18 or 19, developed month by month without races.
  final rng = Random(7);
  final sim = <({SimRider r, int born})>[];
  for (var n = 0; n < 1500; n++) {
    final age = 18 + rng.nextInt(2);
    final y = c.economy.youngRider(rng, age);
    sim.add((
      r: SimRider(
        id: n,
        name: '',
        teamId: 0,
        team: '',
        attributes: y.attributes,
        born: 0,
        potential: y.potential,
        country: '',
        weightKg: y.weight,
        heightCm: y.height,
      ),
      born: age,
    ));
  }
  // Age every rider from 18 to 38 and keep a snapshot per age.
  final byAge = <int, List<SimRider>>{};
  for (var (i, e) in sim.indexed) {
    var r = e.r;
    for (var age = e.born; age <= 38; age++) {
      byAge.putIfAbsent(age, () => []).add(r);
      for (var m = 0; m < 12; m++) {
        r = _month(r, age, factor);
      }
    }
    sim[i] = (r: r, born: e.born);
  }
  stdout.writeln('\nIntake, developed with factor $factor '
      '(one cohort of 1500, as ten years of intake):');
  _table([
    for (final e in byAge.entries) ...e.value,
  ], (r) => -1, byAge: byAge);
  world.close();
}

/// One month of development as Career._develop applies it, without
/// training focus.
SimRider _month(SimRider r, int age, double factor) {
  final perYear = switch (age) {
    <= 19 => 1.5,
    20 => 1.35,
    21 => 1.2,
    22 => 0.85,
    23 => 0.65,
    24 => 0.5,
    25 => 0.3,
    26 => 0.18,
    27 => 0.05,
    <= 29 => 0.0,
    30 => -0.15,
    <= 32 => -0.35,
    <= 34 => -0.7,
    _ => -1.2,
  };
  if (perYear == 0) return r;
  final talent = ((r.potential - 2) / 3).clamp(0.2, 1.4);
  final step = perYear > 0 ? perYear / 12 * talent * factor : perYear / 12;
  var lo = 100.0, hi = 0.0;
  r.attributes.adjusted((_, v) {
    lo = min(lo, v);
    hi = max(hi, v);
    return v;
  });
  return r.withAttributes(r.attributes.adjusted((name, v) {
    if (step > 0) {
      final profile = hi == lo ? 1.0 : 0.3 + 0.7 * (v - lo) / (hi - lo);
      return (v + Career.capped(r, v, step * profile)).clamp(50.0, 86.0);
    }
    final f = name == 'sprint' || name == 'acceleration'
        ? 1.5
        : name == 'endurance'
            ? 0.5
            : 1.0;
    return (v + step * f).clamp(50.0, 86.0);
  }));
}

/// Prints rating, potential and top riders by age.
void _table(List<SimRider> riders, int Function(SimRider) ageOf,
    {Map<int, List<SimRider>>? byAge, int? per}) {
  final groups = byAge ??
      <int, List<SimRider>>{
        for (final r in riders) ageOf(r): [],
      };
  if (byAge == null) {
    for (final r in riders) {
      groups[ageOf(r)]!.add(r);
    }
  }
  // Per cohort of 150 riders (the yearly intake): the rating at ranks 1,
  // 3, 10, 30, 75 and 150, and the potential of the best 30.
  stdout.writeln('Age\tCount\t#1\t#3\t#10\t#30\t#75\t#150\tPot.Top30');
  for (final age in groups.keys.toList()..sort()) {
    if (age < 18 || age > 38) continue;
    final g = [...groups[age]!]
      ..sort((a, b) => Economy.rating(b).compareTo(Economy.rating(a)));
    // A simulated cohort of 1500 stands for ten intakes of 150.
    final n = per ?? (byAge == null ? 1 : 10);
    String at(int rank) {
      final i = rank * n - 1;
      return i < g.length ? Economy.rating(g[i]).toStringAsFixed(1) : '-';
    }

    final top = g.take(30 * n);
    stdout.writeln([
      age,
      g.length ~/ n,
      at(1),
      at(3),
      at(10),
      at(30),
      at(75),
      at(150),
      (top.map((r) => r.potential).reduce((a, b) => a + b) / top.length)
          .toStringAsFixed(2),
    ].join('\t'));
  }
}
