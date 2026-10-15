import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sim/sim.dart';

import 'career.dart';
import 'points.dart';

/// What the planner knows about a rider while it draws up the programme.
class _Load {
  _Load(this.rider, this.age);
  final SimRider rider;
  final int age;

  /// Race days planned so far.
  int days = 0;

  /// Grand Tours planned so far, with the day the last one ends.
  int grandTours = 0;
  DateTime? lastGrandTourEnd;

  /// Periods in which he is racing or resting after a stage race.
  final busy = <(DateTime, DateTime)>[];

  /// Race days a season may hold for him: young riders are brought on
  /// slowly, nobody rides more than eighty.
  int get budget => age <= 21
      ? 45
      : age <= 23
          ? 60
          : 80;

  /// Grand Tours he may ride in a season.
  int get grandTourLimit => age <= 21
      ? 0
      : age <= 23
          ? 1
          : 2;
}

/// The sports director's season plan: which rider starts in which race.
///
/// The races are planned in the order of their importance, so that the
/// leaders are placed in the big races first. For each race the riders who
/// suit its stages best are taken, as long as they are free, have race days
/// left and are not already carrying more than their share of the season;
/// the smaller the race, the more that share counts. That spreads the
/// programme over the squad: the stars ride the races that matter, the rest
/// of the calendar goes to the riders who have ridden less.
class SeasonPlanner {
  /// Creates a planner for a career.
  SeasonPlanner(this.c);
  final Career c;

  /// Days a rider rests after a stage race before he starts again, and
  /// around a Grand Tour: before it he races nothing for a few days, after
  /// it he takes a break.
  static const restAfterStageRace = 3;
  static const restBeforeGrandTour = 6;
  static const restAfterGrandTour = 12;

  /// How much a race matters to the team: its tier, more for a race in the
  /// team's own country.
  ///
  /// @param race The race.
  /// @returns A weight; a Grand Tour has 13, a class 2 race 0.4.
  double importance(RaceEntry race, [int? teamId]) =>
      race.tier.factor *
      // What the team is built for.
      styleWeight(race, c.styleOf(teamId ?? c.teamId)) *
      // What sponsor and board ask of the player's team this season.
      ((teamId ?? c.teamId) == c.teamId ? c.sponsorWeight(race) : 1) *
      (race.info.country == c.teams[teamId ?? c.teamId]?.country ? 1.25 : 1) *
      // The Tour comes before the other Grand Tours.
      (race.info.raceClass == 'CWTGTFrance' ? 1.2 : 1);

  /// How much a team of a style values a race: a team built for the
  /// overall the stage races, a classics team the one-day races, a sprint
  /// team the races with many flat finishes.
  ///
  /// @param race The race.
  /// @param style Style of the team.
  /// @returns A factor around 1.
  double styleWeight(RaceEntry race, TeamStyle style) {
    switch (style) {
      case TeamStyle.gc:
        return race.tier == RaceTier.grandTour
            ? 1.3
            : race.isStageRace
                ? 1.2
                : 0.85;
      case TeamStyle.classics:
        return race.isStageRace ? 0.9 : 1.3;
      case TeamStyle.sprint:
        final sprints =
            race.stages.where((s) => _coefficients(s.id)[7] >= 0.45).length;
        return 0.9 + 0.45 * sprints / max(1, race.stages.length);
      case TeamStyle.balanced:
      case TeamStyle.youth:
      case TeamStyle.experience:
        return 1;
    }
  }

  /// Suitability per race and rider, with the attributes it was worked out
  /// from: riders develop during the season, and a value from older
  /// attributes would make the plan depend on when it was first asked (a
  /// loaded game would plan otherwise than the one played on).
  final _fits = <int, Map<int, (List<double>, double)>>{};

  /// How well a rider suits a race: the mean of his suitability for the
  /// three stages that suit him best.
  ///
  /// @param race The race.
  /// @param r The rider.
  /// @returns A value on the attribute scale.
  double fit(RaceEntry race, SimRider r) {
    final byRider = _fits.putIfAbsent(race.info.id, () => {});
    final values = _values(r.attributes);
    final known = byRider[r.id];
    if (known != null && _same(known.$1, values)) return known.$2;
    final fits = [
      for (final s in race.stages) _dot(_coefficients(s.id), values),
    ]..sort((a, b) => b.compareTo(a));
    final top = fits.take(min(3, fits.length));
    final value = top.reduce((a, b) => a + b) / top.length;
    byRider[r.id] = (values, value);
    return value;
  }

