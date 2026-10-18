import 'i18n.dart';
import 'dart:math';

import 'material.dart';

import 'model.dart';
import 'physics.dart';
import 'tactics.dart';
import 'trace.dart';
import 'tuning.dart';
import 'weather.dart';

/// Condition a rider brings into a stage.
class RiderCondition {
  const RiderCondition({this.form = 1.0, this.energy = 1.0});

  /// Factor on threshold power (1.0 = normal form).
  final double form;

  /// Fill level of the endurance reserve at the start, 0 to 1.
  final double energy;
}

/// A rider's state during the stage.
class _State {
  _State(this.rider, this.form, this.energy, [this.kit = TeamKit.average])
      : mass = rider.massKg + bikeMassKg + kit.bikeKg,
        cda = soloCda * cdaScale(rider) * kit.aero;
  final SimRider rider;
  final double form;

  /// Material and staff of his team.
  final TeamKit kit;

  /// What his power meter records.
  final tally = _PowerTally();

  /// Factor on the rolling resistance of a segment: tyre brand and the
  /// tyres of the day.
  ///
  /// @param s The segment.
  /// @param wet Whether the road is wet.
  /// @returns The factor.
  double roll(Segment s, bool wet) =>
      kit.rolling * kit.tyres.rolling(s.rough, wet: wet);

  /// Factor on his chance of a puncture on a segment.
  ///
  /// @param s The segment.
  /// @returns The factor.
  double punctureRisk(Segment s) =>
      kit.punctures * kit.tyres.punctures(s.rough) * kit.mechanicalRate;

  /// Mass of rider and bike in kg.
  final double mass;

  /// Factor on his energy use in the heat or cold of the day.
  double climate = 1;

  /// Drag area alone in the wind.
  final double cda;

  /// Endurance reserve, drains over the stage.
  double energy;

  /// Short-term reserve for efforts above threshold.
  double reserve = 1;

  /// Threshold power at the start of the stage, for the power zones.
  double ftp = 0;
  Role role = Role.domestique;
  late TeamPlan plan;
  bool favorite = false;

  /// Suitability for the route, see [suitability].
  double fit = 0;
  bool inBreak = false;
  bool droppedReported = false;

  /// Was in the break of the day, even if it was caught later.
  bool everInBreak = false;

  /// Kilometre at which he fell behind the favourites' group, null while he
  /// is in it or ahead of it.
  double? lostKm;

  /// Kilometres spent setting the pace.
  double frontKm = 0;

  /// Radio instruction: do not take turns in the group.
  bool passenger = false;

  /// Gap in the general classification before the stage, null without one.
  double? gcGap;

  /// Threshold power per segment without fatigue, for his build and the
  /// altitude of the segment.
  late List<double> basePower;

  /// Threshold power on the current segment, fatigue included.
  double thr = 0;

  /// How well he is placed in his group; higher is further forward.
  double pos = 0;

  /// His place in the group by [pos], 0 = at the front.
  int rank = 0;

  /// The luck of the current fight for position.
  double posLuck = 0;

  /// Extra effort he spends on the current segment to hold his position.
  double extraEffort = 0;

  /// A helper who has emptied himself and can no longer ride on the front.
  bool blown = false;

  /// Power lost through a crash during this stage.
  double hurt = 0;

  /// Left the race during the stage.
  bool out = false;

  /// Worst mishap of the day.
  RiderIncident incident = RiderIncident.none;

  /// Riders of the group he was in when he had a mishap inside the last
  /// three kilometres; he gets their time.
  List<_State>? ruleMates;
}

/// Sums up a rider's power over a stage.
class _PowerTally {
  double seconds = 0, joules = 0, fourth = 0;
  final zones = List<double>.filled(6, 0);

  /// Per climb index: seconds, joules and metres climbed.
  final climbs = <int, List<double>>{};

  static const _bounds = [0.55, 0.75, 0.9, 1.05, 1.2];

  /// Records power held for a while.
  ///
  /// @param watts Power in watts.
  /// @param dt Seconds.
  /// @param ftp Threshold power for the zones.
  /// @param climb Index of the climb the segment belongs to, or -1.
  /// @param gainM Metres climbed on the segment.
  void add(double watts, double dt, double ftp, int climb, double gainM) {
    if (dt <= 0 || !watts.isFinite) return;
    final w = max(0.0, watts);
    seconds += dt;
    joules += w * dt;
    fourth += pow(w, 4) * dt;
    final x = ftp > 0 ? w / ftp : 0.0;
    var z = 0;
    while (z < _bounds.length && x >= _bounds[z]) {
      z++;
    }
    zones[z] += dt;
    if (climb >= 0) {
      final c = climbs.putIfAbsent(climb, () => [0, 0, 0]);
      c[0] += dt;
      c[1] += w * dt;
      c[2] += gainM;
    }
  }

  /// @param ftp Threshold power at the start.
  /// @param massKg Body weight.
  /// @param tops The climbs of the route.
  /// @returns The figures.
  PowerStats result(double ftp, double massKg, List<RoutePoint> tops) =>
      PowerStats(
        seconds,
        seconds > 0 ? joules / seconds : 0,
        seconds > 0 ? pow(fourth / seconds, 0.25).toDouble() : 0,
        joules / 1000,
        ftp,
        massKg,
        [...zones],
        [
          for (final e
              in climbs.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key)))
            if (e.key < tops.length && e.value[0] > 0)
              ClimbPower(tops[e.key].name, tops[e.key].km, tops[e.key].category,
                  e.value[0], e.value[1] / e.value[0], e.value[2], massKg),
        ],
      );
}

/// Riders travelling together, with their shared clock.
class _Group {
  _Group(this.members, this.clock);
  List<_State> members;

  /// Riding time in seconds at the current kilometre.
  double clock;
  double surgeKm = 0;
  _State? surgeLeader;

  /// Whether the group has given up racing and only rides to the finish.
  bool gruppetto = false;

  /// Riders coming back after a mishap, in the shelter of the team cars.
  bool convoy = false;
}

/// How well a rider suits a route.
///
/// @param route The stage.
/// @param a The rider's attributes.
/// @returns A value on the attribute scale; higher is better.
double suitability(SimRoute route, Attributes a) {
  if (route.kind != StageKind.road) {
    return route.raceKm < 8 ? a.prologue : a.timeTrial;
  }
  if (route.sprintStage) {
    return 0.6 * a.sprint + 0.2 * a.acceleration + 0.2 * a.flat;
  }
  // Selective segments count more, the last third counts double.
  var sum = 0.0, weight = 0.0;
  for (final s in route.segments) {
    var w = (0.2 + max(0.0, s.grade - 0.02) * 40 + s.cobble * 0.5) *
        s.lengthM /
        500;
    if (s.km > route.raceKm * 0.66) w *= 2;
    sum += w * effectiveAttribute(s, a);
    weight += w;
  }
  final base = sum / weight;
  // Flat finish after a hard race: finishing speed helps a little.
  return route.finishGrade < 0.03
      ? 0.85 * base + 0.15 * (0.5 * a.sprint + 0.5 * a.acceleration)
      : base;
}

/// Time limit of a stage as a share of the winner's time, simplified after
/// the rules of the Grand Tours: the faster and the flatter the stage, the
/// tighter the limit.
///
/// @param route The stage.
/// @param winnerKmh Average speed of the winner.
/// @returns E.g. 0.12 for twelve per cent; 0 for team time trials.
double timeLimitShare(SimRoute route, double winnerKmh) {
  switch (route.kind) {
    case StageKind.teamTimeTrial:
      return 0;
    case StageKind.timeTrial:
      return 0.25;
    case StageKind.road:
      if (route.sprintStage) {
        return winnerKmh >= 45
            ? 0.12
            : winnerKmh >= 42
                ? 0.1
                : 0.08;
      }
      if (route.selectivity > 1500) {
        return winnerKmh >= 38
            ? 0.18
            : winnerKmh >= 35
                ? 0.16
                : 0.14;
      }
      return winnerKmh >= 42 ? 0.14 : 0.12;
  }
}

/// @param r Random source.
/// @returns A standard normal sample.
double _gauss(Random r) {
  final u = max(r.nextDouble(), 1e-12);
  return sqrt(-2 * log(u)) * cos(2 * pi * r.nextDouble());
}

/// Lists rider names for an event text.
///
/// @param riders Riders to name.
/// @param limit Number of names before the rest is summarised.
/// @returns A comma-separated list.
String _names(Iterable<_State> riders, [int limit = 6]) {
  final list = riders.map((s) => s.rider.name).toList();
  if (list.length <= limit) return list.join(', ');
  return tr(
      '{0} and {1} more', [list.take(limit).join(', '), list.length - limit]);
}

/// Simulates a stage or one-day race.
///
/// @param route The stage.
/// @param riders Start list.
/// @param seed Seed; the same seed and inputs give the same result.
/// @param conditions Form and energy per rider id.
/// @param plans Tactics per team id; for teams without one the simulation
///   draws up its own plan.
/// @param gcGaps Gaps in the general classification before the stage.
/// @param directorSkills Quality of the sports director per team, 0 to 1.
/// @param radioTeam Team that may be asked over the radio.
/// @param radio Answers of that team per question.
/// @param askRadio Whether to pause at the first unanswered question.
/// @param tuning Tuning values.
/// @param month Month of the race, for the weather.
/// @param country Country of the race, for the weather.
/// @param weather Weather of the day; drawn from the seed if null.
/// @param illness Chance per rider that he is ill and gives up during the stage.
/// @param kits Material, staff and style per team id; teams without one
///   ride on average material.
/// @param mountainLeaders Riders in the running for the mountains jersey.
/// @param track Whether to record where every rider was, for the 3D view.
/// @returns The result, or a paused result with [StageResult.openCall] set.
StageResult simulateStage(
  SimRoute route,
  List<SimRider> riders, {
  required int seed,
  Map<int, RiderCondition> conditions = const {},
  Map<int, TeamPlan> plans = const {},
  Map<int, double> gcGaps = const {},
  Map<int, double> directorSkills = const {},
  int? radioTeam,
  Map<RadioKind, int> radio = const {},
  bool askRadio = false,
  SimTuning? tuning,
  int month = 6,
  String country = '',
  Weather? weather,
  double illness = 0,
  Map<int, TeamKit> kits = const {},
  Set<int> mountainLeaders = const {},
  bool track = false,
}) {
  final rng = Random(seed);
  tuning ??= SimTuning.standard;
  weather ??= Weather.draw(Random(seed * 31 + 7), month, country);
  final wind = windAlong(route, weather, Random(seed * 17 + 3));
  final allPlans = {
    ...autoPlans(route, riders,
        gcGaps: gcGaps,
        styles: {for (final e in kits.entries) e.key: e.value.style},
        crosswindKm: crosswindKm(route, wind),
        mountainLeaders: mountainLeaders),
    ...plans,
  };
  // Quality of the sports director per team, 0 to 1; without an entry the
  // value in the plan applies (0.7 as the average).
  for (final e in directorSkills.entries) {
    final plan = allPlans[e.key];
    if (plan != null) allPlans[e.key] = plan.withDirector(e.value);
  }
  final states = [
    for (final r in riders)
      _State(
        r,
        (conditions[r.id]?.form ?? 1) * (1 + tuning.dayFormSigma * _gauss(rng)),
        conditions[r.id]?.energy ?? 1,
        kits[r.teamId] ?? TeamKit.average,
      )
        ..plan = allPlans[r.teamId]!
        ..role = allPlans[r.teamId]!.roleOf(r.id)
        ..gcGap = gcGaps[r.id]
        ..climate = climateCost(weather.temperatureC, r),
  ];
  final recorded = track
      ? RaceTrack([
          for (final s in route.segments) s.km + s.lengthM / 1000,
        ], [
          for (final r in riders) r.id,
        ])
      : null;
  recorded?.heading = wind.heading;
  final StageResult result;
  if (route.kind != StageKind.road) {
    result = _timeTrial(route, states, rng, tuning, weather, wind, recorded);
  } else {
    final race = _RoadRace(route, states, rng, tuning, weather, wind)
      ..track = recorded
      ..kitted = kits.isNotEmpty
      ..radioTeam = radioTeam
      ..radio = radio
      ..askRadio = askRadio
      ..illness = illness;
    try {
      result = race.run();
    } on _RadioStop catch (stop) {
      // The race so far, for the fast motion up to the question.
      return StageResult(const [], race.events, false)
        ..openCall = stop.call
        ..timeline = race._timeline
        ..weather = weather
        ..track = recorded;
    }
  }
  return result
    ..weather = weather
    ..track = recorded;
}

/// Kilometres of open, flat road on which the crosswind blows at 5 m/s or
/// more: where a team can split the field.
///
/// @param route The stage.
/// @param wind Wind along the route.
/// @returns Kilometres.
double crosswindKm(SimRoute route, WindField wind) {
  var km = 0.0;
  for (var i = 0; i < route.segments.length; i++) {
    final s = route.segments[i];
    if (wind.cross[i] >= 5 && s.grade.abs() < 0.02) km += s.lengthM / 1000;
  }
  return km;
}

/// Which categorised climb each segment belongs to, for the power figures.
/// A climb starts at the lowest point between the previous top and its own,
/// at most 35 km before the top.
///
/// @param route The stage.
/// @returns Per segment the index of the climb in [SimRoute.climbTops], or -1.
List<int> climbSegments(SimRoute route) {
  final segs = route.segments;
  final out = List.filled(segs.length, -1);
  final tops = [...route.climbTops.indexed]
    ..sort((a, b) => a.$2.km.compareTo(b.$2.km));
  var previous = -1;
  for (final (c, point) in tops) {
    final t = segs.lastIndexWhere((s) => s.km <= point.km);
    if (t < 0) continue;
    var foot = t;
    for (var i = t; i > previous && point.km - segs[i].km <= 35; i--) {
      if (segs[i].altitudeM < segs[foot].altitudeM) foot = i;
    }
    for (var i = foot; i <= t; i++) {
      out[i] = c;
    }
    previous = t;
  }
  return out;
}

/// Pauses the stage at a question that has no answer yet.
class _RadioStop implements Exception {
  _RadioStop(this.call);
  final RadioCall call;
}

