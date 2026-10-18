import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'model.dart';
import 'stage_race.dart';
import 'stage_sim.dart';
import 'tactics.dart';
import 'weather.dart';
import 'world.dart';

/// Version of the messages between the game and the 3D viewer. The viewer
/// refuses a race of another version.
const viewerProtocol = 1;

/// The message that hands a stage to the 3D viewer: the route, the teams
/// and riders, what happened and where every rider was. Numbers per rider
/// and point travel as base64 of little-endian arrays to keep it small.
///
/// @param title Name of the race.
/// @param stage Name of the stage, empty for a one-day race.
/// @param route The stage.
/// @param result Its result; without a recorded track the viewer cannot
///   show it.
/// @param riders The riders at the start.
/// @param teams Teams by id, for their names and colours.
/// @param ownTeam Id of the player's team, whose riders the viewer names.
/// @param seed Seed of the stage, from which the viewer lays out the road.
/// @param kits Folder of the 3D kits from the WorldDB (data/kits), if there.
/// @param kitOf Per team id the key of its kit in that folder.
/// @param raceKey Key of the race for its leader jerseys.
/// @param leaders Who wears which leader's jersey, from [leaderJerseys].
/// @param logo Picture of the race's logo, for the arches and barriers.
/// @param live Whether the stage is watched live: the track then follows in
///   the updates of a [LiveFeed].
/// @param roles Each rider's role, where the result has none yet.
/// @returns A JSON-encodable map.
Map<String, Object?> viewerRace({
  required String title,
  required String stage,
  required SimRoute route,
  required StageResult result,
  required List<SimRider> riders,
  required Map<int, TeamInfo> teams,
  int? ownTeam,
  int seed = 0,
  String? kits,
  Map<int, String> kitOf = const {},
  String raceKey = '',
  Map<String, int> leaders = const {},
  String? logo,
  bool live = false,
  Map<int, Role> roles = const {},
}) {
  final track = result.track;
  final open = exposedSegments(route);
  final segs = route.segments;
  String bytes(TypedData d) =>
      base64Encode(d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));
  final teamIds = {for (final r in riders) r.teamId};
  final weather = result.weather;
  return {
    'type': 'race',
    'protocol': viewerProtocol,
    'title': title,
    'stage': stage,
    'live': live,
    'route': route.name,
    'kind': route.kind.name,
    'seed': seed,
    'raceKm': route.raceKm,
    if (kits != null) 'kits': kits,
    'raceKey': raceKey,
    'leaders': leaders,
    if (logo != null) 'logo': logo,
    'startAltitude': route.startAltitudeM,
    'segments': {
      'km': [for (final s in segs) s.km],
      'length': [for (final s in segs) s.lengthM],
      'altitude': [for (final s in segs) s.altitudeM],
      'grade': [for (final s in segs) s.grade],
      'cobble': [for (final s in segs) s.cobble],
      'unpaved': [for (final s in segs) s.unpaved],
      'climb': [for (final s in segs) s.climbKm],
      'open': [for (var i = 0; i < segs.length; i++) open[i] ? 1 : 0],
      'heading': track?.heading ?? const <double>[],
    },
    'climbs': [
      for (final c in route.climbTops)
        {'km': c.km, 'name': c.name, 'category': c.category},
    ],
    'sprints': [
      for (final p in route.sprints) {'km': p.km, 'name': p.name},
    ],
    'weather': weather == null
        ? null
        : {
            'temperature': weather.temperatureC,
            'rain': weather.rain,
            'wind': weather.windMs,
            'windFrom': weather.windFrom,
          },
    'teams': [
      for (final id in teamIds)
        {
          'id': id,
          'abbr': teams[id]?.abbr ?? '',
          'name': teams[id]?.name ?? '',
          'color': teams[id]?.color ?? '',
          'color2': teams[id]?.color2 ?? '',
          'kit': kitOf[id] ?? '',
        },
    ],
    'riders': [
      for (final r in riders)
        {
          'id': r.id,
          'name': r.name,
          'team': r.teamId,
          'own': r.teamId == ownTeam,
          'role': result.traces[r.id]?.role.name ?? roles[r.id]?.name ?? '',
          'weight': r.massKg,
          'height': r.heightM,
        },
    ],
    'track': track == null
        ? null
        : live
            ? {
                'km': track.km,
                'length': 0,
                'times': const <String, String>{},
                'ranks': const <String, String>{},
                'starts': {
                  for (final e in track.starts.entries) '${e.key}': e.value,
                },
              }
            : {
                'km': track.km,
                'length': track.length,
                'times': {
                  for (final e in track.times.entries)
                    '${e.key}': bytes(e.value),
                },
                'ranks': {
                  for (final e in track.ranks.entries)
                    '${e.key}': bytes(e.value),
                },
                'starts': {
                  for (final e in track.starts.entries) '${e.key}': e.value,
                },
              },
    'events': [
      for (final e in result.events) [e.km, e.type.name, e.text, e.riders],
    ],
    'placings': [
      for (final p in result.placings) [p.rider.id, p.timeS],
    ],
    'abandons': [
      for (final a in result.abandons) [a.rider.id, a.km, a.reason.name],
    ],
    'paused': result.openCall != null,
  };
}

