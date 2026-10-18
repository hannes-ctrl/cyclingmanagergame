import 'dart:io';

import 'package:sim/sim.dart';

import '../test/synthetic.dart';

/// Rides a synthetic Grand Tour and prints what happens to the field.
void main(List<String> args) {
  final tuning = args.isNotEmpty ? SimTuning.load(args[0]) : SimTuning.standard;
  final field = syntheticField();
  final routes = grandTour();
  final run = StageRaceRun(field, seed: 5, tuning: tuning, month: 7);
  for (var i = 0; i < routes.length; i++) {
    if (i == 9 || i == 15) run.restDay();
    final r = run.nextStage(routes[i]);
    final out = r.abandons.map((a) => '${a.rider.name}(${a.reason.name})');
    final debts = [for (final x in run.riders) run.debt[x.id]!]..sort();
    final w = r.placings.first;
    stdout.writeln(
        '${(i + 1).toString().padLeft(2)} ${routes[i].name.padRight(22)} '
        '${w.rider.name.padRight(7)} ${(routes[i].raceKm / (w.timeS / 3600)).toStringAsFixed(1)} km/h '
        'riders ${run.riders.length}, fatigue ${debts.first.toStringAsFixed(2)}–'
        '${debts[debts.length ~/ 2].toStringAsFixed(2)}–${debts.last.toStringAsFixed(2)}  '
        '${r.weather?.describe()}  out: ${out.join(', ')}');
  }
  final gc = run.result.gc;
  stdout.writeln('\nGeneral classification:');
  for (var i = 0; i < 10; i++) {
    stdout.writeln(
        '${i + 1}. ${gc[i].rider.name} +${(gc[i].timeS - gc.first.timeS).round()} s');
  }
}
