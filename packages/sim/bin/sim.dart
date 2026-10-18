import 'dart:convert';
import 'dart:io';

import 'package:sim/sim.dart';

const _usage = '''
Usage: dart run sim <command>

  stage "<race>" [stage] [--runs n] [--seed s]   a stage or one-day race
  race "<race>" [--seed s]                       a whole stage race with its classifications
  viewer "<race>" [stage] [--seed s] [--team ABBR] [--out file]
                                                 a stage as a message for the 3D viewer
  check                                          self-test of the simulation
''';

/// Formats a duration for the console.
///
/// @param s Seconds.
/// @returns `h:mm:ss`.
String _time(double s) {
  final t = s.round();
  final h = t ~/ 3600, m = t % 3600 ~/ 60, sec = t % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
      : '$m:${sec.toString().padLeft(2, '0')}';
}

String _gap(double s) => s.round() == 0 ? 'same time' : '+${_time(s)}';

void main(List<String> argv) {
  final args = [...argv];

  /// Reads a numeric command-line option.
  ///
  /// @param name Option name without the leading dashes.
  /// @param fallback Value if the option is missing.
  /// @returns The parsed value.
  int option(String name, int fallback) {
    final i = args.indexOf(name);
    if (i < 0) return fallback;
    final v = int.parse(args[i + 1]);
    args.removeRange(i, i + 2);
    return v;
  }

  final runs = option('--runs', 1);
  final seed = option('--seed', 1);
  String text(String name, String fallback) {
    final i = args.indexOf(name);
    if (i < 0) return fallback;
    final v = args[i + 1];
    args.removeRange(i, i + 2);
    return v;
  }

  final team = text('--team', '');
  final out = text('--out', 'race.json');
  if (args.isNotEmpty && args[0] == 'check') {
    exitCode = _check() ? 0 : 1;
    return;
  }
  if (args.length < 2) {
    stdout.write(_usage);
    return;
  }
  final world =
      World(Platform.script.resolve('../../../data/world.sqlite').toFilePath());
  final race = world.findRace(args[1]);
  if (race == null) {
    stderr.writeln('No race matching "${args[1]}".');
    exit(2);
  }
  final stages = world.stages(race.id);
  // Calibrated tuning values, if present.
  final tuning = SimTuning.load(Platform.script
      .resolve('../../../data/calibration/tuning.json')
      .toFilePath());
  final riders = world.startList(race.id);

  switch (args[0]) {
    case 'stage':
      final number = args.length > 2 ? int.parse(args[2]) : 1;
      final stage = stages.firstWhere((s) => s.number == number);
      final route = world.route(stage.id);
      print(
          '${race.name}${stages.length > 1 ? ', stage $number' : ''}: ${route.name}');
      print('${route.raceKm.toStringAsFixed(1)} km, ${riders.length} starters, '
          'selectivity ${route.selectivity.round()}, '
          'finish gradient ${(route.finishGrade * 100).toStringAsFixed(1)} %');
      if (runs == 1) {
        _printStage(simulateStage(route, riders, seed: seed, tuning: tuning));
      } else {
        _printSeries(route, riders, runs, seed, tuning);
      }
    case 'race':
      final routes = [for (final s in stages) world.route(s.id)];
      final watch = Stopwatch()..start();
      final result =
          simulateStageRace(routes, riders, seed: seed, tuning: tuning);
      print('${race.name}: ${routes.length} stages, ${riders.length} starters, '
          '${watch.elapsedMilliseconds} ms');
      for (var i = 0; i < routes.length; i++) {
        final r = result.stages[i];
        final w = r.placings.first;
        print(
            '${(i + 1).toString().padLeft(3)}  ${routes[i].name.padRight(46)} '
            '${w.rider.name.padRight(18)} ${w.rider.team.padRight(4)} '
            '${r.breakSurvived ? 'breakaway' : ''}');
      }
      print('\nGeneral classification');
      for (var i = 0; i < 15; i++) {
        final e = result.gc[i];
        print('${(i + 1).toString().padLeft(3)}  ${e.rider.name.padRight(22)} '
            '${e.rider.team.padRight(5)} '
            '${i == 0 ? _time(e.timeS) : _gap(e.timeS - result.gc.first.timeS)}');
      }
      final last = result.standings.last;
      String top(Iterable<String> rows) => rows.take(3).join(', ');
      print(
          '\nPoints:    ${top(last.points.map((e) => '${e.rider.name} ${e.points}'))}');
      print(
          'Mountains: ${top(last.mountains.map((e) => '${e.rider.name} ${e.points}'))}');
      print('Youth:     ${top(last.youth.map((e) => e.rider.name))}');
      print('Teams:     ${top(last.teams.map((e) => e.team))}');
    case 'viewer':
      final number = args.length > 2 ? int.parse(args[2]) : 1;
      final stage = stages.firstWhere((s) => s.number == number);
      final route = world.route(stage.id);
      final teams = {for (final t in world.teams()) t.id: t};
      final own = teams.values.where((t) => t.abbr == team).firstOrNull;
      final result =
          simulateStage(route, riders, seed: seed, tuning: tuning, track: true);
      // The leaders' jerseys come from the stages before.
      var leaders = const <String, int>{};
      if (number > 1) {
        final before = [
          for (final s in stages.where((s) => s.number < number))
            world.route(s.id)
        ];
        leaders = leaderJerseys(
            simulateStageRace(before, riders, seed: seed, tuning: tuning)
                .standings
                .last);
      }
      final kits =
          Directory(Platform.script.resolve('../../../data/kits').toFilePath());
      final logo = File(Platform.script
          .resolve('../../../data/logos/${race.id}.png')
          .toFilePath());
      final message = viewerRace(
          title: race.name,
          stage: stages.length > 1 ? 'Stage $number' : '',
          route: route,
          result: result,
          riders: riders,
          teams: teams,
          ownTeam: own?.id,
          seed: seed,
          kits: kits.existsSync() ? kits.absolute.path : null,
          kitOf: world.jerseyKeys(),
          raceKey: world.raceKey(race.id),
          leaders: leaders,
          logo: logo.existsSync() ? logo.absolute.path : null);
      File(out).writeAsStringSync(jsonEncode(message));
      print('${race.name} ${stages.length > 1 ? 'stage $number ' : ''}'
          '(${route.raceKm.toStringAsFixed(1)} km, ${riders.length} riders) '
          'written to $out');
    default:
      stdout.write(_usage);
  }
  world.close();
}

