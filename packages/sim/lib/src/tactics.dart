import 'model.dart';
import 'stage_sim.dart' show suitability;

/// A rider's job in the race.
enum Role {
  /// Rides for the team's main goal and is protected.
  leader('Kapitän'),

  /// Second card; may follow moves and attack himself.
  coLeader('Co-Kapitän'),

  /// Protected, but without a goal of his own.
  protected('Geschützter Fahrer'),

  /// Should make the break of the day and ride for the stage win.
  stageHunter('Etappenjäger'),
  sprinter('Sprinter'),

  /// Last men in front of the sprinter.
  leadOut('Anfahrer'),

  /// Sets the pace on climbs for the leader.
  climbDomestique('Berghelfer'),

  /// Controls the field on the flat and brings groups back.
  tempo('Tempomacher'),

  /// Should make the break as a relay for the leader.
  breakaway('Ausreißer'),
  domestique('Wasserträger'),

  /// Decides for himself as the race unfolds.
  freeRole('Freie Rolle');

  const Role(this.label);
  final String label;

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
  });

  /// Role per rider id; whoever is missing is a domestique.
  final Map<int, Role> roles;
  final Approach approach;
  final BreakPolicy breakPolicy;

  /// Quality of the sports director, 0 to 1. Decides how well the sprint
  /// train and the pace-making work.
  final double directorSkill;

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
      );

  TeamPlan copyWith({Approach? approach, BreakPolicy? breakPolicy}) => TeamPlan(
        roles: roles,
        approach: approach ?? this.approach,
        breakPolicy: breakPolicy ?? this.breakPolicy,
        directorSkill: directorSkill,
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
/// @returns One plan per team id.
Map<int, TeamPlan> autoPlans(SimRoute route, List<SimRider> riders,
    {Map<int, double> gcGaps = const {}}) {
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

  // A stage hunter must be strong enough: at least as good as the 40th best rider.
  final allFits = [for (final r in riders) fit(r)]
    ..sort((a, b) => b.compareTo(a));
  final hunterLevel = allFits.length > 40 ? allFits[40] : null;

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
      for (var i = 0; i < 2; i++) {
        final r = take(fit);
        if (r != null) roles[r.id] = Role.climbDomestique;
      }
    }
    for (var i = 0; i < 2; i++) {
      final r = take((r) => r.attributes.flat);
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
    final hunter = take((r) => r.attributes.breakaway, atLeast: 70);
    if (hunter != null) roles[hunter.id] = Role.breakaway;

    final place = rank[entry.key]!;
    final approach = place == 0 && route.selectivity > 1500
        ? Approach.makeHard
        : place < (route.sprintStage ? 5 : 3)
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
