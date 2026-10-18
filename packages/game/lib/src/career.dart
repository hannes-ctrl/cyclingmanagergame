import 'dart:isolate';
import 'dart:math';

import 'package:sim/sim.dart';

import 'camp.dart';
import 'devteam.dart';
import 'economy.dart';
import 'entries.dart';
import 'equipment.dart';
import 'facilities.dart';
import 'finances.dart';
import 'licence.dart';
import 'manager.dart';
import 'people.dart';
import 'planning.dart';
import 'points.dart';
import 'staff.dart';
import 'templates.dart';
import 'weather_forecast.dart';

/// A race in the season's calendar.
class RaceEntry {
  RaceEntry(this.info, this.stages, this.tier, this.start, this.end);
  final RaceInfo info;
  final List<StageInfo> stages;
  final RaceTier tier;
  final DateTime start;
  final DateTime end;

  /// Whether the race has more than one stage.
  bool get isStageRace => stages.length > 1;
}

/// A running or finished race with its field and results.
class RaceProgress {
  RaceProgress(
      this.race, this.riders, this.run, this.directorSkills, this.ownDirector);
  final RaceEntry race;
  final List<SimRider> riders;
  final StageRaceRun run;

  /// Quality of the sports director per team, 0 to 1.
  final Map<int, double> directorSkills;

  /// Who sits in the car for the player's team.
  final Staff? ownDirector;

  /// Number of stages ridden so far.
  int get stagesDone => run.results.length;

  /// Whether the last stage has been ridden.
  bool get finished => stagesDone >= race.stages.length;
}

/// A race that starts today and waits for the player's line-up. The
/// line-ups of the other teams are already fixed.
class PendingRace {
  PendingRace(this.race, this.routes, this.others, this.available,
      this.suggestedLineup, this.size, this.directors);
  final RaceEntry race;
  final List<SimRoute> routes;

  /// Riders of the other teams.
  final List<SimRider> others;

  /// Own riders who are not tied up in another race.
  final List<SimRider> available;

  /// Suggestion of the sports director.
  final List<SimRider> suggestedLineup;

  /// Maximum number of riders per team.
  final int size;

  /// Own sports directors who are free, best match first.
  final List<Staff> directors;
}

/// At which races the sports director calls in over the radio.
enum RadioMode {
  all('At every race'),
  important('Only at WorldTour races'),
  off('Never – the sports director decides');

  const RadioMode(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
}

/// What the player leaves to his staff.
class Delegation {
  /// The sports director picks the line-ups himself.
  bool lineups = false;

  /// When the sports director asks during a race instead of deciding alone.
  RadioMode radio = RadioMode.all;

  /// The coach sets load and focus for every rider.
  bool training = false;

  /// The head scout chooses whom his people watch.
  bool scouting = false;

  /// The sports director draws up the race programme of the season and
  /// replaces riders who drop out.
  bool planning = true;

  /// The board builds up the facilities when the savings allow it.
  bool facilities = false;

  /// The job market for the manager: the board may dismiss him and other
  /// teams offer him jobs. Off, he stays with his team whatever happens.
  bool jobMarket = false;

  /// @returns The settings as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'planning': planning,
        'lineups': lineups,
        'radio': radio.name,
        'training': training,
        'scouting': scouting,
        'facilities': facilities,
        'jobMarket': jobMarket,
      };

  /// @param j A map written by [toJson].
  void load(Map<String, dynamic> j) {
    lineups = j['lineups'] as bool;
    radio = RadioMode.values.byName(j['radio'] as String);
    training = j['training'] as bool;
    scouting = j['scouting'] as bool;
    planning = j['planning'] as bool? ?? true;
    facilities = j['facilities'] as bool? ?? false;
    jobMarket = j['jobMarket'] as bool? ?? false;
  }
}

/// Training focus: these attributes develop faster, the others more slowly.
enum TrainingFocus {
  balanced('General', []),
  climbing('Mountain', ['mountain', 'mediumMountain', 'hill']),
  sprint('Sprint', ['sprint', 'acceleration']),
  timeTrial('Time trial', ['timeTrial', 'prologue']),
  classics('Classics', ['cobble', 'hill', 'flat']),
  stamina('Stamina', ['endurance', 'resistance', 'recovery']);

  const TrainingFocus(this._label, this.attributes);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
  final List<String> attributes;
}

/// How hard a rider trains on days without a race.
enum TrainingLoad {
  low('Easy', 80),
  normal('Normal', 110),
  high('Hard', 135);

  const TrainingLoad(this._label, this.dailyLoad);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);

  /// Load of a training day in the same units as a race day.
  final double dailyLoad;
}

/// Physical condition of a rider over the season.
///
/// Fitness follows the load of the last six weeks, fatigue that of the last
/// week; freshness is the difference. This is the same model used to analyse
/// real training (CTL, ATL, TSB).
class RiderShape {
  // Starting values in the equilibrium of normal training.
  double fitness = 110;
  double fatigue = 110;
  int raceDays = 0;
  int grandTours = 0;
  DateTime? lastGrandTourEnd;
  TrainingLoad load = TrainingLoad.normal;
  TrainingFocus focus = TrainingFocus.balanced;

  /// Injured or ill until this day.
  DateTime? injuredUntil;

  /// Fitness minus fatigue; negative means tired.
  double get freshness => fitness - fatigue;

  /// Factor on power at the start of a race.
  double get form {
    // Normal training without racing gives 1.0; race days raise fitness and
    // with it form, once the fatigue has faded.
    final fit = 0.97 + 0.06 * ((fitness - 80) / 60).clamp(0.0, 1.0);
    final fresh = freshness >= 0
        ? 0.012 * (freshness / 20).clamp(0.0, 1.0)
        : -0.0006 * (-freshness).clamp(0.0, 65.0);
    return fit + fresh;
  }

  /// Applies one day of load to fitness and fatigue.
  ///
  /// @param load Load of the day.
  void applyDay(double load) {
    fitness += (load - fitness) / 42;
    fatigue += (load - fatigue) / 7;
  }
}

/// A message in the player's inbox.
/// A talk with a rider that waits for the player's decision, carried by a
/// message of the inbox.
class Talk {
  Talk(this.kind, this.riderId, this.choices, [this.answer]);

  /// What it is about: `leave` (he wants to leave) or `days` (too few race
  /// days).
  final String kind;
  final int riderId;

  /// The answers the player can give, in the language of the time.
  final List<String> choices;

  /// Index of the answer given, or null while it is open.
  int? answer;

  /// @returns The talk as a compact list.
  List<Object?> toJson() => [kind, riderId, choices, answer];

  /// @param j A list written by [toJson], or null.
  /// @returns The talk, or null.
  static Talk? fromJson(Object? j) => j is List
      ? Talk(j[0] as String, j[1] as int, (j[2] as List).cast<String>(),
          j[3] as int?)
      : null;
}

class Message {
  Message(this.date, this.from, this.subject, this.body,
      {this.raceId, this.talk});
  final DateTime date;
  final String from;
  final String subject;
  final String body;

  /// The topics of the inbox, as the keys of their translation.
  static const topics = [
    'Races',
    'Medical',
    'Training and youth',
    'Contracts',
    'Licence',
    'Board',
    'Staff',
    'Scouting',
  ];

  /// Topic the inbox files the message under, derived from the sender; one
  /// of [topics], whatever the language.
  String get topicKey {
    // The sender was written in the language of the time.
    bool from_(List<String> senders) => senders.any((s) => isText(from, s));
    if (from_(
        ['Race report', 'Sports director', 'Organiser', 'Season review'])) {
      return 'Races';
    }
    if (from_(['Team doctor'])) return 'Medical';
    if (from_(['Coach', 'Development team'])) return 'Training and youth';
    if (from_(['Agent'])) return 'Contracts';
    if (from_(['UCI'])) return 'Licence';
    if (from_(['Board'])) return 'Board';
    if (from_(['Staff'])) return 'Staff';
    return 'Scouting';
  }

  /// The topic in the current language.
  String get topic => topicKey == 'Scouting' ? 'Scouting' : tr(topicKey);

  /// Race the message belongs to, for the jump to the race report.
  final int? raceId;

  /// A decision the message asks for, or null.
  final Talk? talk;
  bool read = false;
}

/// Today's stage of a race, fixed as a job.
class _DayStage {
  _DayStage(this.race, this.index, this.job);
  final RaceProgress race;
  final int index;
  final StageJob job;
}

/// A stage of the player's team that can be watched live: the race, the
/// stage and the job with everything decided but the answers and orders the
/// player gives while he watches.
typedef LiveJob = ({RaceProgress race, int stageIndex, StageJob job});

/// A question of the team car: race, stage, the question, and the stage as
/// far as it has been ridden when the question comes.
typedef RadioPrompt = ({
  RaceProgress race,
  int stageIndex,
  RadioCall call,
  StageResult trial,
});

/// A day in progress: its stages and what has been ridden of them.
class _Day {
  _Day(this.date, this.inboxBefore, this.stages);
  final DateTime date;

  /// Index of the first inbox message written today.
  final int inboxBefore;
  final List<_DayStage> stages;
  final ridden = <({RaceProgress race, int stageIndex, StageResult result})>[];
}

/// What was ridden on one day.
class DayReport {
  DayReport(this.date, this.stages);
  final DateTime date;
  final List<({RaceProgress race, int stageIndex, StageResult result})> stages;
}

/// A career: calendar, daily routine, rankings and inbox.
///
/// Simplifications still in place: the other teams send their best-suited
/// free riders to every race, and the AI does not plan a season for its
/// riders beyond simple limits on race days and Grand Tours.
class Career {
  Career(
    this.world, {
    required this.teamId,
    this.year = 2026,
    this.seed = 1,
    this.custom,
    this.customRiders,
    SimTuning? tuning,
  })  : startTeam = teamId,
        tuning = tuning ?? SimTuning.standard {
    // UTC so that daylight saving time does not shift a day.
    today = DateTime.utc(year, 1, 1);
    teams = {
      for (final t in world.teams()) t.id: t,
      if (custom case final t?) t.id: t,
    };
    for (final r in world.riders()) {
      squads.putIfAbsent(r.teamId, () => []).add(r);
      riderById[r.id] = r;
    }
    for (final r in world.allRiders()) {
      fullNames[r.rider.id] = '${r.first} ${r.last}'.trim();
    }
    if (custom != null) _found();
    licences.firstYear; // fix licences and development team now
    devTeam.teamId;
    staff.all.length; // create staff now, not on first access
    equipment.supply.length;
    facilities.levels.length;
    finances.books.length;
    if (custom == null) economy.startBudget(finances.breakEven(teamId));
    _assignStyles();
    economy.openSeason();
    manager.openSeason(); // fix the reputation now, not on first access
    people.pairOthers();
    _buildCalendar();
  }

  /// Season the career started in; saved with the licences.
  int get _firstYear => licences.firstYear;

  /// European countries among the possible hosts.
  static const _hostsEurope = {
    'ITA', 'FRA', 'BEL', 'GER', 'DEN', 'POL', 'POR', 'SWD', 'CZE', 'NOR', //
    'AND', 'MCO', 'LIE', 'ESP', 'NED', 'SWI', 'GBR', 'AUT', 'SLO', 'CRO',
    'SVK', 'HUN', 'LUX', 'IRL', 'EST', 'LAT', 'LTU', 'FIN', 'GRE', 'ROM',
  };

  /// Chooses this year's host of a world or European championship. Road race
  /// and time trial of the same championship share the host.
  ///
  /// @param info The race.
  /// @returns The host with its courses, or null for every other race and
  ///   for the first season.
  ({String country, int road, String roadName, int trial, String trialName})?
      _venueOf(RaceInfo info, int year) {
    final world_ = info.raceClass.startsWith('WorldChampionship');
    final europe = info.raceClass.startsWith('EuropeanChampionship');
    if (!world_ && !europe || year == _firstYear) return null;
    final hosts = [
      for (final v in world.championshipVenues())
        if (world_ || _hostsEurope.contains(v.country)) v,
    ];
    if (hosts.isEmpty) return null;
    // The same host never twice in a row: step through a shuffled list.
    hosts.shuffle(Random(seed * 977 + (world_ ? 1 : 2)));
    return hosts[(year - _firstYear - 1) % hosts.length];
  }

  /// The routes a race uses this year. Races change their course from year
  /// to year: the first season rides the routes of the database, every later
  /// one goes through the courses of the other years the WorldDB holds for
  /// the race (2021 to 2025, where they have as many stages as now) in an
  /// order fixed per career, so that no course comes twice in a row. Dates,
  /// country and the number of stages stay those of the calendar.
  ///
  /// @param info The race.
  /// @param now Its stages as the database has them.
  /// @param year The season.
  /// @returns The stages with that year's routes.
  List<StageInfo> _routesOf(RaceInfo info, List<StageInfo> now, int year) {
    if (year == _firstYear) return now;
    final years = world.routeYears(info.id);
    final options = [
      for (final e in years.entries)
        if (e.value.length == now.length) e.key,
    ]..sort();
    if (options.isEmpty) return now;
    options.shuffle(Random(seed * 131 + info.id));
    // Null stands for the routes of the database.
    final cycle = <int?>[null, ...options];
    final pick = cycle[(year - _firstYear) % cycle.length];
    if (pick == null) return now;
    final routes = years[pick]!;
    return [
      for (final (i, s) in now.indexed)
        StageInfo(routes[i].id, s.number, routes[i].name, s.month, s.day),
    ];
  }

  /// Builds the calendar of the current year from the world database.
  void _buildCalendar() {
    calendar
      ..clear()
      ..addAll(_calendarOf(year));
    _nextCalendar = null;
  }

  /// The calendar of a season, with its routes and championship venues.
  /// It depends on the season and the seed only, so the calendar of the
  /// next season can be known in the winter before it.
  ///
  /// @param year The season.
  /// @returns Its races, by start.
  List<RaceEntry> _calendarOf(int year) {
    final calendar = <RaceEntry>[];
    for (var info in world.races()) {
      final tier = RaceTier.of(info.raceClass);
      var stages =
          world.stages(info.id).where((s) => s.name.isNotEmpty).toList();
      if (stages.isEmpty) continue;
      // World and European championships move to another country every
      // year; in the first season they are where the database has them.
      if (_venueOf(info, year) case final v?) {
        final trial = info.raceClass.endsWith('ITT');
        final s = stages.first;
        stages = [
          StageInfo(trial ? v.trial : v.road, s.number,
              trial ? v.trialName : v.roadName, s.month, s.day),
        ];
        info = RaceInfo(info.id, info.name, info.abbr, info.raceClass,
            v.country, info.stages, info.startMonth, info.startDay);
      } else {
        stages = _routesOf(info, stages, year);
      }
      final days = [for (final s in stages) DateTime.utc(year, s.month, s.day)]
        ..sort();
      calendar.add(RaceEntry(info, stages, tier, days.first, days.last));
    }
    return calendar..sort((a, b) => a.start.compareTo(b.start));
  }

  /// The calendar of the next season.
  List<RaceEntry> get nextCalendar => _nextCalendar ??= _calendarOf(year + 1);
  List<RaceEntry>? _nextCalendar;

  // --- The next season, planned in the winter --------------------------------

  /// Whether the next season can be planned: once the racing is over.
  bool get canPlanNext => racingOver && !seasonOver;

  /// The races of the next season the team plans for: those it rides this
  /// year, championships aside. Invitations are only certain at the turn of
  /// the year; a race the team is not invited to then drops out of the plan.
  List<RaceEntry> get nextOwnRaces {
    final own = {for (final r in ownRaces) r.info.id};
    return [
      for (final r in nextCalendar)
        if (own.contains(r.info.id) && r.tier != RaceTier.championship) r,
    ];
  }

  /// The squad of the next season as things stand: riders under contract
  /// beyond this season, and those who have signed for next season.
  List<SimRider> get nextSquad => [
        for (final r in riderById.values)
          if (economy.contracts[r.id] case final k?)
            if (k.nextTeam == teamId ||
                k.nextTeam == null && r.teamId == teamId && k.endYear > year)
              r,
      ];

