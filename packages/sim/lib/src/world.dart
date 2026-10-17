import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'model.dart';
import 'route_builder.dart';
import 'scheme.dart';

/// A team from the world database.
class TeamInfo {
  TeamInfo(this.id, this.name, this.abbr, this.division, this.country,
      this.color, this.color2, this.manager);
  final int id;
  final String name;
  final String abbr;
  final String division;
  final String country;

  /// Team colours as RRGGBB.
  final String color;
  final String color2;
  final String manager;
}

/// A rider with the details only the user interface needs.
class RiderInfo {
  RiderInfo(this.rider, this.firstName, this.lastName, this.country,
      this.potential, this.contractEnd);
  final SimRider rider;
  final String firstName;
  final String lastName;
  final String country;
  final double potential;
  final int contractEnd;
}

/// A race from the world database.
class RaceInfo {
  RaceInfo(this.id, this.name, this.abbr, this.raceClass, this.country,
      this.stages, this.startMonth, this.startDay);
  final int id;
  final String name;
  final String abbr;

  /// Race class of the WorldDB, e.g. `CWTGTFrance`.
  final String raceClass;
  final String country;
  final int stages;
  final int startMonth;
  final int startDay;
}

/// A stage of a race with its date.
class StageInfo {
  StageInfo(this.id, this.number, this.name, this.month, this.day);
  final int id;
  final int number;
  final String name;
  final int month;
  final int day;
}

/// Read-only access to the world database (`data/world.sqlite`).
class World {
  World(this.path) : _db = _open(path);

  /// Path of the database file.
  final String path;

  final Database _db;

  /// Opens the database through the SQLite library that ships with Windows.
  ///
  /// @param path Path of `world.sqlite`.
  /// @returns The open database.
  static Database _open(String path) {
    open.overrideFor(
        OperatingSystem.windows, () => DynamicLibrary.open('winsqlite3.dll'));
    return sqlite3.open(path, mode: OpenMode.readOnly);
  }

  /// Closes the database.
  void close() => _db.dispose();

  /// @returns All teams, sorted by division and name.
  List<TeamInfo> teams() => [
        for (final r
            in _db.select('SELECT * FROM team ORDER BY division, name'))
          TeamInfo(
            r['id'] as int,
            r['name'] as String,
            r['abbr'] as String,
            (r['division'] as String?) ?? '',
            (r['country'] as String?) ?? '',
            r['color'] as String,
            r['color2'] as String,
            (r['manager'] as String?) ?? '',
          ),
      ];

  /// @param teamId Id of a team.
  /// @returns Its riders sorted by last name.
  List<RiderInfo> squad(int teamId) => [
        for (final r in _db.select(
            'SELECT r.*, t.abbr FROM rider r JOIN team t ON t.id = r.team_id '
            'WHERE r.team_id = ? ORDER BY r.last_name',
            [teamId]))
          RiderInfo(
            _rider(r),
            r['first_name'] as String,
            r['last_name'] as String,
            (r['country'] as String?) ?? '',
            (r['potential'] as num).toDouble(),
            (r['contract_end'] as int?) ?? 0,
          ),
      ];

  /// Points scheme of a race from the WorldDB's classification files.
  ///
  /// @param raceId Id of the race.
  /// @returns The scheme, or [PointsScheme.standard] if the database has
  ///   none for this race (or was imported before schemes were read).
  PointsScheme scheme(int raceId) => _schemes.putIfAbsent(raceId, () {
        try {
          final rows = _db.select('''
            SELECT b.sprint_type, b.type_out, b.rank, b.bonus
            FROM race r JOIN classification_bonus b
              ON b.classification = lower(r.classification)
            WHERE r.id = ? AND b.source_in = 'SPRINT' AND b.type_in = 'TIME'
              AND b.type_out IN ('POINTS', 'MOUNTAIN', 'TIME')
            ORDER BY b.sprint_type, b.type_out, b.rank''', [raceId]);
          if (rows.isEmpty) return PointsScheme.standard;
          final tables = {
            'POINTS': <String, List<int>>{},
            'MOUNTAIN': <String, List<int>>{},
            'TIME': <String, List<int>>{},
          };
          for (final r in rows) {
            tables[r['type_out']]!
                .putIfAbsent(r['sprint_type'] as String, () => [])
                // Bonus seconds are stored as negative numbers.
                .add((r['bonus'] as int).abs());
          }
          return PointsScheme(
            points: tables['POINTS']!,
            mountain: tables['MOUNTAIN']!,
            seconds: tables['TIME']!,
          );
        } on SqliteException {
          return PointsScheme.standard;
        }
      });
  final _schemes = <int, PointsScheme>{};

