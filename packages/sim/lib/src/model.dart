import 'trace.dart';

/// Rider attributes on the PCM scale (roughly 50 to 85).
class Attributes {
  /// Creates a set of attributes; every value is required.
  const Attributes({
    required this.flat,
    required this.mountain,
    required this.mediumMountain,
    required this.hill,
    required this.timeTrial,
    required this.prologue,
    required this.cobble,
    required this.sprint,
    required this.acceleration,
    required this.downhill,
    required this.endurance,
    required this.resistance,
    required this.recovery,
    required this.breakaway,
  });

  final double flat;
  final double mountain;
  final double mediumMountain;
  final double hill;
  final double timeTrial;
  final double prologue;
  final double cobble;
  final double sprint;
  final double acceleration;
  final double downhill;
  final double endurance;
  final double resistance;
  final double recovery;
  final double breakaway;

  /// Derives new attributes.
  ///
  /// @param change Receives the name and old value of each attribute and
  ///   returns the new value.
  /// @returns A copy with the changed values.
  Attributes adjusted(double Function(String name, double value) change) =>
      Attributes(
        flat: change('flat', flat),
        mountain: change('mountain', mountain),
        mediumMountain: change('mediumMountain', mediumMountain),
        hill: change('hill', hill),
        timeTrial: change('timeTrial', timeTrial),
        prologue: change('prologue', prologue),
        cobble: change('cobble', cobble),
        sprint: change('sprint', sprint),
        acceleration: change('acceleration', acceleration),
        downhill: change('downhill', downhill),
        endurance: change('endurance', endurance),
        resistance: change('resistance', resistance),
        recovery: change('recovery', recovery),
        breakaway: change('breakaway', breakaway),
      );
}

/// A rider as the simulation sees him: identity, team and attributes.
class SimRider {
  /// Creates a rider.
  const SimRider({
    required this.id,
    required this.name,
    required this.teamId,
    required this.team,
    required this.attributes,
    this.born = 0,
    this.potential = 4,
    this.country = '',
    this.contractEnd = 0,
  });

  final int id;
  final String name;

  /// The name without the leading initial, for sorting.
  String get lastName => name.replaceFirst(RegExp(r'^\S+\.\s+'), '');
  final int teamId;

  /// Team abbreviation for output.
  final String team;
  final Attributes attributes;

  /// Date of birth as YYYYMMDD, 0 if unknown.
  final int born;

  /// Development potential from the WorldDB, roughly 2.5 to 6.
  final double potential;

  /// Country code, e.g. `GER`.
  final String country;

  /// Last contract year according to the WorldDB, 0 if unknown.
  final int contractEnd;

  /// The same rider with different attributes.
  ///
  /// @param a New attributes.
  /// @returns A copy of the rider.
  SimRider withAttributes(Attributes a) => SimRider(
        id: id,
        name: name,
        teamId: teamId,
        team: team,
        attributes: a,
        born: born,
        potential: potential,
        country: country,
        contractEnd: contractEnd,
      );

  /// The same rider at another team.
  ///
  /// @param newTeamId Id of the new team.
  /// @param newTeam Abbreviation of the new team.
  /// @returns A copy of the rider.
  SimRider withTeam(int newTeamId, String newTeam) => SimRider(
        id: id,
        name: name,
        teamId: newTeamId,
        team: newTeam,
        attributes: attributes,
        born: born,
        potential: potential,
        country: country,
        contractEnd: contractEnd,
      );
}

/// Piece of road of fixed length on which the simulation advances one step.
class Segment {
  /// Creates a segment.
  Segment({
    required this.km,
    required this.lengthM,
    required this.grade,
    this.cobble = 0,
    this.unpaved = 0,
    this.climbKm = 0,
  });

  /// Race kilometre at the start of the segment.
  final double km;
  final double lengthM;

  /// Gradient as a fraction (0.07 = 7 %).
  final double grade;

  /// Difficulty of the cobblestones, 0 = tarmac.
  int cobble;

  /// Difficulty of an unpaved section, 0 = tarmac.
  int unpaved;

