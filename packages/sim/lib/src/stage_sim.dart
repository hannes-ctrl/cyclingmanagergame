import 'dart:math';

import 'model.dart';
import 'physics.dart';
import 'tactics.dart';
import 'trace.dart';
import 'tuning.dart';

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
  _State(this.rider, this.form, this.energy);
  final SimRider rider;
  final double form;

  /// Endurance reserve, drains over the stage.
  double energy;

  /// Short-term reserve for efforts above threshold.
  double reserve = 1;
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

  /// Threshold power per segment without fatigue.
  late List<double> basePower;
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
    var w = 0.2 + max(0.0, s.grade - 0.02) * 40 + s.cobble * 0.5;
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
  return '${list.take(limit).join(', ')} und ${list.length - limit} weitere';
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
}) {
  final rng = Random(seed);
  tuning ??= SimTuning.standard;
  final allPlans = {...autoPlans(route, riders, gcGaps: gcGaps), ...plans};
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
      )
        ..plan = allPlans[r.teamId]!
        ..role = allPlans[r.teamId]!.roleOf(r.id)
        ..gcGap = gcGaps[r.id],
  ];
  if (route.kind != StageKind.road) {
    return _timeTrial(route, states, rng, tuning);
  }
  final race = _RoadRace(route, states, rng, tuning)
    ..radioTeam = radioTeam
    ..radio = radio
    ..askRadio = askRadio;
  try {
    return race.run();
  } on _RadioStop catch (stop) {
    return StageResult(const [], race.events, false)..openCall = stop.call;
  }
}

/// Pauses the stage at a question that has no answer yet.
class _RadioStop implements Exception {
  _RadioStop(this.call);
  final RadioCall call;
}

/// One run of a road stage: the state of all groups and the rules that move them.
class _RoadRace {
  _RoadRace(this.route, this.states, this.rng, this.t);

  final SimRoute route;
  final List<_State> states;
  final Random rng;
  final SimTuning t;
  final events = <RaceEvent>[];
  final awards = <PointAward>[];
  final _lastAttackKm = <int, double>{};
  bool _gruppettoReported = false;
  final _timeline = <RaceSample>[];

  // --- Radio ------------------------------------------------------------------
  // The team [radioTeam] is asked at up to three points. If [radio] holds an
  // answer it applies; otherwise [askRadio] pauses the stage, or the plan
  // stands (answer 0). Answer 0 never changes anything, so a race without
  // radio runs exactly as before.
  int? radioTeam;
  Map<RadioKind, int> radio = const {};
  bool askRadio = false;
  final _asked = <RadioKind>{};
  bool _drive = false, _defensive = false;
  _State? _forcedAttacker;

  bool _own(_State m) => m.rider.teamId == radioTeam;

  /// Asks the sports director, or takes the answer already given.
  ///
  /// @param kind Which decision point this is.
  /// @param km Race kilometre of the question.
  /// @param text Situation report.
  /// @param options Possible instructions.
  /// @returns Index of the chosen option.
  /// @throws _RadioStop If there is no answer and [askRadio] is set.
  int _ask(RadioKind kind, double km, String text, List<String> options) {
    _asked.add(kind);
    final answer = radio[kind];
    if (answer != null) return answer.clamp(0, options.length - 1);
    if (askRadio) {
      throw _RadioStop(RadioCall(
          kind, km, route.raceKm - km, text.replaceAll('..', '.'), options));
    }
    return 0;
  }

  /// Changes the plan of the radio team for the rest of the stage.
  ///
  /// @param change Maps the current plan to the new one.
  void _setOwnPlan(TeamPlan Function(TeamPlan) change) {
    for (final m in states.where(_own)) {
      m.plan = change(m.plan);
    }
  }

  String _reserveText(_State m) => m.reserve > 0.7 && m.energy > 0.55
      ? 'wirkt frisch'
      : m.reserve > 0.4 && m.energy > 0.35
          ? 'hat noch etwas im Tank'
          : 'ist am Limit';