/// One run of a road stage: the state of all groups and the rules that move them.
class _RoadRace {
  _RoadRace(this.route, this.states, this.rng, this.t, this.weather, this.wind);

  final SimRoute route;
  final List<_State> states;
  final Random rng;
  final SimTuning t;
  final Weather weather;
  final WindField wind;
  final events = <RaceEvent>[];
  final awards = <PointAward>[];
  final abandons = <Abandon>[];
  final injuries = <int, Injury>{};
  final _lastAttackKm = <int, double>{};
  bool _gruppettoReported = false;
  double _nextReassignKm = 5;
  final _timeline = <RaceSample>[];
  double _nextSampleKm = 2;

  /// Where every rider was, for the 3D view; null unless asked for.
  RaceTrack? track;

  /// Chance per rider that he is ill and gives up.
  double illness = 0;

  /// Whether the teams bring material and staff of their own. Without
  /// them every rider has the same chances.
  bool kitted = false;

  /// Per segment the index of the climb it belongs to, or -1.
  late final List<int> _climbOf;

  // --- Sports directors -------------------------------------------------------
  // Every team has a sports director who decides at the same points of the
  // race by the same rules. The decisions of the team [radioTeam] can be
  // overruled: if [radio] holds an answer it applies; otherwise [askRadio]
  // pauses the stage, or the director's own choice stands.
  int? radioTeam;
  Map<RadioKind, int> radio = const {};
  bool askRadio = false;
  final _asked = <RadioKind>{};

  /// Teams whose helpers ride on the front until they are empty.
  final _driving = <int>{};

  /// Teams that wait for the finish and do not attack themselves.
  final _waiting = <int>{};

  /// Riders told to attack at the next hard section.
  final _forced = <_State>{};

  /// Teams that have already sent a rider after a rival's attack.
  final _reacted = <int>{};
  bool _finaleDecided = false;

  bool _own(_State m) => m.rider.teamId == radioTeam;

  /// Puts a decision of the radio team to the player, or takes the answer
  /// already given.
  ///
  /// @param kind Which decision point this is.
  /// @param km Race kilometre of the question.
  /// @param text Situation report.
  /// @param options Possible instructions.
  /// @param suggested What the sports director would do himself.
  /// @returns Index of the chosen option.
  /// @throws _RadioStop If there is no answer and [askRadio] is set.
  int _ask(RadioKind kind, double km, String text, List<String> options,
      int suggested) {
    _asked.add(kind);
    final answer = radio[kind];
    if (answer != null) return answer.clamp(0, options.length - 1);
    if (askRadio) {
      throw _RadioStop(RadioCall(
          kind, km, route.raceKm - km, text.replaceAll('..', '.'), options)
        ..suggested = suggested);
    }
    return suggested;
  }

  /// Changes a team's plan for the rest of the stage.
  ///
  /// @param team Team id.
  /// @param change Maps the current plan to the new one.
  void _setPlan(int team, TeamPlan Function(TeamPlan) change) {
    for (final m in states) {
      if (m.rider.teamId == team) m.plan = change(m.plan);
    }
  }

  String _reserveText(_State m) => m.reserve > 0.7 && m.energy > 0.55
      ? tr('looks fresh')
      : m.reserve > 0.4 && m.energy > 0.35
          ? tr('has something left in the tank')
          : tr('is on the limit');

  /// Decision point for every team: the break of the day has formed.
  ///
  /// @param escape The breakaway group.
  /// @param peloton The field.
  /// @param km Race kilometre.
  void _breakDecisions(_Group escape, _Group peloton, double km) {
    final danger = hasGc
        ? escape.members
            .where((m) => m.gcGap != null && m.gcGap! < 300)
            .toList()
        : const <_State>[];
    String head() => tr('Km {0}: {1} riders are away – {2}.{3}', [
          km.round(),
          escape.members.length,
          _names(escape.members, 5),
          danger.isEmpty
              ? ''
              : tr(' Dangerous for the general classification: {0}.',
                  [_names(danger, 3)])
        ]);
    final teams = {
      for (final m in escape.members) m.rider.teamId,
      for (final m in peloton.members) m.rider.teamId,
    }.toList()
      ..sort();
    var bridged = 0;
    for (final team in teams) {
      bool of(_State m) => m.rider.teamId == team;
      final mine = escape.members.where(of).toList();
      final field = peloton.members.where(of).toList();
      final asks = team == radioTeam;
      if (mine.isNotEmpty) {
        // A team that controls the race for a favourite in the field keeps
        // its man in the break off the front.
        final suggested = mine.first.plan.approach != Approach.wait &&
                field.any((m) => m.favorite)
            ? 1
            : 0;
        final a = asks
            ? _ask(
                RadioKind.breakGone,
                km,
                tr('{0} With them from us: {1}.', [head(), _names(mine)]),
                [
                  tr('Work with the group, it should stay away'),
                  tr('Do not work, save energy'),
                ],
                suggested)
            : suggested;
        if (a == 1) {
          for (final m in mine) {
            m.passenger = true;
          }
        }
        continue;
      }
      if (field.isEmpty) continue;
      // Who could bridge: no protected rider, preferably one who was meant
      // for the break anyway.
      double chaseScore(_State m) =>
          m.rider.attributes.breakaway +
          (m.role == Role.breakaway ||
                  m.role == Role.stageHunter ||
                  m.role == Role.mountainHunter ||
                  m.role == Role.pointsHunter
              ? 20
              : 0) -
          (hasGc && m.gcGap != null && m.gcGap! < 180 ? 40 : 0);
      final chaser =
          (field.where((m) => !m.role.sheltered && !m.favorite).toList()
                ..sort((a, b) => chaseScore(b).compareTo(chaseScore(a))))
              .firstOrNull;
      final plan = field.first.plan;
      // A team defending a place on the podium does not let a rival go.
      final defends = danger.isNotEmpty &&
          field.any((m) => m.gcGap != null && m.gcGap! < 90);
      var suggested = 0;
      if (defends && plan.breakPolicy != BreakPolicy.chase) {
        suggested = 1;
      } else if (chaser != null &&
          plan.breakPolicy == BreakPolicy.join &&
          escape.members.length < 8 &&
          bridged < 2 &&
          rng.nextDouble() < 0.1 + 0.25 * plan.directorSkill) {
        // The team wanted a man up the road and missed the move.
        suggested = 2;
      }
      final a = asks
          ? _ask(
              RadioKind.breakGone,
              km,
              tr('{0} None of ours is there.', [head()]),
              [
                tr('Stick to the plan'),
                tr('Chase: our helpers to the front of the peloton'),
                if (chaser != null)
                  tr('{0} should bridge across', [chaser.rider.name]),
              ],
              suggested)
          : suggested;
      if (a == 1) {
        _setPlan(
            team,
            (p) => p.copyWith(
                breakPolicy: BreakPolicy.chase,
                approach:
                    p.approach == Approach.wait ? Approach.control : null));
      } else if (a == 2 && chaser != null) {
        // Jumping across costs energy.
        bridged++;
        peloton.members.remove(chaser);
        chaser
          ..inBreak = true
          ..everInBreak = true
          ..energy -= 0.04
          ..reserve = 0.4;
        escape.members.add(chaser);
        events.add(RaceEvent(
            km,
            EventType.breakaway,
            tr('{0} gives chase and bridges to the group', [chaser.rider.name]),
            [chaser.rider.id]));
      }
    }
  }

  /// Decision point for every team with riders among the favourites: the
  /// finale begins.
  ///
  /// @param groups All groups, first on the road first.
  /// @param main The group with the favourites.
  /// @param s Current segment.
  void _finaleDecisions(List<_Group> groups, _Group main, Segment s) {
    if (_finaleDecided) return;
    _finaleDecided = true;
    final flatFinish = route.finishGrade <= 0.035;
    double speed(_State m) =>
        0.7 * m.rider.attributes.sprint + 0.3 * m.rider.attributes.acceleration;
    // The favourites by finishing speed and all leaders by strength.
    final fast = main.members
        .where((m) => m.favorite && m.role.ridesForHimself)
        .toList()
      ..sort((a, b) => speed(b).compareTo(speed(a)));
    final strong = main.members.where((m) => m.role.ridesForHimself).toList()
      ..sort((a, b) => b.fit.compareTo(a.fit));
    final gap = main.clock - groups.first.clock;
    final teams = {for (final m in main.members) m.rider.teamId}.toList()
      ..sort();
    for (final team in teams) {
      final mine = main.members.where((m) => m.rider.teamId == team).toList();
      final leaders = mine.where((m) => m.role.ridesForHimself).toList()
        ..sort((a, b) => b.fit.compareTo(a.fit));
      final helpers = mine.where((m) => m.role.works && !m.blown).length;
      final drive = helpers > 0 ? 1 : 0;
      final canAttack = !sprintStage && leaders.isNotEmpty;
      // What the sports director makes of it.
      var suggested = 0;
      if (leaders.isNotEmpty) {
        final lead = leaders.first;
        final fresh = lead.reserve > 0.7 && lead.energy > 0.55;
        final spent = !(lead.reserve > 0.4 && lead.energy > 0.35);
        final speedRank = fast.indexOf(lead);
        final fitRank = strong.indexOf(lead);
        if (sprintStage) {
          // The gap is still open: everything to the front.
          if (gap > 30 && helpers >= 2 && lead.favorite) suggested = drive;
        } else if (spent) {
          suggested = drive + 2;
        } else if (flatFinish &&
            speedRank >= 0 &&
            speedRank < max(1, (fast.length * 0.3).round())) {
          // One of the fastest finishers: keep it together and wait.
          suggested = drive + 2;
        } else if (helpers >= 2 && fitRank < 3 && main.members.length > 30) {
          // One of the strongest with helpers left: make the selection.
          suggested = drive;
        } else if (flatFinish && speedRank >= fast.length * 0.6 && fresh) {
          // Would lose a sprint: has to go before the line.
          suggested = drive + 1;
        }
      }
      var a = suggested;
      if (team == radioTeam) {
        final ahead = gap > 1
            ? tr(
                'Up front {0} riders with a lead of {1}, behind them the peloton with {2} riders.',
                [
                    groups.first.members.length,
                    _clock(gap),
                    main.members.length
                  ])
            : tr('The peloton is together with {0} riders.',
                [main.members.length]);
        final own = leaders.isEmpty
            ? tr('{0} of our riders are there, no leader.', [mine.length])
            : tr('{0} {1}, {2} helpers are still with him.', [
                leaders.first.rider.name,
                _reserveText(leaders.first),
                helpers
              ]);
        a = _ask(
            RadioKind.finale,
            s.km,
            tr('{0} km to go, the finale begins. {1} {2}',
                [(route.raceKm - s.km).round(), ahead, own]),
            [
              tr('Stick to the plan'),
              if (helpers > 0)
                tr('Sacrifice the helpers: full gas until they blow up'),
              if (canAttack) ...[
                tr('{0} attacks on the next hard section',
                    [leaders.first.rider.name]),
                tr('Only follow, do not attack'),
              ],
            ],
            suggested);
      }
      if (a == drive && drive == 1) {
        _driving.add(team);
      } else if (canAttack && a == drive + 1) {
        _forced.add(leaders.first);
      } else if (canAttack && a == drive + 2) {
        _waiting.add(team);
      }
    }
  }

  late final double finaleKm;
  late final bool sprintStage;
  late final bool sectorRace;
  late final bool hasGc;
  late final double favoriteLevel;
  late final double dayMood;
  late final bool uphillFinish;
  late int seg;

  // Per segment: air density, rolling resistance and whether a key point
  // (cobbles, foot of a climb, crosswind, finale) lies just ahead.
  late final List<double> _rho;
  late final List<double> _crr;
  late final List<bool> _key;

  /// Per segment whether the key point ahead is a cobbled or unpaved sector.
  late final List<bool> _sectorKey;

  /// Decided per five-kilometre block of crosswind: which team splits the
  /// field there, or -1 if nobody does.
  final _echelonBlock = <int, int>{};

  bool get _wet => weather.rain;

  double _threshold(_State s) => s.thr;

  /// Threshold power on the current segment with the fatigue of the day.
  ///
  /// @param s The rider.
  /// @returns Power in watts.
  double _computeThreshold(_State s) =>
      s.basePower[seg] *
      s.form *
      (1 - s.hurt) *
      (1 - t.fatigueLoss * pow(1 - s.energy.clamp(0.0, 1.0), 1.5));