  /// The player's plan for the next season: per race id the riders
  /// pencilled in. It becomes the programme at the turn of the year; the
  /// sports director, if in charge, plans the rest.
  final nextProgram = <int, Set<int>>{};

  /// Season goals for the next season, by rider id.
  final nextGoals = <int, Set<int>>{};

  /// Pencils a rider in for a race of the next season, or removes him.
  ///
  /// @param raceId Id of the race.
  /// @param riderId Id of the rider.
  /// @returns null on success, otherwise the reason.
  String? toggleNext(int raceId, int riderId) {
    if (!canPlanNext) {
      return tr('The next season can be planned once the racing is over.');
    }
    final set = nextProgram.putIfAbsent(raceId, () => {});
    if (!set.remove(riderId)) {
      final race = nextCalendar.where((r) => r.info.id == raceId).firstOrNull;
      final places = race == null ? 8 : world.raceField(raceId).ridersPerTeam;
      if (set.length >= places + 2) {
        return tr('{0} riders are pencilled in already.', [set.length]);
      }
      set.add(riderId);
    } else {
      nextGoals[riderId]?.remove(raceId);
    }
    if (set.isEmpty) nextProgram.remove(raceId);
    return null;
  }

  /// Makes a race of the next season one of a rider's goals, or takes the
  /// goal back; a goal pencils him in.
  ///
  /// @param riderId Id of the rider.
  /// @param raceId Id of the race.
  /// @returns null on success, otherwise the reason.
  String? toggleNextGoal(int riderId, int raceId) {
    if (!canPlanNext) {
      return tr('The next season can be planned once the racing is over.');
    }
    final mine = nextGoals.putIfAbsent(riderId, () => {});
    if (mine.remove(raceId)) {
      if (mine.isEmpty) nextGoals.remove(riderId);
      return null;
    }
    if (mine.length >= People.maxGoals) {
      return tr(
          'A rider can have at most {0} season goals.', [People.maxGoals]);
    }
    mine.add(raceId);
    nextProgram.putIfAbsent(raceId, () => {}).add(riderId);
    return null;
  }

  /// At the turn of the year: the plan made in the winter becomes the
  /// programme, for the riders who are in the squad and the races the team
  /// is invited to.
  void _applyNextPlan() {
    final squad = {for (final r in squads[teamId] ?? const <SimRider>[]) r.id};
    final own = {for (final r in ownRaces) r.info.id};
    for (final e in nextProgram.entries) {
      if (!own.contains(e.key)) continue;
      final riders = e.value.where(squad.contains).toSet();
      if (riders.isNotEmpty) program[e.key] = riders;
    }
    for (final e in nextGoals.entries) {
      if (!squad.contains(e.key)) continue;
      final goals = e.value.where(own.contains).toSet();
      if (goals.isEmpty) continue;
      people.goals[e.key] = goals;
      people.ownGoals.add(e.key);
    }
    nextProgram.clear();
    nextGoals.clear();
  }

  /// Team founded by the player, which does not exist in the WorldDB.
  final TeamInfo? custom;

  /// Squad the player chose for the founded team; without it the game
  /// assembles one from free agents.
  final List<int>? customRiders;

  /// Entries and wildcard applications of the player's team.
  late final entries = Entries(this);

  /// Puts together the first squad of a newly founded team: the riders the
  /// player chose, or free agents as good as the starting budget allows.
  void _found() {
    final picked = customRiders;
    if (picked != null) {
      // Chosen riders move at once; their old teams fill up from the free agents.
      for (final id in picked) {
        final r = riderById[id];
        if (r == null) continue;
        economy.move(r, teamId);
        economy.contracts[id]!.endYear = year + 1 + id % 3;
      }
      economy.refill();
      _strength.clear();
      _fitFounded();
      // The same budget as every other team: its wages, staff and
      // facilities are covered.
      economy.found(max(1000000.0, finances.breakEven(teamId)));
      return;
    }
    final pro = custom!.division.startsWith('[2]');
    final budget = pro ? 6000000.0 : 1300000.0;
    final size = pro ? 22 : 16;
    final free =
        teams.values.where((t) => t.division == 'Free').firstOrNull?.id ?? 0;
    final pool = [...?squads[free]]
      ..sort((a, b) => Economy.rating(b).compareTo(Economy.rating(a)));
    var left = budget * 0.6, count = 0;
    for (final r in pool) {
      if (count >= size) break;
      if (year - r.born ~/ 10000 > 34) continue;
      final wage = economy.marketWage(r);
      final slots = size - count;
      // No star who makes the rest of the squad unaffordable.
      if (wage > left - (slots - 1) * 20000 || wage > left / slots * 2.5) {
        continue;
      }
      economy.move(r, teamId);
      economy.contracts[r.id]!.endYear = year + 1 + r.id % 2;
      left -= wage;
      count++;
    }
    _strength.clear();
    _fitFounded();
    economy.found(budget);
  }

  /// Staff and facilities of the founded team as its squad's strength
  /// deserves: both were made while it had no riders yet.
  void _fitFounded() {
    staff.fitTo(teamId);
    facilities.fitTo(teamId);
  }

  /// Comparable team with the same licence: wherever it is invited, the
  /// founded team may start too.
  int get _twin => _twinCache ??= () {
        final own = teams[teamId]!;
        final same = [
          for (final id in licences.teamsWith(licences.of(teamId)))
            if (id != teamId && (squads[id]?.isNotEmpty ?? false)) id,
        ];
        if (same.isEmpty) return -1;
        double distance(int id) =>
            (_teamStrength(id) - _teamStrength(teamId)).abs() -
            (teams[id]!.country == own.country ? 3 : 0);
        same.sort((a, b) => distance(a).compareTo(distance(b)));
        return same.first;
      }();
  int? _twinCache;
  final _fields = <int, List<int>>{};

  /// Training camps of the player's team.
  late final camps = Camps(this);

  /// Championship titles won by any rider.
  final titles = <({int year, String race, int riderId})>[];

  /// Replaces a rider with his new state (changed attributes).
  ///
  /// @param r The rider with updated values.
  void replaceRider(SimRider r) {
    final squad = squads[r.teamId];
    final at = squad?.indexWhere((x) => x.id == r.id) ?? -1;
    if (at >= 0) squad![at] = r;
    riderById[r.id] = r;
  }

  bool _isOwn(SimRider r) => (riderById[r.id]?.teamId ?? r.teamId) == teamId;

  /// Which points a race is worth; championships count like races of
  /// comparable standing.
  ///
  /// @param race The race.
  /// @returns The tier whose points scale applies.
  RaceTier _pointsTier(RaceEntry race) {
    if (race.tier != RaceTier.championship) return race.tier;
    final cls = race.info.raceClass;
    final timeTrial = cls.endsWith('ITT');
    if (cls.startsWith('World')) {
      return timeTrial ? RaceTier.worldTour : RaceTier.monument;
    }
    if (cls.startsWith('European')) {
      return timeTrial ? RaceTier.class1 : RaceTier.proSeries;
    }
    return timeTrial ? RaceTier.class2 : RaceTier.class1;
  }

  static const _europe = {
    'GER', 'FRA', 'ITA', 'ESP', 'BEL', 'NED', 'GBR', 'DEN', 'NOR', 'SWE', //
    'SWD', 'SER', 'MCO',
    'FIN', 'SUI', 'SWI', 'AUT', 'POL', 'CZE', 'SVK', 'SLO', 'CRO', 'POR',
    'IRL', 'LUX', 'EST', 'LAT', 'LTU', 'UKR', 'HUN', 'ROM', 'ROU', 'BUL',
    'GRE', 'SRB', 'BLR', 'ISL', 'ALB', 'MOL', 'MDA', 'BIH', 'MKD', 'MNE',
    'KOS', 'TUR', 'CYP', 'MLT', 'AND', 'MON', 'LIE', 'RUS', 'GEO', 'ARM',
    'AZE', 'ISR',
  };

  /// Field of a championship. In national championships all available riders
  /// of the country ride in their team jerseys; at world and European
  /// championships every country sends a selection whose size depends on the
  /// number of its professionals. The player does not pick a line-up.
  ///
  /// @param race The championship.
  /// @returns The prepared race with its complete field.
  PendingRace _prepareChampionship(RaceEntry race) {
    final routes = [for (final s in race.stages) world.route(s.id)];
    final route = routes.first;
    final cls = race.info.raceClass;
    final timeTrial = cls.endsWith('ITT');
    double fit(SimRider r) => suitability(route, r.attributes);
    bool available(SimRider r) =>
        (teams[r.teamId]?.division ?? 'Free') != 'Free' &&
        !isBusy(r.id, race.start) &&
        !camps.blocks(r.id, race.start, race.end) &&
        shapeOf(r.id).freshness > -40;
    final byCountry = <String, List<SimRider>>{};
    final national = cls.startsWith('National');
    for (final r in riderById.values) {
      // National championship: only look at that country, which saves time.
      if (national && r.country != race.info.country) continue;
      if (r.country.isNotEmpty && available(r)) {
        byCountry.putIfAbsent(r.country, () => []).add(r);
      }
    }
    for (final list in byCountry.values) {
      list.sort((a, b) {
        final f = fit(b).compareTo(fit(a));
        return f != 0 ? f : a.id.compareTo(b.id);
      });
    }
    var riders = <SimRider>[];
    if (cls.startsWith('National')) {
      riders = (byCountry[race.info.country] ?? const [])
          .take(timeTrial ? 40 : 150)
          .toList();
    } else {
      final european = cls.startsWith('European');
      for (final country in byCountry.keys.toList()..sort()) {
        if (european && !_europe.contains(country)) continue;
        final list = byCountry[country]!;
        final pros = list.where((r) {
          final l = licences.of(r.teamId);
          return l == Licence.worldTour || l == Licence.pro;
        }).length;
        final quota = timeTrial
            ? (pros >= 4
                ? 2
                : pros >= 1
                    ? 1
                    : 0)
            : pros >= 30
                ? 8
                : pros >= 10
                    ? 6
                    : pros >= 3
                        ? 4
                        : pros >= 1
                            ? 1
                            : 0;
        final nation =
            900000 + country.codeUnits.fold(0, (a, b) => a * 31 + b) % 90000;
        riders.addAll(list.take(quota).map((r) => r.withTeam(nation, country)));
      }
    }
    return PendingRace(race, routes, riders, const [], const [], 8, const []);
  }

  final World world;

  /// The team the player runs; it changes when he accepts a job offer.
  int teamId;

  /// The team the career was started with, which a save is created for.
  final int startTeam;
  int year;
  final int seed;
  late final _rng = Rng(seed * 31 + 7);

  /// Random source of the career, shared by all subsystems.
  Random get rng => _rng;

  /// Contracts, finances and transfer market.
  late final economy = Economy(this);

  /// The player as a manager: reputation, the board's verdict, job offers.
  late final manager = Manager(this);

  /// Staff of all teams and scouting.
  late final staff = StaffBook(this);

  /// Bike and tyre suppliers of all teams, and the player's material
  /// choices for the race days.
  late final equipment = Equipment(this);

  /// Factor on the development of a rider of a development team: the
  /// academy of the professional team it belongs to.
  double _academy(int teamId) {
    final parent = devTeam.parentOf(teamId);
    return parent == null ? 1.0 : facilities.academyDevelopment(parent);
  }

  /// Facilities of all teams.
  late final facilities = Facilities(this);

  /// The money of every team.
  late final finances = Finances(this);

  /// Quality of a team's care for its riders in stage races, 0 to 1: its
  /// physiotherapists and its sports science.
  ///
  /// @param teamId Id of the team.
  /// @returns 0 to 1.
  double recoveryQuality(int teamId) =>
      (staff.physioQuality(teamId) + facilities.recoveryBonus(teamId))
          .clamp(0.0, 1.0);

  /// Style of every team: how its sports directors race and build. Follows
  /// from the squad and is worked out again every season.
  final styles = <int, TeamStyle>{};

  /// Style the player chose for his team; null follows from the squad.
  TeamStyle? ownStyle;

  /// @param teamId Id of a team.
  /// @returns Its style.
  TeamStyle styleOf(int teamId) => teamId == this.teamId && ownStyle != null
      ? ownStyle!
      : styles[teamId] ?? TeamStyle.balanced;

  void _assignStyles() {
    styles.clear();
    for (final t in teams.values) {
      if (t.division == 'Free') continue;
      styles[t.id] = styleFromSquad(squads[t.id] ?? const [], year);
    }
  }

  /// The style a squad suggests: a team with several strong climbers and a
  /// leader among them races for the overall, one full of cobble and hill
  /// specialists for the classics, one with several fast men for the
  /// sprints; otherwise its age decides.
  ///
  /// @param squad The riders.
  /// @param year The season.
  /// @returns The style.
  static TeamStyle styleFromSquad(List<SimRider> squad, int year) {
    if (squad.isEmpty) return TeamStyle.balanced;
    final top = [...squad]..sort((a, b) => _overall(b).compareTo(_overall(a)));
    final core = top.take(10).toList();
    final climbers = core.where((r) => r.attributes.mountain >= 76).length;
    final leader = core.take(3).any((r) => r.attributes.mountain >= 80);
    final classics = core
        .where((r) => r.attributes.cobble >= 75 || r.attributes.hill >= 77)
        .length;
    final sprinters = core.where((r) => r.attributes.sprint >= 76).length;
    final fastMan = core.take(5).any((r) => r.attributes.sprint >= 80);
    final age =
        squad.fold(0.0, (s, r) => s + year - r.born ~/ 10000) / squad.length;
    if (climbers >= 4 && leader) return TeamStyle.gc;
    if (sprinters >= 2 && fastMan) return TeamStyle.sprint;
    if (classics >= 4) return TeamStyle.classics;
    if (age <= 25.5) return TeamStyle.youth;
    if (age >= 30) return TeamStyle.experience;
    return TeamStyle.balanced;
  }

  /// What a team brings to a stage: the material of its suppliers, the
  /// tyres and the bike of the day, its mechanics and physiotherapists and
  /// its style. The same for every team; for the player's team his choices
  /// of the day replace the sports director's.
  ///
  /// @param teamId Id of the team.
  /// @param raceId Id of the race.
  /// @param route The stage.
  /// @param weather Weather of the day.
  /// @returns The kit.
  TeamKit kitFor(int teamId, int raceId, SimRoute route, Weather weather) {
    final s = equipment.supplyOf(teamId);
    return TeamKit(
      aero: s.bike.aero,
      bikeKg: s.bike.weightKg,
      rolling: s.tyres.rolling,
      punctures: s.tyres.punctures,
      tyres: equipment.tyresFor(teamId, raceId, route, weather),
      timeTrialBike: route.kind == StageKind.road ||
          equipment.timeTrialBikeFor(teamId, raceId, route),
      mechanics: staff.mechanicQuality(teamId),
      physios: recoveryQuality(teamId),
      style: styleOf(teamId),
    );
  }

  /// Kits of all teams in a race for its next stage.
  Map<int, TeamKit> _kitsFor(RaceProgress p, SimRoute route) {
    final weather = p.run.nextWeather;
    return {
      for (final team in {for (final r in p.run.riders) r.teamId})
        team: kitFor(team, p.race.info.id, route, weather),
    };
  }

  /// Weather forecast for the next stage of a race: its first before the
  /// start, today's while it is running.
  ///
  /// @param race The race.
  /// @returns The forecast, or null for a finished race.
  WeatherForecast? forecastOf(RaceEntry race) {
    final p = progress[race.info.id];
    if (p != null && p.finished) return null;
    final index = p?.stagesDone ?? 0;
    if (index >= race.stages.length) return null;
    final truth = weatherOf(race);
    if (truth == null) return null;
    final stage = race.stages[index];
    final date = DateTime.utc(year, stage.month, stage.day);
    final seed =
        p?.run.nextSeed ?? StageRaceRun.firstSeed(_raceSeed(race.info.id));
    return WeatherForecast.of(
        truth, world.route(stage.id), seed, date.difference(today).inDays);
  }