  /// Decision point: the break of the day has formed.
  ///
  /// @param escape The breakaway group.
  /// @param peloton The field.
  /// @param km Race kilometre.
  void _radioBreak(_Group escape, _Group peloton, double km) {
    if (radioTeam == null ||
        !peloton.members.any(_own) && !escape.members.any(_own)) {
      return;
    }
    final mine = escape.members.where(_own).toList();
    final danger = hasGc
        ? escape.members
            .where((m) => m.gcGap != null && m.gcGap! < 300)
            .toList()
        : const <_State>[];
    final head = 'Km ${km.round()}: ${escape.members.length} Fahrer sind weg – '
        '${_names(escape.members, 5)}.'
        '${danger.isEmpty ? '' : ' Gefährlich für die Gesamtwertung: ${_names(danger, 3)}.'}';
    if (mine.isNotEmpty) {
      final a = _ask(RadioKind.breakGone, km,
          '$head Von uns dabei: ${_names(mine)}.', const [
        'Mitarbeiten, die Gruppe soll durchkommen',
        'Nicht mitführen, Kräfte sparen',
      ]);
      if (a == 1) {
        for (final m in mine) {
          m.passenger = true;
        }
      }
      return;
    }
    // Who could bridge: no protected rider, preferably one who was meant for
    // the break anyway.
    double chaseScore(_State m) =>
        m.rider.attributes.breakaway +
        (m.role == Role.breakaway || m.role == Role.stageHunter ? 20 : 0) -
        (hasGc && m.gcGap != null && m.gcGap! < 180 ? 40 : 0);
    final chaser = (peloton.members
            .where((m) => _own(m) && !m.role.sheltered && !m.favorite)
            .toList()
          ..sort((a, b) => chaseScore(b).compareTo(chaseScore(a))))
        .firstOrNull;
    final a =
        _ask(RadioKind.breakGone, km, '$head Von uns ist niemand dabei.', [
      'Beim Plan bleiben',
      'Nachführen lassen: unsere Helfer an die Spitze des Feldes',
      if (chaser != null) '${chaser.rider.name} soll nachsetzen',
    ]);
    if (a == 1) {
      _setOwnPlan((p) => p.copyWith(
          breakPolicy: BreakPolicy.chase,
          approach: p.approach == Approach.wait ? Approach.control : null));
    } else if (a == 2 && chaser != null) {
      // Jumping across costs energy.
      peloton.members.remove(chaser);
      chaser
        ..inBreak = true
        ..everInBreak = true
        ..energy -= 0.04
        ..reserve = 0.4;
      escape.members.add(chaser);
      events.add(RaceEvent(km, EventType.breakaway,
          '${chaser.rider.name} setzt nach und schließt zur Gruppe auf'));
    }
  }

  /// Decision point: the finale begins.
  ///
  /// @param groups All groups, first on the road first.
  /// @param main The group with the favourites.
  /// @param s Current segment.
  void _radioFinale(List<_Group> groups, _Group main, Segment s) {
    if (radioTeam == null || _asked.contains(RadioKind.finale)) return;
    final mine = main.members.where(_own).toList();
    if (mine.isEmpty) return;
    final leaders = mine.where((m) => m.role.ridesForHimself).toList()
      ..sort((a, b) => b.fit.compareTo(a.fit));
    final helpers = mine.where((m) => m.role.works).length;
    final gap = main.clock - groups.first.clock;
    final ahead = gap > 1
        ? 'Vorn ${groups.first.members.length} Fahrer mit ${_clock(gap)} Vorsprung, '
            'dahinter das Feld mit ${main.members.length} Fahrern.'
        : 'Das Feld ist mit ${main.members.length} Fahrern zusammen.';
    final own = leaders.isEmpty
        ? 'Von uns sind ${mine.length} Fahrer dabei, kein Kapitän.'
        : '${leaders.first.rider.name} ${_reserveText(leaders.first)}, '
            '$helpers Helfer sind noch bei ihm.';
    final a = _ask(
        RadioKind.finale,
        s.km,
        'Noch ${(route.raceKm - s.km).round()} km, das Finale beginnt. $ahead $own',
        [
          'Beim Plan bleiben',
          if (helpers > 0) 'Helfer opfern: volles Tempo, bis sie platzen',
          if (!sprintStage && leaders.isNotEmpty) ...[
            '${leaders.first.rider.name} greift am nächsten schweren Stück an',
            'Nur folgen, nicht selbst angreifen',
          ],
        ]);
    final drive = helpers > 0 ? 1 : 0;
    if (a == drive && drive == 1) {
      _drive = true;
    } else if (a == drive + 1) {
      _forcedAttacker = leaders.first;
    } else if (a == drive + 2) {
      _defensive = true;
    }
  }