  static bool _same(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // The suitability of a rider for a route is a weighted sum of his
  // attributes; the weights depend on the route alone. They are worked out
  // once per stage and kept in a file next to the world database, because
  // building several thousand routes takes seconds and planning the season
  // for every team needs them all.
  static final _weights = <int, List<double>>{};
  static String? _weightsOf;
  static var _weightsDirty = false;

  static List<double> _values(Attributes a) => [
        a.flat, a.mountain, a.mediumMountain, a.hill, a.timeTrial, //
        a.prologue, a.cobble, a.sprint, a.acceleration, a.downhill,
        a.endurance, a.resistance, a.recovery, a.breakaway,
      ];

  static Attributes _unit(int k) {
    double v(int i) => i == k ? 1 : 0;
    return Attributes(
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
    );
  }

  static double _dot(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  File get _weightsFile =>
      File('${File(c.world.path).parent.path}/route_fit.cache.json');

  /// Stamp of the database the stored weights belong to.
  String get _stamp {
    final db = File(c.world.path);
    return '${db.lengthSync()}-${db.lastModifiedSync().millisecondsSinceEpoch}';
  }

  List<double> _coefficients(int stageId) {
    if (_weightsOf != c.world.path) {
      // First use in this process: read what an earlier run stored.
      _weightsOf = c.world.path;
      _weights.clear();
      try {
        final j =
            jsonDecode(_weightsFile.readAsStringSync()) as Map<String, dynamic>;
        if (j['db'] == _stamp) {
          for (final e in (j['stages'] as Map<String, dynamic>).entries) {
            _weights[int.parse(e.key)] = [
              for (final x in e.value as List) (x as num).toDouble(),
            ];
          }
        }
      } on Object {
        // No file yet, or one that cannot be read: work the weights out.
      }
    }
    return _weights.putIfAbsent(stageId, () {
      _weightsDirty = true;
      final route = c.world.route(stageId);
      return [for (var k = 0; k < 14; k++) suitability(route, _unit(k))];
    });
  }

  /// Stores the route weights worked out since the last call.
  void saveWeights() {
    if (!_weightsDirty) return;
    _weightsDirty = false;
    try {
      _weightsFile.writeAsStringSync(jsonEncode({
        'db': _stamp,
        'stages': {
          for (final e in _weights.entries) '${e.key}': e.value,
        },
      }));
    } on FileSystemException {
      // A read-only folder: the weights are worked out again next time.
    }
  }

  /// Forgets what was computed for the races of a season.
  void reset() {
    _fits.clear();
    _sizes.clear();
  }

  final _sizes = <int, int>{};

  /// @param race A race.
  /// @returns Number of riders a team starts with.
  int sizeOf(RaceEntry race) => _sizes.putIfAbsent(
      race.info.id, () => c.world.raceField(race.info.id).ridersPerTeam);

  (DateTime, DateTime) _window(RaceEntry race) {
    final grandTour = race.tier == RaceTier.grandTour;
    return (
      race.start.subtract(Duration(days: grandTour ? restBeforeGrandTour : 0)),
      race.end.add(Duration(
          days: grandTour
              ? restAfterGrandTour
              : race.isStageRace
                  ? restAfterStageRace
                  : 0)),
    );
  }

  bool _free(_Load l, RaceEntry race) {
    final (from, to) = _window(race);
    for (final (a, b) in l.busy) {
      if (!from.isAfter(b) && !a.isAfter(to)) return false;
    }
    return true;
  }

  bool _mayRide(_Load l, RaceEntry race, {required bool strict}) {
    if (!_free(l, race)) return false;
    if (c.isInjured(l.rider.id, race.start)) return false;
    if (race.tier == RaceTier.under23 && l.age > 22) return false;
    final days = race.stages.length;
    if (l.days + days > (strict ? l.budget : 90)) return false;
    if (race.tier == RaceTier.grandTour) {
      if (l.grandTours >= (strict ? l.grandTourLimit : 2)) return false;
      final last = l.lastGrandTourEnd;
      if (last != null && race.start.difference(last).inDays.abs() < 30) {
        return false;
      }
    }
    return true;
  }

  void _book(_Load l, RaceEntry race) {
    l.days += race.stages.length;
    l.busy.add(_window(race));
    if (race.tier == RaceTier.grandTour) {
      l.grandTours++;
      l.lastGrandTourEnd = race.end;
    }
  }

  /// Draws up the programme.
  ///
  /// @param squad The team's riders.
  /// @param races The races to plan; championships are left out, their
  ///   line-ups are picked by the federations.
  /// @param fixed Races that are already planned, by race id; they are kept
  ///   as they are and count towards the riders' load.
  /// @param all All races of the season the team rides, for the share of
  ///   race days a rider should get; defaults to [races].
  /// @param teamId The team, for its home races; defaults to the player's.
  /// @param wishes Goal races per rider id: a rider starts in his goal
  ///   races if he is free and fit for them, whatever else is planned.
  /// @returns The planned riders per race id, for the races of [races] not
  ///   in [fixed].
  Map<int, Set<int>> plan(
    List<SimRider> squad,
    List<RaceEntry> races, {
    Map<int, Set<int>> fixed = const {},
    List<RaceEntry>? all,
    int? teamId,
    Map<int, Set<int>> wishes = const {},
  }) {
    if (squad.isEmpty) return const {};
    final loads = {
      for (final r in squad) r.id: _Load(r, c.year - r.born ~/ 10000),
    };
    final season = [
      for (final r in all ?? races)
        if (r.tier != RaceTier.championship) r,
    ];
    // What is fixed is booked first.
    for (final race in season) {
      for (final id in fixed[race.info.id] ?? const <int>{}) {
        final l = loads[id];
        if (l != null) _book(l, race);
      }
    }
    // An even share of all rider days of the season.
    final riderDays = season.fold<int>(
        0, (n, r) => n + r.stages.length * min(sizeOf(r), squad.length));
    final share = riderDays / squad.length;

    final open = [
      for (final r in races)
        if (r.tier != RaceTier.championship && !fixed.containsKey(r.info.id)) r,
    ]..sort((a, b) {
        final byWeight = importance(b, teamId).compareTo(importance(a, teamId));
        return byWeight != 0 ? byWeight : a.start.compareTo(b.start);
      });
    final out = <int, Set<int>>{};
    // Goal races come first: whoever builds his season around a race
    // starts in it.
    for (final race in open) {
      for (final l in loads.values) {
        if (!(wishes[l.rider.id]?.contains(race.info.id) ?? false)) continue;
        final seats = out.putIfAbsent(race.info.id, () => {});
        if (seats.length >= sizeOf(race)) continue;
        if (!_mayRide(l, race, strict: false)) continue;
        _book(l, race);
        seats.add(l.rider.id);
      }
    }
    for (final race in open) {
      final size = sizeOf(race) - (out[race.info.id]?.length ?? 0);
      final days = race.stages.length;
      // In a big race suitability decides; in a small one the riders who
      // have ridden less than their share come first.
      final evenness =
          (1.5 / (1 + importance(race, teamId) / 3)).clamp(0.3, 1.2);
      double value(_Load l) {
        // Above his share of the season a rider is taken less and less
        // readily; far below it he is preferred.
        final over = l.days + days - share;
        final load = over > 0 ? (over / 6) * (over / 6) : over / 8;
        // A second Grand Tour is the exception, not the rule.
        final second =
            race.tier == RaceTier.grandTour && l.grandTours >= 1 ? 5.0 : 0.0;
        return fit(race, l.rider) - evenness * load - second;
      }

      var pool = [
        for (final l in loads.values)
          if (!(out[race.info.id]?.contains(l.rider.id) ?? false) &&
              _mayRide(l, race, strict: true))
            l,
      ];
      if (pool.length < size) {
        // Too few riders within their limits: stretch them rather than
        // start short.
        pool = [
          for (final l in loads.values)
            if (!(out[race.info.id]?.contains(l.rider.id) ?? false) &&
                _mayRide(l, race, strict: false))
              l,
        ];
      }
      pool.sort((a, b) {
        final byValue = value(b).compareTo(value(a));
        return byValue != 0 ? byValue : a.rider.id.compareTo(b.rider.id);
      });
      // A team does not send all its leaders to the same Grand Tour: of
      // its five best riders for such a race at most two start together,
      // the others lead in the next one.
      final stars = <int>{};
      if (race.tier == RaceTier.grandTour) {
        final best = [...loads.values]
          ..sort((a, b) => fit(race, b.rider).compareTo(fit(race, a.rider)));
        stars.addAll(best.take(5).map((l) => l.rider.id));
      }
      final picked = <_Load>[], spare = <_Load>[];
      var leaders = 0;
      for (final l in pool) {
        if (picked.length >= size) break;
        if (stars.contains(l.rider.id)) {
          if (leaders >= 2) {
            spare.add(l);
            continue;
          }
          leaders++;
        }
        picked.add(l);
      }
      // Too few others: then the leaders ride together after all.
      picked.addAll(spare.take(size - picked.length));
      for (final l in picked) {
        _book(l, race);
      }
      out
          .putIfAbsent(race.info.id, () => {})
          .addAll([for (final l in picked) l.rider.id]);
    }
    return out;
  }

  /// Finds a replacement for a rider who cannot start in a planned race.
  ///
  /// @param squad The team's riders.
  /// @param race The race.
  /// @param program The season plan, by race id.
  /// @param all All races of the season the team rides.
  /// @returns The best-suited rider who is free then and not planned for
  ///   the race, or null if there is none.
  SimRider? substitute(List<SimRider> squad, RaceEntry race,
      Map<int, Set<int>> program, List<RaceEntry> all) {
    final loads = {
      for (final r in squad) r.id: _Load(r, c.year - r.born ~/ 10000),
    };
    for (final other in all) {
      if (other.info.id == race.info.id) continue;
      for (final id in program[other.info.id] ?? const <int>{}) {
        final l = loads[id];
        if (l != null) _book(l, other);
      }
    }
    final planned = program[race.info.id] ?? const <int>{};
    for (final strict in [true, false]) {
      final pool = [
        for (final l in loads.values)
          if (!planned.contains(l.rider.id) &&
              _mayRide(l, race, strict: strict))
            l,
      ]..sort((a, b) => fit(race, b.rider).compareTo(fit(race, a.rider)));
      if (pool.isNotEmpty) return pool.first.rider;
    }
    return null;
  }
}