  /// Licences with promotion and relegation.
  late final licences = Licences(this);

  /// Development team of the player's team.
  late final devTeam = DevTeam(this);

  /// What the staff handles without asking.
  final delegation = Delegation();

  /// Full name per rider id ("Firstname Lastname").
  final fullNames = <int, String>{};

  /// @param riderId Id of a rider.
  /// @returns His full name, or the short name if none is known.
  String fullName(int riderId) =>
      fullNames[riderId] ?? riderById[riderId]?.name ?? '?';

  /// Current state of every rider; attributes change through development.
  final riderById = <int, SimRider>{};

  /// Finished seasons: year, points of the player's team and its rank.
  final history = <({int year, double points, int rank})>[];
  final SimTuning tuning;

  late DateTime today;
  late final Map<int, TeamInfo> teams;
  final squads = <int, List<SimRider>>{};
  final calendar = <RaceEntry>[];

  /// Started races by race id.
  final progress = <int, RaceProgress>{};
  final riderPoints = <int, double>{};
  final teamPoints = <int, double>{};

  /// The place of every team in the team ranking of the season: teams with
  /// points by their points, then those without by strength. Every team has
  /// a place on the same scale as the order by strength at the start of a
  /// career, so that a team without points does not count as better placed
  /// than its strength.
  ///
  /// @returns Places from 1 by team id, the free agents left out.
  Map<int, int> rankingPlaces() {
    final order = [
      for (final t in teams.values)
        if (t.division != 'Free') t.id,
    ]..sort((a, b) {
        final points = (teamPoints[b] ?? 0).compareTo(teamPoints[a] ?? 0);
        if (points != 0) return points;
        final strength = teamStrength(b).compareTo(teamStrength(a));
        return strength != 0 ? strength : a.compareTo(b);
      });
    return {for (final (i, id) in order.indexed) id: i + 1};
  }

  final inbox = <Message>[];

  /// Tactics of the player's team per race; without an entry the sports
  /// director plans every stage himself.
  final ownPlans = <int, TeamPlan>{};

  /// Topics (keys of [Message.topics]) the player does not want messages
  /// about.
  final mutedTopics = <String>{};

  /// Whether three or more messages of one topic on one day arrive as a
  /// single summary.
  var inboxDigest = true;

  /// Applies the player's inbox settings to the messages of the day: drops
  /// those of muted topics and folds many of one topic into a summary. A
  /// message that asks for a decision always arrives on its own.
  ///
  /// @param from Index of the first message written today.
  void _tidyInbox(int from) {
    if (from >= inbox.length) return;
    final fresh = inbox.sublist(from);
    inbox.removeRange(from, inbox.length);
    fresh
        .removeWhere((m) => m.talk == null && mutedTopics.contains(m.topicKey));
    if (!inboxDigest) {
      inbox.addAll(fresh);
      return;
    }
    final byTopic = <String, List<Message>>{};
    for (final m in fresh) {
      // A message that asks for a decision stays on its own.
      byTopic
          .putIfAbsent(m.talk == null ? m.topicKey : '${m.hashCode}', () => [])
          .add(m);
    }
    for (final list in byTopic.values) {
      if (list.length < 3) {
        inbox.addAll(list);
        continue;
      }
      final first = list.first;
      inbox.add(Message(
        first.date,
        first.from,
        tr('{0}: {1} messages', [first.topic, list.length]),
        [for (final m in list) '${m.subject}\n${m.body}'].join('\n\n'),
        raceId: list.map((m) => m.raceId).whereType<int>().firstOrNull,
      ));
    }
  }

