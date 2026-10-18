// Tunes the simulation against real results.
//
//   dart run bin/calibrate.dart report [--runs n] [--sample k] [--types a,b]
//       [--set name=value ...]
//       Compares the current tuning with the real races. With --sample only
//       every k-th race counts and --runs is taken as given: a quick check
//       of a model change. --types limits it to race types (Flat, Hilly,
//       Mountain, Sectors, Time trial). --from 2021 adds the earlier
//       seasons, with anonymous riders for the finishers the database
//       does not know.
//   dart run bin/calibrate.dart run [--hours h] [--runs n] [--margin m] [--from year]
//       Searches for better tuning values for h hours (default 8).
//       Every improvement is written to data/calibration/tuning.json at
//       once; the run can be interrupted at any time and resumed later.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:calibration/calibration.dart';
import 'package:sim/sim.dart';

/// Command-line entry point of the calibration.
///
/// @param argv Command (`report`, `run` or `notes`) and its options.
/// @returns A future that completes when the command has finished.
Future<void> main(List<String> argv) async {
  final args = [...argv];

  /// Reads a numeric command-line option.
  ///
  /// @param name Option name without the leading dashes.
  /// @param fallback Value if the option is missing.
  /// @returns The parsed value.
  double option(String name, double fallback) {
    final i = args.indexOf(name);
    if (i < 0) return fallback;
    final v = double.parse(args[i + 1]);
    args.removeRange(i, i + 2);
    return v;
  }

  const year0 = 2026;
  final root0 = Platform.script.resolve('../../../data/').toFilePath();
  if (args.isNotEmpty && args.first == 'reparse') {
    _reparse(root0, year0);
    return;
  }
  // --dry: search without writing tuning.json, to try the setup out.
  final dry = args.remove('--dry');
  final hours = option('--hours', 8);
  final runs = option('--runs', 4).round();
  final sample = option('--sample', 1).round();
  final ti = args.indexOf('--types');
  final onlyTypes = ti < 0 ? null : args[ti + 1].split(',').toSet();
  if (ti >= 0) args.removeRange(ti, ti + 2);
  final margin = option('--margin', 0.1);
  // --from 2021: earlier seasons too, with anonymous riders for the
  // finishers the database does not know.
  final from = option('--from', firstSeason.toDouble()).round();
  const year = 2026;
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final tuningFile = File('${root}calibration/tuning.json');
  final logFile = File('${root}calibration/log.txt');
  tuningFile.parent.createSync(recursive: true);

  final world = World('${root}world.sqlite');
  // All seasons with stored results from [firstSeason] on.
  final exclude = loadExclusions('${root}calibration/exclude.txt');
  final parts = [
    for (var y = from; y <= year; y++)
      if (Directory('${root}results/$y').existsSync())
        loadDataset(world, '${root}results/$y', y,
            exclude: exclude, fill: y < firstSeason),
  ];
  final data = Dataset(
    [for (final p in parts) ...p.cases],
    [for (final p in parts) ...p.notes],
  );
  world.close();
  final byType = <String, int>{};
  for (final c in data.cases) {
    byType[c.type] = (byType[c.type] ?? 0) + 1;
  }
  stdout.writeln('${data.cases.length} races to compare: $byType');
  final tuning = SimTuning.load(tuningFile.path).toMap();
  // --set name=value: try a value without writing it, for the report.
  for (var i = args.indexOf('--set'); i >= 0; i = args.indexOf('--set')) {
    final kv = args[i + 1].split('=');
    tuning[kv[0]] = double.parse(kv[1]);
    args.removeRange(i, i + 2);
  }
  stdout.writeln(tuningFile.existsSync()
      ? 'Setting from ${tuningFile.path}'
      : 'No calibrated setting yet; the defaults apply');

  switch (args.isEmpty ? 'report' : args[0]) {
    case 'notes':
      data.notes.forEach(stdout.writeln);
    case 'report':
      final watch = Stopwatch()..start();
      final quick = sample > 1 || onlyTypes != null;
      final cases = [
        for (var i = 0; i < data.cases.length; i++)
          if (i % sample == 0 &&
              (onlyTypes == null || onlyTypes.contains(data.cases[i].type)))
            data.cases[i],
      ];
      final e = await evaluate(cases, tuning,
          runs: quick ? runs : max(runs, 8), seed: 12345);
      _report(e);
      _reportSplit(e);
      _reportBounds(tuning);
      stdout.writeln('\n${quick ? runs : max(runs, 8)} runs per race, '
          '${cases.length} races in '
          '${watch.elapsed.inSeconds} s');
    case 'run':
      void log(String line) {
        final stamped =
            '${DateTime.now().toIso8601String().substring(0, 19)}  $line';
        stdout.writeln(stamped);
        logFile.writeAsStringSync('$stamped\n', mode: FileMode.append);
      }

      log('Calibration for ${hours.toStringAsFixed(1)} h, '
          '${data.cases.length} races, $runs runs per race');
      // Keep the previous values: a search can also make things worse in
      // ways the error does not measure.
      if (!dry && tuningFile.existsSync()) {
        final stamp = DateTime.now()
            .toIso8601String()
            .substring(0, 16)
            .replaceAll(':', '')
            .replaceAll('-', '');
        tuningFile.copySync('${root}calibration/tuning_$stamp.json');
      }
      final training = data.training, validation = data.validation;
      log('${training.length} races to tune on, '
          '${validation.length} for control${dry ? ' (dry run, nothing is saved)' : ''}');
      await optimize(
        training,
        validation: validation,
        start: tuning,
        budget: Duration(seconds: (hours * 3600).round()),
        runs: runs,
        margin: margin,
        seed: DateTime.now().millisecondsSinceEpoch % 1000000,
        log: log,
        onImprove: (best, loss, evaluations) {
          if (dry) return;
          tuningFile
              .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
            'loss': loss,
            'evaluations': evaluations,
            'updated': DateTime.now().toIso8601String(),
            'races': data.cases.length,
            'values': best,
          }));
        },
      );
    default:
      stdout.writeln(
          'Commands: report, run [--hours h] [--runs n] [--dry] [--from year], '
          'notes, reparse');
  }
}

