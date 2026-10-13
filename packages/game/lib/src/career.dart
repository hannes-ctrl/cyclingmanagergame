import 'dart:math';

import 'package:sim/sim.dart';

import 'camp.dart';
import 'devteam.dart';
import 'economy.dart';
import 'entries.dart';
import 'licence.dart';
import 'planning.dart';
import 'points.dart';
import 'staff.dart';

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
  all('Bei jedem Rennen'),
  important('Nur bei WorldTour-Rennen'),
  off('Nie – der Sportliche Leiter entscheidet');

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
}

/// Training focus: these attributes develop faster, the others more slowly.
enum TrainingFocus {
  balanced('Ausgewogen', []),
  climbing('Berg', ['mountain', 'mediumMountain', 'hill']),
  sprint('Sprint', ['sprint', 'acceleration']),
  timeTrial('Zeitfahren', ['timeTrial', 'prologue']),
  classics('Klassiker', ['cobble', 'hill', 'flat']),
  stamina('Ausdauer', ['endurance', 'resistance', 'recovery']);

  const TrainingFocus(this._label, this.attributes);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
  final List<String> attributes;
}

/// How hard a rider trains on days without a race.
enum TrainingLoad {
  low('Schonend', 80),
  normal('Normal', 110),
  high('Hart', 135);

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
class Message {
  Message(this.date, this.from, this.subject, this.body, {this.raceId});
  final DateTime date;
  final String from;
  final String subject;
  final String body;

  /// The topics of the inbox, as their German keys.
  static const topics = [
    'Rennen',
    'Medizin',
    'Training und Nachwuchs',
    'Verträge',
    'Lizenz',
    'Teamleitung',
    'Scouting',
  ];

  /// Topic the inbox files the message under, derived from the sender; one
  /// of [topics], whatever the language.
  String get topicKey {
    // The sender was written in the language of the time.
    bool from_(List<String> senders) => senders.any((s) => isText(from, s));
    if (from_([
      'Rennbericht',
      'Sportlicher Leiter',
      'Veranstalter',
      'Saisonrückblick'
    ])) {
      return 'Rennen';
    }
    if (from_(['Teamarzt'])) return 'Medizin';
    if (from_(['Trainer', 'Nachwuchsteam'])) return 'Training und Nachwuchs';
    if (from_(['Berater'])) return 'Verträge';
    if (from_(['UCI'])) return 'Lizenz';
    if (from_(['Teamleitung'])) return 'Teamleitung';
    return 'Scouting';
  }

  /// The topic in the current language.
  String get topic => topicKey == 'Scouting' ? 'Scouting' : tr(topicKey);