/// Who wears which leader's jersey on a stage: the leaders of the
/// classifications after the stage before. A rider who leads two wears the
/// higher one, and the next of the other classification wears its jersey.
///
/// @param s Standings after the stage before.
/// @returns Per classification (time, points, mountain, young) a rider id.
Map<String, int> leaderJerseys(Standings s) {
  final out = <String, int>{};
  final taken = <int>{};
  void pick(String kind, Iterable<int> order) {
    for (final id in order) {
      if (taken.add(id)) {
        out[kind] = id;
        return;
      }
    }
  }

  pick('time', s.general.map((e) => e.rider.id));
  pick('points', s.points.where((e) => e.points > 0).map((e) => e.rider.id));
  pick('mountain',
      s.mountains.where((e) => e.points > 0).map((e) => e.rider.id));
  pick('young', s.youth.map((e) => e.rider.id));
  return out;
}

/// Hands a stage watched live to the 3D viewer piece by piece: each update
/// carries what has changed since the one before.
class LiveFeed {
  LiveFeed(this.live);

  /// The stage.
  final LiveStage live;

  /// Per rider id: points sent so far.
  final _sent = <int, int>{};
  var _events = 0;

  /// The next update: the race clock, the points the riders have passed
  /// and the next one each is on his way to, new events, the state of the
  /// player's riders and the radio question waiting for an answer.
  ///
  /// @param speed Race seconds per second of the game's clock.
  /// @param paused Whether the race clock stands still.
  /// @param own Ids of the player's riders.
  /// @returns A JSON-encodable map.
  Map<String, Object?> update(
      {required double speed,
      required bool paused,
      Iterable<int> own = const []}) {
    final track = live.track;
    final passes = <String, List<num>>{};
    if (track != null) {
      for (final e in track.times.entries) {
        final times = e.value;
        final ranks = track.ranks[e.key]!;
        final start = track.starts[e.key] ?? 0.0;
        final from = _sent[e.key] ?? 0;
        var to = from;
        // Up to the first point the rider has not reached yet: the viewer
        // needs it to show him on his way there.
        while (to < times.length &&
            !times[to].isNaN &&
            (to == 0 || start + times[to - 1] <= live.clock)) {
          to++;
        }
        if (to > from) {
          passes['${e.key}'] = [
            for (var p = from; p < to; p++) ...[p, times[p], ranks[p]],
          ];
          _sent[e.key] = to;
        }
      }
    }
    final events = live.events;
    final finished = live.finished;
    List<Object> event(RaceEvent e) => [e.km, e.type.name, e.text, e.riders];
    final fresh = events.skip(min(_events, events.length));
    _events = events.length;
    final call = live.openCall;
    final result = live.result;
    return {
      'type': 'live',
      'clock': live.clock,
      'speed': speed,
      'paused': paused || call != null,
      'passes': passes,
      // At the finish the events are put in order once more.
      if (finished)
        'allEvents': [for (final e in events) event(e)]
      else
        'events': [for (final e in fresh) event(e)],
      'out': [
        for (final e in events)
          if (e.type == EventType.abandon) ...e.riders,
      ],
      'own': {
        for (final id in own)
          if (live.rider(id) case final r?)
            '$id': [r.energy, r.reserve, r.order.name, r.out],
      },
      'radio': call == null
          ? null
          : {
              'text': call.text,
              'options': call.options,
              'suggested': call.suggested,
              'remaining': call.remainingKm,
            },
      'timeTrial': live.timeTrial,
      'finished': finished,
      if (result != null)
        'placings': [
          for (final p in result.placings) [p.rider.id, p.timeS],
        ],
    };
  }
}
