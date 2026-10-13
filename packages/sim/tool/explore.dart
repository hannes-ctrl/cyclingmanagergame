import 'dart:io';

import 'package:sim/sim.dart';

import '../test/synthetic.dart';

/// Prints key figures of the simulation on the synthetic routes.
/// Usage: dart run tool/explore.dart [runs] [tuning.json] [route] [name=value ...]
void main(List<String> args) {
  final runs = args.isNotEmpty ? int.parse(args[0]) : 20;
  var tuning = args.length > 1 && args[1] != '-'
      ? SimTuning.load(args[1])
      : SimTuning.standard;
  final only = args.length > 2 && args[2] != '-' ? args[2] : null;
  final overrides = {
    for (final a in args.skip(3))
      a.split('=')[0]: double.parse(a.split('=')[1]),
  };
  if (overrides.isNotEmpty)
    tuning = SimTuning({...tuning.toMap(), ...overrides});
  final field = syntheticField();
  final routes = {
    'Flach': flatStage(),
    'Rampe': puncheurFinish(),
    'Hügel': hillyClassic(),
    'Berg': mountainStage(),
    'Pflaster': cobbledClassic(),
    'EZF': timeTrial(),
    'MZF': teamTimeTrial(),
  };
  for (final e in routes.entries) {
    if (only != null && !only.split(',').contains(e.key)) continue;
    final route = e.value;
    final watch = Stopwatch()..start();
    var speed = 0.0, first = 0.0, gap10 = 0.0, gapMid = 0.0, breaks = 0;
    var crashes = 0, abandons = 0, punctures = 0, solo = 0, fav = 0;
    var breakKm = 0.0, breaksFormed = 0, echelons = 0;
    final wins = <String, int>{};
    for (var i = 0; i < runs; i++) {
      final r =
          simulateStage(route, field, seed: 1000 + i, tuning: tuning, month: 6);
      final w = r.placings.first;
      speed += route.raceKm / (w.timeS / 3600);
      final size = r.placings.where((p) => p.group == w.group).length;
      if (size == 1) solo++;
      first += size;
      gap10 += r.placings[9].timeS - w.timeS;
      gapMid += r.placings[r.placings.length ~/ 2].timeS - w.timeS;
      if (r.breakSurvived) breaks++;
      crashes += r.events.where((x) => x.type == EventType.crash).length;
      echelons += r.events.where((x) => x.type == EventType.echelon).length;
      punctures += r.traces.values
          .where((x) => x.incident == RiderIncident.puncture)
          .length;
      abandons += r.abandons.length;
      final b = r.events.where((x) => x.type == EventType.breakaway);
      if (b.isNotEmpty) {
        breakKm += b.first.km;
        breaksFormed++;
      }
      final type = w.rider.id % 100;
      wins['typ$type'] = (wins['typ$type'] ?? 0) + 1;
      if (w.rider.teamId <= 3) fav++;
    }
    String f(double x) => x.toStringAsFixed(1);
    stdout.writeln('${e.key.padRight(9)} ${f(route.raceKm)} km, '
        '${f(speed / runs)} km/h, 1. Gruppe ${f(first / runs)}, '
        'solo ${100 * solo ~/ runs} %, Pl.10 +${f(gap10 / runs)} s, '
        'Mitte +${f(gapMid / runs)} s, Ausreißer ${100 * breaks ~/ runs} %, '
        'Flucht ab km ${breaksFormed == 0 ? '-' : f(breakKm / breaksFormed)}, '
        'Stürze ${f(crashes / runs)}, Defekte ${f(punctures / runs)}, '
        'Aufgaben ${f(abandons / runs)}, Windkanten ${f(echelons / runs)}, '
        'Top-3-Teams siegen ${100 * fav ~/ runs} %, '
        '${watch.elapsedMilliseconds ~/ runs} ms/Lauf');
    stdout.writeln('          Siegertypen: $wins');
  }
}