/// Prints the top of a stage result and the race events.
///
/// @param r Result to print.
void _printStage(StageResult r) {
  print('');
  for (final e in r.events) {
    print('km ${e.km.toStringAsFixed(1).padLeft(6)}  ${e.text}');
  }
  print('');
  for (var i = 0; i < 15 && i < r.placings.length; i++) {
    final p = r.placings[i];
    print('${(i + 1).toString().padLeft(3)}  ${p.rider.name.padRight(22)} '
        '${p.rider.team.padRight(5)} '
        '${i == 0 ? _time(p.timeS) : _gap(p.timeS - r.winnerTimeS)}');
  }
  final speed = r.placings.first.timeS;
  print('\nLast: ${_gap(r.placings.last.timeS - r.winnerTimeS)}, '
      'groups at the finish: ${r.placings.last.group + 1}, winning time ${_time(speed)}');
}

/// Runs a stage several times and prints the spread of outcomes.
///
/// @param route Stage to simulate.
/// @param riders Start list.
/// @param runs Number of runs.
/// @param seed Seed of the first run.
/// @param tuning Tuning values.
void _printSeries(SimRoute route, List<SimRider> riders, int runs, int seed,
    SimTuning tuning) {
  final wins = <String, int>{};
  var breaks = 0, solo = 0;
  var firstGroup = 0.0, gap10 = 0.0, speed = 0.0;
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    final r = simulateStage(route, riders, seed: seed + i, tuning: tuning);
    final w = r.placings.first;
    wins['${w.rider.name} (${w.rider.team})'] =
        (wins['${w.rider.name} (${w.rider.team})'] ?? 0) + 1;
    if (r.breakSurvived) breaks++;
    final size = r.placings.where((p) => p.group == w.group).length;
    if (size == 1) solo++;
    firstGroup += size;
    gap10 += r.placings[9].timeS - w.timeS;
    speed += route.raceKm / (w.timeS / 3600);
  }
  print('\n$runs runs in ${watch.elapsedMilliseconds} ms');
  print('Speed of the winner: ${(speed / runs).toStringAsFixed(1)} km/h');
  print(
      'First group on average: ${(firstGroup / runs).toStringAsFixed(1)} riders, '
      'solo wins: ${(100 * solo / runs).round()} %');
  print('Gap of place 10 on average: ${_gap(gap10 / runs)}');
  print('Breakaways win: ${(100 * breaks / runs).round()} %');
  final order = wins.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  print('Winners:');
  for (final e in order.take(10)) {
    print(
        '  ${(100 * e.value / runs).round().toString().padLeft(3)} %  ${e.key}');
  }
}