  /// Names the best of the season: the rider with the most points, the
  /// best rider aged 23 or younger, the rider with the most wins and the
  /// best team. Runs after the last race and again before the rankings
  /// start over.
  ///
  /// @param message Whether to send the message.
  /// @param record Whether to note the winners in the archive of the season.
  void _awards({bool message = true, bool record = true}) {
    if (riderPoints.isEmpty) return;
    SimRider? best(Iterable<SimRider> of, num Function(SimRider) by) {
      SimRider? top;
      for (final r in of) {
        if (by(r) > 0 && (top == null || by(r) > by(top))) top = r;
      }
      return top;
    }

    final all = riderById.values;
    num points(SimRider r) => riderPoints[r.id] ?? 0;
    final rider = best(all, points);
    final young = best(all.where((r) => year - r.born ~/ 10000 <= 23), points);
    final winner = best(all, (r) => winsOf(r.id, year));
    final team = (teamPoints.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .firstOrNull;
    String of(SimRider? r) => r == null
        ? '–'
        : '${fullName(r.id)} (${teams[r.teamId]?.name ?? r.team})';
    final lines = [
      tr('Rider of the year: {0}, {1} points',
          [of(rider), rider == null ? 0 : points(rider).round()]),
      tr('Best young rider: {0}', [of(young)]),
      tr('Most wins: {0}, {1} wins',
          [of(winner), winner == null ? 0 : winsOf(winner.id, year)]),
      if (team != null)
        tr('Team of the year: {0}, {1} points',
            [teams[team.key]?.name ?? '', team.value.round()]),
    ];
    if (record && archive.isNotEmpty) {
      archive.last['awards'] = {
        'rider': rider?.id,
        'young': young?.id,
        'wins': winner?.id,
        'team': team?.key,
      };
    }
    if (!message) return;
    inbox.add(Message(
      today,
      tr('Season review'),
      tr('The best of the {0} season', [year]),
      lines.join('\n'),
    ));
  }

  /// Whether the last race of the season has been ridden and the winter
  /// has begun.
  bool racingOver = false;

  /// The day of the last race: the best of the season, and what the winter
  /// holds until the turn of the year.
  void _endOfRacing() {
    racingOver = true;
    _awards(record: false);
    final place = rankingPlaces()[teamId];
    inbox.add(Message(
      today,
      tr('Board'),
      tr('The racing season {0} is over', [year]),
      tr('Place {0} in the team ranking with {1} points. The board assesses the goals at the turn of the year.',
          [place ?? '-', (teamPoints[teamId] ?? 0).round()]),
    ));
  }

  /// The riders as people: personality, morale, goals and promises.
  late final people = People(this);

  /// How much the goals of sponsor and board raise the importance of a race
  /// for the player's team: a Grand Tour goal lifts the Grand Tours, a
  /// number of wins lifts the smaller races in which wins are within reach.
  ///
  /// @param race The race.
  /// @returns A factor, 1 without a matching goal.
  double sponsorWeight(RaceEntry race) {
    var factor = 1.0;
    for (final goal in economy.goals) {
      switch (goal.kind) {
        case GoalKind.grandTourPodium:
          if (race.tier == RaceTier.grandTour) factor *= 1.25;
        case GoalKind.grandTourStage:
          if (race.tier == RaceTier.grandTour) factor *= 1.1;
        case GoalKind.wins:
          if (race.tier == RaceTier.proSeries || race.tier == RaceTier.class1) {
            factor *= 1.2;
          }
        case GoalKind.ranking:
          break;
      }
    }
    return factor;
  }

  /// The sports director's planner for the race programme.
  late final planner = SeasonPlanner(this);

  /// Races of the player's team that can still be planned: they have not
  /// started and their line-up is not picked by a federation.
  List<RaceEntry> get _plannable => [
        for (final r in ownRaces)
          if (r.start.isAfter(today) &&
              r.tier != RaceTier.championship &&
              !progress.containsKey(r.info.id))
            r,
      ];

  /// Lets the sports director plan the season: every race of the player's
  /// team that has no programme yet gets one.
  ///
  /// @param replace Whether to plan all coming races anew, discarding what
  ///   is pencilled in for them.
  /// @returns The number of races planned.
  int planSeason({bool replace = false}) {
    final races = _plannable;
    if (replace) {
      for (final r in races) {
        program.remove(r.info.id);
      }
      // Goals the sports director chose go with the old plan; those the
      // player set stay.
      for (final r in squads[teamId] ?? const <SimRider>[]) {
        if (!people.ownGoals.contains(r.id)) people.goals.remove(r.id);
      }
    }
    final open = [
      for (final r in races)
        if (!program.containsKey(r.info.id)) r,
    ];
    if (open.isEmpty) return 0;
    final all = [
      for (final r in ownRaces)
        if (r.tier != RaceTier.championship) r,
    ];
    final planned = planner.plan(
      squads[teamId] ?? const [],
      open,
      fixed: program,
      all: all,
      wishes: people.goals,
    );
    program.addAll(planned);
    people.goalsFrom(program, all, teamId);
    planner.saveWeights();
    return planned.length;
  }

  /// The season plan as the sports director reports it.
  ///
  /// @returns Races and race days planned, and the mean and the highest
  ///   number of race days per rider.
  ({int races, int days, double mean, int most}) programSummary() {
    final perRider = <int, int>{};
    var races = 0, days = 0;
    for (final r in ownRaces) {
      final riders = program[r.info.id];
      if (riders == null || riders.isEmpty) continue;
      races++;
      days += r.stages.length;
      for (final id in riders) {
        perRider[id] = (perRider[id] ?? 0) + r.stages.length;
      }
    }
    final squad = squads[teamId]?.length ?? 0;
    return (
      races: races,
      days: days,
      mean: squad == 0 ? 0 : perRider.values.fold(0, (a, b) => a + b) / squad,
      most: perRider.values.fold(0, (a, b) => a > b ? a : b),
    );
  }

  /// Season plans of the other teams: riders per race id, by team id. Every
  /// team's sports director plans like the player's.
  final teamPrograms = <int, Map<int, Set<int>>>{};

  /// Lets the sports directors of the other teams plan their seasons, once
  /// per season. Races that have started are left alone.
  void _planOthers() {
    if (teamPrograms.isNotEmpty) return;
    final byTeam = <int, List<RaceEntry>>{};
    for (final race in calendar) {
      if (race.tier == RaceTier.championship ||
          !race.start.isAfter(today) ||
          progress.containsKey(race.info.id)) {
        continue;
      }
      for (final team in _field(race)) {
        if (team != teamId) byTeam.putIfAbsent(team, () => []).add(race);
      }
    }
    for (final team in byTeam.keys.toList()..sort()) {
      final squad = squads[team] ?? const <SimRider>[];
      if (squad.length < 4) continue;
      teamPrograms[team] = planner.plan(squad, byTeam[team]!, teamId: team);
      people.goalsFrom(teamPrograms[team]!, byTeam[team]!, team);
    }
    planner.saveWeights();
  }

  /// Plans what is still open: the seasons of the other teams, and, if the
  /// sports director is in charge of the programme, the player's own, at
  /// the start of a season everything, later the races the team is newly
  /// invited to.
  void ensureProgram() {
    _planOthers();
    if (!delegation.planning) return;
    final first = program.isEmpty;
    final planned = planSeason();
    if (planned == 0 || !first) return;
    final sum = programSummary();
    inbox.add(Message(
      today,
      tr('Sports director'),
      tr('The season plan is ready'),
      tr('I have planned {0} races with {1} race days, the most important first. On average every rider gets {2} race days, none more than {3}. You can change every entry in the race planner.',
          [sum.races, sum.days, sum.mean.round(), sum.most]),
    ));
  }

  /// A rider of the player's team is out until [until]: the sports director
  /// takes him out of the races he would miss and names a replacement.
  ///
  /// @param r The rider.
  /// @param until First day he can race again.
  void replaceInProgram(SimRider r, DateTime until) {
    if (!delegation.planning) return;
    final squad = squads[teamId] ?? const <SimRider>[];
    final all = [
      for (final x in ownRaces)
        if (x.tier != RaceTier.championship) x,
    ];
    final lines = <String>[];
    for (final race in _plannable) {
      final riders = program[race.info.id];
      if (riders == null || !riders.contains(r.id)) continue;
      if (!race.start.isBefore(until)) continue;
      riders.remove(r.id);
      final stand = planner.substitute(squad, race, program, all);
      if (stand != null) riders.add(stand.id);
      lines.add(stand == null
          ? tr('{0}: no replacement free', [race.info.name])
          : tr('{0}: {1} steps in', [race.info.name, stand.name]));
    }
    if (lines.isEmpty) return;
    inbox.add(Message(
      today,
      tr('Sports director'),
      tr('Replacement for {0}', [r.name]),
      tr('{0} misses races he was planned for. {1}.',
          [r.name, lines.join('; ')]),
    ));
  }

  /// Riders of the season plan who are pencilled in for two races that run
  /// at the same time. Races that have started are left out.
  ///
  /// @returns One entry per rider and pair of overlapping races.
  List<({SimRider rider, RaceEntry first, RaceEntry second})> programClashes() {
    final races = [
      for (final r in ownRaces)
        if (r.start.isAfter(today) && (program[r.info.id]?.isNotEmpty ?? false))
          r,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final out = <({SimRider rider, RaceEntry first, RaceEntry second})>[];
    for (var i = 0; i < races.length; i++) {
      for (var k = i + 1; k < races.length; k++) {
        if (races[k].start.isAfter(races[i].end)) break;
        for (final id in program[races[i].info.id]!) {
          if (!program[races[k].info.id]!.contains(id)) continue;
          final rider = riderById[id];
          if (rider != null) {
            out.add((rider: rider, first: races[i], second: races[k]));
          }
        }
      }
    }
    return out;
  }

  /// What else speaks against the season plan beside riders entered twice:
  /// riders who would reach too many race days, goal races a rider is not
  /// planned for, and races with more riders pencilled in than places.
  ///
  /// @returns The warnings, empty if there is nothing to say.
  List<String> programWarnings() {
    final out = <String>[];
    final ahead = [
      for (final r in ownRaces)
        if (!progress.containsKey(r.info.id)) r,
    ];
    final days = <int, int>{};
    for (final race in ahead) {
      final planned = program[race.info.id] ?? const <int>{};
      final size = world.raceField(race.info.id).ridersPerTeam;
      if (planned.length > size) {
        out.add(tr('{0}: {1} riders pencilled in for {2} places.',
            [race.info.name, planned.length, size]));
      }
      for (final id in planned) {
        days[id] = (days[id] ?? 0) + race.stages.length;
      }
    }
    for (final r in squads[teamId] ?? const <SimRider>[]) {
      final total = shapeOf(r.id).raceDays + (days[r.id] ?? 0);
      if (total > 85) {
        out.add(tr('{0} would reach {1} race days.', [r.name, total]));
      }
      for (final goal in people.goals[r.id] ?? const <int>{}) {
        final race = ahead.where((x) => x.info.id == goal).firstOrNull;
        if (race != null && !(program[goal]?.contains(r.id) ?? false)) {
          out.add(tr('{0} is not planned for his goal race {1}.',
              [r.name, race.info.name]));
        }
      }
    }
    return out;
  }

  /// Line-ups the player saved under a name, as rider ids.
  final lineupTemplates = <String, List<int>>{};

  /// The player's own programme templates.
  final ownTemplates = <ProgramTemplate>[];

  /// The built-in templates and the player's own.
  List<ProgramTemplate> get templates =>
      [...ProgramTemplate.builtIns, ...ownTemplates];

  /// Pencils a rider in for the races of a template that lie ahead, as far
  /// as they do not overlap with races he is already planned for.
  ///
  /// @param key Key of the template: the English name of a built-in one,
  ///   the name of an own one.
  /// @param riderId Id of the rider.
  /// @returns The number of races added.
  int applyTemplate(String key, int riderId) {
    final t = templates.where((x) => x.key == key).firstOrNull;
    if (t == null) return 0;
    final ahead = [
      for (final r in ownRaces)
        if (r.start.isAfter(today) && !progress.containsKey(r.info.id)) r,
    ]..sort((a, b) => a.start.compareTo(b.start));
    bool overlaps(RaceEntry race) => ahead.any((x) =>
        x != race &&
        (program[x.info.id]?.contains(riderId) ?? false) &&
        !x.start.isAfter(race.end) &&
        !race.start.isAfter(x.end));
    var added = 0;
    for (final race in ahead) {
      if (!t.includes(this, race) || overlaps(race)) continue;
      final set = program.putIfAbsent(race.info.id, () => {});
      if (set.add(riderId)) added++;
    }
    return added;
  }

  /// Saves the season programme of a rider as an own template.
  ///
  /// @param name Name of the template; one of the same name is replaced.
  /// @param riderId Id of the rider whose programme it takes.
  /// @returns null on success, otherwise the reason.
  String? saveTemplate(String name, int riderId) {
    final races = [
      for (final r in ownRaces)
        if (program[r.info.id]?.contains(riderId) ?? false) r.info.id,
    ];
    if (name.trim().isEmpty) return tr('The template needs a name.');
    if (races.isEmpty) return tr('He has no races in his programme.');
    if (ProgramTemplate.builtIns.any((t) => t.key == name.trim())) {
      return tr('A built-in template already has that name.');
    }
    ownTemplates
      ..removeWhere((t) => t.key == name.trim())
      ..add(ProgramTemplate.own(name.trim(), races));
    return null;
  }

  /// Deletes an own template.
  ///
  /// @param name Its name.
  void deleteTemplate(String name) =>
      ownTemplates.removeWhere((t) => t.key == name);

  // --- Breakaways ---------------------------------------------------------------

  /// Days in the break of the season per rider id.
  final breakDays = <int, int>{};

  /// Combativity awards of the season per rider id: on every road stage
  /// the rider of the break who did the most work in front.
  final combative = <int, int>{};

  /// Counts the break of a stage and names its most combative rider.
  ///
  /// @param result The stage just ridden.
  void _countBreak(StageResult result) {
    int? best;
    var bestKm = -1.0;
    var bestPlace = 1 << 20;
    final place = {
      for (final (i, p) in result.placings.indexed) p.rider.id: i,
    };
    for (final e in result.traces.entries) {
      if (!e.value.inBreak) continue;
      breakDays[e.key] = (breakDays[e.key] ?? 0) + 1;
      final km = e.value.frontKm;
      final at = place[e.key] ?? 1 << 19;
      if (km > bestKm || km == bestKm && at < bestPlace) {
        best = e.key;
        bestKm = km;
        bestPlace = at;
      }
    }
    if (best != null) combative[best] = (combative[best] ?? 0) + 1;
  }

  /// @param team A team.
  /// @returns The days its riders spent in the break this season.
  int teamBreakDays(int team) => [
        for (final r in squads[team] ?? const <SimRider>[])
          breakDays[r.id] ?? 0,
      ].fold(0, (a, b) => a + b);

  /// @param team A team.
  /// @returns Its combativity awards this season.
  int teamCombative(int team) => [
        for (final r in squads[team] ?? const <SimRider>[])
          combative[r.id] ?? 0,
      ].fold(0, (a, b) => a + b);

  /// Answers the open talk of a kind with a rider.
  ///
  /// @param kind Kind of the talk.
  /// @param riderId Id of the rider.
  /// @param choice Index of the answer.
  /// @returns null on success, otherwise the reason.
  String? answerTalk(String kind, int riderId, int choice) {
    final m = inbox.reversed
        .where((m) =>
            m.talk?.kind == kind &&
            m.talk?.riderId == riderId &&
            m.talk?.answer == null)
        .firstOrNull;
    if (m == null) return tr('The talk is over.');
    final answer = kind == 'job'
        ? manager.answer(riderId, choice)
        : people.answer(m.talk!, choice);
    if (answer == null) m.talk!.answer = choice;
    return answer;
  }

  /// What the player had delegated before the staff took over for a run
  /// (vacation, or simulating without stops); null outside such a run.
  Map<String, dynamic>? heldDelegation;

  /// The shortlist: riders the player keeps an eye on. He gets a message
  /// when one of them becomes available or signs somewhere.
  final watch = <int>{};

  /// The player's own notes on riders, by rider id.
  final notes = <int, String>{};

  /// What the player has pinned down per race id; the sports director plans
  /// the rest for every stage. A complete plan in [ownPlans] comes first.
  final ownWishes = <int, PlanWish>{};

  /// Physical condition per rider id.
  final shape = <int, RiderShape>{};

  /// The player's season plan: per race id the riders pencilled in.
  final program = <int, Set<int>>{};

  /// @param riderId Id of a rider.
  /// @returns His condition, created on first access.
  RiderShape shapeOf(int riderId) => shape.putIfAbsent(riderId, RiderShape.new);

  /// Races of the season the player's team starts in.
  List<RaceEntry> get ownRaces => _ownRaces ??= [
        for (final r in calendar)
          if (_field(r).contains(teamId)) r,
      ];
  List<RaceEntry>? _ownRaces;

  /// @param riderId Id of a rider.
  /// @param date A day.
  /// @returns Whether he is racing, injured or in a camp on that day.
  bool isBusy(int riderId, DateTime date) =>
      (_busyUntil[riderId]?.isAfter(date) ?? false) ||
      isInjured(riderId, date) ||
      camps.campOf(riderId, date) != null;

  /// @param riderId Id of a rider.
  /// @param date A day.
  /// @returns Whether he is injured or ill on that day.
  bool isInjured(int riderId, DateTime date) =>
      shape[riderId]?.injuredUntil?.isAfter(date) ?? false;

  final _busyUntil = <int, DateTime>{};
  final _strength = <int, double>{};
  final _pending = <int, PendingRace>{};
  final _skipped = <int>{};

  /// Whether the last day of the season has been played.
  bool get seasonOver => today.year > year;

  /// @param date A day.
  /// @returns The races that have a stage on that day.
  List<RaceEntry> racesOn(DateTime date) => [
        for (final r in calendar)
          if (!date.isBefore(r.start) &&
              !date.isAfter(r.end) &&
              r.stages.any((s) => s.month == date.month && s.day == date.day))
            r,
      ];

  /// The next race of today for which the player has to confirm his line-up.
  /// As long as there is one, the day does not advance.
  PendingRace? get needsDecision {
    for (final race in racesOn(today)) {
      final id = race.info.id;
      if (progress.containsKey(id) || _skipped.contains(id)) continue;
      final pending = _pending[id] ??= _prepare(race);
      if (pending.available.length >= 4 &&
          _field(race).contains(teamId) &&
          pending.others.length >= 20) {
        return pending;
      }
    }
    return null;
  }

  /// Tactics the sports director suggests for a stage.
  ///
  /// @param route The stage.
  /// @param lineup Own riders at the start.
  /// @param others Riders of the other teams.
  /// @param gcGaps Gaps in the general classification before the stage.
  /// @param crosswindKm Kilometres of crosswind the forecast expects.
  /// @returns The suggested plan for the player's team.
  TeamPlan suggestPlan(
      SimRoute route, List<SimRider> lineup, List<SimRider> others,
      {Map<int, double> gcGaps = const {}, double crosswindKm = 0}) {
    final riders = [...others, ...lineup];
    return autoPlans(route, riders,
        gcGaps: gcGaps,
        styles: {
          for (final team in {for (final r in riders) r.teamId})
            team: styleOf(team),
        },
        crosswindKm: crosswindKm)[teamId]!;
  }

  /// Confirms the line-up for a waiting race.
  ///
  /// @param pending The waiting race.
  /// @param lineup Own riders, in the order they were picked.
  /// @param plan Complete tactics for the whole race.
  /// @param wish What the player pins down; the sports director decides the
  ///   rest for every stage. Without [plan] and [wish] he decides everything.
  /// @param directorId Sports director to send; without it the best free one.
  void confirm(PendingRace pending, List<SimRider> lineup,
      {TeamPlan? plan,
      PlanWish? wish,
      int? directorId,
      int? captainId,
      bool waitForLeader = false}) {
    final id = pending.race.info.id;
    if (plan != null) ownPlans[id] = plan;
    if (wish != null && !wish.isEmpty) ownWishes[id] = wish;
    if (captainId != null) captains[id] = captainId;
    if (waitForLeader) tttWait.add(id);
    _launch(pending, lineup, directorId: directorId);
  }

  // --- Weather ----------------------------------------------------------------

  /// Seed a race of this season is simulated with.
  int _raceSeed(int raceId) => seed * 104729 + raceId;

  /// Weather of the next stage of a race: of its first stage before the
  /// start, of today's stage while it is running.
  ///
  /// @param race The race.
  /// @returns The weather, or null once the race is over.
  Weather? weatherOf(RaceEntry race) {
    final p = progress[race.info.id];
    if (p == null) {
      return StageRaceRun.firstWeather(
          _raceSeed(race.info.id), race.start.month, race.info.country);
    }
    return p.finished ? null : p.run.nextWeather;
  }

  // --- Radio ------------------------------------------------------------------

  /// The player's answers for today's stage per race id.
  final _radio = <int, Map<RadioKind, int>>{};

  /// The player's orders to his riders in today's stage per race id, as he
  /// gave them while he watched it live.
  final _orders = <int, List<TimedOrder>>{};

  /// The player's tactics for the next stage of a race: his complete plan,
  /// or his wishes laid over what the sports director plans for that stage.
  ///
  /// @param raceId Id of a race.
  /// @param route The stage.
  /// @returns The plan as a one-entry map, or an empty map if the sports
  ///   director decides everything.
  Map<int, TeamPlan> _plansFor(int raceId, SimRoute route) {
    final plans = _ownPlanFor(raceId, route);
    // In a team time trial the line may wait for the leader.
    if (route.kind == StageKind.teamTimeTrial && tttWait.contains(raceId)) {
      final p = progress[raceId];
      final base = plans[teamId] ??
          (p == null
              ? null
              : autoPlans(route, p.run.riders, gcGaps: p.run.gcGaps)[teamId]);
      if (base != null) return {teamId: base.copyWith(waitForLeader: true)};
    }
    return plans;
  }

  Map<int, TeamPlan> _ownPlanFor(int raceId, SimRoute route) {
    final plan = ownPlans[raceId];
    if (plan != null) return {teamId: plan};
    final wish = ownWishes[raceId];
    final p = progress[raceId];
    if (wish == null || p == null) return const {};
    final auto = autoPlans(route, p.run.riders, gcGaps: p.run.gcGaps)[teamId];
    if (auto == null) return const {};
    return {
      teamId: wish.applyTo(auto, route, {
        for (final r in p.run.riders)
          if (r.teamId == teamId) r.id,
      }),
    };
  }

  /// The road captain the player chose per race id.
  final captains = <int, int>{};

  /// Races whose team time trial waits for the leader.
  final tttWait = <int>{};

  /// The road captain of a team in a race: the player's choice for his
  /// team, otherwise the rider best suited.
  ///
  /// @param p The race.
  /// @param team Id of the team.
  /// @returns The captain, or null for a team without riders in it.
  SimRider? captainOf(RaceProgress p, int team) {
    final riders = [
      for (final r in p.riders)
        if (r.teamId == team) r,
    ];
    if (team == teamId) {
      final chosen = captains[p.race.info.id];
      final r = riders.where((x) => x.id == chosen).firstOrNull;
      if (r != null) return r;
    }
    return people.bestCaptain(riders);
  }

  /// Finds the next question from one of today's races that the player has
  /// not answered yet, by simulating the stage up to that point as a trial.
  ///
  /// @returns Race, stage and question, or null if there is none or the radio
  ///   is switched off ([Delegation.radio]).
  RadioPrompt? nextRadioCall() {
    for (final job in _radioJobs()) {
      final trial = job.job.run();
      if (trial.openCall case final call?) {
        return (
          race: job.race,
          stageIndex: job.index,
          call: call,
          trial: trial,
        );
      }
    }
    return null;
  }

  /// Today's stages in which the sports director may call in, each as a
  /// trial run that pauses at the first question without an answer.
  Iterable<_DayStage> _radioJobs() sync* {
    if (delegation.radio == RadioMode.off) return;
    for (final race in racesOn(today)) {
      final id = race.info.id;
      // At championships the team's own sports director is not in charge.
      if (race.tier == RaceTier.championship) continue;
      if (delegation.radio == RadioMode.important && race.tier.factor < 5) {
        continue;
      }
      final p = progress[id];
      if (p == null || p.finished) continue;
      if (!p.run.riders.any((r) => r.teamId == teamId)) continue;
      final route = world.route(race.stages[p.stagesDone].id);
      yield _DayStage(
        p,
        p.stagesDone,
        p.run.previewJob(
          route,
          plans: _plansFor(id, route),
          directorSkills: p.directorSkills,
          radioTeam: teamId,
          radio: _radio[id] ?? const {},
          askRadio: true,
          kits: _kitsFor(p, route),
          track: true,
          orders: _orders[id] ?? const [],
        ),
      );
    }
  }

  /// Today's stages of the player's team, to be watched live. The sports
  /// director asks over the radio as he would otherwise.
  ///
  /// @returns Race, stage and job of each.
  List<LiveJob> liveJobs() {
    final out = <LiveJob>[];
    for (final race in racesOn(today)) {
      final id = race.info.id;
      final p = progress[id];
      if (p == null || p.finished) continue;
      if (!p.run.riders.any((r) => r.teamId == teamId)) continue;
      final asks = race.tier != RaceTier.championship &&
          (delegation.radio == RadioMode.all ||
              delegation.radio == RadioMode.important && race.tier.factor >= 5);
      final route = world.route(race.stages[p.stagesDone].id);
      out.add((
        race: p,
        stageIndex: p.stagesDone,
        job: p.run.previewJob(
          route,
          plans: _plansFor(id, route),
          directorSkills: p.directorSkills,
          radioTeam: teamId,
          radio: _radio[id] ?? const {},
          askRadio: asks,
          kits: _kitsFor(p, route),
          track: true,
          orders: _orders[id] ?? const [],
        ),
      ));
    }
    return out;
  }

  /// Takes what the player did while he watched today's stage of a race
  /// live: his answers to the radio and his orders. The stage is ridden
  /// with them when the day is played.
  ///
  /// @param raceId Id of the race.
  /// @param answers Answers per question.
  /// @param orders Orders, each with the race clock at which it was given.
  void watched(
      int raceId, Map<RadioKind, int> answers, List<TimedOrder> orders) {
    _radio.putIfAbsent(raceId, () => {}).addAll(answers);
    _orders[raceId] = [...orders];
  }

  /// Like [nextRadioCall], with the trial run of the stage on another
  /// isolate.
  ///
  /// @returns Race, stage and question, or null.
  Future<RadioPrompt?> nextRadioCallAsync() async {
    for (final job in _radioJobs()) {
      final trial = await Isolate.run(job.job.run);
      if (trial.openCall case final call?) {
        return (
          race: job.race,
          stageIndex: job.index,
          call: call,
          trial: trial,
        );
      }
    }
    return null;
  }

  /// Stores the player's answer to a radio question of today's stage.
  ///
  /// @param raceId Id of the race.
  /// @param kind Which decision point.
  /// @param choice Index of the chosen option.
  void answerRadio(int raceId, RadioKind kind, int choice) =>
      _radio.putIfAbsent(raceId, () => {})[kind] = choice;

  /// Simulates a ridden stage once more with the same randomness and the same
  /// opponents, but with different tactics or radio instructions for the
  /// player's team. Does not change the game state.
  ///
  /// @param raceId Id of the race.
  /// @param stageIndex Zero-based index of the stage.
  /// @param plan New tactics; null keeps the original.
  /// @param radio New radio answers; null keeps the original.
  /// @param askRadio Whether to pause at the first unanswered question.
  /// @returns The alternative result.
  StageResult whatIf(int raceId, int stageIndex,
      {TeamPlan? plan, Map<RadioKind, int>? radio, bool askRadio = false}) {
    final p = progress[raceId]!;
    return p.run.replay(
      stageIndex,
      world.route(p.race.stages[stageIndex].id),
      radioTeam: teamId,
      plan: plan,
      radio: radio,
      askRadio: askRadio,
    );
  }

  /// Tactics the player's team rode a stage with.
  ///
  /// @param raceId Id of the race.
  /// @param stageIndex Zero-based index of the stage.
  /// @returns The player's plan, or else the sports director's own plan.
  TeamPlan planUsed(int raceId, int stageIndex) {
    final p = progress[raceId]!;
    return p.run.planUsed(stageIndex, teamId) ??
        p.run.autoPlanUsed(
            stageIndex, world.route(p.race.stages[stageIndex].id), teamId) ??
        TeamPlan(roles: const {});
  }

  // --- Delegation -------------------------------------------------------------

  /// The coach sets load and focus for every rider, each Monday.
  void _coachPlans() {
    for (final r in squads[teamId] ?? const <SimRider>[]) {
      final s = shapeOf(r.id);
      final age = year - r.born ~/ 10000;
      // Ease off before a planned race, otherwise dose by freshness.
      final racesSoon = ownRaces.any((race) {
        final days = race.start.difference(today).inDays;
        return days >= 0 &&
            days <= 5 &&
            (program[race.info.id]?.contains(r.id) ?? false);
      });
      s.load = racesSoon || s.freshness < -25
          ? TrainingLoad.low
          : age <= 25 && s.freshness > -8
              ? TrainingLoad.high
              : TrainingLoad.normal;
      final a = r.attributes;
      final best = {
        TrainingFocus.climbing: a.mountain,
        TrainingFocus.sprint: a.sprint,
        TrainingFocus.timeTrial: a.timeTrial,
        TrainingFocus.classics: (a.cobble + a.hill) / 2 + 1,
      }.entries.reduce((x, y) => y.value > x.value ? y : x);
      s.focus = age >= 31 ? TrainingFocus.stamina : best.key;
    }
  }

  /// Simulates all of today's stages and moves on to the next day. If a race
  /// is waiting for the player ([needsDecision]), the sports director's
  /// suggestion is taken.
  ///
  /// @returns What was ridden today.
  DayReport advance() => advanceSteps().last!;

  /// The same day in steps: after every race a null is yielded, at the end
  /// the report of the day. A caller that waits a moment between the steps
  /// keeps its window responsive on days with many races.
  ///
  /// @returns The steps; the day is only complete once all were taken.
  Iterable<DayReport?> advanceSteps() sync* {
    final day = _dayBegin();
    for (final stage in day.stages) {
      _stageEnd(day, stage, stage.job.run());
      yield null;
    }
    yield _dayEnd(day);
  }

  /// The same day with the stages simulated on other isolates, all races of
  /// the day at the same time. The thread that draws the window is free
  /// meanwhile. The result is the same as that of [advance].
  ///
  /// @param onRaces Called with the races that are being simulated.
  /// @returns The report of the day.
  Future<DayReport> advanceAsync(
      {void Function(List<RaceEntry> races)? onRaces}) async {
    final day = _dayBegin();
    onRaces?.call([for (final s in day.stages) s.race.race]);
    final results = await Future.wait([
      for (final stage in day.stages) Isolate.run(stage.job.run),
    ]);
    for (var i = 0; i < day.stages.length; i++) {
      _stageEnd(day, day.stages[i], results[i]);
    }
    return _dayEnd(day);
  }

  /// Opens the day: plans what is open, confirms waiting line-ups with the
  /// sports director's suggestion, starts the races of the day and fixes
  /// today's stage of each as a job. Nothing is simulated yet.
  _Day _dayBegin() {
    final inboxBefore = inbox.length;
    ensureProgram();
    for (var p = needsDecision; p != null; p = needsDecision) {
      confirm(p, p.suggestedLineup);
    }
    final stages = <_DayStage>[];
    for (final race in racesOn(today)) {
      final id = race.info.id;
      if (!progress.containsKey(id) && !_skipped.contains(id)) {
        // Races without the player's team start without asking.
        _launch(_pending[id] ??= _prepare(race), const []);
      }
      final p = progress[id];
      if (p == null || p.finished) continue;
      final route = world.route(race.stages[p.stagesDone].id);
      stages.add(_DayStage(
        p,
        p.stagesDone,
        p.run.begin(
          route,
          plans: _plansFor(id, route),
          directorSkills: p.directorSkills,
          radioTeam: teamId,
          radio: _radio.remove(id) ?? const {},
          orders: _orders.remove(id) ?? const [],
          kits: _kitsFor(p, route),
          // Where every rider was, for the 3D view of the player's races.
          track: p.run.riders.any((r) => r.teamId == teamId),
        ),
      ));
    }
    return _Day(today, inboxBefore, stages);
  }

  /// Takes the result of a stage into the race and the rankings.
  void _stageEnd(_Day day, _DayStage stage, StageResult simulated) {
    final result = stage.race.run.finish(stage.job, simulated);
    // The groups along the route are kept for the races of the player's
    // team, for the stage in fast motion.
    if (!result.placings.any((p) => p.rider.teamId == teamId)) {
      for (final s in result.timeline) {
        s.groups = const [];
      }
      result.track = null;
    } else {
      // The tracks for the 3D view take a megabyte a stage: only the race
      // that is running keeps them.
      for (final other in progress.values) {
        if (identical(other, stage.race)) continue;
        for (final r in other.run.results) {
          r.track = null;
        }
      }
    }
    // Power figures are kept for the player's riders and the first ten.
    final top = {for (final p in result.placings.take(10)) p.rider.id};
    result.power.removeWhere(
        (id, _) => !top.contains(id) && riderById[id]?.teamId != teamId);
    day.ridden.add((race: stage.race, stageIndex: stage.index, result: result));
    _credit(stage.race, stage.index, result);
  }

  /// Closes the day: rest days, training, injuries, development, money,
  /// staff, and the inbox as the player wants it.
  DayReport _dayEnd(_Day day) {
    final date = day.date;
    final ridden = day.ridden;
    // A stage race without a stage today has a rest day.
    for (final p in progress.values) {
      if (p.finished || p.stagesDone == 0) continue;
      if (ridden.any((r) => identical(r.race, p))) continue;
      if (date.isAfter(p.race.start) && date.isBefore(p.race.end)) {
        p.run.restDay({
          for (final team in {for (final r in p.run.riders) r.teamId})
            team: TeamKit(physios: recoveryQuality(team)),
        });
      }
    }
    _trainAndRecover(ridden);
    _incidents(ridden);
    if (today.day == 1) {
      _recordGrowth();
      _develop();
      people.mentoring();
      if (delegation.facilities) facilities.boardBuilds();
    }
    if (today.weekday == DateTime.monday) {
      _recordForm();
      people.weekly();
    }
    if (delegation.training && today.weekday == DateTime.monday) _coachPlans();
    economy.daily(ridden);
    finances.daily(ridden);
    if (!racingOver &&
        calendar.isNotEmpty &&
        !date.isBefore(calendar
            .map((r) => r.end)
            .reduce((a, b) => a.isAfter(b) ? a : b))) {
      _endOfRacing();
    }
    staff.daily();
    equipment.daily();
    facilities.daily();
    camps.daily();
    manager.daily();
    entries.daily();
    if (delegation.scouting && today.month >= 6) staff.scoutOnOwn();
    _tidyInbox(day.inboxBefore);
    today = today.add(const Duration(days: 1));
    return DayReport(date, ridden);
  }

  /// Applies the day's load to every rider: race day, rest day within a race,
  /// or training.
  ///
  /// @param ridden Today's stages.
  void _trainAndRecover(
      List<({RaceProgress race, int stageIndex, StageResult result})> ridden) {
    final raced = <int, double>{};
    for (final r in ridden) {
      final hours = r.result.winnerTimeS / 3600;
      for (final p in r.result.placings) {
        raced[p.rider.id] = 40 + 55 * hours;
      }
    }
    for (final squad in squads.values) {
      for (final r in squad) {
        final s = shapeOf(r.id);
        final load = raced[r.id];
        if (load != null) {
          s.raceDays++;
          s.applyDay(load);
        } else {
          // In a race without a stage: rest day. In a camp: hard. Otherwise training.
          s.applyDay(isInjured(r.id, today)
              ? 25
              : camps.campOf(r.id, today) != null
                  ? 140
                  : isBusy(r.id, today)
                      ? 40
                      : s.load.dailyLoad);
        }
      }
    }
  }

  /// Crashes in races and illness in everyday life.
  ///
  /// @param ridden Today's stages.
  void _incidents(
      List<({RaceProgress race, int stageIndex, StageResult result})> ridden) {
    void sideline(SimRider r, int rawDays, String what, {RaceProgress? race}) {
      // A good team doctor shortens the time out.
      final days = max(
          2,
          (rawDays * staff.doctorFactor(r.teamId) * facilities.layOff(r.teamId))
              .round());
      final until = today.add(Duration(days: days));
      shapeOf(r.id).injuredUntil = until;
      final abandons = race != null && !race.finished;
      if (abandons) race.run.withdraw(r.id);
      if (r.teamId != teamId) return;
      replaceInProgram(r, until);
      inbox.add(Message(
        today,
        tr('Team doctor'),
        tr('{0} is out for {1} days', [r.name, days]),
        tr('{0}. Expected back on {1}.{2}', [
          what,
          dayText(until),
          abandons ? tr(' He had to abandon the race.') : ''
        ]),
        raceId: race?.race.info.id,
      ));
    }

    // Crashes, illness and the time limit come from the simulation of the
    // stage itself.
    final racing = <int>{};
    for (final day in ridden) {
      for (final p in day.result.placings) {
        racing.add(p.rider.id);
      }
      for (final a in day.result.abandons) {
        racing.add(a.rider.id);
        switch (a.reason) {
          case AbandonReason.crash:
            sideline(
                a.rider,
                a.days,
                a.days >= 30
                    ? tr('Heavy crash with several fractures')
                    : a.days >= 14
                        ? tr('Fracture after a crash, the operation went well')
                        : tr('Bruises after a crash'),
                race: day.race);
          case AbandonReason.illness:
            sideline(a.rider, a.days, tr('Infection, a few days off'),
                race: day.race);
          case AbandonReason.timeCut:
            if (a.rider.teamId != teamId) continue;
            inbox.add(Message(
              today,
              tr('Sports director'),
              tr('{0} outside the time limit', [a.rider.name]),
              tr('{0} finished outside the time limit and is out of the race.',
                  [a.rider.name]),
              raceId: day.race.race.info.id,
            ));
        }
      }
      for (final e in day.result.injuries.entries) {
        final r = day.result.placings
            .where((p) => p.rider.id == e.key)
            .firstOrNull
            ?.rider;
        if (r == null || r.teamId != teamId) continue;
        inbox.add(Message(
          today,
          tr('Team doctor'),
          tr('{0} has crashed', [r.name]),
          e.value.formLoss >= 0.02
              ? tr(
                  '{0} crashed and fought his way to the finish. He will be in pain for the next few days.',
                  [r.name])
              : tr('{0} crashed but got away without serious harm.', [r.name]),
          raceId: day.race.race.info.id,
        ));
      }
    }
    for (final r in riderById.values) {
      if (racing.contains(r.id) || isInjured(r.id, today)) continue;
      // Hard training and a body that does not recover make a rider prone
      // to infections and overuse; easy training spares him.
      final s = shapeOf(r.id);
      final risk = 0.0006 *
          switch (s.load) {
            TrainingLoad.low => 0.7,
            TrainingLoad.normal => 1.0,
            TrainingLoad.high => 1.9,
          } *
          (s.freshness < -30
              ? 2.0
              : s.freshness < -15
                  ? 1.4
                  : 1.0) *
          facilities.infections(r.teamId);
      if (_rng.nextDouble() < risk) {
        sideline(
            r,
            3 + _rng.nextInt(8),
            s.freshness < -30
                ? tr('Overtrained and run down, a few days off')
                : tr('Infection, a few days off'));
      }
    }
  }

  /// @param age Age of a rider in years.
  /// @returns Attribute points a rider of that age gains or loses per year
  ///   before potential, training and coaching are applied.
  static double _yearlyStep(int age) => switch (age) {
        <= 19 => 1.5,
        20 => 1.35,
        21 => 1.2,
        22 => 0.85,
        23 => 0.65,
        24 => 0.5,
        25 => 0.3,
        26 => 0.18,
        27 => 0.05,
        <= 29 => 0.0,
        30 => -0.15,
        <= 32 => -0.35,
        <= 34 => -0.7,
        _ => -1.2,
      };

  /// The level a rider's best attributes approach but hardly exceed; it
  /// follows from his potential (6 gives about 87, 4 about 81).
  ///
  /// @param r The rider.
  /// @returns The ceiling on the attribute scale.
  static double ceiling(SimRider r) => 70 + 2.8 * r.potential;

  /// Scales a gain so that an attribute slows down over the last ten points
  /// below the rider's ceiling and stops there.
  ///
  /// @param r The rider.
  /// @param value Current value of the attribute.
  /// @param gain Gain without the ceiling.
  /// @returns The gain that is actually applied.
  static double capped(SimRider r, double value, double gain) =>
      gain <= 0 ? gain : gain * ((ceiling(r) - value) / 10).clamp(0.0, 1.0);

  /// How much faster or slower a rider develops than one of potential 5.
  static double _talent(SimRider r) => ((r.potential - 2) / 3).clamp(0.2, 1.4);

  /// A rider as he was a year earlier: what a year of development at that
  /// age adds with an average coach and normal training, taken off again.
  ///
  /// @param r The rider.
  /// @param age His age during the year that is taken off.
  /// @returns The rider a year younger in his attributes.
  static SimRider yearEarlier(SimRider r, int age) {
    final step = _yearlyStep(age) * _talent(r);
    if (step <= 0) return r;
    var lo = 100.0, hi = 0.0;
    r.attributes.adjusted((_, v) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
      return v;
    });
    return r.withAttributes(r.attributes.adjusted((_, v) {
      final profile = hi == lo ? 1.0 : 0.3 + 0.7 * (v - lo) / (hi - lo);
      return (v - capped(r, v, step * profile)).clamp(50.0, 86.0);
    }));
  }

  /// What a rider can expect over the next twelve months with normal
  /// training and an average coach.
  ///
  /// @param r The rider.
  /// @returns Attribute points per year; negative from the age of 32.
  double outlook(SimRider r) {
    final step = _yearlyStep(year - r.born ~/ 10000);
    if (step <= 0) return step;
    // For his best attribute, which is the one closest to the ceiling.
    var best = 0.0;
    r.attributes.adjusted((_, v) {
      if (v > best) best = v;
      return v;
    });
    return capped(r, best, step * _talent(r));
  }

  /// Attribute history of the player's riders by rider id, one line per
  /// month: `[year * 100 + month, attributes in the order of
  /// Attributes.adjusted]`. The first line is the state when the rider
  /// joined or the career began.
  final growth = <int, List<List<num>>>{};

  /// Form of the player's riders in the running season by rider id, one line
  /// per week: `[day of the year, form, fitness, fatigue]`.
  final formLog = <int, List<List<num>>>{};

  /// Riders whose development is recorded: the player's team and its
  /// development team.
  Iterable<SimRider> get _tracked => [
        ...?squads[teamId],
        if (devTeam.teamId case final dev?) ...?squads[dev],
      ];

  /// Appends this month's attributes of the tracked riders to [growth].
  void _recordGrowth() {
    for (final r in _tracked) {
      final line = <num>[year * 100 + today.month];
      r.attributes.adjusted((_, v) {
        line.add((v * 100).round() / 100);
        return v;
      });
      growth.putIfAbsent(r.id, () => []).add(line);
    }
  }

  /// Appends this week's form of the player's riders to [formLog].
  void _recordForm() {
    final day = today.difference(DateTime.utc(year, 1, 1)).inDays;
    for (final r in squads[teamId] ?? const <SimRider>[]) {
      final s = shapeOf(r.id);
      formLog.putIfAbsent(r.id, () => []).add([
        day,
        (s.form * 1000).round() / 1000,
        s.fitness.round(),
        s.fatigue.round(),
      ]);
    }
  }

  /// Monthly development: young riders with potential improve, from 32 on
  /// they decline. The training focus steers which attributes grow.
  void _develop() {
    for (final squad in squads.values) {
      for (var i = 0; i < squad.length; i++) {
        final r = squad[i];
        final perYear = _yearlyStep(year - r.born ~/ 10000);
        if (perYear == 0) continue;
        final s = shapeOf(r.id);
        final load = switch (s.load) {
          TrainingLoad.low => 0.8,
          TrainingLoad.normal => 1.0,
          TrainingLoad.high => 1.15,
        };
        // The development team works with the coaches of the professional team.
        final coach = r.teamId == devTeam.teamId
            ? max(staff.coachFactor(r.teamId), staff.coachFactor(teamId))
            : staff.coachFactor(r.teamId);
        final step = perYear > 0
            ? perYear /
                12 *
                _talent(r) *
                load *
                coach *
                people.growthFactor(r.id) *
                people.mentorFactor(r.id) *
                facilities.development(r.teamId) *
                // A development team grows with the academy of its parent.
                _academy(r.teamId)
            : perYear / 12;
        final focus = s.focus.attributes;
        // A rider grows where he is already strong: his best attribute at
        // the full rate, his weakest at under a third of it.
        var lo = 100.0, hi = 0.0;
        r.attributes.adjusted((_, v) {
          if (v < lo) lo = v;
          if (v > hi) hi = v;
          return v;
        });
        final updated = r.withAttributes(r.attributes.adjusted((name, v) {
          if (step > 0) {
            final profile = hi == lo ? 1.0 : 0.3 + 0.7 * (v - lo) / (hi - lo);
            final training = focus.isEmpty
                ? 1.0
                : focus.contains(name)
                    ? 1.4
                    : 0.85;
            return (v + capped(r, v, step * profile * training))
                .clamp(50.0, 86.0);
          }
          // Explosiveness goes first, endurance last.
          final factor = name == 'sprint' || name == 'acceleration'
              ? 1.5
              : name == 'endurance'
                  ? 0.5
                  : 1.0;
          return (v + step * factor).clamp(50.0, 86.0);
        }));
        squad[i] = updated;
        riderById[r.id] = updated;
      }
    }
  }

  /// Closes the season and starts the next: rankings and race days start
  /// over, riders keep their development.
  void startNextSeason() {
    _archiveSeason();
    _awards(message: !racingOver);
    racingOver = false;
    people.closeSeason();
    staff.closeSeason();
    licences.noteSeason();
    finances.closeSeason();
    economy.closeSeason();
    equipment.closeSeason();
    licences.closeSeason();
    // Teams that moved up now need the squad of their new licence: they
    // fill it from the riders without a team.
    economy.refill();
    history.add((
      year: year,
      points: teamPoints[teamId] ?? 0,
      rank: rankingPlaces()[teamId] ?? 0,
    ));
    final newTeam = manager.closeSeason();
    year++;
    today = DateTime.utc(year, 1, 1);
    progress.clear();
    formLog.clear();
    devTeam.stagiaires.clear();
    riderPoints.clear();
    teamPoints.clear();
    breakDays.clear();
    combative.clear();
    ownPlans.clear();
    ownWishes.clear();
    captains.clear();
    tttWait.clear();
    program.clear();
    teamPrograms.clear();
    _pending.clear();
    _skipped.clear();
    _busyUntil.clear();
    _fields.clear();
    _invited.clear();
    entries.reset();
    _twinCache = null;
    // Camps of the winter run on; those over for four weeks are forgotten.
    camps.all.removeWhere(
        (k) => k.closed && today.difference(k.end) > const Duration(days: 28));
    for (final s in staff.all) {
      s
        ..busyUntil = null
        ..atRace = null;
    }
    for (final s in shape.values) {
      s.raceDays = 0;
      s.grandTours = 0;
      s.lastGrandTourEnd = null;
    }
    if (newTeam != null) _switchTeam(newTeam);
    _strength.clear();
    _assignStyles();
    _buildCalendar();
    _ownRaces = null;
    planner.reset();
    economy.openSeason();
    manager.openSeason();
    people.pairOthers();
    _applyNextPlan();
    inbox.add(Message(
      today,
      tr('Board'),
      tr('Season {0} begins', [year]),
      tr('We finished the {0} season in place {1} of the team ranking with {2} points.',
          [year - 1, history.last.rank, history.last.points.round()]),
    ));
  }

  /// Hands the player over to another team at the turn of the year. The
  /// old team keeps its riders, staff, money, facilities and development
  /// team and goes on as a team the player does not run; the new one brings
  /// its own. What belonged to the player's work with the old riders ends:
  /// promises, roles, talks, scouting jobs, booked camps, offers to riders,
  /// material choices and the sponsors' offers.
  ///
  /// @param to Id of the new team.
  void _switchTeam(int to) {
    final from = teamId;
    final books = finances.handOver(from, to);
    facilities.handOver(from);
    teamId = to;
    economy.takeOver(books);
    people.handOver();
    staff.handOver();
    equipment.handOver();
    camps.all.removeWhere((k) => !k.closed);
    devTeam.teamId = devTeam.links[to];
    lineupTemplates.clear();
    lastLineups.clear();
    nextProgram.clear();
    nextGoals.clear();
    ownStyle = null;
    inbox.add(Message(
      today,
      tr('Board'),
      tr('Welcome to {0}', [teams[to]!.name]),
      tr('You have taken over {0} from {1}. The riders, staff, money and sponsors of the team are yours now; the board sets its goals for the season.',
          [teams[to]!.name, teams[from]!.name]),
    ));
  }

  /// Mean strength of a team's eight best riders, used for invitations.
  ///
  /// @param team Team id.
  /// @returns The strength on the attribute scale.
  double teamStrength(int team) => _teamStrength(team);

  /// A rider joined a team during the season: its strength is measured
  /// anew.
  ///
  /// @param team Id of the team.
  void teamJoined(int team) => _strength.remove(team);

  double _teamStrength(int team) => _strength.putIfAbsent(team, () {
        final best = [
          for (final r in squads[team] ?? const <SimRider>[]) _overall(r)
        ]..sort((a, b) => b.compareTo(a));
        if (best.isEmpty) return 0;
        final top = best.take(8);
        return top.reduce((a, b) => a + b) / top.length;
      });

  /// @param r A rider.
  /// @returns His highest main attribute.
  static double _overall(SimRider r) {
    final a = r.attributes;
    return [a.flat, a.mountain, a.hill, a.timeTrial, a.sprint, a.cobble]
        .reduce(max);
  }

  /// Teams invited to a race before the player withdraws or applies: the
  /// invitations of the WorldDB, otherwise a selection by race tier.
  ///
  /// @param race The race.
  /// @returns Team ids.
  List<int> invitedTeams(RaceEntry race) =>
      _invited.putIfAbsent(race.info.id, () {
        if (race.tier == RaceTier.championship) return const [];
        final field = _fieldBase(race);
        return custom != null &&
                !field.contains(teamId) &&
                field.contains(_twin)
            ? [...field, teamId]
            : field;
      });
  final _invited = <int, List<int>>{};

  /// @param race A race.
  /// @returns Whether the player's team is invited to it.
  bool isInvited(RaceEntry race) => invitedTeams(race).contains(teamId);

  /// Recomputes the field of a race after a withdrawal, a re-entry or a wildcard.
  ///
  /// @param raceId Id of the race.
  void refreshEntries(int raceId) {
    _fields.remove(raceId);
    _pending.remove(raceId);
    _ownRaces = null;
  }

  List<int> _field(RaceEntry race) => _fields.putIfAbsent(
      race.info.id, () => entries.adjust(race, invitedTeams(race)));

  /// Invited teams from the WorldDB, or a selection by tier if it names none.
  ///
  /// @param race The race.
  /// @returns Team ids.
  List<int> _fieldBase(RaceEntry race) {
    final invited = world.raceField(race.info.id).teams;
    if (invited.isNotEmpty) return licences.field(invited, race.tier);
    List<int> sorted(List<int> ids) =>
        ids..sort((a, b) => _teamStrength(b).compareTo(_teamStrength(a)));
    List<int> division(String prefix) => sorted([
          for (final t in teams.values)
            if (t.division.startsWith(prefix)) t.id,
        ]);
    // A different selection per race, but always the same for the same seed.
    List<int> pick(List<int> from, int count, {bool best = false}) {
      if (best) return from.take(count).toList();
      final shuffled = [...from]..shuffle(Random(seed * 7919 + race.info.id));
      return shuffled.take(count).toList();
    }

    // Smaller teams mostly race in their own country.
    List<int> local(List<int> from, int count) {
      final home = [
        for (final id in from)
          if (teams[id]!.country == race.info.country) id,
      ];
      final rest = pick([
        for (final id in from)
          if (!home.contains(id)) id,
      ], count);
      return [...home, ...rest].take(count).toList();
    }

    final wt = sorted(licences.teamsWith(Licence.worldTour));
    final pro = sorted(licences.teamsWith(Licence.pro));
    final conti = sorted(licences.teamsWith(Licence.continental));
    final u23 = division('Under23');
    return switch (race.tier) {
      RaceTier.grandTour || RaceTier.monument || RaceTier.worldTour => [
          ...wt,
          ...{...licences.wildcards, ...pick(pro, 5, best: true)}.take(5),
        ],
      RaceTier.proSeries => [...pick(wt, 9), ...pro, ...local(conti, 2)],
      RaceTier.class1 => [...pick(wt, 5), ...pick(pro, 11), ...local(conti, 6)],
      RaceTier.class2 => [...pick(pro, 3), ...local(conti, 19)],
      RaceTier.under23 => [...local(u23, 18), ...local(conti, 4)],
      RaceTier.championship => const [],
    };
  }

  /// Riders available for a race. For the other teams there are additional
  /// rules that make for a sensible programme: nobody starts completely
  /// drained, with too many race days or in more than two Grand Tours.
  ///
  /// @param team Team id.
  /// @param race The race.
  /// @returns The available riders.
  List<SimRider> _free(int team, RaceEntry race) {
    final grandTour = race.tier == RaceTier.grandTour;
    bool ready(SimRider r) =>
        !isBusy(r.id, race.start) &&
        !camps.blocks(r.id, race.start, race.end) &&
        (team == teamId || _fitToStart(shapeOf(r.id), race, grandTour));
    return [
      for (final r in squads[team] ?? const <SimRider>[])
        if (ready(r)) r,
      // Trainees from the team's own development team ride in its colours.
      if (DevTeam.allows(race.tier))
        for (final r in devTeam.stagiairesOf(team, race.start))
          if (ready(r)) r.withTeam(team, teams[team]?.abbr ?? ''),
    ];
  }

  /// @param s Condition of a rider.
  /// @param race The race.
  /// @param grandTour Whether the race is a Grand Tour.
  /// @returns Whether an AI team would send him.
  bool _fitToStart(RiderShape s, RaceEntry race, bool grandTour) {
    if (s.freshness < -40 || s.raceDays >= 80) return false;
    if (!grandTour) return true;
    if (s.grandTours >= 2) return false;
    final last = s.lastGrandTourEnd;
    return last == null || race.start.difference(last).inDays > 30;
  }

  /// Picks a line-up by suitability: whoever fits at least some stages best.
  ///
  /// @param available Riders to choose from.
  /// @param routes Stages of the race.
  /// @param size Number of riders wanted.
  /// @returns The line-up.
  List<SimRider> _bestLineup(
      List<SimRider> available, List<SimRoute> routes, int size) {
    double score(SimRider r) {
      final fits = [
        for (final route in routes) suitability(route, r.attributes)
      ]..sort((a, b) => b.compareTo(a));
      final top = fits.take(min(3, fits.length));
      return top.reduce((a, b) => a + b) / top.length;
    }

    final scored = {for (final r in available) r: score(r)};
    return ([...available]..sort((a, b) => scored[b]!.compareTo(scored[a]!)))
        .take(size)
        .toList();
  }

  /// Puts together the line-ups of the other teams and the suggestion for
  /// the player's own.
  ///
  /// @param race The race.
  /// @returns The race, ready for the player's decision.
  PendingRace _prepare(RaceEntry race, {bool withOwn = false}) {
    if (race.tier == RaceTier.championship) return _prepareChampionship(race);
    final routes = [for (final s in race.stages) world.route(s.id)];
    final size = world.raceField(race.info.id).ridersPerTeam;
    final others = <SimRider>[];
    var own = const <SimRider>[];
    // A trainee rides for the professional team; his development team, if
    // it starts in the same race, has to do without him.
    final field = [
      ..._field(race),
      // A single race outside the season: the player's team starts anyway.
      if (withOwn && !_field(race).contains(teamId)) teamId,
    ];
    final lent = <int>{
      if (DevTeam.allows(race.tier))
        for (final team in field)
          for (final r in devTeam.stagiairesOf(team, race.start)) r.id,
    };
    for (final team in field) {
      final available = _free(team, race)
        ..removeWhere(
            (r) => lent.contains(r.id) && riderById[r.id]?.teamId == team);
      if (team == teamId) {
        own = available;
        continue;
      }
      if (available.length < 4) continue;
      // Whoever the team's sports director planned for the race and is fit
      // to start; the best-suited of the others fill the gaps.
      final planned = teamPrograms[team]?[race.info.id] ?? const <int>{};
      final lineup = [
        for (final r in available)
          if (planned.contains(r.id)) r,
      ].take(size).toList();
      if (lineup.length < size) {
        lineup.addAll(_bestLineup([
          for (final r in available)
            if (!planned.contains(r.id)) r,
        ], routes, size - lineup.length));
      }
      others.addAll(lineup);
    }
    // Own suggestion: first the riders pencilled in in the season plan, then
    // fill up with the best-suited.
    final planned = program[race.info.id] ?? const <int>{};
    final suggestion = [
      for (final r in own)
        if (planned.contains(r.id)) r,
    ].take(size).toList();
    // The sports director rests drained riders just like the other teams do.
    final grandTour = race.tier == RaceTier.grandTour;
    final rested = [
      for (final r in own)
        if (_fitToStart(shapeOf(r.id), race, grandTour)) r,
    ];
    for (final r in [
      ..._bestLineup(rested, routes, size),
      ..._bestLineup(own, routes, size),
    ]) {
      if (suggestion.length >= size) break;
      if (!suggestion.contains(r)) suggestion.add(r);
    }
    final sprintStart = routes.first.sprintStage;
    final directors = staff.availableDirectors(teamId, race.start)
      ..sort((a, b) => b
          .raceSkill(race, sprintStart: sprintStart)
          .compareTo(a.raceSkill(race, sprintStart: sprintStart)));
    return PendingRace(race, routes, others, own, suggestion, size, directors);
  }

  /// Puts a race together as the season would: the line-ups of all teams
  /// and the suggestion for the player's, who starts even if the race did
  /// not invite him. For a single race outside the season.
  ///
  /// @param race The race.
  /// @returns The race, ready for the player's decision.
  PendingRace prepareSingle(RaceEntry race) => _prepare(race, withOwn: true);

  /// Starts a race: ties up riders and directors and creates the race run.
  ///
  /// @param pending The prepared race.
  /// @param ownLineup Riders of the player's team, empty if it does not start.
  /// @param directorId Sports director the player wants in the car.
  void _launch(PendingRace pending, List<SimRider> ownLineup,
      {int? directorId}) {
    final race = pending.race;
    final id = race.info.id;
    _pending.remove(id);
    // The line-ups of all races of a day are drawn up before the first one
    // starts. A rider who has started elsewhere since must not start twice:
    // then the other teams choose again, and the player's line-up loses him.
    bool taken(SimRider r) => _busyUntil[r.id]?.isAfter(race.start) ?? false;
    final others =
        pending.others.any(taken) ? _prepare(race).others : pending.others;
    ownLineup = [
      for (final r in ownLineup)
        if (!taken(r)) r,
    ];
    final riders = [...others, ...ownLineup];
    if (riders.length < 20) {
      _skipped.add(id);
      return;
    }
    final free = race.end.add(Duration(days: race.isStageRace ? 4 : 1));
    for (final r in riders) {
      _busyUntil[r.id] = free;
      if (race.tier == RaceTier.grandTour) {
        shapeOf(r.id)
          ..grandTours += 1
          ..lastGrandTourEnd = race.end;
      }
    }
    if (ownLineup.isNotEmpty) {
      inbox.add(Message(
        today,
        tr('Sports director'),
        tr('Line-up for {0}', [race.info.name]),
        tr('At the start: {0}.', [ownLineup.map((r) => r.name).join(', ')]),
        raceId: id,
      ));
    }
    // Every team puts a sports director in the car. His quality acts in the
    // race, his motivation on the riders' form.
    final sprintStart = pending.routes.first.sprintStage;
    final skills = <int, double>{};
    final motivation = <int, int>{};
    Staff? ownDirector;
    final championship = race.tier == RaceTier.championship;
    for (final team in {for (final r in riders) r.teamId}) {
      if (championship) {
        // No team car of the trade team: an average director everywhere.
        motivation[team] = 12;
        continue;
      }
      final seat = staff.seat(team, race, sprintStart,
          wanted: team == teamId ? directorId : null);
      // The road captain carries the plan out on the road: a good one
      // makes up for some of what the car cannot see.
      final crew = [
        for (final r in riders)
          if (r.teamId == team) r,
      ];
      final chosen = team == teamId ? captains[id] : null;
      final captain = crew.where((r) => r.id == chosen).firstOrNull ??
          people.bestCaptain(crew);
      skills[team] = (seat.skill +
              (captain == null
                  ? 0
                  : 0.3 * (people.captainSkill(captain.id) - 0.5)))
          .clamp(0.0, 1.0);
      motivation[team] = seat.motivation;
      if (team == teamId) ownDirector = seat.staff;
    }
    progress[id] = RaceProgress(
      race,
      riders,
      StageRaceRun(riders,
          seed: _raceSeed(id),
          year: year,
          tuning: tuning,
          scheme: world.scheme(id),
          oneDay: !race.isStageRace,
          month: race.start.month,
          country: race.info.country,
          baseForm: {
            for (final r in riders)
              r.id: shapeOf(r.id).form *
                  camps.peak(r.id, race.start) *
                  people.formFactor(r, id) *
                  (1 + 0.006 * (motivation[r.teamId]! / 20 - 0.6)),
          }),
      skills,
      ownDirector,
    );
  }

  /// Credits ranking points to a rider and his team.
  ///
  /// @param r The rider.
  /// @param points Points to add.
  void _add(SimRider r, double points) {
    if (points <= 0) return;
    // In a national selection the points count for the trade team.
    final team = riderById[r.id]?.teamId ?? r.teamId;
    riderPoints[r.id] = (riderPoints[r.id] ?? 0) + points;
    teamPoints[team] = (teamPoints[team] ?? 0) + points;
  }

  /// Credits ranking points and reports to the player's team.
  ///
  /// @param p The race.
  /// @param index Zero-based index of the stage just ridden.
  /// @param result Its result.
  void _credit(RaceProgress p, int index, StageResult result) {
    final race = p.race;
    people.afterStage(p, index, result);
    _countBreak(result);
    final own = result.placings.indexWhere((x) => _isOwn(x.rider));
    final winner = result.placings.first.rider;
    final tier = _pointsTier(race);
    final championship = race.tier == RaceTier.championship;
    if (race.isStageRace) {
      for (var i = 0; i < 3 && i < result.placings.length; i++) {
        _add(result.placings[i].rider, stagePoints(tier, i));
      }
    }
    if (championship) {
      titles.add((year: year, race: race.info.name, riderId: winner.id));
    }
    if (race.isStageRace) _honour(winner, race, tr('Stage {0}', [index + 1]));
    if (p.finished) {
      final gc = p.run.standings.last.general;
      final order = race.isStageRace
          ? [for (final e in gc) e.rider]
          : [for (final x in result.placings) x.rider];
      if (!race.isStageRace) {
        _honour(order.first, race, tr('Win'));
      } else {
        for (var i = 0; i < 3 && i < order.length; i++) {
          _honour(order[i], race,
              i == 0 ? tr('Overall win') : tr('{0}. overall', [i + 1]));
        }
      }
      for (var i = 0; i < 10 && i < order.length; i++) {
        _add(order[i], finalPoints(tier, i));
      }
    }
    if (own < 0) return;
    // Report national championships only if it was good enough for the podium.
    if (championship && race.info.raceClass.startsWith('National') && own > 2) {
      return;
    }
    final best = result.placings[own].rider;
    final stageLabel = race.isStageRace ? tr(', stage {0}', [index + 1]) : '';
    var body = own == 0
        ? championship
            ? tr(
                '{0} takes the title and wears the champion\'s jersey for a year.',
                [
                    best.name
                  ])
            : tr('{0} wins for us.', [best.name])
        : tr('Winner: {0} ({1}). Our best: {2} in place {3}.',
            [winner.name, winner.team, best.name, own + 1]);
    // Our rider of the stage may no longer be in the general
    // classification, for example outside the time limit.
    final gc =
        race.isStageRace ? p.run.standings.last.general : const <TimeEntry>[];
    final place = gc.indexWhere((e) => e.rider.teamId == teamId);
    if (race.isStageRace && place >= 0) {
      body += p.finished
          ? tr(' {0} wins {1}, {2} finishes {3}.', [
              gc.first.rider.name,
              race.info.name,
              gc[place].rider.name,
              place + 1
            ])
          : tr(' General classification: {0} in place {1}.',
              [gc[place].rider.name, place + 1]);
    }
    inbox.add(Message(
      today,
      tr('Race report'),
      '${race.info.name}$stageLabel: '
      '${own == 0 ? tr('Win') : tr('Place {0}', [own + 1])}',
      body,
      raceId: id(race),
    ));
  }

  /// @param race A race.
  /// @returns Its id.
  static int id(RaceEntry race) => race.info.id;

  // --- Honours and archive ----------------------------------------------------

  /// Wins and overall podiums per rider id, oldest first. Each entry is
  /// `[year, race name, what, tier index]`.
  final palmares = <int, List<List<dynamic>>>{};

  /// Finished seasons, oldest first: rankings, winners of the big races and
  /// the result of the player's team, as plain JSON-style maps.
  final archive = <Map<String, dynamic>>[];

  /// Season lines per rider id: `[year, team, points, wins, race days]`.
  final riderSeasons = <int, List<List<dynamic>>>{};

  /// Records a win or overall podium.
  ///
  /// @param r The rider.
  /// @param race The race.
  /// @param what Text such as "Win" or "Stage 3".
  void _honour(SimRider r, RaceEntry race, String what) => palmares
      .putIfAbsent(r.id, () => [])
      .add([year, race.info.name, what, race.tier.index]);

  /// @param riderId Id of a rider.
  /// @param inYear A season.
  /// @returns His number of wins (races, stages, overall) in that season.
  int winsOf(int riderId, int inYear) => (palmares[riderId] ?? const [])
      .where((p) =>
          p[0] == inYear &&
          !(p[2] as String).contains('overall') &&
          !(p[2] as String).contains('. overall'))
      .length;

  /// Championship titles a rider currently holds (won this season, or last
  /// season while this year's race has not been ridden yet).
  ///
  /// @param riderId Id of the rider.
  /// @returns The names of the championships.
  List<String> titlesHeld(int riderId) {
    final thisYear = {
      for (final t in titles)
        if (t.year == year) t.race,
    };
    return [
      for (final t in titles)
        if (t.riderId == riderId &&
            (t.year == year ||
                (t.year == year - 1 && !thisYear.contains(t.race))))
          t.race,
    ];
  }

  /// Riders who ended their careers, oldest first:
  /// `[id, full name, country, year of birth, last team, year]`. Their
  /// palmarès and seasons stay in [palmares] and [riderSeasons].
  final retired = <List<dynamic>>[];

  /// Notes a rider who ends his career, if he ever won or scored.
  ///
  /// @param r The rider.
  void noteRetired(SimRider r) {
    final seasons = riderSeasons[r.id];
    if (seasons == null && palmares[r.id] == null) return;
    retired.add([
      r.id,
      fullName(r.id),
      r.country,
      r.born ~/ 10000,
      seasons?.last[1] ?? r.team,
      year,
    ]);
  }

  /// The player's riders in each race of the last season, by race id, for
  /// "line-up of last year".
  final lastLineups = <int, List<int>>{};

  /// What speaks against a line-up before it is confirmed: places left
  /// empty, a leader who races too often, sprint stages without a
  /// sprinter, tired riders and riders with too many race days.
  ///
  /// @param race The race.
  /// @param lineup The chosen riders.
  /// @param size Places the team has.
  /// @returns The warnings, empty if there is nothing to say.
  List<String> lineupWarnings(RaceEntry race, List<SimRider> lineup, int size) {
    final out = <String>[];
    if (lineup.length < size) {
      out.add(tr('Only {0} of {1} places are taken.', [lineup.length, size]));
    }
    if (lineup.isNotEmpty) {
      final leader = lineup.reduce(
          (a, b) => planner.fit(race, b) > planner.fit(race, a) ? b : a);
      final since = race.start.subtract(const Duration(days: 9));
      final recent = progress.values
          .where((p) =>
              !p.race.start.isBefore(since) &&
              p.race.start.isBefore(race.start) &&
              p.riders.any((r) => r.id == leader.id))
          .length;
      if (recent >= 2) {
        out.add(tr('{0}, the leader, would ride his third race in nine days.',
            [leader.name]));
      }
    }
    final sprints =
        race.stages.where((s) => world.route(s.id).sprintStage).length;
    if (sprints > 0 && !lineup.any((r) => r.attributes.sprint >= 74)) {
      out.add(tr(
          'No sprinter, although {0} stages are likely to end in a bunch sprint.',
          [sprints]));
    }
    // A hot or a cold day: riders who cope badly with it.
    final forecast = forecastOf(race);
    if (forecast != null &&
        (forecast.temperatureC > 28 || forecast.temperatureC < 6)) {
      final hot = forecast.temperatureC > 28;
      final poor = [
        for (final r in lineup)
          if ((hot ? heatFactor(r) : coldFactor(r)) > 1.15) r.name,
      ];
      if (poor.isNotEmpty) {
        out.add(tr(
            hot
                ? '{0} °C are forecast; {1} cope badly with the heat.'
                : '{0} °C are forecast; {1} cope badly with the cold.',
            [forecast.temperatureC.round(), poor.join(', ')]));
      }
    }
    for (final r in lineup) {
      final s = shapeOf(r.id);
      if (s.freshness < -20) {
        out.add(
            tr('{0} is tired (freshness {1}).', [r.name, s.freshness.round()]));
      }
      final days = s.raceDays + race.stages.length;
      if (days > 85) {
        out.add(tr('{0} would reach {1} race days.', [r.name, days]));
      }
    }
    return out;
  }

  /// Stores the finished season in [archive] and [riderSeasons]. Runs before
  /// transfers happen, so team names are those of the season.
  void _archiveSeason() {
    lastLineups
      ..clear()
      ..addAll({
        for (final p in progress.values)
          if (p.riders.any((r) => r.teamId == teamId))
            p.race.info.id: [
              for (final r in p.riders)
                if (r.teamId == teamId) r.id,
            ],
      });
    final teamRanking = teamPoints.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final riderRanking = riderPoints.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final winners = <List<dynamic>>[];
    for (final p in progress.values) {
      final national = p.race.info.raceClass.startsWith('National');
      final big = p.race.tier.factor >= 5 ||
          (p.race.tier == RaceTier.championship && !national);
      if (!p.finished || !big) continue;
      final w = p.race.isStageRace
          ? p.run.standings.last.general.first.rider
          : p.run.results.last.placings.first.rider;
      winners.add([
        p.race.info.name,
        p.race.tier.label,
        fullName(w.id),
        riderById[w.id]?.team ?? w.team,
      ]);
    }
    archive.add({
      'year': year,
      'teams': [
        for (final e in teamRanking.take(25))
          [e.key, teams[e.key]?.name ?? '?', e.value],
      ],
      'riders': [
        for (final e in riderRanking.take(25))
          [e.key, fullName(e.key), riderById[e.key]?.team ?? '', e.value],
      ],
      'winners': winners,
      'own': {
        'rank': teamRanking.indexWhere((e) => e.key == teamId) + 1,
        'points': teamPoints[teamId] ?? 0,
        'wins': economy.wins,
      },
    });
    for (final r in riderById.values) {
      final points = riderPoints[r.id] ?? 0;
      final days = shape[r.id]?.raceDays ?? 0;
      if (points <= 0 && !(r.teamId == teamId && days > 0)) continue;
      riderSeasons
          .putIfAbsent(r.id, () => [])
          .add([year, r.team, points, winsOf(r.id, year), days]);
    }
  }

  // --- Snapshot ---------------------------------------------------------------
  // A save stores the complete state of the career. Riders are shared between
  // squads and races and change over time, so every rider object is written
  // once into a pool and referenced by its position there.
  static int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;
  static DateTime? _date(Object? ms) => ms == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);
  static List<dynamic> _riderJson(SimRider r) {
    final a = r.attributes;
    return [
      r.id, r.name, r.teamId, r.team, r.born, r.potential, r.country, //
      r.contractEnd, a.flat, a.mountain, a.mediumMountain, a.hill,
      a.timeTrial, a.prologue, a.cobble, a.sprint, a.acceleration, a.downhill,
      a.endurance, a.resistance, a.recovery, a.breakaway, //
      r.weightKg, r.heightCm,
    ];
  }

