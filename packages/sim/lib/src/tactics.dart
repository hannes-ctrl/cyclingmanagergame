import 'i18n.dart';
import 'model.dart';
import 'stage_sim.dart' show suitability;

/// A rider's job in the race.
enum Role {
  /// Rides for the team's main goal and is protected.
  leader('Leader'),

  /// Second card; may follow moves and attack himself.
  coLeader('Co-leader'),

  /// Protected, but without a goal of his own.
  protected('Protected rider'),

  /// Should make the break of the day and ride for the stage win.
  stageHunter('Stage hunter'),
  sprinter('Sprinter'),

  /// Last men in front of the sprinter.
  leadOut('Lead-out man'),

  /// Sets the pace on climbs for the leader.
  climbDomestique('Climbing domestique'),

  /// Controls the field on the flat and brings groups back.
  tempo('Tempo rider'),

  /// Should make the break as a relay for the leader.
  breakaway('Breakaway'),
  domestique('Water carrier'),

  /// Decides for himself as the race unfolds.
  freeRole('Free role'),

  /// Goes into the breaks of mountain stages and takes the points on the
  /// climbs, for the mountains jersey.
  mountainHunter('Mountains jersey hunter'),

  /// Goes into the breaks of flat stages and sprints at the intermediate
  /// sprints, for the points jersey.
  pointsHunter('Points jersey hunter');

  const Role(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);

  /// Riders who ride for themselves and may attack.
  bool get ridesForHimself =>
      this == leader ||
      this == coLeader ||
      this == stageHunter ||
      this == sprinter ||
      this == freeRole;

  /// Riders who set the pace for others.
  bool get works =>
      this == tempo ||
      this == domestique ||
      this == climbDomestique ||
      this == leadOut;

  /// Riders who are kept out of the wind.
  bool get sheltered =>
      this == leader ||
      this == coLeader ||
      this == protected ||
      this == sprinter;
}

/// How the team approaches the race.
enum Approach {
  /// Ride along and wait for the finale.
  wait,

  /// Control the field and catch the breakaway in time.
  control,

  /// Set a hard pace on the climbs before the finale.
  makeHard,

  /// Split the field in the crosswind: the team rides in the gutter on
  /// open roads wherever the wind allows it, and controls the race
  /// otherwise.
  echelon,
}

/// How a team's sports directors like to race and to build their squad.
/// The same rules decide for every team; the style only shifts weights.
enum TeamStyle {
  /// No preference.
  balanced('All-round'),

  /// Built around the sprinters: controls flat stages, values races with
  /// many of them.
  sprint('Sprint'),

  /// Built around the general classification: makes mountain stages hard,
  /// values stage races.
  gc('General classification'),

  /// Built for the classics: makes one-day races hard, values cobbles and
  /// hills.
  classics('Classics'),

  /// Builds on young riders and develops them.
  youth('Youth'),

  /// Builds on experienced riders.
  experience('Experience');

  const TeamStyle(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
}

/// What the team does about the break of the day.
enum BreakPolicy {
  /// Nobody should go in the break.
  ignore,

  /// Put a rider in the break.
  join,

  /// Do not let the break go.
  chase,
}

/// A team's tactics for one stage.
class TeamPlan {
  /// Creates a plan.
  const TeamPlan({
    required this.roles,
    this.approach = Approach.wait,
    this.breakPolicy = BreakPolicy.ignore,
    this.directorSkill = 0.7,
    this.waitForLeader = false,
  });

  /// Role per rider id; whoever is missing is a domestique.
  final Map<int, Role> roles;
  final Approach approach;
  final BreakPolicy breakPolicy;

  /// Quality of the sports director, 0 to 1. Decides how well the sprint
  /// train and the pace-making work.
  final double directorSkill;

  /// In a team time trial the line waits for the leader instead of
  /// letting him go when he cannot hold the wheel.
  final bool waitForLeader;

  /// @param riderId Id of a rider.
  /// @returns His role, domestique by default.
  Role roleOf(int riderId) => roles[riderId] ?? Role.domestique;

