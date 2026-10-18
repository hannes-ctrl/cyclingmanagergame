import 'dart:typed_data';

import 'tactics.dart';

/// Where every rider was during a stage, for the 3D view: for the end of
/// every segment the time each rider passed it and his place in his group.
/// It is only recorded for the races the game shows, and never saved.
class RaceTrack {
  /// @param km Race kilometre at the end of each segment.
  /// @param riders Ids of the riders at the start.
  RaceTrack(this.km, Iterable<int> riders)
      : times = {
          for (final id in riders)
            id: Float32List(km.length)..fillRange(0, km.length, double.nan),
        },
        ranks = {for (final id in riders) id: Uint8List(km.length)};

  /// Race kilometre at the end of each segment.
  final List<double> km;

  /// Per rider id: seconds after his start at which he passed each point;
  /// NaN where he did not, because he had left the race or the stage was
  /// paused before.
  final Map<int, Float32List> times;

  /// Per rider id: his place within his group at each point, 0 at the
  /// front.
  final Map<int, Uint8List> ranks;

  /// Per rider id: seconds after the first start at which he set off; empty
  /// in a road race, where everybody starts together.
  final Map<int, double> starts = {};

  /// Direction of the road per segment in radians, as the simulation laid
  /// the wind over it; empty on a day without wind.
  List<double> heading = const [];

  /// Points recorded so far, from the start.
  int length = 0;

  /// Records a rider passing a point.
  ///
  /// @param point Index of the point.
  /// @param riderId Id of the rider.
  /// @param timeS Seconds after his start; never earlier than at the point
  ///   before.
  /// @param rank His place in his group, 0 at the front.
  void pass(int point, int riderId, double timeS, int rank) {
    final t = times[riderId];
    if (t == null) return;
    // A group that catches the one ahead takes over its clock, which puts
    // the chasers a few seconds back in time; on the screen they close the
    // rest of the gap over the next segment instead.
    final before = point > 0 ? t[point - 1] : double.nan;
    t[point] = before.isNaN || timeS > before ? timeS : before + 0.5;
    ranks[riderId]![point] = rank.clamp(0, 255);
    if (point >= length) length = point + 1;
  }
}

/// State of the race at one kilometre, for the chart of the race report.
class RaceSample {
  RaceSample(
      this.km, this.frontGapS, this.frontSize, this.mainSize, this.lastGapS,
      [this.groups = const []]);

  /// Every group on the road, head of the race first, for the stage in fast
  /// motion. Kept only for the races the game shows that way.
  List<GroupSample> groups;

  /// Race kilometre.
  final double km;

  /// Seconds the head of the race is ahead of the favourites' group; 0 if
  /// the favourites lead.
  final double frontGapS;

  /// Riders at the head of the race.
  final int frontSize;

  /// Riders in the favourites' group.
  final int mainSize;

  /// Seconds the rider in the middle of the field is behind the favourites;
  /// 0 while he rides with them or ahead of them.
  final double lastGapS;

  /// @returns The sample as a compact list.
  List<Object> toJson() => [
        km,
        frontGapS,
        frontSize,
        mainSize,
        lastGapS,
        if (groups.isNotEmpty) [for (final g in groups) g.toJson()],
      ];

  /// @param j A list written by [toJson].
  /// @returns The sample.
  static RaceSample fromJson(List<dynamic> j) => RaceSample(
      (j[0] as num).toDouble(),
      (j[1] as num).toDouble(),
      j[2] as int,
      j[3] as int,
      (j[4] as num).toDouble(),
      j.length > 5
          ? [for (final g in j[5] as List) GroupSample.fromJson(g as List)]
          : []);
}

/// What one rider did during a stage, for the race report.
class RiderTrace {
  RiderTrace(this.role, this.inBreak, this.lostKm, this.frontKm, this.energy,
      this.gruppetto,
      [this.incident = RiderIncident.none]);

  /// His role in the team's plan.
  final Role role;

  /// Whether he was in the break of the day.
  final bool inBreak;

  /// Kilometre at which he lost contact with the favourites' group for good;
  /// null if he finished in it or ahead of it.
  final double? lostKm;

  /// Kilometres he spent setting the pace.
  final double frontKm;

  /// Endurance reserve left at the finish, 0 to 1.
  final double energy;

  /// Whether he finished in the gruppetto.
  final bool gruppetto;

  /// Worst mishap of his day.
  final RiderIncident incident;

  /// @returns The trace as a compact list.
  List<Object?> toJson() =>
      [role.index, inBreak, lostKm, frontKm, energy, gruppetto, incident.index];

  /// @param j A list written by [toJson].
  /// @returns The trace.
  static RiderTrace fromJson(List<dynamic> j) => RiderTrace(
      Role.values[j[0] as int],
      j[1] as bool,
      (j[2] as num?)?.toDouble(),
      (j[3] as num).toDouble(),
      (j[4] as num).toDouble(),
      j[5] as bool,
      j.length > 6 ? RiderIncident.values[j[6] as int] : RiderIncident.none);
}