  static SimRider _rider(List<dynamic> j) {
    double d(int i) => (j[i] as num).toDouble();
    return SimRider(
      id: j[0] as int,
      name: j[1] as String,
      teamId: j[2] as int,
      team: j[3] as String,
      born: j[4] as int,
      potential: d(5),
      country: j[6] as String,
      contractEnd: j[7] as int,
      attributes: Attributes(
        flat: d(8),
        mountain: d(9),
        mediumMountain: d(10),
        hill: d(11),
        timeTrial: d(12),
        prologue: d(13),
        cobble: d(14),
        sprint: d(15),
        acceleration: d(16),
        downhill: d(17),
        endurance: d(18),
        resistance: d(19),
        recovery: d(20),
        breakaway: d(21),
      ),
      // Saves before version 0.3.0 hold no weight and height.
      weightKg: j.length > 22 ? d(22) : 0,
      heightCm: j.length > 23 ? d(23) : 0,
    );
  }

  /// Serialises one race on its own, with its riders as they were at the
  /// time. Races are stored separately from the rest of the career because
  /// a finished race never changes again and need not be written twice.
  ///
  /// @param p The race.
  /// @returns A JSON-encodable map; [restore] reads it back.
  Map<String, dynamic> raceJson(RaceProgress p) {
    final pool = <SimRider>[];
    final index = Map<SimRider, int>.identity();
    int ref(SimRider r) => index.putIfAbsent(r, () {
          pool.add(r);
          return pool.length - 1;
        });
    final j = <String, dynamic>{
      'race': p.race.info.id,
      'riders': [for (final r in p.riders) ref(r)],
      'run': p.run.toJson(ref),
      'dir': {
        for (final e in p.directorSkills.entries) '${e.key}': e.value,
      },
      'own': p.ownDirector?.id,
    };
    j['pool'] = [for (final r in pool) _riderJson(r)];
    return j;
  }