  /// Copies the plan with a different approach or breakaway policy.
  ///
  /// @param approach New approach; null keeps the current one.
  /// @param breakPolicy New policy; null keeps the current one.
  /// @returns The new plan.
  /// @returns The plan as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'roles': {for (final e in roles.entries) '${e.key}': e.value.name},
        'approach': approach.name,
        'breakPolicy': breakPolicy.name,
        'director': directorSkill,
        if (waitForLeader) 'wait': true,
      };

  /// @param j A map written by [toJson].
  /// @returns The plan.
  static TeamPlan fromJson(Map<String, dynamic> j) => TeamPlan(
        roles: {
          for (final e in (j['roles'] as Map<String, dynamic>).entries)
            int.parse(e.key): Role.values.byName(e.value as String),
        },
        approach: Approach.values.byName(j['approach'] as String),
        breakPolicy: BreakPolicy.values.byName(j['breakPolicy'] as String),
        directorSkill: (j['director'] as num?)?.toDouble() ?? 0.7,
        waitForLeader: j['wait'] as bool? ?? false,
      );

  TeamPlan copyWith(
          {Approach? approach,
          BreakPolicy? breakPolicy,
          bool? waitForLeader}) =>
      TeamPlan(
        roles: roles,
        approach: approach ?? this.approach,
        breakPolicy: breakPolicy ?? this.breakPolicy,
        directorSkill: directorSkill,
        waitForLeader: waitForLeader ?? this.waitForLeader,
      );

  /// The same plan with a different sports director.
  ///
  /// @param skill Quality of the director, 0 to 1.
  /// @returns The new plan.
  TeamPlan withDirector(double skill) => TeamPlan(
        roles: roles,
        approach: approach,
        breakPolicy: breakPolicy,
        directorSkill: skill,
        waitForLeader: waitForLeader,
      );
}

/// What the player pins down for a race: roles of single riders and, if he
/// wants, the approach and the breakaway policy. Everything he leaves open
/// the sports director decides anew for every stage.
class PlanWish {
  /// Creates a wish.
  const PlanWish({this.roles = const {}, this.approach, this.breakPolicy});

  /// Pinned role per rider id.
  final Map<int, Role> roles;

  /// Pinned approach, or null to leave it to the sports director.
  final Approach? approach;

  /// Pinned breakaway policy, or null to leave it to the sports director.
  final BreakPolicy? breakPolicy;

  /// Whether nothing is pinned.
  bool get isEmpty => roles.isEmpty && approach == null && breakPolicy == null;

  /// Lays the wishes over the plan the sports director drew up for a stage.
  ///
  /// A pinned sprinter is a protected rider on a stage that does not end in
  /// a sprint, and a pinned lead-out man an ordinary helper. If the player
  /// pins a leader or a sprinter, the rider the director had in that place
  /// becomes co-leader or lead-out man.
  ///
  /// @param auto The director's plan for the stage.
  /// @param route The stage.
  /// @param present Ids of the team's riders still in the race.
  /// @returns The plan the team rides with.
  TeamPlan applyTo(TeamPlan auto, SimRoute route, Set<int> present) {
    final out = {...auto.roles};
    for (final e in roles.entries) {
      if (!present.contains(e.key)) continue;
      var role = e.value;
      if (!route.sprintStage && route.kind == StageKind.road) {
        if (role == Role.sprinter) role = Role.protected;
        if (role == Role.leadOut) role = Role.domestique;
      }
      out[e.key] = role;
    }
    for (final unique in [Role.leader, Role.sprinter]) {
      final pinned = out.entries
          .where((e) => e.value == unique && roles.containsKey(e.key))
          .isNotEmpty;
      if (!pinned) continue;
      for (final id in out.keys.toList()) {
        if (out[id] == unique && !roles.containsKey(id)) {
          out[id] = unique == Role.leader ? Role.coLeader : Role.leadOut;
        }
      }
    }
    return TeamPlan(
      roles: out,
      approach: approach ?? auto.approach,
      breakPolicy: breakPolicy ?? auto.breakPolicy,
      directorSkill: auto.directorSkill,
    );
  }

