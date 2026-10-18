import 'trace.dart';
import 'weather.dart';

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
    this.weightKg = 0,
    this.heightCm = 0,
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

  /// Body weight in kg from the WorldDB, 0 if unknown.
  final double weightKg;

  /// Height in cm from the WorldDB, 0 if unknown.
  final double heightCm;

  /// Body weight the physics works with; 70 kg if unknown or implausible.
  double get massKg => weightKg >= 45 && weightKg <= 100 ? weightKg : 70;

  /// Height the physics works with; 1.80 m if unknown or implausible.
  double get heightM =>
      heightCm >= 150 && heightCm <= 210 ? heightCm / 100 : 1.8;

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
        weightKg: weightKg,
        heightCm: heightCm,
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
        weightKg: weightKg,
        heightCm: heightCm,
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
    this.altitudeM = 0,
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

  /// Difficulty of the surface whatever its kind, 0 = tarmac. Cobbles and
  /// unpaved roads share one scale here; their rolling resistance differs.
  int get rough => cobble > 0 ? cobble : unpaved;

  /// Altitude in the middle of the segment in metres.
  final double altitudeM;
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
  late final bool sprintStage =
      !sectorRace && selectivity < 600 && finishGrade < 0.03;

  /// Kilometres of cobbles and unpaved road, each weighted with its
  /// difficulty (unpaved counts 60 %).
  late final double sectorLoad = () {
    var sum = 0.0;
    for (final s in segments) {
      sum += (s.cobble + 0.6 * s.unpaved) * s.lengthM / 1000;
    }
    return sum;
  }();

  /// Whether the sectors decide the race: a cobbled classic, a gravel race
  /// or a stage over many sectors. Such races are simulated with the sector
  /// model (the group as a line, splits by position, wear from the surface).
  late final bool sectorRace = kind == StageKind.road && sectorLoad >= 25;

  /// Mean gradient of the last 1.5 km.
  late final double finishGrade = () {
    var rise = 0.0, length = 0.0;
    for (final s in segments.reversed) {
      rise += s.grade * s.lengthM;
      length += s.lengthM;
      if (length >= 1500) break;
    }
    return length == 0 ? 0.0 : rise / length;
  }();

  /// Metres of climbing above 3 % gradient plus a surcharge for cobbles.
  /// A rough measure of how much the route pulls the field apart. The
  /// gradient is taken over pieces of about 500 m, so that the measure does
  /// not depend on the segment length.
  late final double selectivity = () {
    var sum = 0.0, rise = 0.0, length = 0.0;
    for (final s in segments) {
      rise += s.grade * s.lengthM;
      length += s.lengthM;
      if (length >= 499) {
        final grade = rise / length;
        if (grade > 0.03) sum += (grade - 0.03) * length;
        rise = 0;
        length = 0;
      }
      sum += s.cobble * s.lengthM * 0.004;
    }
    if (length > 0 && rise / length > 0.03) sum += rise - 0.03 * length;
    return sum;
  }();
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
enum RadioKind { breakGone, finale, rivalAttack, mishap }

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

  /// What the sports director would do himself. This is what happens when
  /// the question is not answered, and what every other team does in the
  /// same situation.
  int suggested = 0;
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
  gruppetto,
  // Added in 0.3.0; the index is stored in saves, so new values go last.
  weather,
  crash,
  puncture,
  echelon,
  abandon,
  timeCut,
}

/// Why a rider left the race.
enum AbandonReason { crash, illness, timeCut }

/// A rider who did not finish a stage, or was taken out of the race after it.
class Abandon {
  Abandon(this.rider, this.km, this.reason, [this.days = 0]);
  final SimRider rider;

  /// Race kilometre at which he stopped.
  final double km;
  final AbandonReason reason;

  /// Days he is out after a crash or illness, 0 for the time limit.
  final int days;
}

/// A rider who crashed and carries on, hurt.
class Injury {
  Injury(this.formLoss, this.energyLoss);

  /// Share of power he loses in the next days.
  final double formLoss;

  /// Share of the endurance reserve the crash cost him.
  final double energyLoss;
}

/// Something that happened during the stage, with the kilometre it happened at.
class RaceEvent {
  RaceEvent(this.km, this.type, this.text, [this.riders = const []]);
  final double km;
  final EventType type;
  final String text;

  /// Ids of the riders it is about, for the 3D viewer: who went clear,
  /// attacked (the attacker first), crashed, punctured or abandoned. Empty
  /// for events about nobody in particular.
  final List<int> riders;
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

  /// Power figures per rider id. The game keeps them only for the riders
  /// it shows.
  Map<int, PowerStats> power = {};

  /// Riders who did not finish; they have no placing.
  List<Abandon> abandons = const [];

  /// Riders who crashed and finished hurt, by rider id.
  Map<int, Injury> injuries = const {};

  /// Weather of the day; null for results stored before it was simulated.
  Weather? weather;

  /// Where every rider was along the route, for the 3D view; null unless
  /// asked for, and never saved.
  RaceTrack? track;

  /// Finishing time of the winner in seconds.
  double get winnerTimeS => placings.first.timeS;
}