  /// Simulates the stage segment by segment.
  ///
  /// @returns The stage result.
  StageResult run() {
    final segments = route.segments;
    _rho = [for (final s in segments) airDensity(s.altitudeM)];
    _crr = [for (final s in segments) rollingResistance(s, wet: _wet)];
    _sectorKey = List.filled(segments.length, false);
    _key = _keyPoints();
    for (final s in states) {
      s.basePower = [
        for (final x in segments)
          thresholdPower(effectiveAttribute(x, s.rider.attributes), t) *
              bodyScale(s.rider, x.grade) *
              altitudePower(x.altitudeM),
      ];
    }
    // Favourites are the strongest riders who are allowed to ride for themselves.
    for (final s in states) {
      s.fit = suitability(route, s.rider.attributes);
      final sorted = [...s.basePower]..sort();
      s.ftp = sorted.isEmpty ? 0 : sorted[sorted.length ~/ 2] * s.form;
    }
    _climbOf = climbSegments(route);
    final ranked = states.where((s) => s.role.ridesForHimself).toList()
      ..sort((a, b) => b.fit.compareTo(a.fit));
    favoriteLevel = ranked.isEmpty
        ? 70
        : ranked.length > 11
            ? ranked[11].fit
            : ranked.last.fit;
    for (final s in ranked.take(12)) {
      s.favorite = true;
    }
    sprintStage = route.sprintStage;
    sectorRace = route.sectorRace;
    uphillFinish = route.finishGrade > 0.035;
    // The general classification only matters once it has gaps. Then the top
    // ten are among the riders the field watches.
    final withGap = states.where((s) => s.gcGap != null).toList()
      ..sort((a, b) => a.gcGap!.compareTo(b.gcGap!));
    hasGc = withGap.length > 20 && withGap[20].gcGap! > 60;
    if (hasGc && !sprintStage) {
      for (final s in withGap.take(10)) {
        s.favorite = true;
      }
    }
    finaleKm = _finaleStart();
    // Mood of the day in the field: sometimes it chases early, sometimes it lets go.
    dayMood = 0.96 + 0.07 * rng.nextDouble();
    events.add(RaceEvent(
        0, EventType.weather, tr('Weather: {0}', [weather.describe()])));

    // Riders who are ill give up somewhere in the first half.
    final sick = <_State, double>{};
    if (illness > 0) {
      for (final s in states) {
        if (rng.nextDouble() < illness) {
          sick[s] = rng.nextDouble() * route.raceKm * 0.5;
        }
      }
    }

    seg = 0;
    for (final s in states) {
      s.thr = _computeThreshold(s);
    }
    var groups = [
      _Group([...states], 0)
    ];
    _position(groups.first, fresh: true);
    var breakFormed = false;
    var maxGap = 0.0, maxGapKm = 0.0;
    final pending = <RoutePoint>[...route.climbTops, ...route.sprints]
      ..sort((a, b) => a.km.compareTo(b.km));

    for (seg = 0; seg < segments.length; seg++) {
      final s = segments[seg];
      final inFinale = s.km >= finaleKm;
      _inFinale = inFinale;
      for (final m in states) {
        if (m.out) continue;
        m.thr = _computeThreshold(m);
        if (!_key[seg]) m.extraEffort = 0;
      }
      for (final e in sick.entries) {
        if (!e.key.out && s.km >= e.value) {
          _abandon(
              e.key, groups, s.km, AbandonReason.illness, 3 + rng.nextInt(6));
        }
      }
      groups.removeWhere((g) => g.members.isEmpty);

      // The fight for the break: the field rides hard until a move sticks.
      final fighting = !breakFormed && s.km < finaleKm;
      if (fighting &&
          s.km >= 1.5 &&
          rng.nextDouble() < _stickChance(s, groups)) {
        breakFormed = true;
        // The break goes from the field, which is not always the group at
        // the head of the race: stragglers of an early split may lead.
        final field = _mainGroup(groups);
        final escape = _formBreak(field, s);
        if (escape != null) {
          _breakDecisions(escape, field, s.km);
          groups.insert(0, escape);
        }
      } else if (!breakFormed && s.km >= finaleKm) {
        breakFormed = true;
      }

      // Every five kilometres: does each team still have someone to ride for?
      if (s.km >= _nextReassignKm) {
        _nextReassignKm = s.km + 5;
        _reassign(groups);
      }
      final main = _mainGroup(groups);
      if (inFinale) _finaleDecisions(groups, main, s);
      if (inFinale) {
        _maybeAttack(groups, main, s);
      } else if (!fighting) {
        _maybeAttack(groups, main, s, longRange: true);
      }
      // Up the road the break splits as the finish nears.
      final remainingKm = route.raceKm - s.km;
      if (inFinale || remainingKm < 25) {
        for (final g in [...groups]) {
          if (!identical(g, main) && g.clock < main.clock) {
            _maybeAttack(groups, g, s, breakaway: true);
          }
        }
      }
      // A group is dangerous if someone in it is less than five minutes down in
      // the general classification.
      final threat = groups.any((g) =>
          g.clock < main.clock &&
          g.members.any((m) => m.gcGap != null && m.gcGap! < 300));
      final chasing = _chasingTeams(groups, main, s, threat);
      if (_key[seg]) {
        final fresh = seg == 0 || !_key[seg - 1];
        for (final g in groups) {
          _position(g, fresh: fresh);
        }
      }

      final next = <_Group>[];
      for (var gi = 0; gi < groups.length; gi++) {
        final g = groups[gi];
        final dropped = _advance(g, s,
            isFront: gi == 0,
            isMain: identical(g, main),
            aheadOfMain: g.clock < main.clock,
            gapToFront: g.clock - groups.first.clock,
            gapToMain: g.clock - main.clock,
            inFinale: inFinale,
            fighting: fighting && identical(g, main),
            chasingTeams: chasing,
            threatAhead: threat);
        next.add(g);
        next.addAll(dropped);
      }
      _incidents(next, s);
      next.removeWhere((g) => g.members.isEmpty);
      groups = _merge(next, s);

      _record(groups, s);
      final rec = track;
      if (rec != null) {
        for (final g in groups) {
          for (final m in g.members) {
            rec.pass(seg, m.rider.id, g.clock, m.rank);
          }
        }
      }
      final gap = _mainGroup(groups).clock - groups.first.clock;
      if (gap > maxGap) {
        maxGap = gap;
        maxGapKm = s.km;
      }
      while (
          pending.isNotEmpty && pending.first.km <= s.km + s.lengthM / 1000) {
        _awardPoints(pending.removeAt(0), groups);
      }
    }

    if (maxGap > 45) {
      events.add(RaceEvent(maxGapKm, EventType.maxGap,
          tr('Biggest lead of the front: {0}', [_clock(maxGap)])));
    }
    return _finish(groups);
  }

  /// Marks the segments just before the places where position decides:
  /// hard cobbled sectors, the foot of a climb in the second half, open
  /// roads in the crosswind and the last kilometres.
  ///
  /// @returns Per segment whether the fight for position is on.
  List<bool> _keyPoints() {
    final segs = route.segments;
    final key = List.filled(segs.length, false);
    void before(int i, {bool sector = false}) {
      final km = segs[i].km;
      for (var k = i; k >= 0 && segs[k].km > km - 2.5; k--) {
        key[k] = true;
        if (sector) _sectorKey[k] = true;
      }
    }

    // In a race decided by its sectors every sector worth the name is
    // fought for, elsewhere only the hard ones.
    final level = route.sectorRace ? 2 : 3;

    for (var i = 1; i < segs.length; i++) {
      final s = segs[i], prev = segs[i - 1];
      if (s.rough >= level && prev.rough < level) before(i, sector: true);
      if (s.climbKm >= 3 &&
          s.grade > 0.03 &&
          prev.climbKm == 0 &&
          s.km > route.raceKm * 0.4) {
        before(i);
      }
      if (wind.cross[i] >= 5 && wind.cross[i - 1] < 5 && s.grade.abs() < 0.02) {
        before(i);
      }
      if (route.raceKm - s.km <= 8) key[i] = true;
    }
    return key;
  }

  /// Notes the state of the race for the report: who has lost contact with
  /// the favourites, and every two kilometres a sample for the chart.
  ///
  /// @param groups All groups after the step.
  /// @param s The segment just ridden.
  void _record(List<_Group> groups, Segment s) {
    final main = _mainGroup(groups);
    final km = s.km + s.lengthM / 1000;
    for (final g in groups) {
      final behind = g.clock > main.clock;
      for (final m in g.members) {
        if (behind) {
          m.lostKm ??= km;
        } else {
          m.lostKm = null;
        }
      }
    }
    final last = seg == route.segments.length - 1;
    if (km >= _nextSampleKm - 1e-6 || last) {
      _nextSampleKm += 2;
      final head = groups.first.clock;
      _timeline.add(RaceSample(
          km,
          main.clock - head,
          groups.first.members.length,
          main.members.length,
          max(0.0, _middle(groups).clock - main.clock), [
        for (final g in groups)
          GroupSample(
            g.clock - head,
            g.members.length,
            g.members.where((m) => m.favorite).length,
            [
              for (final m in g.members)
                if (_own(m)) m.rider.id,
            ],
            breakaway: g.members.every((m) => m.inBreak),
            gruppetto: g.gruppetto,
            stars: [
              for (final m in g.members)
                if (m.favorite) m.rider.id,
            ],
          ),
      ]));
    }
  }

  /// @param groups All groups, first on the road first.
  /// @returns The group in which the rider in the middle of the field rides.
  _Group _middle(List<_Group> groups) {
    final total = groups.fold(0, (n, g) => n + g.members.length);
    var before = 0;
    for (final g in groups) {
      before += g.members.length;
      if (before * 2 >= total) return g;
    }
    return groups.last;
  }

  /// From here on the race for the win is on: foot of the last big climb,
  /// first hard sector in the second half, otherwise 15 km from the finish.
  /// In a race decided by its sectors without a very hard one, the finale
  /// starts where half of the sectors are done.
  ///
  /// @returns Race kilometre at which the finale starts.
  double _finaleStart() {
    var start = route.raceKm - 15;
    for (final s in route.segments) {
      if (s.km < route.raceKm * 0.55) continue;
      final bigClimb = s.climbKm >= 3 && s.grade > 0.03;
      final hardSector = s.rough >= 4;
      if (bigClimb && s.km > route.raceKm - 45 || hardSector) {
        start = min(start, s.km);
        break;
      }
    }
    if (route.sectorRace && start > route.raceKm - 15.01) {
      final half = route.sectorLoad / 2;
      var done = 0.0;
      for (final s in route.segments) {
        done += (s.cobble + 0.6 * s.unpaved) * s.lengthM / 1000;
        if (done >= half) {
          start = min(start, s.km);
          break;
        }
      }
    }
    return max(start, route.raceKm * 0.3);
  }

  /// @param groups All groups.
  /// @returns The group holding most of the favourites.
  _Group _mainGroup(List<_Group> groups) {
    var best = groups.first, bestScore = -1.0;
    for (final g in groups) {
      final score =
          g.members.where((m) => m.favorite).length + g.members.length / 1000;
      if (score > bestScore) {
        best = g;
        bestScore = score;
      }
    }
    return best;
  }

  /// @param g A group.
  /// @returns Teams whose leader or sprinter rides in it.
  Set<int> _goalTeams(_Group g) => {
        for (final m in g.members)
          if (m.role.sheltered || m.favorite) m.rider.teamId,
      };

  /// Gap the field tolerates.
  ///
  /// @param remainingKm Kilometres to the finish.
  /// @param threatAhead Whether a rider dangerous for the general
  ///   classification is up the road.
  /// @returns Seconds.
  double _allowedGap(double remainingKm, bool threatAhead) {
    // If nobody dangerous for the general classification is up the road, the
    // GC teams let the group go on hard days.
    // In a stage race that is already from the second stage on: the
    // favourites ride for the overall, not for the stage.
    final letGo =
        _stageRace && !sprintStage && !threatAhead ? t.letGoFactor : 1.0;
    // On a summit finish the favourites take minutes out of a break on the
    // last climb, so the field can leave it more.
    final summit = uphillFinish && route.selectivity > 1500 ? 120.0 : 0.0;
    return max(
        20.0,
        summit +
            t.secondsPerKmAllowed *
                (sprintStage ? t.sprintStageAllowed : 1) *
                letGo *
                remainingKm);
  }

  /// Teams working in the field: they want to control, their leader is
  /// there, they have no rider in a group ahead and still have a helper
  /// with something left. If the gap gets out of hand and too few are
  /// chasing, the next teams with a favourite join in, whatever they had
  /// planned.
  ///
  /// @param groups All groups.
  /// @param main The field.
  /// @param s Current segment.
  /// @param threatAhead Whether a rider dangerous for the general
  ///   classification is up the road.
  /// @returns Ids of the chasing teams.
  Set<int> _chasingTeams(
      List<_Group> groups, _Group main, Segment s, bool threatAhead) {
    final ahead = <int>{
      for (final g in groups)
        if (g.clock < main.clock)
          for (final m in g.members) m.rider.teamId,
    };
    final fresh = <int>{
      for (final m in main.members)
        if (m.role.works && !m.blown) m.rider.teamId,
    };
    final goals = _goalTeams(main);
    final out = {
      for (final m in main.members)
        if ((m.plan.approach != Approach.wait ||
                m.plan.breakPolicy == BreakPolicy.chase) &&
            !ahead.contains(m.rider.teamId) &&
            fresh.contains(m.rider.teamId) &&
            goals.contains(m.rider.teamId))
          m.rider.teamId,
    };
    final gap = main.clock - groups.first.clock;
    if (out.length < 2 &&
        gap > 0.8 * _allowedGap(route.raceKm - s.km, threatAhead)) {
      // Best favourite per team that could still chase.
      final cards = <int, double>{};
      for (final m in main.members) {
        final team = m.rider.teamId;
        if (!m.favorite ||
            ahead.contains(team) ||
            !fresh.contains(team) ||
            out.contains(team)) {
          continue;
        }
        if (m.fit > (cards[team] ?? 0)) cards[team] = m.fit;
      }
      final more = cards.entries.toList()
        ..sort((a, b) {
          final byFit = b.value.compareTo(a.value);
          return byFit != 0 ? byFit : a.key.compareTo(b.key);
        });
      for (final e in more.take(3 - out.length)) {
        out.add(e.key);
      }
    }
    return out;
  }

  /// Gives a team a new rider to ride for when it has none left at the front:
  /// its leaders have abandoned or are more than a minute behind the
  /// favourites. The best-suited rider it still has there may then ride for
  /// himself.
  ///
  /// @param groups All groups.
  void _reassign(List<_Group> groups) {
    final main = _mainGroup(groups);
    final front = <int, List<_State>>{};
    final led = <int>{};
    for (final g in groups) {
      final close = g.clock - main.clock <= 60;
      for (final m in g.members) {
        // A leader on his way back after a mishap still counts.
        if (m.role.ridesForHimself && (close || g.convoy)) {
          led.add(m.rider.teamId);
        }
        if (g.clock <= main.clock) {
          front.putIfAbsent(m.rider.teamId, () => []).add(m);
        }
      }
    }
    for (final e in front.entries) {
      if (led.contains(e.key)) continue;
      e.value.reduce((a, b) => b.fit > a.fit ? b : a).role = Role.freeRole;
    }
  }

  /// Chance that the current move goes clear. On sprint stages a group gets
  /// away almost at once; on hard days many teams want to be in it and the
  /// fight can last for an hour. Moves on a climb stick more easily.
  ///
  /// @param s Current segment.
  /// @param groups All groups.
  /// @returns Probability for this segment.
  double _stickChance(Segment s, List<_Group> groups) {
    final field = _mainGroup(groups);
    final wanting = <int>{
      for (final m in field.members)
        if (m.plan.breakPolicy == BreakPolicy.join ||
            m.role == Role.stageHunter ||
            m.role == Role.breakaway)
          m.rider.teamId,
    }.length;
    final rate = t.breakStickRate *
        (sprintStage ? 5 : 1) *
        (s.grade > 0.03 ? 1.8 : 1) /
        (1 + (sprintStage ? 0 : wanting / 8));
    return (rate * s.lengthM / 1000).clamp(0.0, 1.0);
  }