  late final double finaleKm;
  late final bool sprintStage;
  late final bool hasGc;
  late final double favoriteLevel;
  late final double dayMood;
  late int seg;

  double _threshold(_State s) =>
      s.basePower[seg] *
      s.form *
      (1 - t.fatigueLoss * pow(1 - s.energy.clamp(0.0, 1.0), 1.5));

  /// Simulates the stage segment by segment.
  ///
  /// @returns The stage result.
  StageResult run() {
    final segments = route.segments;
    for (final s in states) {
      s.basePower = [
        for (final x in segments)
          thresholdPower(effectiveAttribute(x, s.rider.attributes), t),
      ];
    }
    // Favourites are the strongest riders who are allowed to ride for themselves.
    final ranked = states.where((s) => s.role.ridesForHimself).toList()
      ..sort((a, b) => suitability(route, b.rider.attributes)
          .compareTo(suitability(route, a.rider.attributes)));
    for (final s in states) {
      s.fit = suitability(route, s.rider.attributes);
    }
    favoriteLevel = ranked.length > 11 ? ranked[11].fit : ranked.last.fit;
    for (final s in ranked.take(12)) {
      s.favorite = true;
    }
    sprintStage = route.sprintStage;
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

    var groups = [
      _Group([...states], 0)
    ];
    final breakKm = 3 + rng.nextDouble() * min(30.0, route.raceKm * 0.15);
    var breakFormed = false;
    var maxGap = 0.0, maxGapKm = 0.0;
    final pending = <RoutePoint>[...route.climbTops, ...route.sprints]
      ..sort((a, b) => a.km.compareTo(b.km));

    for (seg = 0; seg < segments.length; seg++) {
      final s = segments[seg];
      final inFinale = s.km >= finaleKm;

      if (!breakFormed && s.km >= breakKm && s.km < finaleKm) {
        breakFormed = true;
        final escape = _formBreak(groups.first);
        if (escape != null) {
          _radioBreak(escape, groups.first, s.km);
          groups.insert(0, escape);
        }
      }

      final main = _mainGroup(groups);
      if (inFinale) _radioFinale(groups, main, s);
      if (inFinale) _maybeAttack(groups, main, s);
      final chasing = _chasingTeams(groups, main);
      // A group is dangerous if someone in it is less than five minutes down in
      // the general classification.
      final threat = groups.any((g) =>
          g.clock < main.clock &&
          g.members.any((m) => m.gcGap != null && m.gcGap! < 300));

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
            chasingTeams: chasing,
            threatAhead: threat);
        next.add(g);
        if (dropped != null) next.add(dropped);
      }
      groups = _merge(next, s);

