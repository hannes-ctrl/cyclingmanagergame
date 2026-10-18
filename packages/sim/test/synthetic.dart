import 'dart:math';

import 'package:sim/sim.dart';

/// A field and routes that need no world database, for tests of the
/// simulation's behaviour.

/// Builds a field of [teams] teams with eight riders each: a leader for the
/// mountains, two climbers, a sprinter, a lead-out man, two rouleurs and a
/// puncheur. Teams get weaker down the list.
///
/// @param teams Number of teams.
/// @param seed Seed for the spread of the attributes.
/// @returns The riders.
List<SimRider> syntheticField({int teams = 22, int seed = 1}) {
  final r = Random(seed);
  final riders = <SimRider>[];
  double n() => (r.nextDouble() - 0.5) * 6;
  // flat, mountain, mediumMountain, hill, timeTrial, prologue, cobble,
  // sprint, acceleration, downhill, endurance, resistance, recovery,
  // breakaway, weight, height
  const types = <List<double>>[
    [69, 80, 78, 76, 74, 70, 56, 60, 68, 72, 78, 76, 76, 64, 62, 176],
    [68, 75, 74, 72, 68, 66, 56, 58, 64, 70, 75, 72, 72, 66, 61, 174],
    [68, 74, 73, 71, 66, 64, 58, 58, 64, 70, 74, 70, 72, 68, 63, 177],
    [74, 56, 60, 64, 62, 68, 66, 80, 78, 68, 70, 66, 68, 58, 74, 181],
    [75, 58, 62, 66, 66, 68, 68, 74, 72, 68, 72, 68, 70, 62, 76, 185],
    [77, 60, 64, 66, 72, 70, 70, 66, 64, 68, 74, 70, 70, 70, 78, 188],
    [76, 62, 66, 68, 74, 70, 68, 64, 64, 70, 74, 70, 70, 72, 74, 184],
    [71, 68, 72, 78, 68, 68, 72, 70, 75, 72, 74, 72, 70, 72, 67, 178],
  ];
  for (var team = 0; team < teams; team++) {
    final level = -team * 0.3;
    for (var k = 0; k < types.length; k++) {
      final x = types[k];
      double v(int i) => x[i] + level + n();
      riders.add(SimRider(
        id: team * 100 + k,
        name: 'R$team-$k',
        teamId: team + 1,
        team: 'T${team + 1}',
        born: 19960101,
        weightKg: x[14] + n(),
        heightCm: x[15] + n(),
        attributes: Attributes(
          flat: v(0),
          mountain: v(1),
          mediumMountain: v(2),
          hill: v(3),
          timeTrial: v(4),
          prologue: v(5),
          cobble: v(6),
          sprint: v(7),
          acceleration: v(8),
          downhill: v(9),
          endurance: v(10),
          resistance: v(11),
          recovery: v(12),
          breakaway: v(13),
        ),
      ));
    }
  }
  return riders;
}

/// A profile from a list of (length in km, gradient) pieces.
List<(double, double)> _profile(
    double startAltitude, List<(double, double)> pieces) {
  final out = <(double, double)>[(0, startAltitude)];
  var km = 0.0, alt = startAltitude;
  for (final (length, grade) in pieces) {
    final steps = (length / 0.1).round();
    for (var i = 0; i < steps; i++) {
      km += length / steps;
      alt += grade * length / steps * 1000;
      out.add((km, alt));
    }
  }
  return out;
}

double _sum(List<(double, double)> pieces) =>
    pieces.fold(0.0, (s, p) => s + p.$1);

SimRoute _road(String name, double start, List<(double, double)> pieces,
        {List<SectorSpan> sectors = const [],
        StageKind kind = StageKind.road,
        List<ClimbSpan> climbs = const [],
        List<RoutePoint> climbTops = const []}) =>
    buildRoute(
      name: name,
      kind: kind,
      raceKm: _sum(pieces),
      profile: _profile(start, pieces),
      sectors: sectors,
      climbs: climbs,
      climbTops: climbTops,
    );

/// A flat stage of 180 km with small rollers.
SimRoute flatStage() => _road('Flat stage', 50, [
      for (var i = 0; i < 18; i++) ...[(5.0, 0.004), (5.0, -0.004)],
    ]);

/// A hilly classic of 250 km with ten short climbs and a flat finish.
SimRoute hillyClassic() => _road('Hills', 100, [
      (60, 0.0),
      for (var i = 0; i < 10; i++) ...[
        (2.5 + (i % 3), 0.07 + 0.01 * (i % 3)),
        (3.0 + (i % 3), -0.06),
        (12, 0.0),
      ],
      (8, 0.0),
    ]);

/// A mountain stage with two long climbs and a summit finish at 2100 m.
SimRoute mountainStage() => _road('Mountain', 1100, [
      (40, 0.0),
      (14, 0.07),
      (16, -0.06),
      (20, 0.0),
      (15, 0.075),
      (18, -0.06),
      (25, 0.0),
      (12, 0.08),
    ]);

/// The mountain stage with its mountain prizes.
SimRoute mountainStageWithTops() => _road('Mountain', 1100, [
      (40, 0.0),
      (14, 0.07),
      (16, -0.06),
      (20, 0.0),
      (15, 0.075),
      (18, -0.06),
      (25, 0.0),
      (12, 0.08),
    ], climbTops: const [
      RoutePoint(54, 'Col A', 2),
      RoutePoint(105, 'Col B', 1),
      RoutePoint(160, 'Finish', 1),
    ]);

/// A time trial with a long climb in it.
SimRoute mountainTimeTrial() =>
    _road('Mountain time trial', 600, [(0.4, 0.0), (14, 0.085)],
        kind: StageKind.timeTrial);

/// A cobbled classic of 255 km with 25 sectors in its second half.
SimRoute cobbledClassic() {
  final sectors = <SectorSpan>[];
  var km = 100.0;
  for (var i = 0; i < 25; i++) {
    final length = 1.0 + (i % 4) * 0.6;
    sectors.add(SectorSpan(km, km + length, 2 + (i * 7) % 4, true));
    km += length + 4.5;
  }
  return _road('Cobbles', 30, [(255, 0.0)], sectors: sectors);
}

/// A flat stage with a short steep finish.
SimRoute puncheurFinish() => _road('Ramp', 50, [(198.8, 0.0), (1.2, 0.09)]);

/// An individual time trial of 35 km.
SimRoute timeTrial() =>
    _road('Time trial', 50, [(35, 0.0)], kind: StageKind.timeTrial);

/// A team time trial of 30 km.
SimRoute teamTimeTrial() =>
    _road('Team time trial', 50, [(30, 0.0)], kind: StageKind.teamTimeTrial);

/// Twenty-one stages in the shape of a Grand Tour.
List<SimRoute> grandTour() => [
      timeTrial(),
      flatStage(),
      puncheurFinish(),
      hillyClassic(),
      flatStage(),
      mountainStage(),
      flatStage(),
      cobbledClassic(),
      mountainStage(),
      teamTimeTrial(),
      flatStage(),
      mountainStage(),
      hillyClassic(),
      flatStage(),
      mountainStage(),
      puncheurFinish(),
      mountainStage(),
      flatStage(),
      mountainStage(),
      timeTrial(),
      flatStage(),
    ];
