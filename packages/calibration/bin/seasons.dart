// Shows how well the fields of the earlier seasons are covered by the world
// database, which knows the riders as they are in the current season.
//
// Usage: dart run bin/seasons.dart
//
// Per season: the number of races, the share of the real finishers found in
// the database, how often the real winner and the real top ten are among
// them, and how many of the riders found were very young or old at the
// time (their strength then differed most from what the database holds).
import 'dart:io';

import 'package:calibration/calibration.dart';
import 'package:sim/sim.dart';

void main() {
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final exclude = loadExclusions('${root}calibration/exclude.txt');
  stdout.writeln('Jahr   Rennen  zugeordnet  Sieger dabei  Top 10 dabei  '
      'unter 24 damals  über 33 heute');
  for (var year = 2021; year <= currentSeason; year++) {
    final dir = Directory('${root}results/$year');
    if (!dir.existsSync()) continue;
    final cases = loadDataset(world, dir.path, year, exclude: exclude).cases;
    if (cases.isEmpty) continue;
    var matched = 0.0, winner = 0, top10 = 0.0, young = 0.0, old = 0.0;
    for (final c in cases) {
      final all = c.allTimes.isEmpty ? c.realTimes : c.allTimes;
      matched += c.riders.length / all.length;
      // The real winner is in the field if the best matched time is his.
      if ((c.realTimes.first - all.first).abs() < 0.5) winner++;
      // Of the ten best real times, how many belong to a matched rider.
      final limit = all[all.length > 9 ? 9 : all.length - 1];
      top10 +=
          c.realTimes.where((t) => t <= limit + 0.5).length.clamp(0, 10) / 10;
      var y = 0, o = 0, known = 0;
      for (final r in c.riders) {
        if (r.born == 0) continue;
        known++;
        final birth = r.born ~/ 10000;
        if (year - birth < 24) y++;
        if (currentSeason - birth > 33) o++;
      }
      if (known > 0) {
        young += y / known;
        old += o / known;
      }
    }
    String pct(double x) => '${(100 * x / cases.length).round()} %'.padLeft(6);
    stdout.writeln('$year   ${'${cases.length}'.padLeft(6)}  '
        '${pct(matched).padLeft(10)}  ${pct(winner.toDouble()).padLeft(12)}  '
        '${pct(top10).padLeft(12)}  ${pct(young).padLeft(15)}  '
        '${pct(old).padLeft(13)}');
  }
  world.close();
}