  /// Forms the break of the day.
  ///
  /// @param peloton The field; the chosen riders are removed from it.
  /// @param s The segment where the move sticks.
  /// @returns The breakaway group, or null if fewer than two riders went.
  _Group? _formBreak(_Group peloton, Segment s) {
    final size = sprintStage
        ? 2 + rng.nextInt(5)
        : route.selectivity > 2500
            ? 6 + rng.nextInt(14)
            : 4 + rng.nextInt(9);
    final sorted = [...peloton.members]..sort((a, b) => a.thr.compareTo(b.thr));
    final median = sorted.isEmpty ? 1.0 : sorted[sorted.length ~/ 2].thr;
    // Role and team instruction decide who may go in the break.
    double weight(_State c) {
      final byRole = switch (c.role) {
        Role.stageHunter => 10.0,
        Role.breakaway => 6.0,
        Role.mountainHunter => route.selectivity > 1200 ? 12.0 : 3.0,
        Role.pointsHunter => route.selectivity <= 1200 ? 10.0 : 2.0,
        Role.freeRole => 2.0,
        Role.domestique => 1.0,
        Role.tempo || Role.climbDomestique => 0.3,
        _ => 0.0,
      };
      final byTeam = switch (c.plan.breakPolicy) {
        BreakPolicy.join => 2.0,
        BreakPolicy.ignore => 0.4,
        BreakPolicy.chase => 0.15,
      };
      // On hard days only riders who can handle the terrain make the break; on
      // the flat, wanting to is enough. On a climb the strongest get away.
      // A jersey hunter only has to be good enough for the break, not for
      // the stage.
      final byFit = sprintStage
          ? 1.0
          : exp((c.fit - favoriteLevel) /
              (c.role == Role.mountainHunter ? 6 : 3));
      final byLegs =
          s.grade > 0.03 ? exp((c.thr / median - 1) * 25).toDouble() : 1.0;
      // A good sports director gets his riders into the break more often.
      return (0.65 + 0.5 * c.plan.directorSkill) *
          byRole *
          byTeam *
          byFit *
          byLegs *
          exp((c.rider.attributes.breakaway - 70) / 5);
    }

    final candidates = peloton.members
        .where((m) =>
            !m.favorite &&
            weight(m) > 0 &&
            !(hasGc && m.gcGap != null && m.gcGap! < 180))
        .toList();
    final picked = <_State>[];
    final teams = <int, int>{};
    while (picked.length < size && candidates.isNotEmpty) {
      final weights = [for (final c in candidates) weight(c)];
      var x = rng.nextDouble() * weights.reduce((a, b) => a + b);
      var i = 0;
      while (i < weights.length - 1 && x > weights[i]) {
        x -= weights[i++];
      }
      final c = candidates.removeAt(i);
      // At most two riders per team.
      if ((teams[c.rider.teamId] ?? 0) >= 2) continue;
      teams[c.rider.teamId] = (teams[c.rider.teamId] ?? 0) + 1;
      picked.add(c);
    }
    // Never the whole group: somebody has to be left to chase.
    if (picked.length < 2 || picked.length >= peloton.members.length) {
      return null;
    }
    for (final p in picked) {
      p
        ..inBreak = true
        ..everInBreak = true
        // Going clear took a hard effort.
        ..reserve = min(p.reserve, 0.6);
    }
    peloton.members.removeWhere(picked.contains);
    events.add(RaceEvent(
        s.km,
        EventType.breakaway,
        tr('{0} riders go clear: {1}', [picked.length, _names(picked)]),
        [for (final p in picked) p.rider.id]));
    // The group starts with a small cushion; the rest follows from the pace.
    return _Group(picked, peloton.clock - 20);
  }

  /// Lets a rider attack out of a group if the moment is right.
  ///
  /// In the finale the favourites attack on climbs and cobbles, late on the
  /// flat and, if they descend well, downhill. Before the finale a clearly
  /// stronger rider may go from far out on a long climb. Up the road the
  /// riders of the break attack each other as the finish nears.
  ///
  /// @param groups All groups; a new group is inserted on an attack.
  /// @param lead The group the attack comes from.
  /// @param s Current segment.
  /// @param breakaway Whether [lead] is a group ahead of the favourites.
  /// @param longRange Whether this is an attack before the finale.
  void _maybeAttack(List<_Group> groups, _Group lead, Segment s,
      {bool breakaway = false, bool longRange = false}) {
    if (lead.members.length < 2 || lead.surgeKm > 0 || lead.gruppetto) return;
    final remaining = route.raceKm - s.km;
    final climbing = s.grade >= 0.04 || s.rough >= 3;
    final descending = s.grade <= -0.04;
    double terrain;
    if (longRange) {
      if (sprintStage || !(s.climbKm >= 5 && s.grade >= 0.05)) return;
      terrain = 1;
    } else if (climbing) {
      terrain = 1;
    } else if (descending || breakaway || remaining < 12) {
      terrain = t.flatAttackRate;
    } else {
      return;
    }
    final order = [...lead.members]
      ..sort((a, b) => _threshold(b).compareTo(_threshold(a)));
    // Helpers do not attack; in a break everyone rides for himself unless
    // he was told to sit on.
    final goals = _goalTeams(lead);
    final own = order
        .where((m) => breakaway
            ? !m.passenger && !(m.role.works && goals.contains(m.rider.teamId))
            : m.role.ridesForHimself)
        .toList();
    if (own.isEmpty) return;
    // Among the favourites, a team that waits for the finish does not start
    // the attacking itself.
    final keen = breakaway
        ? own
        : own.where((m) => !_waiting.contains(m.rider.teamId)).toList();
    final forced = breakaway || !climbing
        ? null
        : order
            .where((m) => _forced.contains(m) && m.reserve >= 0.5)
            .firstOrNull;
    if (keen.isEmpty && forced == null) return;
    var best = keen.isEmpty ? forced! : keen.first;
    if (descending && !climbing) {
      // Downhill the best descender goes, if he is clearly better than the rest.
      final downhill = [for (final m in order) m.rider.attributes.downhill]
        ..sort();
      final median = downhill[downhill.length ~/ 2];
      best = keen.reduce((a, b) =>
          a.rider.attributes.downhill >= b.rider.attributes.downhill ? a : b);
      if (best.rider.attributes.downhill < median + 5) return;
    }
    // Told by the team car: he attacks as soon as he can.
    if (forced != null) {
      best = forced;
      _forced.remove(forced);
    } else {
      if (best.reserve < 0.5) return;
      final rival = own.where((m) => m != best).firstOrNull ??
          order.firstWhere((m) => m != best);
      final edge = _threshold(best) / _threshold(rival) - 1;
      double rate;
      if (longRange) {
        // Only a rider who is clearly the strongest tries it from far out.
        if (edge < 0.03 || !best.favorite) return;
        rate = t.longAttackRate * (1 + 10 * edge);
      } else {
        rate = (t.attackRatePerKm + t.attackEdgeGain * max(0.0, edge)) *
            terrain *
            // On sprint stages the sprinters' teams hold the field together.
            (sprintStage && !breakaway ? 0.2 : 1);
      }
      final chance = (s.lengthM / 1000 * rate).clamp(0.0, 0.8);
      if (rng.nextDouble() > chance) return;
    }

    final followers = [
      for (final m in order)
        if (m != best &&
            own.contains(m) &&
            _threshold(m) >= _threshold(best) * (1 - t.followMargin) &&
            m.reserve > 0.35 &&
            rng.nextDouble() <
                t.followChance +
                    0.2 * m.plan.directorSkill +
                    // Who waits for the sprint must not let anyone go.
                    (!breakaway && _waiting.contains(m.rider.teamId)
                        ? 0.15
                        : 0))
          m,
    ];
    // A favourite attacks and a team's leader hesitates: its sports director
    // can send him after the move, even if it is beyond his means. Every
    // team reacts like this once per stage.
    final teams = breakaway
        ? const <int>[]
        : ({
            for (final m in order)
              if (m.role.ridesForHimself) m.rider.teamId,
          }.toList()
          ..sort());
    for (final team in teams) {
      if (team == best.rider.teamId ||
          followers.any((m) => m.rider.teamId == team)) {
        continue;
      }
      final asks = team == radioTeam;
      if (asks
          ? _asked.contains(RadioKind.rivalAttack)
          : _reacted.contains(team)) {
        continue;
      }
      final mine = order
          .where((m) =>
              m.rider.teamId == team &&
              m.role.ridesForHimself &&
              m.reserve > 0.2 &&
              _threshold(m) >= _threshold(best) * (1 - 2.5 * t.followMargin))
          .firstOrNull;
      if (mine == null) continue;
      final suggested =
          best.favorite && mine.favorite && mine.reserve > 0.5 ? 1 : 0;
      final a = asks
          ? _ask(
              RadioKind.rivalAttack,
              s.km,
              tr('{0} ({1}) attacks {2} km from the finish{3}. {4} {5}.', [
                best.rider.name,
                best.rider.team,
                (route.raceKm - s.km).toStringAsFixed(1),
                followers.isEmpty
                    ? tr(', nobody follows')
                    : tr(', followed by {0}', [_names(followers, 4)]),
                mine.rider.name,
                _reserveText(mine)
              ]),
              [
                tr('Ride our own pace'),
                tr('{0} should follow', [mine.rider.name]),
              ],
              suggested)
          : suggested;
      if (a == 1) {
        _reacted.add(team);
        followers.add(mine);
      }
    }
    final move = [best, ...followers];
    if (move.length >= lead.members.length) return;
    lead.members.removeWhere(move.contains);
    final g = _Group(move, lead.clock - 1)
      ..surgeKm = 1.0
      ..surgeLeader = best;
    groups.insert(groups.indexOf(lead), g);
    // Do not report repeated moves by the same rider every time.
    final previous = _lastAttackKm[best.rider.id];
    _lastAttackKm[best.rider.id] = s.km;
    if (previous != null && s.km - previous < 15) return;
    final rest = route.raceKm - s.km;
    events.add(RaceEvent(
        s.km,
        EventType.attack,
        followers.isEmpty
            ? tr('{0} attacks {1} km from the finish, nobody follows',
                [best.rider.name, rest.toStringAsFixed(1)])
            : tr('{0} attacks {1} km from the finish, followed by: {2}',
                [best.rider.name, rest.toStringAsFixed(1), _names(followers)]),
        [best.rider.id, for (final f in followers) f.rider.id]));
  }

  /// Fight for position before a key point. Leaders and sprinters want to
  /// be at the front; their helpers bring them there, a good sports director
  /// helps, and luck plays its part. Being at the front costs extra effort.
  ///
  /// @param g The group.
  /// @param fresh Whether a new fight begins, with new luck.
  void _position(_Group g, {required bool fresh}) {
    final helpers = <int, int>{};
    for (final m in g.members) {
      if (m.role.works && !m.blown && m.energy > 0.25) {
        helpers[m.rider.teamId] = (helpers[m.rider.teamId] ?? 0) + 1;
      }
    }
    // The strong ride further forward without trying: they can close a gap
    // and move up on the side.
    final legs = [for (final m in g.members) m.thr]..sort();
    final median = legs.isEmpty ? 1.0 : legs[legs.length ~/ 2];
    final goals = _goalTeams(g);
    for (final m in g.members) {
      // In the wet the order going into a sector is more of a lottery.
      if (fresh) {
        m.posLuck = (_sectorKey[seg] && _wet ? 6 : 4) * _gauss(rng);
      }
      final a = m.rider.attributes;
      final wants = m.role.sheltered || m.role.ridesForHimself;
      final desire = wants
          ? 5.0
          : m.role.works && goals.contains(m.rider.teamId)
              ? 3.0
              : 0.0;
      final support = wants
          ? min(3, helpers[m.rider.teamId] ?? 0) *
              2.5 *
              (0.6 + 0.8 * m.plan.directorSkill)
          : 0.0;
      // Before a sector the riders who are at home on rough roads find
      // their way to the front.
      m.pos = (_sectorKey[seg]
              ? 0.5 * a.cobble + 0.25 * a.flat + 0.25 * a.acceleration
              : 0.5 * a.flat + 0.5 * a.acceleration) -
          70 +
          desire +
          support +
          m.posLuck +
          100 * (m.thr / median - 1) -
          (m.blown ? 10 : 0);
    }
    _rank(g);
    final n = g.members.length;
    for (final m in g.members) {
      final wants = m.role.sheltered || m.role.ridesForHimself || m.role.works;
      m.extraEffort = wants && m.rank < n * 0.3 ? t.positionCost : 0;
    }
  }

  /// Orders a group by position.
  ///
  /// @param g The group.
  void _rank(_Group g) {
    final byPos = [...g.members]..sort((a, b) => b.pos.compareTo(a.pos));
    for (var i = 0; i < byPos.length; i++) {
      byPos[i].rank = i;
    }
  }