/// Prints the comparison of real and simulated races by race type.
///
/// @param e Evaluation to print.
void _report(Evaluation e) {
  /// @param v A number.
  /// @param digits Decimal places.
  /// @returns The formatted number.
  String f(double v, [int digits = 1]) => v.toStringAsFixed(digits);

  /// @param logValue Natural logarithm of a time gap in seconds.
  /// @returns The gap as readable text.
  String secs(double logValue) {
    final s = (exp(logValue) - 1).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// @param x Values.
  /// @returns Their arithmetic mean.
  double avg(Iterable<double> x) => x.reduce((a, b) => a + b) / x.length;
  final types = ['Flat', 'Hilly', 'Mountain', 'Sectors', 'Time trial'];
  stdout.writeln('\nTotal error ${f(e.loss, 4)}  (lower is better)');
  stdout.writeln('  per race ${f(e.caseLoss, 3)}: '
      'shape ${f(avg(e.scores.map((x) => x.shapeTerm)), 3)}, '
      'speed ${f(avg(e.scores.map((x) => x.speedTerm)), 3)}, '
      'breakaway ${f(avg(e.scores.map((x) => x.breakTerm)), 3)}'
      ' (shape and speed capped together per race)');
  stdout.writeln('  frequencies per race type ${f(e.frequencyLoss, 3)}');
  stdout.writeln('  favourite wins per race type ${f(e.favouriteLoss, 3)}, '
      'general classification ${f(avg(e.scores.map((x) => x.gcTerm)), 3)} per race, '
      'time limit ${f(e.cutLoss, 3)}\n');
  stdout.writeln(
      '                      Races   1st group      Gap place 10     Gap of middle    '
      'Speed km/h       Break wins       Winner in top 3 / top 10 (for information)');
  stdout.writeln(
      '                              real   sim     real    sim      real    sim      '
      'real   sim      real   sim');
  for (final type in [...types, 'all']) {
    final s = e.scores.where((x) => type == 'all' || x.type == type).toList();
    if (s.isEmpty) continue;
    stdout.writeln('${type.padRight(20)} ${s.length.toString().padLeft(5)}   '
        '${f(exp(avg(s.map((x) => x.real.logFirstGroup)))).padLeft(5)} '
        '${f(exp(avg(s.map((x) => x.sim.logFirstGroup)))).padLeft(5)}    '
        '${secs(avg(s.map((x) => x.real.logGap10))).padLeft(6)} '
        '${secs(avg(s.map((x) => x.sim.logGap10))).padLeft(6)}    '
        '${secs(avg(s.map((x) => x.real.logGapMedian))).padLeft(6)} '
        '${secs(avg(s.map((x) => x.sim.logGapMedian))).padLeft(6)}    '
        '${f(avg(s.map((x) => x.real.speedKmh))).padLeft(5)} '
        '${f(avg(s.map((x) => x.sim.speedKmh))).padLeft(5)}    '
        '${f(100 * avg(s.map((x) => x.real.breakWin)), 0).padLeft(4)} % '
        '${f(100 * avg(s.map((x) => x.sim.breakWin)), 0).padLeft(3)} %     '
        '${f(100 * avg(s.map((x) => x.winnerTop3)), 0).padLeft(3)} % / '
        '${f(100 * avg(s.map((x) => x.winnerTop10)), 0)} %');
  }
  // How the race was decided: real field from ProCyclingStats against the
  // share of simulation runs.
  stdout.writeln(
      '\nSize of the winner\'s group (real / simulation, share in %):');
  stdout.writeln('                     Races    ${[
    for (final k in FinishKind.road) k.label.padRight(17)
  ].join()}Real solo: median km');
  for (final type in ['Flat', 'Hilly', 'Mountain', 'Sectors', 'all']) {
    final s = e.scores
        .where((x) =>
            (type == 'all' ? x.type != 'Time trial' : x.type == type) &&
            x.realKind != null &&
            x.finishShares.isNotEmpty)
        .toList();
    if (s.isEmpty) continue;
    final cells = <String>[];
    for (var k = 0; k < FinishKind.road.length; k++) {
      final real =
          s.where((x) => x.realKind == FinishKind.road[k]).length / s.length;
      final sim = avg(s.map((x) => x.finishShares[k]));
      cells.add('${f(100 * real, 0).padLeft(3)} / ${f(100 * sim, 0).padLeft(3)}'
          .padRight(17));
    }
    final solos = [
      for (final x in s)
        if (FinishKind.soloKm(x.wonHow) case final km?) km,
    ]..sort();
    stdout.writeln('${type.padRight(20)} ${s.length.toString().padLeft(5)}   '
        '${cells.join()}'
        '${solos.isEmpty ? '–' : '${f(solos[solos.length ~/ 2])} (${solos.length} races)'}');
  }

  // Stage races: time gaps add up over the stages, so compare the sum of
  // the gap of tenth place per race.
  final byRace = <String, List<CaseScore>>{};
  for (final x in e.scores) {
    final race =
        x.label.replaceAll(RegExp(r'-(stage-\d+|prologue|result)$'), '');
    if (race != x.label && !x.label.endsWith('result')) {
      byRace.putIfAbsent(race, () => []).add(x);
    }
  }
  stdout.writeln(
      '\nStage races: sum of the gaps of place 10 over all stages (real / simulation):');
  double seconds(double logValue) => exp(logValue) - 1;
  String clock(double seconds) {
    final s = seconds.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  for (final r in byRace.entries.where((r) => r.value.length >= 3)) {
    final real = r.value.fold(0.0, (sum, x) => sum + seconds(x.real.logGap10));
    final sim = r.value.fold(0.0, (sum, x) => sum + seconds(x.sim.logGap10));
    stdout.writeln(
        '  ${r.key.padRight(34)} ${r.value.length.toString().padLeft(2)} stages    '
        '${clock(real).padLeft(7)} / ${clock(sim).padLeft(7)}   '
        'factor ${f(sim / (real == 0 ? 1 : real), 2)}');
  }

  // The fields of earlier seasons are covered less well by the database
  // (see bin/seasons.dart); this shows whether they are matched worse.
  stdout.writeln('\nPer season, road races only (real / simulation):');
  stdout.writeln('           Races    Error   Gap place 10        '
      'Gap of middle      1st group');
  final bySeason = <String, List<CaseScore>>{};
  for (final x in e.scores) {
    if (x.type == 'Time trial') continue;
    final season = RegExp(r'^\d{4}/').hasMatch(x.label)
        ? x.label.substring(0, 4)
        : '$currentSeason';
    bySeason.putIfAbsent(season, () => []).add(x);
  }
  for (final season in bySeason.keys.toList()..sort()) {
    final s = bySeason[season]!;
    String pair(double Function(RaceShape) of) =>
        '${clock(exp(avg(s.map((x) => of(x.real)))) - 1).padLeft(6)} / '
        '${clock(exp(avg(s.map((x) => of(x.sim)))) - 1).padLeft(6)}';
    stdout.writeln('  $season    ${'${s.length}'.padLeft(6)}   '
        '${f(avg(s.map((x) => x.loss)), 2).padLeft(6)}   '
        '${pair((r) => r.logGap10)}    ${pair((r) => r.logGapMedian)}    '
        '${f(exp(avg(s.map((x) => x.real.logFirstGroup)))).padLeft(5)} / '
        '${f(exp(avg(s.map((x) => x.sim.logFirstGroup)))).padLeft(5)}');
  }

  // How often one of the three riders best suited to the route wins.
  stdout.writeln(
      '\nWin of one of the three top favourites, ${currentSeason} only (real / simulation):');
  for (final type in [...types, 'all']) {
    final s = e.scores
        .where(
            (x) => (type == 'all' || x.type == type) && x.realFavourite != null)
        .toList();
    if (s.isEmpty) continue;
    final real = s.where((x) => x.realFavourite!).length / s.length;
    stdout.writeln('  ${type.padRight(20)} ${s.length.toString().padLeft(5)}   '
        '${f(100 * real, 0).padLeft(3)} % / '
        '${f(100 * avg(s.map((x) => x.simFavourite)), 0).padLeft(3)} %');
  }
  // Sprinters outside the time limit on hard stages of stage races.
  stdout.writeln('\nSprinters outside the time limit (real / simulation):');
  for (final type in ['Hilly', 'Mountain']) {
    final s = e.scores.where((x) => x.type == type && x.cutSprinters > 0);
    final n = s.fold(0, (a, x) => a + x.cutSprinters);
    if (n == 0) continue;
    stdout.writeln('  ${type.padRight(20)} ${n.toString().padLeft(5)}   '
        '${f(100 * s.fold(0, (a, x) => a + x.realCutOut) / n, 0).padLeft(3)} % / '
        '${f(100 * s.fold(0.0, (a, x) => a + x.simCutOut) / n, 0).padLeft(3)} %');
  }
  // Time the ten best of the general classification lose per stage.
  final gc = e.scores.where((x) => x.realGcLoss != null).toList();
  if (gc.isNotEmpty) {
    stdout.writeln(
        '\nTime lost by the top 10 of the general classification per stage, '
        'mean over ${gc.length} stages (real / simulation): '
        '${secs(avg(gc.map((x) => x.realGcLoss!)))} / '
        '${secs(avg(gc.map((x) => x.simGcLoss!)))}');
  }

  final worst = [...e.scores]..sort((a, b) => b.loss.compareTo(a.loss));
  stdout.writeln('\nLargest deviations:');
  for (final s in worst.take(8)) {
    stdout.writeln(
        '  ${f(s.loss, 2).padLeft(6)}  ${s.label.padRight(34)} ${s.type.padRight(10)} '
        '1st group ${f(exp(s.real.logFirstGroup), 0)}/${f(exp(s.sim.logFirstGroup), 0)}, '
        'place 10 ${secs(s.real.logGap10)}/${secs(s.sim.logGap10)}, '
        'km/h ${f(s.real.speedKmh)}/${f(s.sim.speedKmh)} (real/sim)');
  }
}

/// Rebuilds the stored results from the cached ProCyclingStats pages without
/// touching the network, e.g. after the parser learned a new field.
///
/// @param root Data folder with a trailing slash.
/// @param year Season.
void _reparse(String root, int year) {
  final bySlug = {for (final e in pcsSlugs.entries) e.value: e.key};
  final outDir = Directory('${root}results/$year')..createSync(recursive: true);
  final name = RegExp('^(.+)-$year-(result|prologue|stage-\\d+)\\.html\$');
  var written = 0, withHow = 0;
  for (final file
      in Directory('${root}pcs_cache').listSync().whereType<File>()) {
    final m = name.firstMatch(file.uri.pathSegments.last);
    final raceId = m == null ? null : bySlug[m[1]];
    if (m == null || raceId == null) continue;
    final result =
        parseResultPage(file.readAsStringSync(), raceId, m[2]!, year);
    if (result == null) continue;
    File('${outDir.path}/${m[1]}-${m[2]}.json')
        .writeAsStringSync(jsonEncode(result.toJson()));
    written++;
    if (result.wonHow != null) withHow++;
  }
  stdout.writeln(
      '$written results written anew, $withHow with how the race was won');
}

/// Prints the error of the training and of the validation races. A tuning
/// that is much better on the training races has fitted noise.
///
/// @param e Evaluation of all races.
void _reportSplit(Evaluation e) {
  final training = [
    for (final s in e.scores)
      if (!Dataset.isValidation(s.label)) s,
  ];
  final validation = [
    for (final s in e.scores)
      if (Dataset.isValidation(s.label)) s,
  ];
  if (training.isEmpty || validation.isEmpty) return;
  stdout.writeln('\nError of the ${training.length} races to tune on: '
      '${Evaluation(training).loss.toStringAsFixed(4)} · '
      'of the ${validation.length} control races: '
      '${Evaluation(validation).loss.toStringAsFixed(4)}');
}

/// Lists tuning values that sit at the edge of their permitted range: there
/// the search wanted to go further than the range allows, which points at a
/// range that is too narrow or at something the model cannot express.
///
/// @param tuning Current values by name.
void _reportBounds(Map<String, double> tuning) {
  final lines = <String>[];
  for (final p in SimTuning.params) {
    final v = tuning[p.name] ?? p.standard;
    final at = (v - p.min) / (p.max - p.min);
    if (at < 0.02 || at > 0.98) {
      lines.add('  ${p.name.padRight(22)} ${v.toStringAsFixed(3).padLeft(9)}  '
          '(${at < 0.5 ? 'lower' : 'upper'} limit, range ${p.min} to ${p.max})  ${p.meaning}');
    }
  }
  if (lines.isEmpty) return;
  stdout.writeln('\nTuning values at the edge of their range:');
  lines.forEach(stdout.writeln);
}
