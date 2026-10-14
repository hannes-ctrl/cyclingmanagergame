// Whether the time limit takes too many riders, and too many sprinters, out
// of the stage races.
//
//   dart run bin/timecut.dart [--runs n]
//
// For every real mountain and hilly stage of a stage race: how many riders
// finished outside the limit of the stage in reality and in the
// simulation, all of them and the sprinters among them.
import 'dart:io';

import 'package:calibration/calibration.dart';
import 'package:sim/sim.dart';

/// Command-line entry point.
///
/// @param argv Options.
/// @returns A future that completes when the table is printed.
Future<void> main(List<String> argv) async {
  final i = argv.indexOf('--runs');
  final runs = i < 0 ? 2 : int.parse(argv[i + 1]);
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
  bool sprinter(SimRider r) =>
      r.attributes.sprint >= 76 && r.attributes.mountain < 70;

  stdout.writeln(
      'Typ     Etappen   außerhalb echt   Sim    Sprinter echt   Sim   '
      '(je Etappe, in % der Fahrer)');
  for (final type in ['Hügel', 'Berg']) {
    final picked = [
      for (final c in cases)
        if (c.type == type && c.gcGaps.isNotEmpty) c,
    ];
    var realOut = 0.0, simOut = 0.0, realSprint = 0.0, simSprint = 0.0;
    var sprinters = 0, riders = 0, simRuns = 0;
    for (final c in picked) {
      final winner = c.realTimes.first;
      final share = timeLimitShare(c.route, c.route.raceKm / (winner / 3600));
      final limit = winner * (1 + share);
      final byId = {for (final r in c.riders) r.id: r};
      for (var k = 0; k < c.realOrder.length; k++) {
        final r = byId[c.realOrder[k]];
        if (r == null) continue;
        riders++;
        final out = c.realTimes[k] > limit;
        if (out) realOut++;
        if (sprinter(r)) {
          sprinters++;
          if (out) realSprint++;
        }
      }
      for (var run = 0; run < runs; run++) {
        simRuns++;
        final result = simulateStage(c.route, c.riders,
            seed: 11 + 7919 * run + c.label.hashCode % 100000,
            tuning: tuning,
            gcGaps: c.gcGaps,
            month: c.month,
            country: c.country);
        final w = result.winnerTimeS;
        final cut =
            w * (1 + timeLimitShare(c.route, c.route.raceKm / (w / 3600)));
        for (final p in result.placings) {
          if (p.timeS > cut) {
            simOut += 1 / runs;
            if (sprinter(p.rider)) simSprint += 1 / runs;
          }
        }
      }
    }
    String pct(double x, int n) =>
        n == 0 ? '–' : '${(100 * x / n).toStringAsFixed(1)} %';
    stdout.writeln(
        '${type.padRight(7)} ${picked.length.toString().padLeft(7)}   '
        '${pct(realOut, riders).padLeft(14)} ${pct(simOut, riders).padLeft(7)}   '
        '${pct(realSprint, sprinters).padLeft(12)} ${pct(simSprint, sprinters).padLeft(6)}   '
        '($simRuns Läufe, $sprinters Sprinter-Starts)');
  }
}
