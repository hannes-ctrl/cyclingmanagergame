import 'dart:io';

import 'package:sim/sim.dart';

import '../test/synthetic.dart';

/// Prints the events and the timeline of one run.
/// Usage: dart run tool/trace_run.dart route seed [tuning.json]
void main(List<String> args) {
  final routes = {
    'Flach': flatStage(),
    'Rampe': puncheurFinish(),
    'Hügel': hillyClassic(),
    'Berg': mountainStage(),
    'Pflaster': cobbledClassic(),
  };
  final tuning = args.length > 2 ? SimTuning.load(args[2]) : SimTuning.standard;
  final r = simulateStage(routes[args[0]]!, syntheticField(),
      seed: int.parse(args[1]), tuning: tuning);
  for (final e in r.events) {
    stdout.writeln('km ${e.km.toStringAsFixed(1).padLeft(6)}  ${e.text}');
  }
  for (final x in r.timeline) {
    stdout.writeln(
        'km ${x.km.toStringAsFixed(0).padLeft(4)}  vorn ${x.frontSize.toString().padLeft(3)} +${x.frontGapS.round().toString().padLeft(4)}  Favoriten ${x.mainSize.toString().padLeft(3)}  Mitte +${x.lastGapS.round()}');
  }
}
