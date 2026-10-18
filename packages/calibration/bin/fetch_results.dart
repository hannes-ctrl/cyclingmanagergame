// Fetches the results of a season's WorldTour races from ProCyclingStats and
// stores them as JSON under data/results/<year>/.
//
// Usage: dart run bin/fetch_results.dart [year]
import 'dart:convert';
import 'dart:io';

import 'package:calibration/calibration.dart';
import 'package:sim/sim.dart';

/// Command-line entry point.
///
/// @param args Optional year, default 2026.
/// @returns A future that completes when all pages are stored.
Future<void> main(List<String> args) async {
  final year = args.isEmpty ? 2026 : int.parse(args[0]);
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final client = PcsClient('${root}pcs_cache');
  final outDir = Directory('${root}results/$year')..createSync(recursive: true);

  var saved = 0, missing = 0;
  for (final entry in pcsSlugs.entries) {
    final stages = world.stages(entry.key);
    // Earlier seasons: only races whose route of that year is in the
    // database, with as many stages as it had then.
    var count = stages.length;
    if (year != currentSeason) {
      final old = world.variantStages(entry.key, year);
      if (old.isEmpty) continue;
      count = old.keys.reduce((a, b) => a > b ? a : b);
    }
    // One-day races have one page, stage races one per stage; some start with a
    // prologue that is not counted as a stage.
    final pages = stages.length == 1
        ? ['result']
        : ['prologue', for (var i = 1; i <= count; i++) 'stage-$i'];
    for (final page in pages) {
      final html = await client.page(entry.value, year, page);
      final result =
          html == null ? null : parseResultPage(html, entry.key, page, year);
      if (result == null) {
        if (page != 'prologue') {
          missing++;
          stdout.writeln('  no result: ${entry.value} $page');
        }
        continue;
      }
      File('${outDir.path}/${entry.value}-$page.json')
          .writeAsStringSync(jsonEncode(result.toJson()));
      saved++;
      final w = result.rows.first;
      stdout.writeln('${entry.value} $page '
          '(${result.day}.${result.month}.): ${w.name}, ${result.rows.length} riders');
    }
  }
  client.close();
  world.close();
  stdout.writeln('$saved results saved, $missing pages without a result');
}