  /// Advances a group by one segment.
  ///
  /// @param g The group.
  /// @param s The segment.
  /// @param isFront Whether the group leads the race.
  /// @param isMain Whether it is the group with the favourites.
  /// @param aheadOfMain Whether it rides ahead of that group.
  /// @param gapToFront Seconds behind the head of the race.
  /// @param gapToMain Seconds behind the group with the favourites.
  /// @param inFinale Whether the finale has started.
  /// @param fighting Whether the field is still fighting for the break.
  /// @param chasingTeams Teams working in the field.
  /// @param threatAhead Whether a rider dangerous for the general
  ///   classification is up the road.
  /// @returns The riders who lost contact, as new groups.
  List<_Group> _advance(
    _Group g,
    Segment s, {
    required bool isFront,
    required bool isMain,
    required bool aheadOfMain,
    required double gapToFront,
    required double gapToMain,
    required bool inFinale,
    required bool fighting,
    required Set<int> chasingTeams,
    required bool threatAhead,
  }) {
    final order = g.members
      ..sort((a, b) => _threshold(b).compareTo(_threshold(a)));
    final n = order.length;
    // Places in the group only matter where the road is narrow or open.
    final rough = s.rough;
    if (rough >= 2 || wind.cross[seg] >= 5) _rank(g);
    final crr = _crr[seg];
    final rho = _rho[seg];
    final headwind = wind.head[seg];
    final cross = wind.cross[seg];
    // On cobbles everyone rides his own line; the slipstream hardly helps.
    // A crosswind blows some of the shelter away.
    var draft = 1 -
        (1 - draftFactor(n, t)) *
            (1 - t.cobbleDraftLoss * (s.cobble + 0.5 * s.unpaved))
                .clamp(0.0, 1.0);
    if (cross > 2) draft = 1 - (1 - draft) * max(0.7, 1 - 0.03 * cross);
    // Hard sectors are ridden flat out even far from the finish.
    final racing = inFinale || rough >= 3 && s.km > route.raceKm * 0.35;
    final remainingKm = route.raceKm - s.km;
    // A dropped group with a favourite or a rider placed in the general
    // classification: his helpers bring him back, as long as it is possible.
    List<_State>? rescue;
    var rescued = const <_State>[];
    if (!isMain && !aheadOfMain && !g.convoy && gapToMain < 150) {
      rescued = [
        for (final m in order)
          if (m.favorite ||
              hasGc && m.gcGap != null && m.gcGap! < 300 ||
              // On a hilly day a sprinter dropped on a climb is paced back
              // by his team while there is road enough to the line.
              m.role == Role.sprinter &&
                  !_mountainStage &&
                  remainingKm > 12 &&
                  gapToMain < 90)
            m,
      ];
      if (rescued.isNotEmpty) {
        final teams = {for (final m in rescued) m.rider.teamId};
        rescue = [
          for (final m in order)
            if (m.role.works && !m.blown && teams.contains(m.rider.teamId)) m,
        ];
      }
    }

    // Who sets the pace, how hard he rides and who is in the wind with him.
    _State ref;
    double effort;
    var workers = <_State>{};
    var echelon = false;
    if (g.surgeKm > 0 &&
        g.surgeLeader != null &&
        g.surgeLeader!.reserve > 0.08 &&
        order.contains(g.surgeLeader)) {
      ref = g.surgeLeader!;
      effort = t.surgeEffort;
      workers = {ref};
    } else if (racing && (isMain || aheadOfMain)) {
      final hard = s.grade > 0.02 || rough > 0 || remainingKm < 5;
      // Between the hard parts the front keeps going; chase groups watch
      // each other and work less well. In a race over sectors a small front
      // group commits, and a chase only runs with a team behind it.
      // On the sectors the front rides above threshold: that is where the
      // cobbled classics are decided.
      final organised = sectorRace
          ? order.any((m) =>
              m.role.works &&
              !m.blown &&
              order.any((o) => o.favorite && o.rider.teamId == m.rider.teamId))
          : n > 8;
      effort = hard
          ? (rough >= 2 ? t.cobbleEffort : 1.0)
          : isFront
              ? (sectorRace && n <= 6
                  ? max(0.95, t.finaleEaseEffort)
                  : t.finaleEaseEffort)
              : organised
                  ? t.chaseGroupEffort
                  : 0.9;
      final byRank = order[
          ((n * t.finaleRefShare).ceil().clamp(1, 6) - 1).clamp(0, n - 1)];
      // As long as a helper can match the pace of the best, he rides on the
      // front for his leader; otherwise the leaders have to do it themselves.
      final helper = _strongestHelper(order);
      if (helper != null && _threshold(helper) >= _threshold(byRank) * 0.97) {
        ref = helper;
        workers = {helper};
      } else {
        ref = byRank;
        final at = order.indexOf(byRank);
        workers = {for (var i = at; i < n && i <= at + 3; i++) order[i]};
      }
      // On a climb the pace is only full when the team on the front wants a
      // selection. A team waiting for the sprint rides tempo, unless it has
      // to bring somebody back.
      if (hard &&
          rough < 2 &&
          remainingKm >= 5 &&
          gapToFront <= 0 &&
          _waiting.contains(ref.rider.teamId)) {
        effort = 0.95;
      }
      // Told by the team car: the helpers ride on the front until they are empty.
      if (isMain && _driving.isNotEmpty) {
        final lead = order
            .where((m) =>
                _driving.contains(m.rider.teamId) &&
                m.role.works &&
                m.energy > 0.15)
            .firstOrNull;
        if (lead != null && _threshold(lead) >= _threshold(byRank) * 0.92) {
          effort = max(effort, 1.0);
          ref = lead;
          workers = order
              .where((m) =>
                  m.rider.teamId == lead.rider.teamId &&
                  m.role.works &&
                  m.energy > 0.15)
              .take(3)
              .toSet();
        }
      }
      // Nobody rides above his threshold on an empty tank.
      if (effort > 1 && ref.reserve < 0.05) effort = 1.0;
    } else if (aheadOfMain && n >= 8 && !order.any((m) => m.inBreak)) {
      // A front part of the field after a split (an echelon, a hard climb):
      // the teams in it press on to keep the others behind.
      ref = order[n ~/ 2];
      effort = max(t.chaseGroupEffort, t.breakEffort);
      workers = {
        for (final m in order)
          if (!m.role.sheltered && !m.blown) m,
      }.take(10).toSet();
      if (workers.isEmpty) workers = order.take(6).toSet();
    } else if (aheadOfMain) {
      ref = order[n ~/ 2];
      effort = inFinale ? 0.96 : t.breakEffort;
      workers = order.any((m) => m.passenger)
          ? order.where((m) => !m.passenger).toSet()
          : order.toSet();
    } else if (fighting) {
      // Attack after attack until a group goes clear: the field rides hard
      // and the strongest are in the wind.
      ref = order[(n * 0.25).floor()];
      effort = t.fightEffort * dayMood;
      workers = order.take(max(8, n * 3 ~/ 10)).toSet();
    } else if (isMain) {
      // In the field the helpers of the teams with something to win do the
      // work, as long as they have something left.
      final pool = [
        for (final m in order)
          // The climbing domestiques are saved for the finale.
          if (m.role.works &&
              !m.blown &&
              m.role != Role.climbDomestique &&
              chasingTeams.contains(m.rider.teamId))
            m,
      ];
      final pace = pool.isEmpty
          ? [
              for (final m in order)
                if (!m.role.sheltered && !m.blown) m
            ]
          : pool;
      final crew = pace.isEmpty ? order : pace;
      ref = crew[crew.length ~/ 2];
      // The bigger the gap relative to the distance left, the harder the chase.
      // If nobody dangerous for the general classification is up the road, the
      // GC teams let the group go on hard days.
      final allowed = _allowedGap(remainingKm, threatAhead);
      final pressure = (gapToFront / allowed).clamp(0.0, 1.0);
      // On a climb the riders on the front climb at the field's own tempo,
      // not at the pace a rouleur would ride uphill: that of its stronger
      // riders while it controls or chases, that of the middle of the
      // field while it lets a group go.
      if (s.grade > 0.03) {
        final tempo = order[(n * (pressure >= 0.6 ? 0.35 : 0.55)).floor()];
        if (_threshold(tempo) > _threshold(ref)) ref = tempo;
      }
      workers = crew.take(8).toSet();
      // Nobody chases: the field dawdles. Several teams: the chase runs smoothly.
      final interest =
          const [0.86, 0.95, 1.0, 1.03][min(chasingTeams.length, 3)];
      // As long as the group is far below the tolerated gap, the field eases off
      // and lets it go; only above that does it control and finally chase.
      final base = gapToFront <= 0
          ? t.controlEffort
          : pressure < 0.6
              ? t.easeEffort + (t.controlEffort - t.easeEffort) * pressure / 0.6
              : t.controlEffort +
                  (t.chaseEffort - t.controlEffort) * (pressure - 0.6) / 0.4;
      effort = (base + (s.climbKm >= 5 ? 0.05 : 0)) *
          interest *
          (sprintStage ? 1 : t.selectiveStageChase) *
          dayMood;
      // A team wants to make the race hard early and sends its climbing
      // domestiques to the front on the climbs.
      if (s.climbKm >= 3 && s.grade > 0.03 && s.km > route.raceKm * 0.35) {
        final drivers = [
          for (final m in order)
            if (m.plan.approach == Approach.makeHard &&
                m.role.works &&
                !m.blown)
              m,
        ];
        if (drivers.isNotEmpty) {
          final hardEffort =
              t.makeHardEffort + 0.06 * drivers.first.plan.directorSkill;
          if (hardEffort > effort) {
            effort = hardEffort;
            ref = drivers.first;
            workers = drivers.take(3).toSet();
          }
        }
      }
    } else if (rescue != null) {
      g.gruppetto = false;
      if (rescue.isNotEmpty) {
        ref = rescue.first;
        effort = t.chaseEffort;
        workers = rescue.take(6).toSet();
      } else {
        // No helper left: the leaders have to close the gap themselves.
        ref = rescued.first;
        effort = 0.97;
        workers = rescued.take(4).toSet();
      }
    } else if (_formsGruppetto(order, gapToMain)) {
      // Gruppetto: nobody here has anything left to win, so the group rides
      // at a pace its weaker riders can hold and saves itself for tomorrow.
      g.gruppetto = true;
      // The bus rides for its weakest riders, the sprinters it exists for.
      ref = order[min(n - 1, (n * 0.95).floor())];
      // The closer the bus comes to the time limit, the harder it rides; at
      // the share [SimTuning.gruppettoCutShare] of the limit it rides flat out.
      effort = t.gruppettoEffort +
          (1.0 - t.gruppettoEffort) * _cutDanger(g, s, gapToFront);
      workers = order.take(12).toSet();
      if (n >= 20 && !_gruppettoReported) {
        _gruppettoReported = true;
        events.add(RaceEvent(
            s.km,
            EventType.gruppetto,
            tr('The gruppetto forms at the back: {0} riders, {1} behind the favourites',
                [n, _clock(gapToMain)])));
      }
    } else if (g.convoy && gapToMain < 150 && remainingKm > 3) {
      // Back after a mishap: helpers who waited pace their man, and the
      // team cars give shelter.
      g.gruppetto = false;
      final helpers = order.where((m) => m.role.works && !m.blown).toList();
      ref = helpers.isNotEmpty ? helpers.first : order[n ~/ 2];
      effort = 0.98;
      workers = helpers.isNotEmpty ? helpers.toSet() : order.toSet();
    } else {
      // Dropped riders: chase at first, far behind just get to the finish.
      // On a hard day a group in which nobody races any more rolls in.
      g.gruppetto = false;
      ref = order[n ~/ 2];
      final leaders = _leadersIn(order);
      final aimless = (_selective || remainingKm < t.rollInKm) &&
          !order.any((m) => _hasStake(m, leaders));
      // A group that only rolls in still watches the time limit.
      effort = aimless
          ? t.aimlessEffort +
              (1.0 - t.aimlessEffort) * _cutDanger(g, s, gapToFront)
          : gapToFront < 180 && !inFinale
              ? 0.92
              // Far behind, the time limit sets the pace as for the bus.
              : t.droppedEffort +
                  (1.0 - t.droppedEffort) * _cutDanger(g, s, gapToFront);
      workers = order.where((m) => !m.role.sheltered).take(6).toSet();
    }

    // Crosswind on open road: a team with strong riders puts the field in
    // the gutter. Only the first riders find shelter in the echelon.
    if (cross >= 5 &&
        s.grade.abs() < 0.02 &&
        n > t.echelonSize + 5 &&
        !fighting &&
        (isMain || isFront)) {
      final forcing = _echelonTeam(order, s, cross);
      if (forcing >= 0) {
        echelon = true;
        final crew = [
          for (final m in order)
            if (m.rider.teamId == forcing && !m.blown && !m.role.sheltered) m,
        ];
        if (crew.isNotEmpty && t.echelonEffort > effort) {
          effort = t.echelonEffort;
          ref = crew.first;
          workers = {...crew.take(4)};
        }
      }
    }

    final convoyShelter = g.convoy && remainingKm > 3 ? 0.7 : 1.0;
    // Whoever sets the pace takes turns and feels more wind than the rest.
    // Only the riders who work share the front: in a big field a handful of
    // them rotate, and they have the shelter of a small group, not of the
    // whole bunch.
    // The field always has a few riders to share the front with, a team
    // train in the finale.
    // In an echelon the whole line in the shelter takes turns.
    final rotating = workers.isEmpty
        ? n
        : echelon
            ? min(n, max(4, t.echelonSize.round()))
            : min(n, max(isMain ? 4 : 2, workers.length));
    var frontDraft = 1 -
        (1 - draftFactor(rotating, t)) *
            (1 - t.cobbleDraftLoss * (s.cobble + 0.5 * s.unpaved))
                .clamp(0.0, 1.0);
    if (cross > 2) {
      frontDraft = 1 - (1 - frontDraft) * max(0.7, 1 - 0.03 * cross);
    }
    final frontShare = rotating >= 3
        ? (1 + frontDraft) / 2
        : rotating == 2
            ? 0.86
            : 1.0;
    final frontCda = ref.cda * frontShare * convoyShelter;
    var v = speedFor(
        _threshold(ref) * effort, s.grade, frontCda, crr * ref.roll(s, _wet),
        mass: ref.mass, rho: rho, headwind: headwind);
    // Downhill the riders at the front set the speed their skill allows.
    final cap = _groupDescentCap(order, s, g.surgeKm > 0 ? ref : null);
    v = min(v, cap);
    final dt = s.lengthM / v;
    final lengthKm = s.lengthM / 1000;

    // The more riders share the work in front, the less wind each one gets.
    final share = workers.isEmpty ? 0.0 : min(1.0, 3 / workers.length);
    // On a sector the group is a line, in the order of the fight for
    // position. The further back, the harder: every corner and every gap
    // has to be closed. Behind a rider who lets the wheel go, the rest is
    // gapped too, unless they have the punch to come round him.
    final onSector = rough >= 2 && n >= 4;
    // On a hard day, once the race is on, whoever has nothing left to ride
    // for does not suffer on the climbs to stay with the group.
    final easing = _selective &&
        (isMain || aheadOfMain) &&
        s.grade > 0.02 &&
        (inFinale || remainingKm < route.raceKm * 0.4);
    // Close to the line, on any day, whoever has nothing to ride for lets
    // the front go: helpers whose work is done, lead-out men after their
    // turn. They roll in a little behind.
    final rollingIn = (isMain || aheadOfMain) &&
        n > 8 &&
        remainingKm < t.rollInKm &&
        route.kind == StageKind.road;
    final leadersHere = easing || rollingIn ? _leadersIn(order) : const <int>{};
    final line = onSector
        ? ([...order]..sort((a, b) => a.rank.compareTo(b.rank)))
        : order;
    final penalty = onSector
        ? 0.04 * rough * (s.cobble > 0 ? 1 : 0.5) * (_wet ? 1.3 : 1)
        : 0.0;
    var gapOpen = false;
    final dropped = <_State>[];
    for (var i = 0; i < n; i++) {
      final m = line[i];
      final working = n <= 3 || workers.contains(m);
      if (working && n > 1) m.frontKm += lengthKm;
      // In the gutter of an echelon there is hardly any shelter.
      final myDraft =
          echelon && m.rank >= t.echelonSize ? 1 - (1 - draft) * 0.3 : draft;
      final myCrr = crr * m.roll(s, _wet);
      final follow = powerFor(
          v, s.grade, m.cda * myDraft * convoyShelter, myCrr,
          mass: m.mass, rho: rho, headwind: headwind);
      final power = working
          ? follow +
              (powerFor(v, s.grade, m.cda * frontShare * convoyShelter, myCrr,
                          mass: m.mass, rho: rho, headwind: headwind) -
                      follow) *
                  share
          : follow;
      var e = max(0.0, power / _threshold(m)) + m.extraEffort;
      if (onSector) e *= 1 + penalty * min(1.0, i / t.cobbleSqueeze);
      final burst = 1.35 + 0.01 * (m.rider.attributes.acceleration - 70);
      final stuck = gapOpen && !(m.reserve > 0.3 && e * 1.08 <= burst);
      // A poor descender cannot hold the wheels on a fast descent.
      var lostDownhill = false;
      if (s.grade <= -0.04 && n > 1) {
        final own = descentCap(s.grade, m.rider.attributes.downhill,
            massKg: m.rider.massKg, wet: _wet);
        if (own < v * 0.98) {
          lostDownhill = rng.nextDouble() <
              ((v - own) / v * 10).clamp(0.0, 0.8) * lengthKm * 2;
        }
      }
      final sitsUp = (easing && e > t.sitUpEffort || rollingIn) &&
          !working &&
          !_hasStake(m, leadersHere);
      if (!identical(m, ref) &&
          (stuck ||
              lostDownhill ||
              sitsUp ||
              e > burst ||
              e > 1.0 && m.reserve <= 0.03)) {
        dropped.add(m);
        if (onSector) gapOpen = true;
        continue;
      }
      _spend(m, gapOpen ? e * 1.08 : e, dt, rough);
    }
    g.clock += dt;
    if (g.surgeKm > 0) g.surgeKm -= lengthKm;

    if (dropped.isEmpty) return const [];
    g.members.removeWhere(dropped.contains);
    if (inFinale && isFront) {
      final lost =
          dropped.where((m) => m.favorite && !m.droppedReported).toList();
      for (final m in lost) {
        m.droppedReported = true;
      }
      if (lost.isNotEmpty) {
        events.add(RaceEvent(
            s.km,
            EventType.dropped,
            tr('{0} {1} to let go',
                [_names(lost), lost.length == 1 ? tr('has') : tr('have')])));
      }
    }
    if (echelon && dropped.length >= 10 && isMain) {
      if (s.km - _lastEchelonKm >= 20) {
        _lastEchelonKm = s.km;
        events.add(RaceEvent(
            s.km,
            EventType.echelon,
            tr('Echelons: {0} riders lose contact in the crosswind',
                [dropped.length])));
      }
    }
    // The dropped riders ride this segment together at their own pace.
    dropped.sort((a, b) => _threshold(b).compareTo(_threshold(a)));
    final mid = dropped[dropped.length ~/ 2];
    final dv = min(
        min(
            speedFor(
                _threshold(mid) * 0.95,
                s.grade,
                mid.cda * (dropped.length > 2 ? 0.8 : 1),
                crr * mid.roll(s, _wet),
                mass: mid.mass,
                rho: rho,
                headwind: headwind),
            v * 0.995),
        _groupDescentCap(dropped, s, null));
    final ddt = s.lengthM / dv;
    for (final m in dropped) {
      _spend(m, 0.95, ddt, rough);
    }
    return [_Group(dropped, g.clock - dt + ddt)..convoy = g.convoy];
  }

