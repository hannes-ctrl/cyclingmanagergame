// Compares tuning files on fresh random numbers.
//
//   dart run bin/compare.dart [--runs n] [--seeds n] file1.json file2.json ...
//
// A calibration run reports its error on the random numbers it searched
// with, which flatters the result. This evaluates every file on the same
// new draws, on all races and on the held-back ones, so that settings can
// be compared honestly. "standard" stands for the default values.
import 'dart:io';

import 'package:calibration/calibration.dart';
import 'package:sim/sim.dart';

/// Command-line entry point.
///
/// @param argv Options and the tuning files to compare.
/// @returns A future that completes when all files have been evaluated.
Future<void> main(List<String> argv) async {
  final args = [...argv];
  int option(String name, int fallback) {
    final i = args.indexOf(name);
    if (i < 0) return fallback;
    final v = int.parse(args[i + 1]);
    args.removeRange(i, i + 2);
    return v;
  }

  final runs = option('--runs', 6);
  final seeds = option('--seeds', 4);
  if (args.isEmpty) {
    stdout.writeln(
        'Usage: dart run bin/compare.dart [--runs n] [--seeds n] file.json ... (or standard)');
    return;
  }
  const year = 2026;
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final exclude = loadExclusions('${root}calibration/exclude.txt');
  final parts = [
    for (var y = firstSeason; y <= year; y++)
      if (Directory('${root}results/$y').existsSync())
        loadDataset(world, '${root}results/$y', y, exclude: exclude),
  ];
  final data = Dataset(
    [for (final p in parts) ...p.cases],
    [for (final p in parts) ...p.notes],
  );
  world.close();
  stdout
      .writeln('${data.cases.length} races, ${data.validation.length} of them '
          'for control; $seeds draws of $runs runs each\n');
  stdout.writeln('${'Setting'.padRight(34)}  error per draw   '
      '${' ' * (seeds * 7 - 17).clamp(1, 99)}  mean  control');
  for (final name in args) {
    final tuning = name == 'standard'
        ? SimTuning().toMap()
        : SimTuning.load(name.contains('/') || name.contains('\\')
                ? name
                : '${root}calibration/$name')
            .toMap();
    final all = <double>[], held = <double>[];
    for (var s = 0; s < seeds; s++) {
      final e = await evaluate(data.cases, tuning,
          runs: runs, seed: 900001 + s * 7919);
      all.add(e.loss);
      // The held-back races, scored from the same simulations.
      final ids = {for (final c in data.validation) c.label};
      final part = Evaluation([
        for (final x in e.scores)
          if (ids.contains(x.label)) x,
      ]);
      held.add(part.loss);
    }
    double mean(List<double> x) => x.reduce((a, b) => a + b) / x.length;
    String f(double x) => x.toStringAsFixed(2).padLeft(6);
    stdout.writeln('${name.split(RegExp(r'[\\/]')).last.padRight(34)}  '
        '${all.map(f).join(' ')}  ${f(mean(all))}  ${f(mean(held))}');
  }
}