  /// @returns Per team id the file name key of its jersey in the WorldDB's
  ///   graphics pack.
  Map<int, String> jerseyKeys() => {
        for (final r in _db.select(
            'SELECT IDteam AS id, jersey_sz_abbreviation AS k FROM raw_DYN_team'))
          r['id'] as int: ((r['k'] as String?) ?? '').toLowerCase(),
      };

  /// Field of a race according to the WorldDB.
  ///
  /// @param raceId Id of the race.
  /// @returns The invited teams (empty if the database names none) and the
  ///   number of riders per team.
  ({List<int> teams, int ridersPerTeam}) raceField(int raceId) {
    final r = _db.select('''
      SELECT r.gene_ilist_fkIDteam AS teams, k.gene_i_max_riders AS size
      FROM raw_STA_race r
      LEFT JOIN raw_STA_race_class k ON k.IDrace_class = r.fkIDrace_class
      WHERE r.IDrace = ?''', [raceId]).first;
    final size = (r['size'] as int?) ?? 7;
    return (
      teams: (jsonDecode(r['teams'] as String) as List).cast<int>(),
      ridersPerTeam: size == 0 ? 7 : size,
    );
  }

  /// @returns All riders with their team, for the season simulation.
  List<SimRider> riders() => [
        for (final r in _db.select(
            'SELECT r.*, t.abbr FROM rider r JOIN team t ON t.id = r.team_id'))
          _rider(r),
      ];

  /// What the WorldDB tells about the character and career of its riders,
  /// by rider id: loyalty to his contracts (1 to 5, 0 where the database
  /// has none), whether his present contract continues one with the same
  /// team, the year he turned professional (0 unknown) and his wins.
  ///
  /// @returns The traits; empty for a database without the raw tables.
  Map<int, ({int fidelity, bool stayed, int neoPro, int wins})> riderTraits() {
    final out = <int, ({int fidelity, bool stayed, int neoPro, int wins})>{};
    try {
      for (final r in _db.select('''
          SELECT c.IDcyclist id, c.iContract_fidelity f,
                 c.value_i_yearneopro neo, c.gene_i_nb_total_victory w,
                 c.fkIDteam team, k.fkIDprevteam prev
          FROM raw_DYN_cyclist c
          LEFT JOIN raw_DYN_contract_cyclist k ON k.fkIDcyclist = c.IDcyclist''')) {
        out[r['id'] as int] = (
          fidelity: (r['f'] as int?) ?? 0,
          stayed: r['prev'] != null && r['prev'] == r['team'],
          neoPro: (r['neo'] as int?) ?? 0,
          wins: (r['w'] as int?) ?? 0,
        );
      }
    } on SqliteException {
      // A database built without the raw tables: no traits.
    }
    return out;
  }

  /// @returns All races that have a date, in calendar order.
  List<RaceInfo> races() => [
        for (final r in _db.select(
            'SELECT * FROM race WHERE start_mmdd IS NOT NULL ORDER BY start_mmdd, name'))
          RaceInfo(
            r['id'] as int,
            r['name'] as String,
            (r['abbr'] as String?) ?? '',
            (r['class'] as String?) ?? '',
            (r['country'] as String?) ?? '',
            r['stages'] as int,
            (r['start_mmdd'] as int) ~/ 100,
            (r['start_mmdd'] as int) % 100,
          ),
      ];

  /// Finds a race by part of its name. With several hits the exact name wins,
  /// otherwise the shortest.
  ///
  /// @param query Text to look for.
  /// @returns Id and name, or null if nothing matches.
  ({int id, String name})? findRace(String query) {
    final rows = _db.select(
        'SELECT id, name FROM race WHERE name LIKE ? ORDER BY name = ? DESC, length(name)',
        ['%$query%', query]);
    if (rows.isEmpty) return null;
    return (id: rows.first['id'] as int, name: rows.first['name'] as String);
  }

  /// @param raceId Id of a race.
  /// @returns Its stages in order.
  List<StageInfo> stages(int raceId) => [
        for (final r in _db.select(
            'SELECT id, number, name, month, day FROM stage WHERE race_id = ? ORDER BY number',
            [
              raceId
            ]))
          StageInfo(r['id'] as int, r['number'] as int,
              (r['name'] as String?) ?? '', r['month'] as int, r['day'] as int),
      ];