  /// Kilometre of the last reported split in the crosswind.
  double _lastEchelonKm = -100;

  /// Whether the stage belongs to a stage race that has started: the
  /// riders bring gaps in the general classification.
  late final bool _stageRace = states.any((m) => m.gcGap != null);

  /// How close a group behind comes to the time limit: 0 while it is far
  /// from it, 1 once it has used up the share
  /// [SimTuning.gruppettoCutShare] of the limit.
  ///
  /// @param g The group.
  /// @param s Current segment.
  /// @param gapToFront Seconds behind the head of the race.
  /// @returns 0 to 1.
  double _cutDanger(_Group g, Segment s, double gapToFront) {
    final frontClock = g.clock - gapToFront;
    final km = s.km + s.lengthM / 1000;
    final kmh = frontClock > 0 ? km / (frontClock / 3600) : 40.0;
    final limit = t.gruppettoCutShare * timeLimitShare(route, kmh);
    return limit <= 0
        ? 0.0
        : ((gapToFront / max(1.0, frontClock) / limit - 0.5) / 0.5)
            .clamp(0.0, 1.0);
  }

  /// Whether the day is a mountain stage, on which no team waits for its
  /// sprinter.
  late final bool _mountainStage = route.selectivity > 1500;

  /// Whether the current segment lies in the finale.
  bool _inFinale = false;

  /// Whether the day is hard enough for riders to give up on it.
  late final bool _selective = !route.sprintStage && route.selectivity > 600;

  /// Whether a rider still has a reason to race with the front of his
  /// group: a favourite, a rider in the break or riding for himself, one
  /// placed in the general classification, or a helper who can still
  /// help a leader of his in the same group. Everybody else saves himself
  /// on a hard day once the race is on.
  ///
  /// @param m The rider.
  /// @param leaders Teams with a leader in the group.
  /// @returns Whether he races on.
  bool _hasStake(_State m, Set<int> leaders) {
    if (m.favorite || m.inBreak) return true;
    if (hasGc && m.gcGap != null && m.gcGap! < 600) return true;
    // A sprinter hangs on on a hilly day, not in the mountains.
    if (m.role == Role.sprinter) return route.selectivity <= 1500;
    if (m.role.ridesForHimself) return true;
    if (!m.role.works ||
        m.blown ||
        m.energy <= t.helperEmpty ||
        !leaders.contains(m.rider.teamId)) {
      return false;
    }
    // In the finale only the climbing domestiques and the lead-out men
    // still have a job, and the helpers of a team that rides for its
    // sprinter or has been told to empty itself; the others have done
    // theirs.
    return !_inFinale ||
        m.role == Role.climbDomestique ||
        m.role == Role.leadOut ||
        _driving.contains(m.rider.teamId) ||
        _sprinting.contains(m.rider.teamId);
  }

  /// Teams with a rider in the group they ride for. Also fills
  /// [_sprinting] with the teams whose sprinter is in it.
  Set<int> _leadersIn(List<_State> order) {
    _sprinting = {
      for (final m in order)
        if (m.role == Role.sprinter) m.rider.teamId,
    };
    return {
      for (final m in order)
        if (m.favorite || m.role.sheltered) m.rider.teamId,
    };
  }

  /// Teams whose sprinter is in the group just looked at.
  var _sprinting = <int>{};

  /// Decides, once per five-kilometre block of crosswind, whether a team
  /// splits the field: one whose plan is to ride the race, with fresh strong
  /// riders on the flat, and the stronger the wind the likelier.
  ///
  /// @param order Riders of the group.
  /// @param s Current segment.
  /// @param cross Crosswind in m/s.
  /// @returns Id of the team that rides in the gutter, or -1.
  int _echelonTeam(List<_State> order, Segment s, double cross) {
    final block = (s.km / 5).floor();
    return _echelonBlock.putIfAbsent(block, () {
      final strength = <int, double>{};
      final planned = <int>{};
      for (final m in order) {
        if (m.plan.approach == Approach.wait || m.blown || !m.role.works) {
          continue;
        }
        // A team that came to split the field puts everything into it.
        final keen = m.plan.approach == Approach.echelon;
        if (keen) planned.add(m.rider.teamId);
        strength[m.rider.teamId] = (strength[m.rider.teamId] ?? 0) +
            max(0.0, m.rider.attributes.flat - 68) * (keen ? 1.6 : 1);
      }
      if (strength.isEmpty) return -1;
      final best =
          strength.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final keen = planned.contains(best.key);
      if (best.value < (keen ? 8 : 12)) return -1;
      final chance = keen
          ? ((cross - 3) / 4).clamp(0.0, 0.95)
          : ((cross - 4) / 5).clamp(0.0, 0.9);
      return rng.nextDouble() < chance ? best.key : -1;
    });
  }

  /// Top speed of a group on a descent: the riders at the front set it.
  ///
  /// @param members The group.
  /// @param s Current segment.
  /// @param leader A rider who leads alone, e.g. after an attack.
  /// @returns Speed limit in m/s.
  double _groupDescentCap(List<_State> members, Segment s, _State? leader) {
    if (s.grade > -0.03) return 40;
    if (leader != null || members.length == 1) {
      final m = leader ?? members.first;
      return descentCap(s.grade, m.rider.attributes.downhill,
          massKg: m.rider.massKg, wet: _wet);
    }
    final skills = [for (final m in members) m.rider.attributes.downhill]
      ..sort((a, b) => b.compareTo(a));
    final masses = [for (final m in members) m.rider.massKg]..sort();
    return descentCap(s.grade, skills[(skills.length * 0.3).floor()],
        massKg: masses[masses.length ~/ 2], wet: _wet);
  }

  /// Decides whether a group behind the favourites stops racing. That happens
  /// on mountain stages once the favourites are out of reach and nobody in
  /// the group is a favourite or defends a place in the general classification.
  ///
  /// @param members The group's riders.
  /// @param gapToMain Seconds behind the group with the favourites.
  /// @returns true if the group rides as a gruppetto.
  bool _formsGruppetto(List<_State> members, double gapToMain) =>
      _selective &&
      gapToMain > (route.selectivity > 1500 ? 90 : 60) &&
      !members
          .any((m) => m.favorite || hasGc && m.gcGap != null && m.gcGap! < 900);

  /// Finds the strongest helper in a group whose leader (a favourite) is
  /// there too. Helpers of a team that wants a selection come before those
  /// of a team that waits for the sprint.
  ///
  /// @param order The group's riders sorted by strength.
  /// @returns The helper, or null if there is none with energy left.
  _State? _strongestHelper(List<_State> order) {
    final leaders = {
      for (final m in order)
        if (m.favorite) m.rider.teamId,
    };
    _State? fallback;
    for (final m in order) {
      if (m.role.works &&
          !m.blown &&
          m.reserve > 0.1 &&
          leaders.contains(m.rider.teamId)) {
        if (!_waiting.contains(m.rider.teamId)) return m;
        fallback ??= m;
      }
    }
    return fallback;
  }

  /// Charges an effort to a rider's reserves.
  ///
  /// @param m The rider.
  /// @param effort Power relative to his threshold.
  /// @param dt Duration in seconds.
  /// @param rough Difficulty of the surface; rough roads wear down riders
  ///   who are not made for them.
  void _spend(_State m, double effort, double dt, [int rough = 0]) {
    final s = route.segments[seg];
    m.tally.add(effort * m.thr, dt, m.ftp, _climbOf[seg],
        s.grade > 0 ? s.grade * s.lengthM : 0);
    final a = m.rider.attributes;
    final shaking = rough == 0
        ? 1.0
        : 1 + 0.1 * rough * ((80 - a.cobble) / 20).clamp(0.2, 1.5);
    m.energy -= dt /
        3600 *
        t.energyPerHour *
        m.climate *
        shaking *
        pow(effort, 2.2) /
        (1 + 0.02 * (a.endurance - 70));
    if (effort > 1) {
      m.reserve -= (effort - 1) /
          0.25 *
          dt /
          (t.reserveDrainS * (1 + 0.03 * (a.resistance - 70)));
    } else {
      m.reserve += (1 - effort) /
          0.3 *
          dt /
          t.reserveRefillS *
          (0.5 + 0.5 * m.energy.clamp(0.0, 1.0));
    }
    m.reserve = m.reserve.clamp(0.0, 1.0);
    // A helper who has emptied himself can no longer ride on the front.
    if (m.role.works && m.energy < t.helperEmpty) m.blown = true;
  }

  // --- Crashes and punctures ----------------------------------------------------

  /// Rolls for punctures and crashes in every group after a step.
  ///
  /// @param groups All groups; riders who lose time leave theirs for a new
  ///   group behind it.
  /// @param s The segment just ridden.
  void _incidents(List<_Group> groups, Segment s) {
    final lengthKm = s.lengthM / 1000;
    final remaining = route.raceKm - s.km;
    for (final g in [...groups]) {
      final n = g.members.length;
      if (n == 0) continue;
      // Punctures: at most one per group and segment.
      // Cobbles cost wheels and skin, the more the rougher they are.
      final cobbles = t.cobbleMishap * s.cobble / 3;
      final puncture =
          (t.punctureRate * (s.unpaved > 0 ? 5 : 1) + 0.6 * cobbles) *
              lengthKm *
              n *
              (_wet ? 1.5 : 1);
      // With material of their own the riders do not puncture alike: the
      // rate follows the group's mean risk and falls on a rider by his.
      final risks = kitted
          ? [for (final m in g.members) m.punctureRisk(s)]
          : const <double>[];
      final risk = kitted ? risks.reduce((a, b) => a + b) / n : 1.0;
      if (puncture > 0 && rng.nextDouble() < puncture * risk) {
        final _State m;
        if (kitted) {
          var x = rng.nextDouble() * risk * n;
          var i = 0;
          while (i < n - 1 && x > risks[i]) {
            x -= risks[i++];
          }
          m = g.members[i];
        } else {
          m = g.members[rng.nextInt(n)];
        }
        // In a small group the neutral service is slower than the team car;
        // a good mechanic changes the wheel faster.
        final loss = (12 + 18 * rng.nextDouble() + (n <= 15 ? 15 : 0)) *
            m.kit.serviceLoss;
        _mishap(m, g, groups, s, loss, crash: false);
      }
      if (n < 2 || t.crashRate <= 0) continue;
      final nervous = _key[seg]
          ? 2.5
          : sprintStage && remaining < 20
              ? 3.0
              : 1.0;
      final lambda = t.crashRate *
              lengthKm *
              pow(n / 50, 0.8) *
              nervous *
              (s.grade < -0.05 ? 3 : 1) *
              (_wet ? (s.grade < -0.04 ? 4 : 2) : 1) *
              (s.cobble >= 3 ? 2 : 1) +
          0.2 * cobbles * lengthKm * n * (_wet ? 2 : 1);
      if (rng.nextDouble() < lambda) _crash(g, groups, s);
    }
  }