  /// Version of the save format. [restore] brings older snapshots up to it
  /// step by step, so that a save opens in every later version.
  static const saveVersion = 4;

  /// The steps of the save format, by the version they start from. Each
  /// turns a snapshot of version n into one of n + 1, giving what that
  /// version added the value a career had before it.
  static final _migrations = <int, void Function(Map<String, dynamic>)>{
    // 0.5.0: the manager's career, the job market, the plan for the next
    // season and the delegation held during a run.
    1: (j) {
      (j['delegation'] as Map<String, dynamic>)
          .putIfAbsent('jobMarket', () => false);
      j.putIfAbsent('nextProgram', () => <String, dynamic>{});
      j.putIfAbsent('nextGoals', () => <String, dynamic>{});
    },
    // 0.6.0: nothing in the snapshot changes; a founded team is repaired
    // after loading (see [restore]).
    2: (j) {},
    // 0.6.0: two facilities can be built at the same time.
    3: (j) {
      if (j['facilities'] case final Map<String, dynamic> f) {
        final one = f.remove('building');
        f['builds'] = [if (one != null) one];
      }
    },
  };

  /// Brings a snapshot up to [saveVersion].
  ///
  /// @param j A map written by [toJson] of this or an earlier version; it is
  ///   changed in place.
  /// @throws FormatException for a snapshot of a newer version.
  static void migrate(Map<String, dynamic> j) {
    var v = j['version'] as int? ?? 1;
    if (v > saveVersion) {
      throw FormatException(
          tr('The save comes from a newer version of the game.'));
    }
    while (v < saveVersion) {
      _migrations[v]!(j);
      v++;
      j['version'] = v;
    }
  }