  /// Countries that can host a world or European championship: those whose
  /// national championships have a road course of at least 170 km and a
  /// time trial of 20 to 55 km in the database.
  ///
  /// @returns Per country the stage id and name of both courses.
  List<({String country, int road, String roadName, int trial, String trialName})>
      championshipVenues() => [
            for (final r in _db.select(
                "SELECT a.country, sa.id AS road, sa.name AS road_name, "
                "sb.id AS trial, sb.name AS trial_name "
                "FROM race a JOIN stage sa ON sa.race_id = a.id "
                "JOIN race b ON b.country = a.country "
                "JOIN stage sb ON sb.race_id = b.id "
                "WHERE a.class = 'NationalChampionship' "
                "AND b.class = 'NationalChampionshipITT' "
                "AND sa.name <> '' AND sb.name <> '' "
                "AND sa.race_km >= 170 AND sb.race_km BETWEEN 20 AND 55 "
                "ORDER BY a.country"))
              (
                country: r['country'] as String,
                road: r['road'] as int,
                roadName: r['road_name'] as String,
                trial: r['trial'] as int,
                trialName: r['trial_name'] as String,
              ),
          ];

  /// Routes of earlier seasons, added by `worlddb variants`.
  ///
  /// @param raceId Id of the race.
  /// @param year Season.
  /// @returns Stage numbers of that season with the id of their route; empty
  ///   if the database has none.
  Map<int, int> variantStages(int raceId, int year) {
    try {
      return {
        for (final r in _db.select(
            'SELECT number, stage_id FROM stage_variant WHERE race_id = ? AND year = ?',
            [raceId, year]))
          r['number'] as int: r['stage_id'] as int,
      };
    } on Object {
      // The table only exists once the variants were imported.
      return const {};
    }
  }

  /// The courses of other years a race can switch to: the routes of
  /// earlier seasons added by `worlddb variants`, without the year the
  /// current routes come from.
  ///
  /// @param raceId Id of the race.
  /// @returns Per year its stages in order, as id, number and name of the
  ///   route; empty if the database has none.
  Map<int, List<StageInfo>> routeYears(int raceId) {
    final out = <int, List<StageInfo>>{};
    try {
      for (final r in _db.select(
          'SELECT v.year, v.number, v.stage_id, o.name FROM stage_variant v '
          'JOIN stage_route o ON o.stage_id = v.stage_id '
          'WHERE v.race_id = ? AND v.year NOT IN ('
          ' SELECT CAST(c.variant AS INTEGER) FROM stage s '
          ' JOIN stage_route c ON c.stage_id = s.id WHERE s.race_id = ?) '
          'ORDER BY v.year, v.number',
          [raceId, raceId])) {
        out.putIfAbsent(r['year'] as int, () => []).add(StageInfo(
            r['stage_id'] as int,
            r['number'] as int,
            (r['name'] as String?) ?? '',
            0,
            0));
      }
    } on Object {
      // The table only exists once the variants were imported.
    }
    return out;
  }

  /// Looks up a stage of a race by its number.
  ///
  /// @param raceId Id of the race.
  /// @param number Stage number, starting at 1.
  /// @returns Stage id and the year of its route file, or null.
  ({int id, String variant})? stageNumber(int raceId, int number) {
    final rows = _db.select(
        'SELECT id, variant FROM stage WHERE race_id = ? AND number = ? AND variant IS NOT NULL',
        [raceId, number]);
    if (rows.isEmpty) return null;
    return (
      id: rows.first['id'] as int,
      variant: rows.first['variant'] as String
    );
  }

  /// @returns All riders of the database with first and last name, for
  ///   matching names.
  List<({SimRider rider, String first, String last})> allRiders() => [
        for (final r in _db.select(
            'SELECT r.*, t.abbr FROM rider r LEFT JOIN team t ON t.id = r.team_id'))
          (
            rider: _rider(r),
            first: r['first_name'] as String,
            last: r['last_name'] as String,
          ),
      ];