  /// Length of the climb the segment belongs to, 0 outside of climbs.
  double climbKm;
}

/// Kind of stage: road race, individual or team time trial.
enum StageKind { road, timeTrial, teamTimeTrial }

/// A mountain prize or intermediate sprint on the route.
class RoutePoint {
  const RoutePoint(this.km, this.name, this.category);
  final double km;
  final String name;

  /// For mountain prizes 1 = HC … 5 = fourth category, for sprints 0.
  final int category;
}

/// A stage as the simulation needs it: segments plus classification points.
class SimRoute {
  /// Creates a route.
  SimRoute({
    required this.name,
    required this.kind,
    required this.raceKm,
    required this.segments,
    required this.climbTops,
    required this.sprints,
    this.startAltitudeM = 0,
  });

  final String name;
  final StageKind kind;
  final double raceKm;
  final List<Segment> segments;
  final List<RoutePoint> climbTops;
  final List<RoutePoint> sprints;

  /// Altitude at the start in metres, only used to draw the profile.
  final double startAltitudeM;

  /// Whether the stage is expected to end in a bunch sprint.
  bool get sprintStage => selectivity < 600 && finishGrade < 0.03;

  /// Mean gradient of the last 1.5 km.
  double get finishGrade {
    var rise = 0.0, length = 0.0;
    for (final s in segments.reversed) {
      rise += s.grade * s.lengthM;
      length += s.lengthM;
      if (length >= 1500) break;
    }
    return length == 0 ? 0 : rise / length;
  }

  /// Metres of climbing above 3 % gradient plus a surcharge for cobbles.
  /// A rough measure of how much the route pulls the field apart.
  double get selectivity {
    var sum = 0.0;
    for (final s in segments) {
      if (s.grade > 0.03) sum += (s.grade - 0.03) * s.lengthM;
      sum += s.cobble * s.lengthM * 0.004;
    }
    return sum;
  }
}

/// One rider's finishing time and group.
class Placing {
  Placing(this.rider, this.timeS, this.group);
  final SimRider rider;
  final double timeS;

  /// Number of the group at the finish, 0 = first group.
  final int group;
}

/// Order of riders at a mountain prize or intermediate sprint.
class PointAward {
  PointAward(this.point, this.order);
  final RoutePoint point;

  /// The first riders across, best first.
  final List<SimRider> order;
}

/// Moments at which the sports director can step in over the radio. Each
/// occurs at most once per stage.
enum RadioKind { breakGone, finale, rivalAttack }

/// A question from the race to the sports director.
class RadioCall {
  RadioCall(this.kind, this.km, this.remainingKm, this.text, this.options);
  final RadioKind kind;
  final double km;
  final double remainingKm;

  /// The situation as seen from the team car.
  final String text;

  /// Possible instructions; the first always means: stick to the plan.
  final List<String> options;
}

/// Kind of a race event, used for reports.
enum EventType {
  breakaway,
  maxGap,
  caught,
  attack,
  dropped,
  points,
  finish,
  gruppetto
}

/// Something that happened during the stage, with the kilometre it happened at.
class RaceEvent {
  RaceEvent(this.km, this.type, this.text);
  final double km;
  final EventType type;
  final String text;
}

/// Outcome of a stage or one-day race.
class StageResult {
  StageResult(this.placings, this.events, this.breakSurvived,
      [this.awards = const []]);

  /// Sorted by finishing time.
  final List<Placing> placings;
  final List<RaceEvent> events;

  /// Mountain prizes and sprints along the way, in route order.
  final List<PointAward> awards;

  /// true if a rider from the early breakaway won.
  final bool breakSurvived;

  /// Open question: the stage was paused at this point and has not been
  /// simulated to the end ([placings] is empty in that case).
  RadioCall? openCall;

  /// Course of the race in samples along the route; empty for time trials
  /// and for results stored before this was recorded.
  List<RaceSample> timeline = const [];

  /// What each rider did, by rider id; empty like [timeline].
  Map<int, RiderTrace> traces = const {};

  /// Finishing time of the winner in seconds.
  double get winnerTimeS => placings.first.timeS;
}