/// Mishaps a rider can have during a stage, mildest first.
enum RiderIncident { none, puncture, crash }

/// What a rider's power meter would have shown after a stage.
class PowerStats {
  PowerStats(this.seconds, this.averageW, this.normalizedW, this.kilojoules,
      this.ftpW, this.massKg, this.zones, this.climbs);

  /// Riding time in seconds.
  final double seconds;

  /// Average power in watts.
  final double averageW;

  /// Normalised power in watts: weighs hard efforts as the body feels them.
  final double normalizedW;

  /// Work done in kilojoules.
  final double kilojoules;

  /// Threshold power at the start of the stage, in watts.
  final double ftpW;

  /// Body weight in kg.
  final double massKg;

  /// Seconds in the six power zones, relative to the threshold: below
  /// 55 %, 55–75 %, 75–90 %, 90–105 %, 105–120 % and above 120 %.
  final List<double> zones;

  /// Power on each categorised climb, in the order of the route.
  final List<ClimbPower> climbs;

  /// Average power per kg of body weight.
  double get averageWkg => averageW / massKg;

  /// Normalised power relative to the threshold.
  double get intensity => ftpW <= 0 ? 0 : normalizedW / ftpW;

  /// @returns The figures as a compact list.
  List<Object> toJson() => [
        seconds.round(),
        averageW.round(),
        normalizedW.round(),
        kilojoules.round(),
        ftpW.round(),
        massKg,
        [for (final z in zones) z.round()],
        [for (final c in climbs) c.toJson()],
      ];

  /// @param j A list written by [toJson].
  /// @returns The figures.
  static PowerStats fromJson(List<dynamic> j) => PowerStats(
        (j[0] as num).toDouble(),
        (j[1] as num).toDouble(),
        (j[2] as num).toDouble(),
        (j[3] as num).toDouble(),
        (j[4] as num).toDouble(),
        (j[5] as num).toDouble(),
        [for (final z in j[6] as List) (z as num).toDouble()],
        [for (final c in j[7] as List) ClimbPower.fromJson(c as List)],
      );
}

/// A rider's effort on one climb.
class ClimbPower {
  ClimbPower(this.name, this.topKm, this.category, this.seconds, this.averageW,
      this.gainM, this.massKg);

  /// Name of the climb.
  final String name;

  /// Race kilometre of the top.
  final double topKm;

  /// Category, 1 for hors catégorie up to 5 for the fourth.
  final int category;

  /// Seconds from the foot to the top.
  final double seconds;

  /// Average power in watts.
  final double averageW;

  /// Metres climbed.
  final double gainM;

  /// Body weight in kg.
  final double massKg;

  /// Average power per kg of body weight.
  double get averageWkg => averageW / massKg;

  /// Metres climbed per hour.
  double get vam => seconds <= 0 ? 0 : gainM / seconds * 3600;

  /// @returns The figures as a compact list.
  List<Object> toJson() => [
        name,
        topKm,
        category,
        seconds.round(),
        averageW.round(),
        gainM.round(),
        massKg,
      ];

  /// @param j A list written by [toJson].
  /// @returns The figures.
  static ClimbPower fromJson(List<dynamic> j) => ClimbPower(
        j[0] as String,
        (j[1] as num).toDouble(),
        j[2] as int,
        (j[3] as num).toDouble(),
        (j[4] as num).toDouble(),
        (j[5] as num).toDouble(),
        (j[6] as num).toDouble(),
      );
}

/// One group on the road at a moment of the stage.
class GroupSample {
  GroupSample(this.gapS, this.size, this.favourites, this.watched,
      {this.breakaway = false, this.gruppetto = false, this.stars = const []});

  /// Seconds behind the head of the race.
  final double gapS;

  /// Riders in the group.
  final int size;

  /// Favourites of the day in it.
  final int favourites;

  /// Ids of the riders of the watched team in it.
  final List<int> watched;

  /// Ids of the favourites of the day in it, for the stage watched live.
  final List<int> stars;

  /// Whether it is (part of) the break of the day.
  final bool breakaway;

  /// Whether it rides as a gruppetto.
  final bool gruppetto;

  /// @returns The group as a compact list.
  List<Object> toJson() => [
        gapS.round(),
        size,
        favourites,
        watched,
        (breakaway ? 1 : 0) + (gruppetto ? 2 : 0),
        stars,
      ];

  /// @param j A list written by [toJson].
  /// @returns The group.
  static GroupSample fromJson(List<dynamic> j) => GroupSample(
        (j[0] as num).toDouble(),
        j[1] as int,
        j[2] as int,
        (j[3] as List).cast<int>(),
        breakaway: (j[4] as int) & 1 != 0,
        gruppetto: (j[4] as int) & 2 != 0,
        stars: j.length > 5 ? (j[5] as List).cast<int>() : const [],
      );
}