  /// Builds the route of a stage from the stored profile.
  ///
  /// @param stageId Id of the stage.
  /// @returns The route, cut into segments.
  SimRoute route(int stageId) {
    final r = _db.select(
        'SELECT * FROM stage_route WHERE stage_id = ?', [stageId]).first;
    final raceKm = r['race_km'] as double;
    final start = r['start_km'] as double;
    final raw =
        Float32List.sublistView(Uint8List.fromList(r['profile'] as Uint8List));
    final profile = <(double, double)>[
      for (var i = 0; i < raw.length; i += 2) (raw[i] - start, raw[i + 1]),
    ];
    final waypoints = _db.select(
        'SELECT race_km, type, detail, name FROM stage_waypoint WHERE stage_id = ? ORDER BY seq',
        [stageId]);
    var kind = StageKind.road;
    final tops = <RoutePoint>[];
    final sprints = <RoutePoint>[];
    for (final w in waypoints) {
      final km = w['race_km'] as double;
      switch (w['type'] as String) {
        case 'timeTrialStart':
          kind = StageKind.timeTrial;
        case 'teamTimeTrialStart':
          kind = StageKind.teamTimeTrial;
        case 'climb' || 'summitFinish':
          tops.add(RoutePoint(km, w['name'] as String, w['detail'] as int));
        case 'sprint' when w['detail'] == 14:
          sprints.add(RoutePoint(km, w['name'] as String, 0));
      }
    }
    final climbs = <ClimbSpan>[];
    try {
      for (final c in _db.select(
          'SELECT from_race_km, to_race_km, max_gradient FROM stage_climb '
          'WHERE stage_id = ? AND kind = 0',
          [stageId])) {
        climbs.add(ClimbSpan(c['from_race_km'] as double,
            c['to_race_km'] as double, (c['max_gradient'] as double) / 100));
      }
    } on SqliteException {
      // Databases imported before climbs were stored.
    }
    return buildRoute(
      name: r['name'] as String,
      climbs: climbs,
      kind: kind,
      raceKm: raceKm,
      profile: profile,
      climbTops: tops,
      sprints: sprints,
      sectors: [
        for (final x in _db.select(
            'SELECT from_race_km, to_race_km, difficulty, cobbled FROM stage_sector WHERE stage_id = ?',
            [
              stageId
            ]))
          SectorSpan(x['from_race_km'] as double, x['to_race_km'] as double,
              x['difficulty'] as int, x['cobbled'] == 1),
      ],
    );
  }

  /// Start list: the teams invited by the WorldDB, otherwise the World and
  /// ProTeams, each with its strongest riders.
  ///
  /// Only used outside of a career: a team sends the riders with the highest
  /// peak attributes, whatever their discipline.
  ///
  /// @param raceId Id of the race.
  /// @returns The riders at the start.
  List<SimRider> startList(int raceId) {
    final race = _db.select('''
      SELECT r.gene_ilist_fkIDteam AS teams, k.gene_i_max_riders AS size
      FROM raw_STA_race r
      LEFT JOIN raw_STA_race_class k ON k.IDrace_class = r.fkIDrace_class
      WHERE r.IDrace = ?''', [raceId]).first;
    var teams = (jsonDecode(race['teams'] as String) as List).cast<int>();
    if (teams.isEmpty) {
      teams = [
        for (final t in _db.select(
            "SELECT id FROM team WHERE division LIKE '[1]%' OR division LIKE '[2]%'"))
          t['id'] as int,
      ];
    }
    final size = (race['size'] as int?) ?? 7;
    final riders = <SimRider>[];
    for (final team in teams) {
      riders.addAll(_db.select('''
        SELECT r.*, t.abbr FROM rider r JOIN team t ON t.id = r.team_id
        WHERE r.team_id = ?
        ORDER BY 0.6 * max(mountain, sprint, time_trial, hill, cobble, flat)
               + 0.4 * (mountain + sprint + time_trial + hill + cobble + flat) / 6.0 DESC
        LIMIT ?''', [team, size == 0 ? 7 : size]).map(_rider));
    }
    return riders;
  }

  /// Converts a database row into a rider.
  ///
  /// @param r Row of the `rider` view joined with the team abbreviation.
  /// @returns The rider.
  SimRider _rider(Row r) {
    double v(String column) => (r[column] as num).toDouble();
    return SimRider(
      id: r['id'] as int,
      name:
          '${(r['first_name'] as String).isEmpty ? '' : '${(r['first_name'] as String)[0]}. '}${r['last_name']}',
      teamId: r['team_id'] as int,
      team: (r['abbr'] as String?) ?? '',
      born: (r['birthdate'] as int?) ?? 0,
      potential: (r['potential'] as num?)?.toDouble() ?? 4,
      country: (r['country'] as String?) ?? '',
      contractEnd: (r['contract_end'] as int?) ?? 0,
      weightKg: (r['weight_kg'] as num?)?.toDouble() ?? 0,
      heightCm: (r['height_cm'] as num?)?.toDouble() ?? 0,
      attributes: Attributes(
        flat: v('flat'),
        mountain: v('mountain'),
        mediumMountain: v('medium_mountain'),
        hill: v('hill'),
        timeTrial: v('time_trial'),
        prologue: v('prologue'),
        cobble: v('cobble'),
        sprint: v('sprint'),
        acceleration: v('acceleration'),
        downhill: v('downhill'),
        endurance: v('endurance'),
        resistance: v('resistance'),
        recovery: v('recovery'),
        breakaway: v('breakaway'),
      ),
    );
  }
}