/// Checks basic properties that must hold regardless of fine tuning.
///
/// @returns true if every check passed.
bool _check() {
  var ok = true;

  /// Records one check and prints the outcome.
  ///
  /// @param what Label of the check.
  /// @param good Whether it passed.
  /// @param detail Optional value to print next to it.
  void expect(String what, bool good, [Object? detail]) {
    ok &= good;
    print(
        '${good ? 'ok  ' : 'FAIL'} $what${detail == null ? '' : ': $detail'}');
  }

  final world =
      World(Platform.script.resolve('../../../data/world.sqlite').toFilePath());
  final tour = world.findRace('Tour de France')!;
  final stages = world.stages(tour.id);
  final riders = world.startList(tour.id);
  expect('start list of the Tour', riders.length == 184, riders.length);

  /// Loads a stage of the test race by its number.
  ///
  /// @param n Stage number, starting at 1.
  /// @returns The route.
  SimRoute stage(int n) =>
      world.route(stages.firstWhere((s) => s.number == n).id);
  final mountain = stage(20), flat = stage(7), timeTrial = stage(16);

  final a = simulateStage(mountain, riders, seed: 7);
  final b = simulateStage(mountain, riders, seed: 7);
  expect(
      'same seed, same result',
      Iterable.generate(a.placings.length).every((i) =>
          a.placings[i].rider.id == b.placings[i].rider.id &&
          a.placings[i].timeS == b.placings[i].timeS));
  expect('every rider finishes or abandons',
      a.placings.length + a.abandons.length == riders.length);
  expect(
      'every rider exactly once',
      {
            ...a.placings.map((p) => p.rider.id),
            ...a.abandons.map((x) => x.rider.id)
          }.length ==
          riders.length);
  final kmh = mountain.raceKm / (a.winnerTimeS / 3600);
  expect('segments of 200 m', mountain.segments.first.lengthM == 200);
  expect('mountain stage: speed between 28 and 38 km/h', kmh > 28 && kmh < 38,
      kmh.toStringAsFixed(1));

  /// @param r A stage result.
  /// @returns The number of riders in the winner's group.
  int firstGroup(StageResult r) =>
      r.placings.where((p) => p.group == r.placings.first.group).length;
  var bunch = 0, small = 0;
  const runs = 30;
  for (var i = 0; i < runs; i++) {
    final f = simulateStage(flat, riders, seed: 100 + i);
    if (firstGroup(f) > 50 || f.breakSurvived) bunch++;
    if (firstGroup(simulateStage(mountain, riders, seed: 100 + i)) <= 12)
      small++;
  }
  expect('flat stage: bunch finish or breakaway win', bunch >= runs * 0.9,
      '$bunch of $runs');
  expect('mountain stage: small leading group', small >= runs * 0.9,
      '$small of $runs');

  final tt = simulateStage(timeTrial, riders, seed: 1);
  final top = tt.placings.take(10).map((p) => p.rider.attributes.timeTrial);
  final all = riders.map((r) => r.attributes.timeTrial);

  /// @param x Values.
  /// @returns Their arithmetic mean.
  double mean(Iterable<double> x) => x.reduce((p, q) => p + q) / x.length;
  expect(
      'time trial: the best have high time trial values',
      mean(top) > mean(all) + 5,
      '${mean(top).toStringAsFixed(1)} against ${mean(all).toStringAsFixed(1)}');

  final roubaix = world.findRace('Paris-Roubaix')!;
  final cobbles = world.route(world.stages(roubaix.id).first.id);
  final field = world.startList(roubaix.id);
  var selective = 0;
  for (var i = 0; i < runs; i++) {
    if (firstGroup(simulateStage(cobbles, field, seed: 200 + i)) <= 30)
      selective++;
  }
  expect('Roubaix: the cobbles split the field', selective >= runs * 0.8,
      '$selective of $runs');
  world.close();
  return ok;
}