  /// A crash in a group. On a descent it takes one or two riders, mostly
  /// poor descenders; in a bunch it takes a few riders at one spot and
  /// holds up those behind them.
  ///
  /// @param g The group.
  /// @param groups All groups.
  /// @param s Current segment.
  void _crash(_Group g, List<_Group> groups, Segment s) {
    _rank(g);
    final byPos = [...g.members]..sort((a, b) => a.rank.compareTo(b.rank));
    final n = byPos.length;
    final fallen = <_State>[];
    final held = <_State>[];
    if (s.grade < -0.04 || n < 6) {
      final weights = [
        for (final m in byPos) exp((70 - m.rider.attributes.downhill) / 5)
      ];
      var x = rng.nextDouble() * weights.reduce((a, b) => a + b);
      var i = 0;
      while (i < n - 1 && x > weights[i]) {
        x -= weights[i++];
      }
      fallen.add(byPos[i]);
      if (n > 1 && rng.nextDouble() < 0.3) fallen.add(byPos[(i + 1) % n]);
    } else {
      final at = rng.nextInt(n);
      final k = 1 + rng.nextInt(min(8, 1 + n ~/ 15));
      fallen.addAll(byPos.sublist(at, min(n, at + k)));
      final end = min(n, at + k + 3 * k + rng.nextInt(15));
      for (final m in byPos.sublist(min(n, at + k), end)) {
        if (rng.nextDouble() < 0.6) held.add(m);
      }
    }
    final notable =
        fallen.any((m) => m.favorite || _own(m)) || fallen.length >= 3;
    for (final m in fallen) {
      // Part of the loss is the bike: a good mechanic has a spare at once.
      _mishap(
          m,
          g,
          groups,
          s,
          (12 + 30 * rng.nextDouble() + (_wet ? 10 : 0)) +
              (8 + 20 * rng.nextDouble()) * m.kit.serviceLoss,
          crash: true);
    }
    if (notable && fallen.isNotEmpty) {
      events.add(RaceEvent(
          s.km,
          EventType.crash,
          tr('Crash: {0} go down', [_names(fallen, 5)]),
          [for (final m in fallen) m.rider.id]));
    }
    if (held.isNotEmpty) {
      held.removeWhere((m) => !g.members.contains(m));
      g.members.removeWhere(held.contains);
      if (g.members.isEmpty) {
        g.members.addAll(held);
        return;
      }
      groups.add(
          _Group(held, g.clock + 4 + 16 * rng.nextDouble())..convoy = true);
    }
  }

  /// A rider punctures or crashes: he loses time and drops back, helpers
  /// wait for a leader, a bad crash ends his race.
  ///
  /// @param m The rider.
  /// @param g His group.
  /// @param groups All groups; the rider's new group is added.
  /// @param s Current segment.
  /// @param loss Seconds he loses.
  /// @param crash Whether he crashed rather than punctured.
  void _mishap(_State m, _Group g, List<_Group> groups, Segment s, double loss,
      {required bool crash}) {
    // He may already have dropped back, e.g. to wait for a fallen leader.
    g = groups.firstWhere((x) => x.members.contains(m), orElse: () => g);
    final remaining = route.raceKm - s.km;
    if (remaining <= 3 && !uphillFinish) {
      // Three-kilometre rule: he gets the time of the group he was in.
      m.ruleMates ??= g.members.where((x) => x != m).toList();
    }
    if (crash) {
      m.incident = RiderIncident.crash;
      var x = rng.nextDouble();
      if (_wet && s.grade < -0.04) x = max(0.0, x - 0.08);
      if (x > 0.92) {
        _abandon(m, groups, s.km, AbandonReason.crash, 7 + rng.nextInt(54));
        return;
      }
      final hurt = x > 0.72;
      final formLoss = hurt ? 0.03 : 0.008;
      final energyLoss = hurt ? 0.08 : 0.03;
      m
        ..hurt += formLoss
        ..energy -= energyLoss
        ..reserve = min(m.reserve, 0.5);
      if (hurt) loss += 30;
      injuries[m.rider.id] = Injury(
          (injuries[m.rider.id]?.formLoss ?? 0) + formLoss,
          (injuries[m.rider.id]?.energyLoss ?? 0) + energyLoss);
    } else {
      if (m.incident == RiderIncident.none) {
        m.incident = RiderIncident.puncture;
      }
      if (m.favorite || _own(m)) {
        events.add(RaceEvent(s.km, EventType.puncture,
            tr('Puncture for {0}', [m.rider.name]), [m.rider.id]));
      }
    }
    if (g.members.length <= 1) {
      g.clock += loss;
      return;
    }
    g.members.remove(m);
    final back = _Group([m], g.clock + loss)..convoy = true;
    // Helpers wait for their leader and bring him back. Two as a rule; the
    // whole team when a leader of the general classification is at stake.
    if (m.role.sheltered && remaining > 3) {
      final available = g.members
          .where((x) =>
              x.rider.teamId == m.rider.teamId &&
              x.role.works &&
              !x.blown &&
              x.energy > 0.3)
          .toList();
      final suggested = m.favorite &&
              hasGc &&
              m.gcGap != null &&
              m.gcGap! < 120 &&
              remaining > 25 &&
              available.length > 2
          ? 1
          : 0;
      var answer = suggested;
      if (_own(m) && available.isNotEmpty) {
        answer = _ask(
            RadioKind.mishap,
            s.km,
            tr(
                'Km {0}: {1} {2} and loses about {3}. {4} of our helpers are in his group.',
                [
                  s.km.round(),
                  m.rider.name,
                  crash ? tr('crashes') : tr('punctures'),
                  _clock(loss),
                  available.length,
                ]),
            [
              tr('Two helpers wait for him'),
              tr('The whole team waits'),
              tr('Nobody waits, the others ride on'),
            ],
            suggested);
      }
      final helpers = answer == 2
          ? const <_State>[]
          : available.take(answer == 1 ? available.length : 2).toList();
      if (helpers.length < g.members.length) {
        g.members.removeWhere(helpers.contains);
        back.members.addAll(helpers);
      }
    }
    groups.add(back);
  }

  /// Takes a rider out of the race.
  ///
  /// @param m The rider.
  /// @param groups All groups.
  /// @param km Race kilometre.
  /// @param reason Why he stops.
  /// @param days Days he is out.
  void _abandon(_State m, List<_Group> groups, double km, AbandonReason reason,
      int days) {
    m.out = true;
    for (final g in groups) {
      g.members.remove(m);
    }
    abandons.add(Abandon(m.rider, km, reason, days));
    events.add(RaceEvent(
        km,
        EventType.abandon,
        reason == AbandonReason.crash
            ? tr('{0} has to abandon after a crash', [m.rider.name])
            : tr('{0} abandons, ill', [m.rider.name]),
        [m.rider.id]));
  }

  /// Sorts groups by riding time and merges those that have caught each other.
  ///
  /// @param groups All groups after the step.
  /// @param s Current segment, for event texts.
  /// @returns The merged groups, first on the road first.
  List<_Group> _merge(List<_Group> groups, Segment s) {
    groups.sort((a, b) => a.clock.compareTo(b.clock));
    final out = <_Group>[groups.first];
    for (final g in groups.skip(1)) {
      final ahead = out.last;
      // A gruppetto waits for riders just behind it: the bigger the bus, the
      // easier the ride to the finish.
      final waits =
          ahead.gruppetto && g.gruppetto && g.clock - ahead.clock < 40;
      if (waits) ahead.clock = g.clock;
      if (waits || g.clock - ahead.clock < 1.5) {
        final caught = ahead.members.where((m) => m.inBreak).length;
        final catching = g.members.where((m) => m.favorite).length;
        if (caught > 0 &&
            catching >= 6 &&
            ahead.members.every((m) => m.inBreak)) {
          events.add(RaceEvent(
              s.km,
              EventType.caught,
              tr('The break is caught {0} km from the finish',
                  [(route.raceKm - s.km).toStringAsFixed(1)])));
          for (final m in ahead.members) {
            m.inBreak = false;
          }
        }
        ahead.members.addAll(g.members);
        // Riders back from a mishap are in the bunch again.
        ahead.convoy = ahead.convoy && g.convoy;
        if (g.surgeKm > ahead.surgeKm) {
          ahead.surgeKm = g.surgeKm;
          ahead.surgeLeader = g.surgeLeader;
        }
      } else {
        out.add(g);
      }
    }
    return out;
  }

  /// Awards a mountain prize or intermediate sprint. Points go to riders of
  /// the leading groups; leaders rarely sprint for them.
  ///
  /// @param p The classification point.
  /// @param groups All groups.
  void _awardPoints(RoutePoint p, List<_Group> groups) {
    final climb = p.category > 0;
    double score(_State m) =>
        (climb ? m.rider.attributes.hill : m.rider.attributes.sprint) +
        (m.role.sheltered && !(m.role == Role.sprinter && !climb) ? -4 : 0) +
        // A jersey hunter goes all out for the points.
        (climb && m.role == Role.mountainHunter ||
                !climb && m.role == Role.pointsHunter
            ? 8
            : 0) +
        3 * _gauss(rng);
    final order = <_State>[];
    for (final g in groups) {
      order
          .addAll([...g.members]..sort((a, b) => score(b).compareTo(score(a))));
      if (order.length >= 15) break;
    }
    final top = order.take(15).toList();
    awards.add(PointAward(p, [for (final m in top) m.rider]));
    final label = climb
        ? tr('Mountain prize {0} {1}', [
            [
              '',
              'HC',
              tr('cat. 1'),
              tr('cat. 2'),
              tr('cat. 3'),
              tr('cat. 4')
            ][p.category.clamp(0, 5)],
            p.name
          ])
        : 'Sprint ${p.name}';
    events.add(
        RaceEvent(p.km, EventType.points, '$label: ${_names(top.take(3))}'));
  }

  /// Decides the finish: uphill everyone for himself, otherwise a sprint per group.
  ///
  /// @param groups All groups at the line.
  /// @returns The stage result.
  StageResult _finish(List<_Group> groups) {
    seg = route.segments.length - 1;
    final placings = <Placing>[];
    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      _rank(g);
      if (uphillFinish) {
        // Uphill everyone rides the last 1.5 km with whatever he has left.
        double kick(_State m) =>
            1500 /
            speedFor(_threshold(m) * (1 + t.kickGain * m.reserve),
                route.finishGrade, m.cda, _crr[seg],
                mass: m.mass, rho: _rho[seg], headwind: wind.head[seg]);
        final best = g.members.map(kick).reduce(min);
        for (final m in g.members) {
          placings.add(Placing(m.rider, g.clock + kick(m) - best, gi));
        }
      } else {
        final rising = route.finishGrade > 0.015;
        final n = g.members.length;
        // Lead-out men who still have legs and are well placed: up to two
        // count, and a good sports director puts them in a better position.
        final train = <int, int>{};
        for (final m in g.members) {
          if (m.role == Role.leadOut &&
              !m.blown &&
              m.energy > t.helperEmpty &&
              m.rank < 20) {
            train[m.rider.teamId] = (train[m.rider.teamId] ?? 0) + 1;
          }
        }
        double sprint(_State m) {
          final x = m.rider.attributes;
          final base = rising
              ? 0.35 * x.sprint + 0.3 * x.acceleration + 0.35 * x.hill
              : 0.7 * x.sprint + 0.3 * x.acceleration;
          final support = m.role.ridesForHimself
              ? min(2, train[m.rider.teamId] ?? 0) *
                  (0.6 + 0.8 * m.plan.directorSkill)
              // Helpers do not sprint for places when their leader is there.
              : g.members.any((o) =>
                      o.rider.teamId == m.rider.teamId &&
                      o.role.ridesForHimself)
                  ? -8.0
                  : 0.0;
          // Position going into the last kilometre.
          final place =
              n >= 10 ? 4 * (1 - m.rank / min(n, 25)).clamp(0.0, 1.0) - 1 : 0.0;
          return base +
              support +
              place +
              6 * (m.energy.clamp(0.0, 1.0) - 0.5) +
              3 * m.reserve -
              100 * m.hurt +
              t.sprintNoise * _gauss(rng);
        }

        final scored = {for (final m in g.members) m: sprint(m)};
        final order = [...g.members]
          ..sort((x, y) => scored[y]!.compareTo(scored[x]!));
        // A crash in a bunch sprint: the riders involved roll in at the back
        // of the group, with its time.
        if (n >= 20 &&
            t.crashRate > 0 &&
            rng.nextDouble() < 0.03 * (_wet ? 2 : 1) * t.crashRate / 0.001) {
          final at = rng.nextInt(min(20, n - 1));
          final fallen = order.sublist(at, min(n, at + 1 + rng.nextInt(3)));
          order
            ..removeWhere(fallen.contains)
            ..addAll(fallen);
          for (final m in fallen) {
            m.incident = RiderIncident.crash;
            injuries[m.rider.id] = Injury(0.01, 0.02);
          }
          events.add(RaceEvent(
              route.raceKm - 0.2,
              EventType.crash,
              tr('Crash in the sprint: {0}', [_names(fallen, 4)]),
              [for (final m in fallen) m.rider.id]));
        }
        // At sprint speed the line of a big group breaks: behind the first
        // ones a gap of a second or more opens now and then, and everyone
        // behind it gets a slower time. The favourites and those placed in
        // the general classification ride at the front and keep the time
        // of the group.
        var split = 0.0;
        for (var i = 0; i < order.length; i++) {
          final m = order[i];
          if (n >= 20 &&
              i >= t.bunchSplitFrom &&
              rng.nextDouble() < t.bunchSplitRate) {
            split += 1 + rng.nextDouble();
          }
          final front =
              m.favorite || hasGc && m.gcGap != null && m.gcGap! < 300;
          // Otherwise the same time for the group; the fraction only
          // fixes the order.
          placings.add(
              Placing(m.rider, g.clock + (front ? 0 : split) + i * 1e-4, gi));
        }
      }
    }
    // Three-kilometre rule: a rider held up by a mishap gets the time of the
    // group he was in.
    final at = {for (final p in placings) p.rider.id: p};
    for (final s in states) {
      final mates = s.ruleMates;
      final mine = at[s.rider.id];
      if (mates == null || mine == null) continue;
      final times = [
        for (final m in mates)
          if (at[m.rider.id] != null && m.ruleMates == null) at[m.rider.id]!
      ]..sort((a, b) => a.timeS.compareTo(b.timeS));
      if (times.isEmpty) continue;
      final ref = times[times.length ~/ 2];
      if (ref.timeS < mine.timeS) {
        final i = placings.indexOf(mine);
        placings[i] = Placing(mine.rider, ref.timeS + 5e-5, ref.group);
      }
    }
    placings.sort((a, b) => a.timeS.compareTo(b.timeS));
    final winner =
        states.firstWhere((s) => identical(s.rider, placings.first.rider));
    final firstGroup =
        placings.where((p) => p.group == placings.first.group).length;
    events.add(RaceEvent(
        route.raceKm,
        EventType.finish,
        firstGroup == 1
            ? tr('{0} wins solo', [winner.rider.name])
            : tr('{0} wins from a group of {1} riders',
                [winner.rider.name, firstGroup])));
    events.sort((a, b) => a.km.compareTo(b.km));
    final inGruppetto = {
      for (final g in groups)
        if (g.gruppetto)
          for (final m in g.members) m,
    };
    return StageResult(placings, events, winner.inBreak, awards)
      ..timeline = _timeline
      ..abandons = abandons
      ..injuries = {
        for (final e in injuries.entries)
          if (!abandons.any((a) => a.rider.id == e.key)) e.key: e.value,
      }
      ..traces = {
        for (final m in states)
          m.rider.id: RiderTrace(m.role, m.everInBreak, m.lostKm, m.frontKm,
              m.energy.clamp(0.0, 1.0), inGruppetto.contains(m), m.incident),
      }
      ..power = {
        for (final m in states)
          m.rider.id: m.tally.result(m.ftp, m.rider.massKg, route.climbTops),
      };
  }
}