  /// Serialises the career without its races; see [raceJson] for those.
  ///
  /// @returns A JSON-encodable map; [restore] reads it back.
  Map<String, dynamic> toJson() {
    final pool = <SimRider>[];
    final index = Map<SimRider, int>.identity();
    int ref(SimRider r) => index.putIfAbsent(r, () {
          pool.add(r);
          return pool.length - 1;
        });
    Map<String, dynamic> ints<T>(Map<int, T> m, [Object? Function(T)? f]) => {
          for (final e in m.entries)
            '${e.key}': f == null ? e.value : f(e.value)
        };
    final j = <String, dynamic>{
      'version': saveVersion,
      'team': teamId,
      'manager': manager.toJson(),
      'year': year,
      'today': _ms(today),
      'rng': _rng.state,
      'riders': [for (final r in riderById.values) ref(r)],
      'squads': [
        for (final e in squads.entries)
          [
            e.key,
            [for (final r in e.value) ref(r)],
          ],
      ],
      'names': ints(fullNames),
      'history': [
        for (final h in history) [h.year, h.points, h.rank],
      ],
      'racingOver': racingOver,
      'riderPoints': ints(riderPoints),
      'retired': retired,
      'lineupTemplates': lineupTemplates,
      'captains': ints(captains),
      'tttWait': tttWait.toList(),
      'breakDays': ints(breakDays),
      'combative': ints(combative),
      'templates': [
        for (final t in ownTemplates) [t.key, t.races],
      ],
      'teamPoints': ints(teamPoints),
      'inbox': [
        for (final m in inbox)
          [
            _ms(m.date),
            m.from,
            m.subject,
            m.body,
            m.raceId,
            m.read,
            m.talk?.toJson()
          ],
      ],
      'ownPlans': ints<TeamPlan>(ownPlans, (p) => p.toJson()),
      'ownWishes': ints<PlanWish>(ownWishes, (w) => w.toJson()),
      'program': ints<Set<int>>(program, (s) => s.toList()),
      'nextProgram': ints<Set<int>>(nextProgram, (s) => s.toList()),
      'nextGoals': ints<Set<int>>(nextGoals, (s) => s.toList()),
      'teamPrograms': ints<Map<int, Set<int>>>(
          teamPrograms, (m) => ints<Set<int>>(m, (s) => s.toList())),
      'people': people.toJson(),
      'watch': watch.toList(),
      'muted': mutedTopics.toList(),
      'digest': inboxDigest,
      'notes': ints<String>(notes, (s) => s),
      'shape': ints<RiderShape>(
          shape,
          (s) => [
                s.fitness,
                s.fatigue,
                s.raceDays,
                s.grandTours,
                _ms(s.lastGrandTourEnd),
                s.load.index,
                s.focus.index,
                _ms(s.injuredUntil),
              ]),
      'busy': ints<DateTime>(_busyUntil, _ms),
      'skipped': _skipped.toList(),
      // The fields are fixed when first asked for; recomputing them after a
      // load could invite other teams, because team strengths have moved.
      'fields': ints(_fields),
      'strength': ints(_strength),
      'radio': ints<Map<RadioKind, int>>(
          _radio, (m) => {for (final e in m.entries) e.key.name: e.value}),
      'orders': ints<List<TimedOrder>>(
          _orders, (l) => [for (final o in l) o.toJson()]),
      'delegation': delegation.toJson(),
      if (heldDelegation case final held?) 'heldDelegation': held,
      'titles': [
        for (final t in titles) [t.year, t.race, t.riderId],
      ],
      'palmares': ints(palmares),
      'archive': archive,
      'riderSeasons': ints(riderSeasons),
      'growth': ints(growth),
      'formLog': ints(formLog),
      'economy': economy.toJson(),
      'staff': staff.toJson(),
      'equipment': equipment.toJson(),
      'facilities': facilities.toJson(),
      'finances': finances.toJson(),
      'lastLineups': ints<List<int>>(lastLineups, (l) => l),
      'styles': ints<TeamStyle>(styles, (s) => s.index),
      if (ownStyle != null) 'ownStyle': ownStyle!.index,
      'licences': licences.toJson(),
      'dev': devTeam.teamId,
      'stagiaires': devTeam.stagiaires.toList(),
      if (devTeam.founded case final t?) 'devParent': devTeam.parentOf(t.id),
      'devFounded': switch (devTeam.founded) {
        final t? => [
            t.id, t.name, t.abbr, t.division, t.country, t.color, t.color2, //
          ],
        null => null,
      },
      'camps': camps.toJson(),
      'entries': entries.toJson(),
    };
    // Last, when every reference has been handed out.
    j['pool'] = [for (final r in pool) _riderJson(r)];
    return j;
  }

