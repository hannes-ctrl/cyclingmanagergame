import 'dart:io';

import 'package:sim/sim.dart';

import '../test/synthetic.dart';

/// Prints the events and the timeline of one run.
/// Usage: dart run tool/trace_run.dart route seed [tuning.json]
void main(List<String> args) {
  final routes = {
    'Flat': flatStage(),
    'Ramp': puncheurFinish(),
    'Hills': hillyClassic(),
    'Mountain': mountainStage(),
    'Cobbles': cobbledClassic(),
  };
  final tuning = args.length > 2 ? SimTuning.load(args[2]) : SimTuning.standard;
  final r = simulateStage(routes[args[0]]!, syntheticField(),
      seed: int.parse(args[1]), tuning: tuning);
  for (final e in r.events) {
    stdout.writeln('km ${e.km.toStringAsFixed(1).padLeft(6)}  ${e.text}');
  }
  for (final x in r.timeline) {
    stdout.writeln(
        'km ${x.km.toStringAsFixed(0).padLeft(4)}  front ${x.frontSize.toString().padLeft(3)} +${x.frontGapS.round().toString().padLeft(4)}  favourites ${x.mainSize.toString().padLeft(3)}  middle +${x.lastGapS.round()}');
  }
}