  /// @returns The wish as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'roles': {for (final e in roles.entries) '${e.key}': e.value.name},
        if (approach != null) 'approach': approach!.name,
        if (breakPolicy != null) 'breakPolicy': breakPolicy!.name,
      };

  /// @param j A map written by [toJson].
  /// @returns The wish.
  static PlanWish fromJson(Map<String, dynamic> j) => PlanWish(
        roles: {
          for (final e in (j['roles'] as Map<String, dynamic>).entries)
            int.parse(e.key): Role.values.byName(e.value as String),
        },
        approach: j['approach'] == null
            ? null
            : Approach.values.byName(j['approach'] as String),
        breakPolicy: j['breakPolicy'] == null
            ? null
            : BreakPolicy.values.byName(j['breakPolicy'] as String),
      );
}

/// Plans for all teams as a sensible sports director would draw them up
/// without instructions. The player later replaces his own team's plan.
///
/// @param route The stage.
/// @param riders Start list.
/// @param gcGaps Gaps in the general classification before the stage. With
///   them, strong riders who no longer matter overall become stage hunters
///   on hard days.
/// @param styles Style of each team; teams without one race balanced.
/// @param crosswindKm Kilometres of open road in a strong crosswind, as
///   the team cars know it from the forecast.
/// @param mountainLeaders Riders who lead or are close to the lead of the
///   mountains classification.
/// @returns One plan per team id.
Map<int, TeamPlan> autoPlans(SimRoute route, List<SimRider> riders,
    {Map<int, double> gcGaps = const {},
    Map<int, TeamStyle> styles = const {},
    double crosswindKm = 0,
    Set<int> mountainLeaders = const {}}) {
  final teams = <int, List<SimRider>>{};
  for (final r in riders) {
    teams.putIfAbsent(r.teamId, () => []).add(r);
  }

  /// @param r A rider.
  /// @returns His suitability for the route.
  double fit(SimRider r) => suitability(route, r.attributes);
  for (final members in teams.values) {
    members.sort((a, b) => fit(b).compareTo(fit(a)));
  }
  // Rank of each team's best rider among all teams.
  final byStrength = teams.keys.toList()
    ..sort((a, b) => fit(teams[b]!.first).compareTo(fit(teams[a]!.first)));
  final rank = {
    for (var i = 0; i < byStrength.length; i++) byStrength[i]: i,
  };

  // Teams by the strength of their four best riders on the flat, for the
  // crosswind.
  double flat(int team) {
    final values = [for (final r in teams[team]!) r.attributes.flat]
      ..sort((a, b) => b.compareTo(a));
    return values.take(4).fold(0.0, (s, v) => s + v);
  }

  final flatStrength = teams.keys.toList()
    ..sort((a, b) => flat(b).compareTo(flat(a)));

  // A stage hunter must be strong enough: at least as good as the 40th best rider.
  final allFits = [for (final r in riders) fit(r)]
    ..sort((a, b) => b.compareTo(a));
  final hunterLevel = allFits.length > 40 ? allFits[40] : null;

  // Whether the route has climbs worth a climbing domestique: at least
  // 500 m of height on climbs of two kilometres or more.
  var climbed = 0.0;
  for (final s in route.segments) {
    if (s.climbKm >= 2 && s.grade > 0.03) climbed += s.grade * s.lengthM;
  }
  final climbing = climbed >= 500;

  final plans = <int, TeamPlan>{};
  for (final entry in teams.entries) {
    final members = entry.value;
    final roles = <int, Role>{};
    if (route.kind != StageKind.road) {
      for (final r in members) {
        roles[r.id] = Role.freeRole;
      }
      plans[entry.key] = TeamPlan(roles: roles);
      continue;
    }
    final rest = [...members];
    SimRider? take(double Function(SimRider) score, {double atLeast = 0}) {
      if (rest.isEmpty) return null;
      rest.sort((a, b) => score(b).compareTo(score(a)));
      if (score(rest.first) < atLeast) return null;
      return rest.removeAt(0);
    }

    final leader = take(fit)!;
    roles[leader.id] = route.sprintStage ? Role.sprinter : Role.leader;
    if (route.sprintStage) {
      for (var i = 0; i < 2; i++) {
        final r = take((r) =>
            0.5 * r.attributes.sprint +
            0.3 * r.attributes.acceleration +
            0.2 * r.attributes.flat);
        if (r != null) roles[r.id] = Role.leadOut;
      }
    } else {
      final second = take(fit, atLeast: fit(leader) - 1.5);
      if (second != null) roles[second.id] = Role.coLeader;
      // Climbing domestiques only where there is something to climb; on a
      // day of cobbles or open roads the helpers are rouleurs, on cobbles
      // the best on the stones.
      for (var i = 0; i < 2; i++) {
        final r = climbing
            ? take(fit)
            : take((r) => route.sectorRace
                ? 0.6 * r.attributes.cobble + 0.4 * r.attributes.flat
                : r.attributes.flat);
        if (r != null) {
          roles[r.id] = climbing ? Role.climbDomestique : Role.tempo;
        }
      }
    }
    for (var i = 0; i < 2; i++) {
      final r = take((r) => route.sectorRace
          ? 0.6 * r.attributes.cobble + 0.4 * r.attributes.flat
          : r.attributes.flat);
      if (r != null) roles[r.id] = Role.tempo;
    }
    if (!route.sprintStage && gcGaps.isNotEmpty && hunterLevel != null) {
      for (var i = 0; i < 2; i++) {
        rest.sort((a, b) => fit(b).compareTo(fit(a)));
        final at = rest.indexWhere(
            (r) => (gcGaps[r.id] ?? 0) > 600 && fit(r) >= hunterLevel);
        if (at < 0) break;
        roles[rest.removeAt(at).id] = Role.stageHunter;
      }
    }
    final style = styles[entry.key] ?? TeamStyle.balanced;
    final place = rank[entry.key]!;
    // In a stage race a team without a leader for the overall goes for the
    // mountains jersey on the hard days: with the rider who is already in
    // the running, or with its best climber among the breakaway riders.
    final jerseyDay = gcGaps.isNotEmpty &&
        !route.sprintStage &&
        route.selectivity > 1200 &&
        (place >= 6 || rest.any((r) => mountainLeaders.contains(r.id)));
    final hunter = jerseyDay
        ? take(
            (r) =>
                (mountainLeaders.contains(r.id) ? 30 : 0) +
                0.6 * r.attributes.breakaway +
                0.4 * r.attributes.mountain,
            atLeast: 66)
        : take((r) => r.attributes.breakaway, atLeast: 70);
    if (hunter != null) {
      roles[hunter.id] = jerseyDay ? Role.mountainHunter : Role.breakaway;
    }

    // The style shifts how far down the order a team still takes on the
    // race: a sprint team controls flat stages, a team built for the
    // overall makes the mountains hard, a classics team the hilly days.
    final hard = route.selectivity > 1500;
    final hilly = !route.sprintStage && !hard && route.selectivity > 600;
    final makesHard = hard
        ? place < (style == TeamStyle.gc ? 2 : 1)
        : hilly && style == TeamStyle.classics && place < 3;
    final controls =
        place < (route.sprintStage ? (style == TeamStyle.sprint ? 7 : 5) : 3);
    // A strong crosswind: the teams with the strongest rouleurs split the
    // field rather than wait for it.
    final flatRank = flatStrength.indexOf(entry.key);
    final echelons = crosswindKm >= 8 &&
        !hard &&
        flatRank >= 0 &&
        flatRank <
            (style == TeamStyle.classics || style == TeamStyle.sprint ? 3 : 2);
    final approach = makesHard
        ? Approach.makeHard
        : echelons
            ? Approach.echelon
            : controls
                ? Approach.control
                : Approach.wait;
    plans[entry.key] = TeamPlan(
      roles: roles,
      approach: approach,
      // Whoever rides for the win stays in the field; the others try their luck up front.
      breakPolicy: approach != Approach.wait
          ? BreakPolicy.chase
          : place >= 8
              ? BreakPolicy.join
              : BreakPolicy.ignore,
    );
  }
  return plans;
}