/// @param seconds A time gap.
/// @returns `m:ss`.
String _clock(double seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Simulates an individual or team time trial.
///
/// Riders start in reverse order of the general classification (in random
/// order without one) and the wind changes over the day, so the time of
/// day matters. Fatigue from earlier stages and from the effort itself
/// counts. In a team time trial the team rides in a line that is as fast
/// as its riders can share; whoever cannot hold the wheel is let go once
/// the team has enough riders left for the time to be taken.
///
/// @param route The stage.
/// @param states Riders with their condition.
/// @param rng Random source.
/// @param t Tuning values.
/// @param weather Weather of the day.
/// @param wind Wind along the route.
/// @returns The stage result.
StageResult _timeTrial(SimRoute route, List<_State> states, Random rng,
    SimTuning t, Weather weather, WindField wind, RaceTrack? track) {
  final segments = route.segments;
  final rho = [for (final s in segments) airDensity(s.altitudeM)];
  final crr = [
    for (final s in segments) rollingResistance(s, wet: weather.rain)
  ];
  final alt = [for (final s in segments) altitudePower(s.altitudeM)];
  final tops = route.climbTops;
  final climbOf = climbSegments(route);
  // Drag area and mass on the bike of the day.
  double ttCda(_State m) =>
      (m.kit.timeTrialBike ? timeTrialCda : roadBikeTimeTrialCda) *
      cdaScale(m.rider) *
      m.kit.aero;
  // The bike mass of the model is that of a time trial bike; the road bike
  // is lighter.
  double ttMass(_State m) =>
      m.mass - (m.kit.timeTrialBike ? 0 : timeTrialBikeExtraKg);
  for (final m in states) {
    final a = m.rider.attributes;
    m.ftp = thresholdPower(route.raceKm < 8 ? a.prologue : a.timeTrial, t) *
        bodyScale(m.rider, 0) *
        m.form;
  }
  void record(_State m, int i, double watts, double dt) {
    final s = segments[i];
    m.tally.add(
        watts, dt, m.ftp, climbOf[i], s.grade > 0 ? s.grade * s.lengthM : 0);
  }

  // Short time trials are ridden above threshold, long ones just below.
  final pacing = route.raceKm < 8
      ? 1.08
      : route.raceKm < 25
          ? 1.02
          : 0.98;
  final events = <RaceEvent>[
    RaceEvent(0, EventType.weather, tr('Weather: {0}', [weather.describe()])),
  ];
  final abandons = <Abandon>[];
  final injuries = <int, Injury>{};

  // Start order and how the wind changes over the day.
  final order = [...states];
  if (states.any((m) => m.gcGap != null)) {
    order.sort((a, b) =>
        (b.gcGap ?? double.infinity).compareTo(a.gcGap ?? double.infinity));
  } else {
    order.shuffle(rng);
  }
  final trend = 0.35 * _gauss(rng);
  double windAt(int startIndex) =>
      (1 + trend * 2 * (startIndex / max(1, order.length - 1) - 0.5))
          .clamp(0.0, 2.0);
  final startIndex = {for (var i = 0; i < order.length; i++) order[i]: i};

  /// Threshold power of a rider on a segment in time trial position.
  double power(_State m, int i) {
    final a = m.rider.attributes;
    final s = segments[i];
    final level = route.raceKm < 8 ? a.prologue : a.timeTrial;
    final attr =
        s.grade > 0.03 ? 0.5 * level + 0.5 * effectiveAttribute(s, a) : level;
    return thresholdPower(attr, t) *
        bodyScale(m.rider, s.grade) *
        alt[i] *
        m.form *
        (1 - t.fatigueLoss * pow(1 - m.energy.clamp(0.0, 1.0), 1.5));
  }

  void drain(_State m, double effort, double dt) {
    m.energy -= dt /
        3600 *
        t.energyPerHour *
        m.climate *
        pow(effort, 2.2) /
        (1 + 0.02 * (m.rider.attributes.endurance - 70));
  }

  double speed(_State m, int i, double p, double cda, double windScale) {
    final s = segments[i];
    return min(
        speedFor(p, s.grade, cda, crr[i] * m.roll(s, weather.rain),
            mass: ttMass(m), rho: rho[i], headwind: wind.head[i] * windScale),
        descentCap(s.grade, m.rider.attributes.downhill,
            massKg: m.rider.massKg, wet: weather.rain));
  }

  /// Punctures and crashes over the whole course for one rider.
  ///
  /// @returns Seconds lost, or null if he had to give up.
  double? mishaps(_State m) {
    var loss = 0.0;
    final risk =
        m.kit.punctures * m.kit.tyres.punctures(0) * m.kit.mechanicalRate;
    if (rng.nextDouble() < t.punctureRate * route.raceKm * 2 * risk) {
      loss += (20 + 15 * rng.nextDouble()) * m.kit.serviceLoss;
      m.incident = RiderIncident.puncture;
      events.add(RaceEvent(rng.nextDouble() * route.raceKm, EventType.puncture,
          tr('Puncture for {0}', [m.rider.name]), [m.rider.id]));
    }
    final technical =
        segments.where((s) => s.grade < -0.04).length / max(1, segments.length);
    if (rng.nextDouble() <
        t.crashRate *
            0.05 *
            route.raceKm *
            (1 + 5 * technical) *
            (weather.rain ? 3 : 1)) {
      m.incident = RiderIncident.crash;
      final km = rng.nextDouble() * route.raceKm;
      if (rng.nextDouble() < 0.08) {
        abandons.add(
            Abandon(m.rider, km, AbandonReason.crash, 7 + rng.nextInt(30)));
        events.add(RaceEvent(
            km,
            EventType.abandon,
            tr('{0} has to abandon after a crash', [m.rider.name]),
            [m.rider.id]));
        return null;
      }
      loss += 30 + 30 * rng.nextDouble();
      injuries[m.rider.id] = Injury(0.01, 0.03);
      events.add(RaceEvent(km, EventType.crash,
          tr('Crash: {0} go down', [m.rider.name]), [m.rider.id]));
    }
    return loss;
  }

  final times = <_State, double>{};
  if (route.kind == StageKind.timeTrial) {
    for (final m in order) {
      final windScale = windAt(startIndex[m]!);
      // How well he judges his effort on the day.
      final pace = pacing * (1 + 0.01 * _gauss(rng));
      final cda = ttCda(m);
      var time = 0.0;
      for (var i = 0; i < segments.length; i++) {
        final p = power(m, i) * pace;
        final v = speed(m, i, p, cda, windScale);
        final dt = segments[i].lengthM / v;
        drain(m, pace, dt);
        record(m, i, p, dt);
        time += dt;
        track?.pass(i, m.rider.id, time, 0);
      }
      // Riders set off a minute apart.
      track?.starts[m.rider.id] = 60.0 * startIndex[m]!;
      final loss = mishaps(m);
      if (loss != null) times[m] = time + loss;
    }
  } else {
    final teams = <int, List<_State>>{};
    for (final m in states) {
      teams.putIfAbsent(m.rider.teamId, () => []).add(m);
    }
    var teamIndex = 0;
    for (final members in teams.values) {
      final windScale =
          windAt((teamIndex++ * order.length / max(1, teams.length)).floor());
      // The time is taken on the fifth rider of a team of seven or more,
      // otherwise on the fourth.
      final needed = min(members.length, members.length >= 7 ? 5 : 4);
      final pace = pacing * (1 + 0.01 * _gauss(rng));
      var line = [...members];
      final alone = <_State, double>{};
      bool waitedFor(_State m) => m.plan.waitForLeader && m.role == Role.leader;
      var clock = 0.0;
      for (var i = 0; i < segments.length; i++) {
        final s = segments[i];
        final powers = {for (final m in line) m: power(m, i) * pace};
        double front(_State m, double v) =>
            powerFor(v, s.grade, ttCda(m), crr[i] * m.roll(s, weather.rain),
                mass: ttMass(m),
                rho: rho[i],
                headwind: wind.head[i] * windScale);
        double behind(_State m, double v) => powerFor(
            v, s.grade, ttCda(m) * t.tttDraft, crr[i] * m.roll(s, weather.rain),
            mass: ttMass(m), rho: rho[i], headwind: wind.head[i] * windScale);
        // Fastest speed the line can share: every rider takes his turn in
        // the wind and must hold the wheel the rest of the time.
        double teamSpeed() {
          var lo = 1.0, hi = 30.0;
          final k = line.length;
          for (var it = 0; it < 30; it++) {
            final v = (lo + hi) / 2;
            var need = 0.0, have = 0.0;
            var holds = true, waits = false;
            for (final m in line) {
              need += front(m, v) / k + behind(m, v) * (k - 1) / k;
              have += powers[m]!;
              if (behind(m, v) > powers[m]! * 1.05) {
                holds = false;
                if (waitedFor(m)) waits = true;
              }
            }
            if (need <= have && !waits && (holds || k > needed)) {
              lo = v;
            } else {
              hi = v;
            }
          }
          return lo;
        }

        var v = teamSpeed();
        // Riders who cannot hold the wheel are let go while enough remain;
        // a leader the team waits for stays.
        while (line.length > needed) {
          final weak = line
              .where((m) => !waitedFor(m) && behind(m, v) > powers[m]! * 1.05);
          if (weak.isEmpty) break;
          final m = weak.reduce((a, b) => powers[a]! <= powers[b]! ? a : b);
          line.remove(m);
          alone[m] = clock;
          v = teamSpeed();
        }
        final mid = line[line.length ~/ 2];
        v = min(
            v,
            descentCap(s.grade, mid.rider.attributes.downhill,
                massKg: mid.rider.massKg, wet: weather.rain));
        final dt = s.lengthM / v;
        for (final m in line) {
          final k = line.length;
          final watts = front(m, v) / k + behind(m, v) * (k - 1) / k;
          drain(m, watts / powers[m]! * pace, dt);
          record(m, i, watts, dt);
        }
        // Dropped riders ride on alone.
        for (final e in alone.entries) {
          final m = e.key;
          final cda = ttCda(m);
          final p = power(m, i) * pace;
          final dv = speed(m, i, p, cda, windScale);
          final ddt = s.lengthM / dv;
          drain(m, pace, ddt);
          record(m, i, p, ddt);
          alone[m] = e.value + ddt;
          track?.pass(i, m.rider.id, alone[m]!, 0);
        }
        clock += dt;
        for (final (k, m) in line.indexed) {
          track?.pass(i, m.rider.id, clock, k);
        }
      }
      // Teams set off two minutes apart.
      for (final m in members) {
        track?.starts[m.rider.id] = 120.0 * (teamIndex - 1);
      }
      final finish = {
        for (final m in members) m: alone[m] ?? clock,
      };
      final sorted = finish.values.toList()..sort();
      final teamTime = sorted[needed - 1];
      for (final m in members) {
        // Everyone who finishes with or before the counting rider gets his time.
        final own = finish[m]!;
        final loss = mishaps(m);
        if (loss == null) continue;
        times[m] = (own <= teamTime ? teamTime : own) + loss;
      }
    }
  }
  final placings = [
    for (final e in times.entries) Placing(e.key.rider, e.value, 0)
  ]..sort((a, b) => a.timeS.compareTo(b.timeS));
  events
    ..add(RaceEvent(route.raceKm, EventType.finish,
        tr('{0} wins the time trial', [placings.first.rider.name])))
    ..sort((a, b) => a.km.compareTo(b.km));
  return StageResult(placings, events, false)
    ..abandons = abandons
    ..injuries = injuries
    ..power = {
      for (final m in states)
        m.rider.id: m.tally.result(m.ftp, m.rider.massKg, tops),
    };
}