      _record(groups, s);
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
          'Größter Vorsprung der Spitze: ${_clock(maxGap)}'));
    }
    return _finish(groups);
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
    if (seg % 4 == 3 || seg == route.segments.length - 1) {
      _timeline.add(RaceSample(
          km,
          main.clock - groups.first.clock,
          groups.first.members.length,
          main.members.length,
          max(0.0, _middle(groups).clock - main.clock)));
    }
  }

  /// @param groups All groups, first on the road first.
  /// @returns The group in which the rider in the middle of the field rides.
  _Group _middle(List<_Group> groups) {
    var before = 0;
    for (final g in groups) {
      before += g.members.length;
      if (before * 2 >= states.length) return g;
    }
    return groups.last;
  }

  /// From here on the race for the win is on: foot of the last big climb,
  /// first hard cobbled sector in the last third, otherwise 15 km from the finish.
  ///
  /// @returns Race kilometre at which the finale starts.
  double _finaleStart() {
    var start = route.raceKm - 15;
    for (final s in route.segments) {
      if (s.km < route.raceKm * 0.55) continue;
      final bigClimb = s.climbKm >= 3 && s.grade > 0.03;
      final hardSector = s.cobble >= 4;
      if (bigClimb && s.km > route.raceKm - 45 || hardSector) {
        start = min(start, s.km);
        break;
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

  /// Teams working in the field: they want to control and have no rider of
  /// their own in a group ahead.
  ///
  /// @param groups All groups.
  /// @param main The field.
  /// @returns Ids of the chasing teams.
  Set<int> _chasingTeams(List<_Group> groups, _Group main) {
    final ahead = <int>{
      for (final g in groups)
        if (g.clock < main.clock)
          for (final m in g.members) m.rider.teamId,
    };
    return {
      for (final m in main.members)
        if ((m.plan.approach != Approach.wait ||
                m.plan.breakPolicy == BreakPolicy.chase) &&
            !ahead.contains(m.rider.teamId))
          m.rider.teamId,
    };
  }

  /// Forms the break of the day.
  ///
  /// @param peloton The field; the chosen riders are removed from it.
  /// @returns The breakaway group, or null if fewer than two riders went.
  _Group? _formBreak(_Group peloton) {
    final size = sprintStage
        ? 2 + rng.nextInt(5)
        : route.selectivity > 2500
            ? 6 + rng.nextInt(14)
            : 4 + rng.nextInt(9);
    // Role and team instruction decide who may go in the break.
    double weight(_State c) {
      final byRole = switch (c.role) {
        Role.stageHunter => 10.0,
        Role.breakaway => 6.0,
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
      // the flat, wanting to is enough.
      final byFit = sprintStage ? 1.0 : exp((c.fit - favoriteLevel) / 3);
      // A good sports director gets his riders into the break more often.
      return (0.65 + 0.5 * c.plan.directorSkill) *
          byRole *
          byTeam *
          byFit *
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
    if (picked.length < 2) return null;
    for (final p in picked) {
      p
        ..inBreak = true
        ..everInBreak = true;
    }
    peloton.members.removeWhere(picked.contains);
    events.add(RaceEvent(route.segments[seg].km, EventType.breakaway,
        '${picked.length} Fahrer setzen sich ab: ${_names(picked)}'));
    // The group starts with a small cushion; the rest follows from the pace.
    return _Group(picked, peloton.clock - 20);
  }

  /// Lets a rider attack out of the leading group if the moment is right.
  ///
  /// @param groups All groups; a new group is inserted on an attack.
  /// @param lead The group the attack comes from.
  /// @param s Current segment.
  void _maybeAttack(List<_Group> groups, _Group lead, Segment s) {
    if (lead.members.length < 2 || lead.surgeKm > 0) return;
    final selective = s.grade >= 0.04 || s.cobble >= 3;
    if (!selective) return;
    final order = [...lead.members]
      ..sort((a, b) => _threshold(b).compareTo(_threshold(a)));
    // Helpers do not attack; the strongest rider allowed to ride for himself goes.
    final own = order.where((m) => m.role.ridesForHimself);
    if (own.isEmpty) return;
    var best = own.first;
    // Instructed over the radio: our man attacks as soon as he can.
    final forced = _forcedAttacker;
    if (forced != null && order.contains(forced) && forced.reserve >= 0.5) {
      best = forced;
      _forcedAttacker = null;
    } else {
      if (best.reserve < 0.5) return;
      final rival = own.skip(1).isEmpty
          ? order.firstWhere((m) => m != best)
          : own.elementAt(1);
      final edge = _threshold(best) / _threshold(rival) - 1;
      // On sprint stages the sprinters' teams hold the field together.
      final chance = (s.lengthM /
              1000 *
              (t.attackRatePerKm + t.attackEdgeGain * edge) *
              (sprintStage ? 0.2 : 1))
          .clamp(0.0, 0.8);
      if (rng.nextDouble() > chance) return;
      if (_defensive && _own(best)) return;
    }

    final followers = [
      for (final m in order)
        if (m != best &&
            m.role.ridesForHimself &&
            _threshold(m) >= _threshold(best) * (1 - t.followMargin) &&
            m.reserve > 0.35 &&
            rng.nextDouble() < t.followChance + 0.2 * m.plan.directorSkill)
          m,
    ];
    // A rival attacks and our man hesitates: the director can send him after
    // the move, even if it is beyond his means.
    if (radioTeam != null &&
        !_own(best) &&
        !_asked.contains(RadioKind.rivalAttack) &&
        !followers.any(_own)) {
      final mine = order
          .where((m) =>
              _own(m) &&
              m.role.ridesForHimself &&
              m.reserve > 0.2 &&
              _threshold(m) >= _threshold(best) * (1 - 2.5 * t.followMargin))
          .firstOrNull;
      if (mine != null) {
        final a = _ask(
            RadioKind.rivalAttack,
            s.km,
            '${best.rider.name} (${best.rider.team}) greift '
            '${(route.raceKm - s.km).toStringAsFixed(1)} km vor dem Ziel an'
            '${followers.isEmpty ? ', niemand folgt' : ', es folgen ${_names(followers, 4)}'}. '
            '${mine.rider.name} ${_reserveText(mine)}.',
            [
              'Eigenes Tempo fahren',
              '${mine.rider.name} soll mitgehen',
            ]);
        if (a == 1) followers.add(mine);
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
            ? '${best.rider.name} greift ${rest.toStringAsFixed(1)} km vor dem Ziel an, niemand folgt'
            : '${best.rider.name} greift ${rest.toStringAsFixed(1)} km vor dem Ziel an, es folgen: ${_names(followers)}'));
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
  /// @param chasingTeams Teams working in the field.
  /// @param threatAhead Whether a rider dangerous for the general
  ///   classification is up the road.
  /// @returns The dropped riders as a new group, or null if nobody was dropped.
  _Group? _advance(
    _Group g,
    Segment s, {
    required bool isFront,
    required bool isMain,
    required bool aheadOfMain,
    required double gapToFront,
    required double gapToMain,
    required bool inFinale,
    required Set<int> chasingTeams,
    required bool threatAhead,
  }) {
    final order = g.members
      ..sort((a, b) => _threshold(b).compareTo(_threshold(a)));
    final n = order.length;
    final crr = rollingResistance(s);
    // On cobbles everyone rides his own line; the slipstream hardly helps.
    final draft =
        1 - (1 - draftFactor(n, t)) * (1 - t.cobbleDraftLoss * s.cobble);
    // Hard sectors are ridden flat out even far from the finish.
    final racing = inFinale || s.cobble >= 3 && s.km > route.raceKm * 0.35;
    // Whoever sets the pace takes turns and feels more wind than the rest.
    final frontCda = soloCda *
        (n >= 3
            ? (1 + draft) / 2
            : n == 2
                ? 0.86
                : 1);
    final remainingKm = route.raceKm - s.km;

    // Who sets the pace, how hard he rides and who is in the wind with him.
    _State ref;
    double effort;
    var workers = <_State>{};
    if (g.surgeKm > 0 &&
        g.surgeLeader != null &&
        g.surgeLeader!.reserve > 0.08 &&
        order.contains(g.surgeLeader)) {
      ref = g.surgeLeader!;
      effort = t.surgeEffort;
      workers = {ref};
    } else if (racing && (isMain || aheadOfMain)) {
      final hard = s.grade > 0.02 || s.cobble > 0 || remainingKm < 5;
      // Between the hard parts the front keeps going; larger chase groups watch
      // each other and work less well.
      effort = hard
          ? 1.0
          : isFront
              ? t.finaleEaseEffort
              : n > 8
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
      // Over the radio: our helpers ride on the front until they are empty.
      if (_drive && isMain) {
        final crew = [
          for (final m in order)
            if (_own(m) && m.role.works && m.energy > 0.15) m,
        ];
        if (crew.isNotEmpty &&
            _threshold(crew.first) >= _threshold(byRank) * 0.92) {
          effort = 1.0;
          ref = crew.first;
          workers = crew.take(3).toSet();
        }
      }
    } else if (aheadOfMain) {
      ref = order[n ~/ 2];
      effort = inFinale ? 0.96 : t.breakEffort;
      workers = order.any((m) => m.passenger)
          ? order.where((m) => !m.passenger).toSet()
          : order.toSet();
    } else if (isMain) {
      // In the field the helpers of the teams with something to win do the work.
      final pool = [
        for (final m in order)
          // The climbing domestiques are saved for the finale.
          if (m.role.works &&
              m.role != Role.climbDomestique &&
              chasingTeams.contains(m.rider.teamId))
            m,
      ];
      final pace = pool.isEmpty
          ? [
              for (final m in order)
                if (!m.role.sheltered) m
            ]
          : pool;
      final crew = pace.isEmpty ? order : pace;
      ref = crew[crew.length ~/ 2];
      workers = crew.take(8).toSet();
      // The bigger the gap relative to the distance left, the harder the chase.
      // If nobody dangerous for the general classification is up the road, the
      // GC teams let the group go on hard days.
      final letGo = hasGc && !sprintStage && !threatAhead ? t.letGoFactor : 1.0;
      final allowed = max(
          20.0,
          t.secondsPerKmAllowed *
              (sprintStage ? t.sprintStageAllowed : 1) *
              letGo *
              remainingKm);
      final pressure = (gapToFront / allowed).clamp(0.0, 1.0);
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
            if (m.plan.approach == Approach.makeHard && m.role.works) m,
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
    } else if (_formsGruppetto(order, gapToMain)) {
      // Gruppetto: nobody here has anything left to win, so the group rides
      // at a pace its weaker riders can hold and saves itself for tomorrow.
      g.gruppetto = true;
      ref = order[min(n - 1, (n * 0.85).floor())];
      // Close to the time limit the bus has to ride.
      final share = gapToMain / max(1.0, g.clock - gapToMain);
      effort = share > t.gruppettoLimit
          ? max(t.gruppettoEffort, t.droppedEffort)
          : t.gruppettoEffort;
      workers = order.take(12).toSet();
      if (n >= 20 && !_gruppettoReported) {
        _gruppettoReported = true;
        events.add(RaceEvent(s.km, EventType.gruppetto,
            'Hinten bildet sich das Gruppetto: $n Fahrer, ${_clock(gapToMain)} hinter den Favoriten'));
      }
    } else {
      // Dropped riders: chase at first, far behind just get to the finish.
      g.gruppetto = false;
      ref = order[n ~/ 2];
      effort = gapToFront < 180 && !inFinale ? 0.92 : t.droppedEffort;
      workers = order.where((m) => !m.role.sheltered).take(6).toSet();
    }
    var v = speedFor(_threshold(ref) * effort, s.grade, frontCda, crr);
    v = min(v, descentCap(s.grade, ref.rider.attributes.downhill));
    final dt = s.lengthM / v;

    final followPower = powerFor(v, s.grade, soloCda * draft, crr);
    final frontPower = powerFor(v, s.grade, frontCda, crr);
    // The more riders share the work in front, the less wind each one gets.
    final share = workers.isEmpty ? 0.0 : min(1.0, 3 / workers.length);
    final workPower = followPower + (frontPower - followPower) * share;
    final dropped = <_State>[];
    for (var i = 0; i < n; i++) {
      final m = order[i];
      final working = n <= 3 || workers.contains(m);
      if (working && n > 1) m.frontKm += s.lengthM / 1000;
      final e = max(0.0, (working ? workPower : followPower) / _threshold(m));
      final burst = 1.35 + 0.01 * (m.rider.attributes.acceleration - 70);
      // On hard cobbles only the front gets through: whoever enters the sector
      // further back loses contact regardless of his legs.
      final squeezed = s.cobble >= 3 && i >= t.cobbleSqueeze;
      if (!identical(m, ref) &&
          (squeezed || e > burst || e > 1.0 && m.reserve <= 0.03)) {
        dropped.add(m);
        continue;
      }
      _spend(m, e, dt);
    }
    g.clock += dt;
    if (g.surgeKm > 0) g.surgeKm -= s.lengthM / 1000;

    if (dropped.isEmpty) return null;
    g.members.removeWhere(dropped.contains);
    if (inFinale && isFront) {
      final lost =
          dropped.where((m) => m.favorite && !m.droppedReported).toList();
      for (final m in lost) {
        m.droppedReported = true;
      }
      if (lost.isNotEmpty) {
        events.add(RaceEvent(s.km, EventType.dropped,
            '${_names(lost)} ${lost.length == 1 ? 'muss' : 'müssen'} abreißen lassen'));
      }
    }
    // The dropped riders ride this segment together at their own pace.
    dropped.sort((a, b) => _threshold(b).compareTo(_threshold(a)));
    final mid = dropped[dropped.length ~/ 2];
    final dv = min(
        speedFor(_threshold(mid) * 0.95, s.grade,
            soloCda * (dropped.length > 2 ? 0.8 : 1), crr),
        v * 0.995);
    final ddt = s.lengthM / dv;
    for (final m in dropped) {
      _spend(m, 0.95, ddt);
    }
    return _Group(dropped, g.clock - dt + ddt);
  }

  /// Decides whether a group behind the favourites stops racing. That happens
  /// on mountain stages once the favourites are out of reach and nobody in
  /// the group is a favourite or defends a place in the general classification.
  ///
  /// @param members The group's riders.
  /// @param gapToMain Seconds behind the group with the favourites.
  /// @returns true if the group rides as a gruppetto.
  bool _formsGruppetto(List<_State> members, double gapToMain) =>
      route.selectivity > 1500 &&
      gapToMain > 90 &&
      !members
          .any((m) => m.favorite || hasGc && m.gcGap != null && m.gcGap! < 900);

  /// Finds the strongest helper in a group whose leader (a favourite) is there too.
  ///
  /// @param order The group's riders sorted by strength.
  /// @returns The helper, or null if there is none with energy left.
  _State? _strongestHelper(List<_State> order) {
    final leaders = {
      for (final m in order)
        if (m.favorite) m.rider.teamId,
    };
    for (final m in order) {
      if (m.role.works && m.reserve > 0.1 && leaders.contains(m.rider.teamId)) {
        return m;
      }
    }
    return null;
  }

  /// Charges an effort to a rider's reserves.
  ///
  /// @param m The rider.
  /// @param effort Power relative to his threshold.
  /// @param dt Duration in seconds.
  void _spend(_State m, double effort, double dt) {
    final a = m.rider.attributes;
    m.energy -= dt /
        3600 *
        t.energyPerHour *
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
          events.add(RaceEvent(s.km, EventType.caught,
              'Die Ausreißer werden ${(route.raceKm - s.km).toStringAsFixed(1)} km vor dem Ziel gestellt'));
          for (final m in ahead.members) {
            m.inBreak = false;
          }
        }
        ahead.members.addAll(g.members);
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
        ? 'Bergwertung ${const [
            '',
            'HC',
            '1. Kat.',
            '2. Kat.',
            '3. Kat.',
            '4. Kat.'
          ][p.category.clamp(0, 5)]} ${p.name}'
        : 'Sprint ${p.name}';
    events.add(
        RaceEvent(p.km, EventType.points, '$label: ${_names(top.take(3))}'));
  }

  /// Decides the finish: uphill everyone for himself, otherwise a sprint per group.
  ///
  /// @param groups All groups at the line.
  /// @returns The stage result.
  StageResult _finish(List<_Group> groups) {
    final last = route.segments.last;
    seg = route.segments.length - 1;
    final uphill = route.finishGrade > 0.035;
    final placings = <Placing>[];
    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      if (uphill) {
        // Uphill everyone rides the last 1.5 km with whatever he has left.
        double kick(_State m) =>
            1500 /
            speedFor(_threshold(m) * (1 + t.kickGain * m.reserve),
                route.finishGrade, soloCda, rollingResistance(last));
        final best = g.members.map(kick).reduce(min);
        for (final m in g.members) {
          placings.add(Placing(m.rider, g.clock + kick(m) - best, gi));
        }
      } else {
        final rising = route.finishGrade > 0.015;
        // Lead-out men and helpers in the train: up to two count, and a good
        // sports director puts them in a better position.
        final train = <int, int>{};
        for (final m in g.members) {
          if (m.role == Role.leadOut) {
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
          return base +
              support +
              6 * (m.energy.clamp(0.0, 1.0) - 0.5) +
              3 * m.reserve +
              t.sprintNoise * _gauss(rng);
        }

        final scored = {for (final m in g.members) m: sprint(m)};
        final order = [...g.members]
          ..sort((x, y) => scored[y]!.compareTo(scored[x]!));
        for (var i = 0; i < order.length; i++) {
          // Same time for the group; the fraction only fixes the order.
          placings.add(Placing(order[i].rider, g.clock + i * 1e-4, gi));
        }
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
            ? '${winner.rider.name} gewinnt als Solist'
            : '${winner.rider.name} gewinnt aus einer Gruppe von $firstGroup Fahrern'));
    events.sort((a, b) => a.km.compareTo(b.km));
    final inGruppetto = {
      for (final g in groups)
        if (g.gruppetto)
          for (final m in g.members) m,
    };
    return StageResult(placings, events, winner.inBreak, awards)
      ..timeline = _timeline
      ..traces = {
        for (final m in states)
          m.rider.id: RiderTrace(m.role, m.everInBreak, m.lostKm, m.frontKm,
              m.energy.clamp(0.0, 1.0), inGruppetto.contains(m)),
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
/// @param route The stage.
/// @param states Riders with their condition.
/// @param rng Random source.
/// @param t Tuning values.
/// @returns The stage result.
StageResult _timeTrial(
    SimRoute route, List<_State> states, Random rng, SimTuning t) {
  /// @param m A rider.
  /// @returns His riding time in seconds.
  double ride(_State m) {
    final a = m.rider.attributes;
    // Short time trials are ridden above threshold, long ones just below.
    final pacing = route.raceKm < 8
        ? 1.08
        : route.raceKm < 25
            ? 1.02
            : 0.98;
    var time = 0.0;
    for (final s in route.segments) {
      final level = route.raceKm < 8 ? a.prologue : a.timeTrial;
      final attr =
          s.grade > 0.03 ? 0.5 * level + 0.5 * effectiveAttribute(s, a) : level;
      final power = thresholdPower(attr, t) * m.form * pacing;
      final v = min(
          speedFor(power, s.grade, timeTrialCda, rollingResistance(s)),
          descentCap(s.grade, a.downhill));
      time += s.lengthM / v;
    }
    return time;
  }

  final times = {for (final m in states) m: ride(m)};
  if (route.kind == StageKind.teamTimeTrial) {
    // Team time: mean of the best four; drafting is worth a good 3 %.
    final teams = <int, List<_State>>{};
    for (final m in states) {
      teams.putIfAbsent(m.rider.teamId, () => []).add(m);
    }
    for (final members in teams.values) {
      final best = members.map((m) => times[m]!).toList()..sort();
      final top = best.take(4);
      final team = top.reduce((a, b) => a + b) / top.length * 0.968;
      for (final m in members) {
        times[m] = team;
      }
    }
  }
  final placings = [for (final m in states) Placing(m.rider, times[m]!, 0)]
    ..sort((a, b) => a.timeS.compareTo(b.timeS));
  return StageResult(
      placings,
      [
        RaceEvent(route.raceKm, EventType.finish,
            '${placings.first.rider.name} gewinnt das Zeitfahren'),
      ],
      false);
}