  /// Race the message belongs to, for the jump to the race report.
  final int? raceId;
  bool read = false;
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
  }) : tuning = tuning ?? SimTuning.standard {
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
    economy.openSeason();
    _buildCalendar();
  }

  /// Season the career started in; fixed by the world database.
  late final int _firstYear = year;

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
      _venueOf(RaceInfo info) {
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

  /// Builds the calendar of the current year from the world database.
  void _buildCalendar() {
    calendar.clear();
    for (var info in world.races()) {
      final tier = RaceTier.of(info.raceClass);
      var stages =
          world.stages(info.id).where((s) => s.name.isNotEmpty).toList();
      if (stages.isEmpty) continue;
      // World and European championships move to another country every
      // year; in the first season they are where the database has them.
      if (_venueOf(info) case final v?) {
        final trial = info.raceClass.endsWith('ITT');
        final s = stages.first;
        stages = [
          StageInfo(trial ? v.trial : v.road, s.number,
              trial ? v.trialName : v.roadName, s.month, s.day),
        ];
        info = RaceInfo(info.id, info.name, info.abbr, info.raceClass,
            v.country, info.stages, info.startMonth, info.startDay);
      }
      final days = [for (final s in stages) DateTime.utc(year, s.month, s.day)]
        ..sort();
      calendar.add(RaceEntry(info, stages, tier, days.first, days.last));
    }
    calendar.sort((a, b) => a.start.compareTo(b.start));
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
      economy.found(max(1000000.0, economy.wageBill(teamId) * 1.45));
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
    economy.found(budget);
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
  final int teamId;
  int year;
  final int seed;
  late final _rng = Rng(seed * 31 + 7);

  /// Random source of the career, shared by all subsystems.
  Random get rng => _rng;

  /// Contracts, finances and transfer market.
  late final economy = Economy(this);

  /// Staff of all teams and scouting.
  late final staff = StaffBook(this);

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
  /// those of muted topics and folds many of one topic into a summary.
  ///
  /// @param from Index of the first message written today.
  void _tidyInbox(int from) {
    if (from >= inbox.length) return;
    final fresh = inbox.sublist(from);
    inbox.removeRange(from, inbox.length);
    fresh.removeWhere((m) => mutedTopics.contains(m.topicKey));
    if (!inboxDigest) {
      inbox.addAll(fresh);
      return;
    }
    final byTopic = <String, List<Message>>{};
    for (final m in fresh) {
      byTopic.putIfAbsent(m.topicKey, () => []).add(m);
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
        tr('{0}: {1} Meldungen', [first.topic, list.length]),
        [for (final m in list) '${m.subject}\n${m.body}'].join('\n\n'),
        raceId: list.map((m) => m.raceId).whereType<int>().firstOrNull,
      ));
    }
  }

  /// Names the best of the season in a message: the rider with the most
  /// points, the best rider aged 23 or younger, the rider with the most
  /// wins and the best team. Runs before the rankings start over.
  void _awards() {
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
      tr('Fahrer des Jahres: {0}, {1} Punkte',
          [of(rider), rider == null ? 0 : points(rider).round()]),
      tr('Bester Nachwuchsfahrer: {0}', [of(young)]),
      tr('Die meisten Siege: {0}, {1} Siege',
          [of(winner), winner == null ? 0 : winsOf(winner.id, year)]),
      if (team != null)
        tr('Team des Jahres: {0}, {1} Punkte',
            [teams[team.key]?.name ?? '', team.value.round()]),
    ];
    if (archive.isNotEmpty) {
      archive.last['awards'] = {
        'rider': rider?.id,
        'young': young?.id,
        'wins': winner?.id,
        'team': team?.key,
      };
    }
    inbox.add(Message(
      today,
      tr('Saisonrückblick'),
      tr('Die Besten der Saison {0}', [year]),
      lines.join('\n'),
    ));
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
    }
    final open = [
      for (final r in races)
        if (!program.containsKey(r.info.id)) r,
    ];
    if (open.isEmpty) return 0;
    final planned = planner.plan(
      squads[teamId] ?? const [],
      open,
      fixed: program,
      all: [
        for (final r in ownRaces)
          if (r.tier != RaceTier.championship) r,
      ],
    );
    program.addAll(planned);
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
      tr('Sportlicher Leiter'),
      tr('Der Saisonplan steht'),
      tr('Ich habe {0} Rennen mit {1} Renntagen verplant, die wichtigsten zuerst. Im Schnitt kommt jeder Fahrer auf {2} Renntage, keiner auf mehr als {3}. Im Rennplaner kannst du jeden Einsatz ändern.',
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
          ? tr('{0}: kein Ersatz frei', [race.info.name])
          : tr('{0}: {1} rückt nach', [race.info.name, stand.name]));
    }
    if (lines.isEmpty) return;
    inbox.add(Message(
      today,
      tr('Sportlicher Leiter'),
      tr('Ersatz für {0}', [r.name]),
      tr('{0} fehlt in Rennen, für die er eingeplant war. {1}.',
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
  /// @returns The suggested plan for the player's team.
  TeamPlan suggestPlan(
          SimRoute route, List<SimRider> lineup, List<SimRider> others,
          {Map<int, double> gcGaps = const {}}) =>
      autoPlans(route, [...others, ...lineup], gcGaps: gcGaps)[teamId]!;

  /// Confirms the line-up for a waiting race.
  ///
  /// @param pending The waiting race.
  /// @param lineup Own riders, in the order they were picked.
  /// @param plan Complete tactics for the whole race.
  /// @param wish What the player pins down; the sports director decides the
  ///   rest for every stage. Without [plan] and [wish] he decides everything.
  /// @param directorId Sports director to send; without it the best free one.
  void confirm(PendingRace pending, List<SimRider> lineup,
      {TeamPlan? plan, PlanWish? wish, int? directorId}) {
    final id = pending.race.info.id;
    if (plan != null) ownPlans[id] = plan;
    if (wish != null && !wish.isEmpty) ownWishes[id] = wish;
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

  /// The player's tactics for the next stage of a race: his complete plan,
  /// or his wishes laid over what the sports director plans for that stage.
  ///
  /// @param raceId Id of a race.
  /// @param route The stage.
  /// @returns The plan as a one-entry map, or an empty map if the sports
  ///   director decides everything.
  Map<int, TeamPlan> _plansFor(int raceId, SimRoute route) {
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

  /// Finds the next question from one of today's races that the player has
  /// not answered yet, by simulating the stage up to that point as a trial.
  ///
  /// @returns Race, stage and question, or null if there is none or the radio
  ///   is switched off ([Delegation.radio]).
  ({RaceProgress race, int stageIndex, RadioCall call})? nextRadioCall() {
    if (delegation.radio == RadioMode.off) return null;
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
      final index = p.stagesDone;
      final route = world.route(race.stages[index].id);
      final result = p.run.preview(
        route,
        plans: _plansFor(id, route),
        directorSkills: p.directorSkills,
        radioTeam: teamId,
        radio: _radio[id] ?? const {},
        askRadio: true,
      );
      final call = result.openCall;
      if (call != null) return (race: p, stageIndex: index, call: call);
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
        autoPlans(
          world.route(p.race.stages[stageIndex].id),
          p.run.ridersBefore(stageIndex),
          gcGaps: p.run.gcGapsBefore(stageIndex),
        )[teamId]!;
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
  DayReport advance() {
    final inboxBefore = inbox.length;
    ensureProgram();
    for (var p = needsDecision; p != null; p = needsDecision) {
      confirm(p, p.suggestedLineup);
    }
    final date = today;
    final ridden =
        <({RaceProgress race, int stageIndex, StageResult result})>[];
    for (final race in racesOn(date)) {
      final id = race.info.id;
      if (!progress.containsKey(id) && !_skipped.contains(id)) {
        // Races without the player's team start without asking.
        _launch(_pending[id] ??= _prepare(race), const []);
      }
      final p = progress[id];
      if (p == null || p.finished) continue;
      final index = p.stagesDone;
      final route = world.route(race.stages[index].id);
      final result = p.run.nextStage(
        route,
        plans: _plansFor(id, route),
        directorSkills: p.directorSkills,
        radioTeam: teamId,
        radio: _radio.remove(id) ?? const {},
      );
      ridden.add((race: p, stageIndex: index, result: result));
      _credit(p, index, result);
    }
    // A stage race without a stage today has a rest day.
    for (final p in progress.values) {
      if (p.finished || p.stagesDone == 0) continue;
      if (ridden.any((r) => identical(r.race, p))) continue;
      if (date.isAfter(p.race.start) && date.isBefore(p.race.end)) {
        p.run.restDay();
      }
    }
    _trainAndRecover(ridden);
    _incidents(ridden);
    if (today.day == 1) {
      _recordGrowth();
      _develop();
    }
    if (today.weekday == DateTime.monday) _recordForm();
    if (delegation.training && today.weekday == DateTime.monday) _coachPlans();
    economy.daily(ridden);
    staff.daily();
    camps.daily();
    entries.daily();
    if (delegation.scouting && today.month >= 6) staff.scoutOnOwn();
    _tidyInbox(inboxBefore);
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
      final days = max(2, (rawDays * staff.doctorFactor(r.teamId)).round());
      final until = today.add(Duration(days: days));
      shapeOf(r.id).injuredUntil = until;
      final abandons = race != null && !race.finished;
      if (abandons) race.run.withdraw(r.id);
      if (r.teamId != teamId) return;
      replaceInProgram(r, until);
      final day = until.day.toString().padLeft(2, '0');
      final month = until.month.toString().padLeft(2, '0');
      inbox.add(Message(
        today,
        tr('Teamarzt'),
        tr('{0} fällt {1} Tage aus', [r.name, days]),
        tr('{0}. Voraussichtlich wieder einsatzbereit am {1}.{2}.{3}', [
          what,
          day,
          month,
          abandons ? tr(' Er musste das Rennen aufgeben.') : ''
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
                    ? tr('Schwerer Sturz mit mehreren Brüchen')
                    : a.days >= 14
                        ? tr(
                            'Bruch nach einem Sturz, die Operation verlief gut')
                        : tr('Prellungen nach einem Sturz'),
                race: day.race);
          case AbandonReason.illness:
            sideline(a.rider, a.days, tr('Infekt, einige Tage Pause'),
                race: day.race);
          case AbandonReason.timeCut:
            if (a.rider.teamId != teamId) continue;
            inbox.add(Message(
              today,
              tr('Sportlicher Leiter'),
              tr('{0} außerhalb der Karenzzeit', [a.rider.name]),
              tr('{0} kam außerhalb der Karenzzeit ins Ziel und ist nicht mehr im Rennen.',
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
          tr('Teamarzt'),
          tr('{0} ist gestürzt', [r.name]),
          e.value.formLoss >= 0.02
              ? tr(
                  '{0} ist gestürzt und hat sich ins Ziel gekämpft. Die nächsten Tage wird er Schmerzen haben.',
                  [
                      r.name
                    ])
              : tr('{0} ist gestürzt, aber ohne ernste Folgen davongekommen.',
                  [r.name]),
          raceId: day.race.race.info.id,
        ));
      }
    }
    for (final r in riderById.values) {
      if (racing.contains(r.id) || isInjured(r.id, today)) continue;
      if (_rng.nextDouble() < 0.0007) {
        sideline(r, 3 + _rng.nextInt(8), tr('Infekt, einige Tage Pause'));
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
        22 => 0.95,
        23 => 0.75,
        24 => 0.6,
        25 => 0.4,
        26 => 0.25,
        27 => 0.1,
        <= 30 => 0.0,
        <= 32 => -0.3,
        <= 34 => -0.7,
        _ => -1.2,
      };

  /// The level a rider's best attributes approach but hardly exceed; it
  /// follows from his potential (6 gives about 87, 4 about 81).
  ///
  /// @param r The rider.
  /// @returns The ceiling on the attribute scale.
  static double ceiling(SimRider r) => 70 + 2.8 * r.potential;

  /// Scales a gain so that an attribute slows down as it nears the rider's
  /// ceiling and stops there.
  ///
  /// @param r The rider.
  /// @param value Current value of the attribute.
  /// @param gain Gain without the ceiling.
  /// @returns The gain that is actually applied.
  static double capped(SimRider r, double value, double gain) =>
      gain <= 0 ? gain : gain * ((ceiling(r) - value) / 7).clamp(0.0, 1.0);

  /// How much faster or slower a rider develops than one of potential 5.
  static double _talent(SimRider r) => ((r.potential - 2) / 3).clamp(0.2, 1.4);

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
            ? perYear / 12 * _talent(r) * load * coach
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
    _awards();
    economy.closeSeason();
    licences.closeSeason();
    final ranking = teamPoints.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    history.add((
      year: year,
      points: teamPoints[teamId] ?? 0,
      rank: ranking.indexWhere((e) => e.key == teamId) + 1,
    ));
    year++;
    today = DateTime.utc(year, 1, 1);
    progress.clear();
    formLog.clear();
    devTeam.stagiaires.clear();
    riderPoints.clear();
    teamPoints.clear();
    ownPlans.clear();
    ownWishes.clear();
    program.clear();
    teamPrograms.clear();
    _pending.clear();
    _skipped.clear();
    _busyUntil.clear();
    _fields.clear();
    _invited.clear();
    entries.reset();
    _twinCache = null;
    camps.all.clear();
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
    _strength.clear();
    _buildCalendar();
    _ownRaces = null;
    planner.reset();
    economy.openSeason();
    inbox.add(Message(
      today,
      tr('Teamleitung'),
      tr('Saison {0} beginnt', [year]),
      tr('Die Saison {0} endete für uns auf Platz {1} der Teamrangliste mit {2} Punkten.',
          [year - 1, history.last.rank, history.last.points.round()]),
    ));
  }

  /// Mean strength of a team's eight best riders, used for invitations.
  ///
  /// @param team Team id.
  /// @returns The strength on the attribute scale.
  double teamStrength(int team) => _teamStrength(team);

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
  PendingRace _prepare(RaceEntry race) {
    if (race.tier == RaceTier.championship) return _prepareChampionship(race);
    final routes = [for (final s in race.stages) world.route(s.id)];
    final size = world.raceField(race.info.id).ridersPerTeam;
    final others = <SimRider>[];
    var own = const <SimRider>[];
    // A trainee rides for the professional team; his development team, if
    // it starts in the same race, has to do without him.
    final field = _field(race);
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
        tr('Sportlicher Leiter'),
        tr('Aufgebot für {0}', [race.info.name]),
        tr('Am Start: {0}.', [ownLineup.map((r) => r.name).join(', ')]),
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
      skills[team] = seat.skill;
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
    final own = result.placings.indexWhere((x) => _isOwn(x.rider));
    final winner = result.placings.first.rider;
    final tier = _pointsTier(race);
    final championship = race.tier == RaceTier.championship;
    if (race.isStageRace) {
      for (var i = 0; i < 3; i++) {
        _add(result.placings[i].rider, stagePoints(tier, i));
      }
    }
    if (championship) {
      titles.add((year: year, race: race.info.name, riderId: winner.id));
    }
    if (race.isStageRace) _honour(winner, race, tr('Etappe {0}', [index + 1]));
    if (p.finished) {
      final gc = p.run.standings.last.general;
      final order = race.isStageRace
          ? [for (final e in gc) e.rider]
          : [for (final x in result.placings) x.rider];
      if (!race.isStageRace) {
        _honour(order.first, race, tr('Sieg'));
      } else {
        for (var i = 0; i < 3 && i < order.length; i++) {
          _honour(
              order[i],
              race,
              i == 0
                  ? tr('Gesamtsieg')
                  : tr('{0}. der Gesamtwertung', [i + 1]));
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
    final stageLabel = race.isStageRace ? tr(', Etappe {0}', [index + 1]) : '';
    var body = own == 0
        ? championship
            ? tr('{0} holt den Titel und fährt ein Jahr im Meistertrikot.',
                [best.name])
            : tr('{0} gewinnt für uns.', [best.name])
        : tr('Sieger: {0} ({1}). Unser Bester: {2} auf Platz {3}.',
            [winner.name, winner.team, best.name, own + 1]);
    if (race.isStageRace) {
      final gc = p.run.standings.last.general;
      final place = gc.indexWhere((e) => e.rider.teamId == teamId);
      body += p.finished
          ? tr(' {0} gewinnt {1}, {2} wird {3}.', [
              gc.first.rider.name,
              race.info.name,
              gc[place].rider.name,
              place + 1
            ])
          : tr(' Gesamtwertung: {0} auf Platz {1}.',
              [gc[place].rider.name, place + 1]);
    }
    inbox.add(Message(
      today,
      tr('Rennbericht'),
      '${race.info.name}$stageLabel: '
      '${own == 0 ? tr('Sieg') : tr('Platz {0}', [own + 1])}',
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
  /// @param what Text such as "Sieg" or "Etappe 3".
  void _honour(SimRider r, RaceEntry race, String what) => palmares
      .putIfAbsent(r.id, () => [])
      .add([year, race.info.name, what, race.tier.index]);

  /// @param riderId Id of a rider.
  /// @param inYear A season.
  /// @returns His number of wins (races, stages, overall) in that season.
  int winsOf(int riderId, int inYear) => (palmares[riderId] ?? const [])
      .where((p) =>
          p[0] == inYear &&
          !(p[2] as String).contains('der Gesamtwertung') &&
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

  /// Stores the finished season in [archive] and [riderSeasons]. Runs before
  /// transfers happen, so team names are those of the season.
  void _archiveSeason() {
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
      'version': 1,
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
      'riderPoints': ints(riderPoints),
      'teamPoints': ints(teamPoints),
      'inbox': [
        for (final m in inbox)
          [_ms(m.date), m.from, m.subject, m.body, m.raceId, m.read],
      ],
      'ownPlans': ints<TeamPlan>(ownPlans, (p) => p.toJson()),
      'ownWishes': ints<PlanWish>(ownWishes, (w) => w.toJson()),
      'program': ints<Set<int>>(program, (s) => s.toList()),
      'teamPrograms': ints<Map<int, Set<int>>>(
          teamPrograms, (m) => ints<Set<int>>(m, (s) => s.toList())),
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
      'delegation': {
        'planning': delegation.planning,
        'lineups': delegation.lineups,
        'radio': delegation.radio.name,
        'training': delegation.training,
        'scouting': delegation.scouting,
      },
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
      'licences': licences.toJson(),
      'dev': devTeam.teamId,
      'stagiaires': devTeam.stagiaires.toList(),
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
              raceId: m[4] as int?)
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
    teamPrograms.clear();
    if (j['teamPrograms'] case final Map<String, dynamic> saved) {
      for (final e in saved.entries) {
        teamPrograms[int.parse(e.key)] = {
          for (final x in (e.value as Map<String, dynamic>).entries)
            int.parse(x.key): (x.value as List).cast<int>().toSet(),
        };
      }
    }
    watch
      ..clear()
      ..addAll((j['watch'] as List? ?? const []).cast<int>());
    mutedTopics
      ..clear()
      ..addAll((j['muted'] as List? ?? const []).cast<String>());
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
    final dj = j['delegation'] as Map<String, dynamic>;
    delegation
      ..lineups = dj['lineups'] as bool
      ..radio = RadioMode.values.byName(dj['radio'] as String)
      ..training = dj['training'] as bool
      ..scouting = dj['scouting'] as bool
      ..planning = dj['planning'] as bool? ?? true;
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
        ..links[teamId] = info.id;
    }
    camps.restore(j['camps'] as List<dynamic>);
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
