import 'dart:math';

import 'model.dart';

/// A stretch of special surface, given in race kilometres.
class SectorSpan {
  const SectorSpan(this.fromKm, this.toKm, this.difficulty, this.cobbled);
  final double fromKm;
  final double toKm;
  final int difficulty;
  final bool cobbled;
}

/// A categorised climb with the steepest gradient the stage file gives for it.
class ClimbSpan {
  const ClimbSpan(this.fromKm, this.toKm, this.maxGrade);
  final double fromKm;
  final double toKm;

  /// Steepest gradient as a fraction (0.12 = 12 %).
  final double maxGrade;
}

/// Cuts an elevation profile into segments of equal length.
///
/// @param name Stage name.
/// @param kind Kind of stage.
/// @param raceKm Race distance in kilometres.
/// @param profile Pairs of race kilometre and altitude in metres; points
///   before the start and after the finish are ignored.
/// @param sectors Cobbled and unpaved sections.
/// @param climbTops Mountain prizes.
/// @param sprints Intermediate sprints.
/// @param climbs Climbs with their steepest gradient; a ramp the profile
///   smooths away is put back into the climb.
/// @param segmentM Segment length in metres.
/// @returns The route.
SimRoute buildRoute({
  required String name,
  required StageKind kind,
  required double raceKm,
  required List<(double km, double altitude)> profile,
  List<SectorSpan> sectors = const [],
  List<RoutePoint> climbTops = const [],
  List<RoutePoint> sprints = const [],
  List<ClimbSpan> climbs = const [],
  double segmentM = 200,
}) {
  /// Interpolates the profile.
  ///
  /// @param km Race kilometre.
  /// @returns Altitude in metres.
  double altitudeAt(double km) {
    if (km <= profile.first.$1) return profile.first.$2;
    for (var i = 1; i < profile.length; i++) {
      final (k1, a1) = profile[i];
      if (km <= k1) {
        final (k0, a0) = profile[i - 1];
        return k1 == k0 ? a1 : a0 + (a1 - a0) * (km - k0) / (k1 - k0);
      }
    }
    return profile.last.$2;
  }

  final count = (raceKm * 1000 / segmentM).ceil();
  final segments = <Segment>[];
  for (var i = 0; i < count; i++) {
    final km0 = i * segmentM / 1000;
    final km1 = ((i + 1) * segmentM / 1000).clamp(0.0, raceKm);
    final length = (km1 - km0) * 1000;
    if (length <= 0) break;
    final grade = (altitudeAt(km1) - altitudeAt(km0)) / length;
    final mid = (km0 + km1) / 2;
    final segment = Segment(
        km: km0,
        lengthM: length,
        grade: grade.clamp(-0.2, 0.25),
        altitudeM: altitudeAt(mid));
    for (final x in sectors) {
      if (mid >= x.fromKm && mid <= x.toKm) {
        if (x.cobbled) {
          segment.cobble = x.difficulty.clamp(1, 5);
        } else {
          segment.unpaved = x.difficulty.clamp(1, 5);
        }
      }
    }
    segments.add(segment);
  }
  final ramped = _addRamps(segments, climbs);
  _markClimbs(ramped);
  return SimRoute(
    name: name,
    kind: kind,
    raceKm: raceKm,
    segments: ramped,
    climbTops: climbTops,
    sprints: sprints,
    startAltitudeM: altitudeAt(0),
  );
}

/// Finds continuous climbs and writes their length into the segments. Short
/// flat pieces and dips of up to 1 km do not interrupt a climb.
///
/// @param segments Segments of the route, modified in place.
void _markClimbs(List<Segment> segments) {
  var i = 0;
  while (i < segments.length) {
    if (segments[i].grade < 0.025) {
      i++;
      continue;
    }
    var end = i, flatM = 0.0, gain = 0.0, last = i;
    while (end < segments.length) {
      final s = segments[end];
      if (s.grade >= 0.015) {
        flatM = 0;
        last = end;
      } else {
        flatM += s.lengthM;
        if (flatM > 1000) break;
      }
      end++;
    }
    var lengthM = 0.0;
    for (var k = i; k <= last; k++) {
      lengthM += segments[k].lengthM;
      gain += segments[k].grade * segments[k].lengthM;
    }
    // It only counts as a climb from 60 m of gain; below that it is a roller.
    if (gain >= 60) {
      for (var k = i; k <= last; k++) {
        segments[k].climbKm = lengthM / 1000;
      }
    }
    i = last + 1;
  }
}

/// Puts the steepest ramp of each climb back into the route. The profile is
/// averaged over the segment length, which hides short walls such as the
/// Mur de Huy. Where the climb's steepest segment stays clearly below the
/// gradient the stage file names, that segment becomes the ramp and the
/// rest of the climb gets a little flatter, so that the climb keeps its
/// height gain.
///
/// @param segments Segments of the route.
/// @param climbs Climbs with their steepest gradient.
/// @returns The segments, changed where a ramp was missing.
List<Segment> _addRamps(List<Segment> segments, List<ClimbSpan> climbs) {
  if (climbs.isEmpty) return segments;
  final out = [...segments];
  for (final c in climbs) {
    final inside = [
      for (var i = 0; i < out.length; i++)
        if (out[i].km >= c.fromKm &&
            out[i].km + out[i].lengthM / 1000 <= c.toKm)
          i,
    ];
    if (inside.length < 3 || c.maxGrade <= 0.03) continue;
    var steepest = inside.first;
    for (final i in inside) {
      if (out[i].grade > out[steepest].grade) steepest = i;
    }
    final missing = min(0.25, c.maxGrade) - out[steepest].grade;
    if (missing < 0.015) continue;
    // Height the ramp adds, taken from the other segments of the climb.
    final extra = missing * out[steepest].lengthM;
    final rest = inside.where((i) => i != steepest);
    final restM = rest.fold(0.0, (sum, i) => sum + out[i].lengthM);
    Segment regrade(Segment s, double grade) => Segment(
        km: s.km,
        lengthM: s.lengthM,
        grade: grade,
        cobble: s.cobble,
        unpaved: s.unpaved,
        altitudeM: s.altitudeM);
    out[steepest] = regrade(out[steepest], out[steepest].grade + missing);
    for (final i in rest) {
      out[i] = regrade(out[i], out[i].grade - extra / restM);
    }
  }
  return out;
}