  /// Puts the career into the state of a snapshot. Call on a career that was
  /// created for the same team and seed.
  ///
  /// @param j A map written by [toJson].
  /// @param races The races of the season, each written by [raceJson], in
  ///   the order they were started.
  void restore(Map<String, dynamic> j, Iterable<Map<String, dynamic>> races) {
    final from = j['version'] as int? ?? 1;
    migrate(j);
    final pool = [
      for (final r in (j['pool'] as List).cast<List<dynamic>>()) _rider(r),
    ];
    Map<int, T> ints<T>(String key, T Function(dynamic) f) => {
          for (final e in (j[key] as Map<String, dynamic>).entries)
            int.parse(e.key): f(e.value),
        };
    double d(dynamic v) => (v as num).toDouble();

    year = j['year'] as int;
    today = _date(j['today'])!;
    _rng.state = j['rng'] as int;
    teamId = j['team'] as int? ?? teamId;
    manager.restore(j['manager'] as Map<String, dynamic>?);
    riderById
      ..clear()
      ..addAll({
        for (final i in (j['riders'] as List).cast<int>()) pool[i].id: pool[i],
      });
    squads
      ..clear()
      ..addAll({
        for (final s in (j['squads'] as List).cast<List<dynamic>>())
          s[0] as int: [for (final i in (s[1] as List).cast<int>()) pool[i]],
      });
    fullNames
      ..clear()
      ..addAll(ints('names', (v) => v as String));
    history
      ..clear()
      ..addAll([
        for (final h in (j['history'] as List).cast<List<dynamic>>())
          (year: h[0] as int, points: d(h[1]), rank: h[2] as int),
      ]);
    racingOver = j['racingOver'] as bool? ?? false;
    captains
      ..clear()
      ..addAll({
        for (final e
            in (j['captains'] as Map<String, dynamic>? ?? const {}).entries)
          int.parse(e.key): e.value as int,
      });
    tttWait
      ..clear()
      ..addAll((j['tttWait'] as List? ?? const []).cast<int>());
    lineupTemplates
      ..clear()
      ..addAll({
        for (final e
            in (j['lineupTemplates'] as Map<String, dynamic>? ?? const {})
                .entries)
          e.key: (e.value as List).cast<int>(),
      });
    retired
      ..clear()
      ..addAll((j['retired'] as List? ?? const []).cast<List<dynamic>>());
    breakDays
      ..clear()
      ..addAll({
        for (final e
            in (j['breakDays'] as Map<String, dynamic>? ?? const {}).entries)
          int.parse(e.key): e.value as int,
      });
    combative
      ..clear()
      ..addAll({
        for (final e
            in (j['combative'] as Map<String, dynamic>? ?? const {}).entries)
          int.parse(e.key): e.value as int,
      });
    ownTemplates
      ..clear()
      ..addAll([
        for (final t
            in (j['templates'] as List? ?? const []).cast<List<dynamic>>())
          ProgramTemplate.own(t[0] as String, (t[1] as List).cast<int>()),
      ]);
    riderPoints
      ..clear()
      ..addAll(ints('riderPoints', d));
    teamPoints
      ..clear()
      ..addAll(ints('teamPoints', d));
    inbox
      ..clear()
      ..addAll([
        for (final m in (j['inbox'] as List).cast<List<dynamic>>())
          Message(_date(m[0])!, m[1] as String, m[2] as String, m[3] as String,
              raceId: m[4] as int?,
              talk: Talk.fromJson(m.length > 6 ? m[6] : null))
            ..read = m[5] as bool,
      ]);
    ownPlans
      ..clear()
      ..addAll(ints(
          'ownPlans', (v) => TeamPlan.fromJson(v as Map<String, dynamic>)));
    ownWishes
      ..clear()
      ..addAll(j['ownWishes'] == null
          ? const {}
          : ints('ownWishes',
              (v) => PlanWish.fromJson(v as Map<String, dynamic>)));
    program
      ..clear()
      ..addAll(ints('program', (v) => (v as List).cast<int>().toSet()));
    // Saves from before the winter plan have none.
    for (final (key, plan) in [
      ('nextProgram', nextProgram),
      ('nextGoals', nextGoals)
    ]) {
      plan
        ..clear()
        ..addAll({
          for (final e in (j[key] as Map<String, dynamic>? ?? const {}).entries)
            int.parse(e.key): (e.value as List).cast<int>().toSet(),
        });
    }
    teamPrograms.clear();
    if (j['teamPrograms'] case final Map<String, dynamic> saved) {
      for (final e in saved.entries) {
        teamPrograms[int.parse(e.key)] = {
          for (final x in (e.value as Map<String, dynamic>).entries)
            int.parse(x.key): (x.value as List).cast<int>().toSet(),
        };
      }
    }
    people.restore(j['people'] as Map<String, dynamic>?);
    watch
      ..clear()
      ..addAll((j['watch'] as List? ?? const []).cast<int>());
    mutedTopics
      ..clear()
      ..addAll(
          (j['muted'] as List? ?? const []).cast<String>().map(sourceText));
    inboxDigest = j['digest'] as bool? ?? true;
    notes
      ..clear()
      ..addAll(
          j['notes'] == null ? const {} : ints('notes', (v) => v as String));
    shape
      ..clear()
      ..addAll(ints('shape', (v) {
        final s = v as List<dynamic>;
        return RiderShape()
          ..fitness = d(s[0])
          ..fatigue = d(s[1])
          ..raceDays = s[2] as int
          ..grandTours = s[3] as int
          ..lastGrandTourEnd = _date(s[4])
          ..load = TrainingLoad.values[s[5] as int]
          ..focus = TrainingFocus.values[s[6] as int]
          ..injuredUntil = _date(s[7]);
      }));
    _busyUntil
      ..clear()
      ..addAll(ints('busy', (v) => _date(v)!));
    _skipped
      ..clear()
      ..addAll((j['skipped'] as List).cast<int>());
    _strength
      ..clear()
      ..addAll(ints('strength', d));
    _radio
      ..clear()
      ..addAll(ints(
          'radio',
          (v) => {
                for (final e in (v as Map<String, dynamic>).entries)
                  RadioKind.values.byName(e.key): e.value as int,
              }));
    _orders.clear();
    if (j['orders'] != null) {
      _orders.addAll(ints(
          'orders',
          (v) => [
                for (final o in v as List) TimedOrder.fromJson(o as List),
              ]));
    }
    delegation.load(j['delegation'] as Map<String, dynamic>);
    // A save made while the staff were in charge for a while: the run
    // ended with the load, so the player's own settings apply again.
    if (j['heldDelegation'] case final Map<String, dynamic> held) {
      delegation.load(held);
    }
    heldDelegation = null;
    titles
      ..clear()
      ..addAll([
        for (final t in (j['titles'] as List).cast<List<dynamic>>())
          (year: t[0] as int, race: t[1] as String, riderId: t[2] as int),
      ]);
    palmares
      ..clear()
      ..addAll(ints('palmares', (v) => (v as List).cast<List<dynamic>>()));
    archive
      ..clear()
      ..addAll((j['archive'] as List).cast<Map<String, dynamic>>());
    riderSeasons
      ..clear()
      ..addAll(ints('riderSeasons', (v) => (v as List).cast<List<dynamic>>()));
    List<List<num>> lines(dynamic v) =>
        [for (final x in v as List) (x as List).cast<num>()];
    growth
      ..clear()
      ..addAll(j.containsKey('growth') ? ints('growth', lines) : const {});
    formLog
      ..clear()
      ..addAll(j.containsKey('formLog') ? ints('formLog', lines) : const {});

    // Subsystems first: the calendar and the fields depend on the licences.
    economy.restore(j['economy'] as Map<String, dynamic>);
    staff.restore(j['staff'] as Map<String, dynamic>);
    equipment.restore(j['equipment'] as Map<String, dynamic>?);
    facilities.restore(j['facilities'] as Map<String, dynamic>?);
    finances.restore(j['finances'] as Map<String, dynamic>?);
    lastLineups
      ..clear()
      ..addAll({
        for (final e
            in (j['lastLineups'] as Map<String, dynamic>? ?? const {}).entries)
          int.parse(e.key): (e.value as List).cast<int>(),
      });
    if (j['styles'] case final Map<String, dynamic> saved) {
      styles
        ..clear()
        ..addAll({
          for (final e in saved.entries)
            int.parse(e.key): TeamStyle.values[e.value as int],
        });
    } else {
      _assignStyles();
    }
    ownStyle =
        j['ownStyle'] == null ? null : TeamStyle.values[j['ownStyle'] as int];
    licences.restore(j['licences'] as Map<String, dynamic>);
    devTeam.teamId = j['dev'] as int?;
    devTeam.stagiaires
      ..clear()
      ..addAll((j['stagiaires'] as List? ?? const []).cast<int>());
    if (j['devFounded'] case final List<dynamic> t) {
      final info = TeamInfo(t[0] as int, t[1] as String, t[2] as String,
          t[3] as String, t[4] as String, t[5] as String, t[6] as String, '');
      teams[info.id] = info;
      devTeam
        ..founded = info
        ..links[j['devParent'] as int? ?? teamId] = info.id;
    }
    camps.restore(j['camps'] as List<dynamic>);
    // Saves before 0.6.0: a founded team got the staff and facilities of
    // a team without riders. They are raised to what its squad deserves;
    // whatever the player has built or hired beyond that stays.
    if (custom case final t? when from < 3) {
      staff.fitTo(t.id, keepBetter: true);
      facilities.fitTo(t.id, keepBetter: true);
      final even = finances.breakEven(t.id);
      if (economy.budget < even) economy.scaleSponsors(even / economy.budget);
    }
    entries.load(j['entries'] as Map<String, dynamic>);

    _buildCalendar();
    _ownRaces = null;
    _twinCache = null;
    _fields
      ..clear()
      ..addAll(j.containsKey('fields')
          ? ints('fields', (v) => (v as List).cast<int>())
          : const {});
    _invited.clear();
    _pending.clear();
    final byId = {for (final r in calendar) r.info.id: r};
    final staffById = {for (final s in staff.all) s.id: s};
    progress.clear();
    for (final p in races) {
      final race = byId[p['race'] as int];
      if (race == null) continue;
      final pool = [
        for (final r in (p['pool'] as List).cast<List<dynamic>>()) _rider(r),
      ];
      final run = StageRaceRun.fromJson(
        p['run'] as Map<String, dynamic>,
        rider: (i) => pool[i],
        routeOf: (i) => world.route(race.stages[i].id),
        tuning: tuning,
        scheme: world.scheme(race.info.id),
      );
      progress[race.info.id] = RaceProgress(
        race,
        [for (final i in (p['riders'] as List).cast<int>()) pool[i]],
        run,
        {
          for (final e in (p['dir'] as Map<String, dynamic>).entries)
            int.parse(e.key): d(e.value),
        },
        staffById[p['own']],
      );
    }
  }
}
