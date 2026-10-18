// How breakaways fare in the simulation, for the work on the model.
//
//   dart run bin/breaks.dart [--sample k] [--runs n] [--types Hilly,Mountain]
//
// For a sample of real races: how often a break goes, how big it is, its
// lead along the route and where it is caught, against how often a
// breakaway rider won in reality.
import 'dart:io';
import 'dart:math';

import 'package:calibration/calibration.dart';
import 'package:sim/sim.dart';

/// Command-line entry point.
///
/// @param argv Options.
/// @returns A future that completes when the table is printed.
Future<void> main(List<String> argv) async {
  final args = [...argv];
  String? option(String name) {
    final i = args.indexOf(name);
    if (i < 0) return null;
    final v = args[i + 1];
    args.removeRange(i, i + 2);
    return v;
  }

  final sample = int.parse(option('--sample') ?? '2');
  final runs = int.parse(option('--runs') ?? '3');
  final types = (option('--types') ?? 'Flat,Hilly,Mountain').split(',');
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final exclude = loadExclusions('${root}calibration/exclude.txt');
  final cases = <CalibrationCase>[];
  for (var y = firstSeason; y <= 2026; y++) {
    if (!Directory('${root}results/$y').existsSync()) continue;
    cases.addAll(
        loadDataset(world, '${root}results/$y', y, exclude: exclude).cases);
  }
  world.close();
  final tuning = SimTuning.load('${root}calibration/tuning.json');

  String clock(double seconds) {
    final s = seconds.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  stdout.writeln('Type        Races  win real   win sim   group   size  '
      'largest lead       at 70 %    at 85 %    at 95 %  caught km to go');
  for (final type in types) {
    final picked = [
      for (var i = 0; i < cases.length; i++)
        if (cases[i].type == type && i % sample == 0) cases[i],
    ];
    if (picked.isEmpty) continue;
    var real = 0, won = 0, formed = 0, n = 0;
    final sizes = <double>[], maxGaps = <double>[], caughtKm = <double>[];
    final at = {0.7: <double>[], 0.85: <double>[], 0.95: <double>[]};
    for (final c in picked) {
      if (c.winnerFromBreak) real++;
      for (var r = 0; r < runs; r++) {
        n++;
        final result = simulateStage(c.route, c.riders,
            seed: 7 + 7919 * r + c.label.hashCode % 100000,
            tuning: tuning,
            gcGaps: c.gcGaps,
            month: c.month,
            country: c.country);
        if (result.breakSurvived) won++;
        final gone = result.events
            .where((e) => e.type == EventType.breakaway)
            .firstOrNull;
        if (gone == null) continue;
        formed++;
        final size = int.tryParse(gone.text.split(' ').first);
        if (size != null) sizes.add(size.toDouble());
        final line = result.timeline;
        if (line.isEmpty) continue;
        maxGaps.add(line.map((x) => x.frontGapS).reduce(max));
        for (final e in at.entries) {
          final km = c.route.raceKm * e.key;
          final x = line.lastWhere((x) => x.km <= km, orElse: () => line.first);
          e.value.add(x.frontGapS);
        }
        final caught =
            result.events.where((e) => e.type == EventType.caught).firstOrNull;
        if (caught != null) caughtKm.add(c.route.raceKm - caught.km);
      }
    }
    double mean(List<double> x) =>
        x.isEmpty ? 0 : x.reduce((a, b) => a + b) / x.length;
    stdout.writeln(
        '${type.padRight(10)} ${picked.length.toString().padLeft(6)}  '
        '${(100 * real / picked.length).round().toString().padLeft(7)} %  '
        '${(100 * won / n).round().toString().padLeft(6)} %  '
        '${(100 * formed / n).round().toString().padLeft(4)} %  '
        '${mean(sizes).toStringAsFixed(1).padLeft(5)}  '
        '${clock(mean(maxGaps)).padLeft(17)}  '
        '${clock(mean(at[0.7]!)).padLeft(8)}   ${clock(mean(at[0.85]!)).padLeft(8)}   '
        '${clock(mean(at[0.95]!)).padLeft(8)}  '
        '${mean(caughtKm).toStringAsFixed(1).padLeft(8)} (${caughtKm.length}×)');
  }
}
