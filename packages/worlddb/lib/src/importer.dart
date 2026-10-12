import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'cdb.dart';
import 'stage_file.dart';

/// Opens a SQLite file through the SQLite library that ships with Windows.
///
/// @param path File path; the file is created if it does not exist.
/// @returns The open database.
Database openSqlite(String path) {
  open.overrideFor(
      OperatingSystem.windows, () => DynamicLibrary.open('winsqlite3.dll'));
  return sqlite3.open(path);
}

/// Reads the classification files (points, mountain points, bonus seconds
/// and prize money per race class) into the table `classification_bonus`.
///
/// Each file lists "sprint types" such as `finish_flat` or `mountain_hc`
/// and, per type, what the first riders receive. Can be run on an existing
/// database; the table is replaced.
///
/// @param db Open world database.
/// @param worlddbDir Folder of the WorldDB copy.
/// @returns The number of rows written.
int importClassifications(Database db, String worlddbDir) {
  db.execute('''
    DROP TABLE IF EXISTS classification_bonus;
    CREATE TABLE classification_bonus (
      classification TEXT NOT NULL,  -- file name without extension
      sprint_type TEXT NOT NULL,     -- '' outside of a sprint type
      source_in TEXT NOT NULL,
      type_in TEXT NOT NULL,
      source_out TEXT NOT NULL,
      type_out TEXT NOT NULL,        -- POINTS, MOUNTAIN, TIME or MONEY
      rank INTEGER NOT NULL,
      bonus INTEGER NOT NULL
    );
    CREATE INDEX classification_bonus_by_name
      ON classification_bonus (classification);''');
  final dir = Directory('$worlddbDir/Classifications');
  if (!dir.existsSync()) return 0;
  final insert = db.prepare(
      'INSERT INTO classification_bonus VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
  final sprintType = RegExp(r'<sprint_type\s+type\s*=\s*"([^"]*)"');
  final bonus = RegExp(
      r'<sprint_bonus\s+source_in="([^"]*)"\s+type_in="([^"]*)"\s+source_out="([^"]*)"\s+type_out="([^"]*)"');
  final rank = RegExp(r'<rank_bonus\s+rank="(\d+)"\s+bonus\s*="(-?\d+)"');
  var rows = 0;
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.toLowerCase().endsWith('.xml')) continue;
    final name = file.uri.pathSegments.last.replaceAll('.xml', '');
    var type = '';
    List<String>? current;
    // The files are simple enough to read line by line.
    for (final line in file.readAsLinesSync()) {
      final t = sprintType.firstMatch(line);
      if (t != null) type = t[1]!;
      if (line.contains('</sprint_type>')) type = '';
      final b = bonus.firstMatch(line);
      if (b != null) current = [b[1]!, b[2]!, b[3]!, b[4]!];
      if (line.contains('</sprint_bonus>')) current = null;
      final r = rank.firstMatch(line);
      if (r != null && current != null) {
        insert.execute(
            [name, type, ...current, int.parse(r[1]!), int.parse(r[2]!)]);
        rows++;
      }
    }
  }
  insert.dispose();
  return rows;
}

/// Counts of what an import wrote, for the console summary.
class ImportSummary {
  int tables = 0;
  int rows = 0;
  int stages = 0;
  int stagesWithRoute = 0;
  int stagesCurrentRoute = 0;
  int stagesWithoutDetails = 0;
}

/// Builds the game's world database from the WorldDB.
///
/// Three layers: `raw_*` mirrors every table of the .cdb unchanged,
/// `stage_*` holds the routes from the stage files, and the views `rider`,
/// `team`, `race`, `stage` give the game readable column names.
///
/// @param worlddbDir Folder of the WorldDB copy.
/// @param outPath Target SQLite file; an existing file is replaced.
/// @param season Season whose stage variants are preferred.
/// @returns What was imported.
ImportSummary importWorld({
  required String worlddbDir,
  required String outPath,
  int season = 2026,
}) {
  final summary = ImportSummary();
  final out = File(outPath);
  if (out.existsSync()) out.deleteSync();
  out.parent.createSync(recursive: true);

  final db = openSqlite(outPath);
  try {
    db.execute('PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF; BEGIN;');
    final cdb = CdbDatabase.readFile('$worlddbDir/OfficialRelease.cdb');
    for (final table in cdb.tables) {
      _mirror(db, table);
      summary.tables++;
      summary.rows += table.rowCount;
    }
    _importRoutes(db, cdb, worlddbDir, season, summary);
    importClassifications(db, worlddbDir);
    db.execute(_views);
    db.execute('COMMIT;');
  } finally {
    db.dispose();
  }
  return summary;
}

String _q(String identifier) => '"${identifier.replaceAll('"', '""')}"';

/// Copies one .cdb table into a `raw_*` table.
///
/// @param db Target database.
/// @param table Source table.
void _mirror(Database db, CdbTable table) {
  /// Chooses the SQLite column type for a .cdb type.
  ///
  /// @param t Column type of the source.
  /// @returns `INTEGER`, `REAL` or `TEXT`.
  String sqlType(CdbType t) => switch (t) {
        CdbType.integer => 'INTEGER',
        CdbType.float => 'REAL',
        // Lists as JSON text so that json_each() can unpack them.
        CdbType.text || CdbType.intList || CdbType.floatList => 'TEXT',
      };
  final name = _q('raw_${table.name}');
  final columns = table.columns;
  db.execute('CREATE TABLE $name '
      '(${columns.map((c) => '${_q(c.name)} ${sqlType(c.type)}').join(', ')});');
  if (table.rowCount == 0) return;
  final insert = db.prepare(
      'INSERT INTO $name VALUES (${List.filled(columns.length, '?').join(', ')});');
  for (var i = 0; i < table.rowCount; i++) {
    insert.execute([
      for (final c in columns)
        c.values[i] is List ? jsonEncode(c.values[i]) : c.values[i],
    ]);
  }
  insert.dispose();
}

const _routeSchema = '''
CREATE TABLE stage_route (
  stage_id INTEGER PRIMARY KEY,
  file TEXT NOT NULL,           -- Dateiname ohne Endung
  variant TEXT NOT NULL,        -- Jahrgang der Strecke, leer = ohne Jahr
  source TEXT NOT NULL,         -- 'mod' oder 'game'
  name TEXT NOT NULL,           -- "Startort - Zielort"
  relief INTEGER NOT NULL,
  race_km REAL NOT NULL,
  road_km REAL NOT NULL,        -- modellierte Straße inkl. Vor- und Auslauf
  start_km REAL NOT NULL,       -- Lage des Starts auf der Straße
  elevation_gain_m REAL NOT NULL,
  max_altitude_m REAL NOT NULL,
  has_details INTEGER NOT NULL, -- 0: nur Profil lesbar
  profile BLOB NOT NULL         -- Float32-Paare (Straßen-km, Höhe in m), little-endian
);
CREATE TABLE stage_waypoint (
  stage_id INTEGER NOT NULL, seq INTEGER NOT NULL,
  race_km REAL NOT NULL, type TEXT NOT NULL, detail INTEGER NOT NULL, name TEXT NOT NULL,
  PRIMARY KEY (stage_id, seq)
);
CREATE TABLE stage_climb (
  stage_id INTEGER NOT NULL, seq INTEGER NOT NULL,
  name TEXT NOT NULL, kind INTEGER NOT NULL,
  from_race_km REAL NOT NULL, to_race_km REAL NOT NULL,
  avg_gradient REAL NOT NULL, min_gradient REAL NOT NULL, max_gradient REAL NOT NULL,
  PRIMARY KEY (stage_id, seq)
);
CREATE TABLE stage_sector (
  stage_id INTEGER NOT NULL, seq INTEGER NOT NULL,
  name TEXT NOT NULL, cobbled INTEGER NOT NULL, difficulty INTEGER NOT NULL,
  from_race_km REAL NOT NULL, to_race_km REAL NOT NULL,
  PRIMARY KEY (stage_id, seq)
);
''';

/// A stage file on disk and where it came from.
class _RouteFile {
  _RouteFile(this.path, this.source);
  final String path;
  final String source;
}

/// Reads the stage files and fills the `stage_*` tables.
///
/// @param db Target database.
/// @param cdb Source database, for the list of stages.
/// @param worlddbDir Folder of the WorldDB copy.
/// @param season Season whose variants are preferred.
/// @param summary Receives the counts.
void _importRoutes(Database db, CdbDatabase cdb, String worlddbDir, int season,
    ImportSummary summary) {
  db.execute(_routeSchema);

  // Base game first so that mod files of the same name override them.
  final files = <String, _RouteFile>{};
  for (final (dir, source) in [('GameStages', 'game'), ('Stages', 'mod')]) {
    final d = Directory('$worlddbDir/$dir');
    if (!d.existsSync()) continue;
    for (final f in d.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last.toLowerCase();
      if (name.endsWith('.cds')) {
        files[name.substring(0, name.length - 4)] = _RouteFile(f.path, source);
      }
    }
  }
  // Variants per base name: "top_tdf_01" -> {"2026", "2025", ...}
  final variants = <String, Set<String>>{};
  final suffix = RegExp(r'^(.*)_([^_]+)$');
  for (final name in files.keys) {
    variants.putIfAbsent(name, () => {}).add('');
    final m = suffix.firstMatch(name);
    if (m != null) variants.putIfAbsent(m[1]!, () => {}).add(m[2]!);
  }

  final races = cdb.table('STA_race')!;
  final raceById = {for (final r in races.rows) r['IDrace'] as int: r};
  final route = db.prepare(
      'INSERT INTO stage_route VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);');
  final waypoint =
      db.prepare('INSERT INTO stage_waypoint VALUES (?, ?, ?, ?, ?, ?);');
  final climb =
      db.prepare('INSERT INTO stage_climb VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);');
  final sector =
      db.prepare('INSERT INTO stage_sector VALUES (?, ?, ?, ?, ?, ?, ?);');

  for (final stage in cdb.table('STA_stage')!.rows) {
    summary.stages++;
    final race = raceById[stage['fkIDrace']];
    if (race == null) continue;
    final raceFile = (race['gene_sz_filename'] as String).toLowerCase();
    final number = '${stage['gene_i_stage_number']}'.padLeft(2, '0');
    final base = (race['gene_i_number_stages'] as int) > 1
        ? '${raceFile}_$number'
        : raceFile;
    final variant = _pickVariant(base, variants, files, season);
    if (variant == null) continue;
    final fileName = variant.isEmpty ? base : '${base}_$variant';
    final file = files[fileName]!;
    final StageFile s;
    try {
      s = StageFile.readFile(file.path);
    } on FormatException {
      continue;
    }
    summary.stagesWithRoute++;
    if (variant == '$season') summary.stagesCurrentRoute++;
    if (!s.detailsDecoded) summary.stagesWithoutDetails++;

    final id = stage['IDstage'] as int;
    final start = s.startKm ?? 0;
    final profile = Float32List(s.profile.length * 2);
    for (var i = 0; i < s.profile.length; i++) {
      profile[i * 2] = s.profile[i].km;
      profile[i * 2 + 1] = s.profile[i].altitude;
    }
    route.execute([
      id, fileName, variant, file.source, s.name, s.relief, s.raceDistanceKm,
      s.lengthKm, start, s.elevationGainM, s.maxAltitudeM,
      s.detailsDecoded ? 1 : 0, profile.buffer.asUint8List(), //
    ]);
    for (final (i, w) in s.waypoints.indexed) {
      waypoint.execute([id, i, w.km - start, w.type.name, w.detail, w.name]);
    }
    for (final (i, c) in s.climbs.indexed) {
      climb.execute([
        id, i, c.name, c.kind, c.fromKm - start, c.toKm - start, //
        _finite(c.avgGradient), _finite(c.minGradient), _finite(c.maxGradient),
      ]);
    }
    for (final (i, x) in s.sectors.indexed) {
      sector.execute([
        id, i, x.name, x.cobbled ? 1 : 0, x.difficulty, //
        x.fromKm - start, x.toKm - start,
      ]);
    }
  }
  for (final st in [route, waypoint, climb, sector]) {
    st.dispose();
  }
}

// A few files contain NaN as a gradient.
double _finite(double v) => v.isFinite ? v : 0;

/// Picks the route of the season, else the latest older year, else the file
/// without a year, else any variant (the fantasy routes of championships
/// carry names instead of years).
///
/// @param base File name without the variant suffix.
/// @param variants Known variants per base name.
/// @param files All stage files by full name.
/// @param season Wanted season.
/// @returns The variant suffix to use, or null if there is no file at all.
String? _pickVariant(String base, Map<String, Set<String>> variants,
    Map<String, _RouteFile> files, int season) {
  final all = variants[base];
  if (all == null) return null;
  final candidates =
      all.where((v) => files.containsKey(v.isEmpty ? base : '${base}_$v'));
  if (candidates.isEmpty) return null;
  final years = candidates
      .where((v) => int.tryParse(v) != null && int.parse(v) <= season)
      .toList()
    ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
  if (years.isNotEmpty) return years.first;
  if (candidates.contains('')) return '';
  return (candidates.toList()..sort()).last;
}

const _views = '''
CREATE VIEW team AS
SELECT t.IDteam AS id, t.gene_sz_name AS name, t.gene_sz_shortname AS short_name,
       t.abbreviation AS abbr, t.jersey_sz_abbreviation AS jersey,
       c.CONSTANT AS country, d.CONSTANT AS division,
       t.gene_sz_color AS color, t.gene_sz_secondary_color AS color2,
       t.value_i_budget AS budget, t.gene_sz_manager_general AS manager
FROM raw_DYN_team t
LEFT JOIN raw_STA_country c ON c.IDcountry = t.fkIDcountry
LEFT JOIN raw_STA_division d ON d.IDdivision = t.fkIDdivision;

CREATE VIEW rider AS
SELECT r.IDcyclist AS id, r.gene_sz_firstname AS first_name, r.gene_sz_lastname AS last_name,
       r.fkIDteam AS team_id, c.CONSTANT AS country, r.gene_i_birthdate AS birthdate,
       r.gene_i_size AS height_cm, r.gene_i_weight AS weight_kg,
       ty.CONSTANT AS type, r.value_f_potentiel AS potential,
       r.charac_i_plain AS flat, r.charac_i_mountain AS mountain,
       r.charac_i_medium_mountain AS medium_mountain, r.charac_i_hill AS hill,
       r.charac_i_timetrial AS time_trial, r.charac_i_prologue AS prologue,
       r.charac_i_cobble AS cobble, r.charac_i_sprint AS sprint,
       r.charac_i_acceleration AS acceleration, r.charac_i_downhilling AS downhill,
       r.charac_i_endurance AS endurance, r.charac_i_resistance AS resistance,
       r.charac_i_recuperation AS recovery, r.charac_i_baroudeur AS breakaway,
       r.charac_i_tour AS stage_race_pref, r.charac_i_classic AS classic_pref,
       k.finan_i_period_wage AS wage, k.iYearEnd AS contract_end
FROM raw_DYN_cyclist r
LEFT JOIN raw_STA_region g ON g.IDregion = r.fkIDregion
LEFT JOIN raw_STA_country c ON c.IDcountry = g.fkIDcountry
LEFT JOIN raw_STA_type_rider ty ON ty.IDtype_rider = r.fkIDtype_rider
LEFT JOIN raw_DYN_contract_cyclist k
       ON k.fkIDcyclist = r.IDcyclist AND k.gene_b_active_contract = 1;

CREATE VIEW race AS
SELECT r.IDrace AS id, r.gene_sz_race_name AS name, r.gene_sz_abbreviation AS abbr,
       c.CONSTANT AS country, k.CONSTANT AS class, k.gene_b_is_stagerace AS is_stage_race,
       r.gene_i_number_stages AS stages, r.gene_sz_classification_xml AS classification,
       (SELECT min(s.gene_i_month * 100 + s.gene_i_day) FROM raw_STA_stage s
         WHERE s.fkIDrace = r.IDrace) AS start_mmdd
FROM raw_STA_race r
LEFT JOIN raw_STA_country c ON c.IDcountry = r.fkIDcountry
LEFT JOIN raw_STA_race_class k ON k.IDrace_class = r.fkIDrace_class;

CREATE VIEW stage AS
SELECT s.IDstage AS id, s.fkIDrace AS race_id, s.gene_i_stage_number AS number,
       s.gene_i_month AS month, s.gene_i_day AS day,
       o.name, o.variant, o.source, o.relief, o.race_km, o.elevation_gain_m,
       o.max_altitude_m, o.has_details
FROM raw_STA_stage s
LEFT JOIN stage_route o ON o.stage_id = s.IDstage;
''';

/// Adds the routes of earlier seasons to an existing world database, for the
/// calibration against real results of those years. The files are named like
/// the current ones with another year at the end (`top_tdf_05_2023`). Each
/// gets an id above two million in the `stage_*` tables, and the table
/// `stage_variant` says which race, stage number and year it belongs to.
///
/// @param db The world database.
/// @param worlddbDir Folder of the WorldDB copy.
/// @param years Seasons to add.
/// @returns Number of routes added.
int importVariants(Database db, String worlddbDir, List<int> years) {
  final files = <String, _RouteFile>{};
  for (final (dir, source) in [('GameStages', 'game'), ('Stages', 'mod')]) {
    final d = Directory('$worlddbDir/$dir');
    if (!d.existsSync()) continue;
    for (final f in d.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last.toLowerCase();
      if (name.endsWith('.cds')) {
        files[name.substring(0, name.length - 4)] = _RouteFile(f.path, source);
      }
    }
  }
  db.execute('''
CREATE TABLE IF NOT EXISTS stage_variant (
  race_id INTEGER NOT NULL, number INTEGER NOT NULL, year INTEGER NOT NULL,
  stage_id INTEGER NOT NULL,
  PRIMARY KEY (race_id, number, year)
);
DELETE FROM stage_variant;
DELETE FROM stage_route WHERE stage_id >= 2000000;
DELETE FROM stage_waypoint WHERE stage_id >= 2000000;
DELETE FROM stage_climb WHERE stage_id >= 2000000;
DELETE FROM stage_sector WHERE stage_id >= 2000000;
''');
  final route = db.prepare(
      'INSERT INTO stage_route VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);');
  final waypoint =
      db.prepare('INSERT INTO stage_waypoint VALUES (?, ?, ?, ?, ?, ?);');
  final climb =
      db.prepare('INSERT INTO stage_climb VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);');
  final sector =
      db.prepare('INSERT INTO stage_sector VALUES (?, ?, ?, ?, ?, ?, ?);');
  final link = db.prepare('INSERT INTO stage_variant VALUES (?, ?, ?, ?);');
  var id = 2000000, added = 0;
  for (final race in db.select(
      'SELECT IDrace, gene_sz_filename, gene_i_number_stages FROM raw_STA_race')) {
    final raceFile = (race['gene_sz_filename'] as String).toLowerCase();
    final stageRace = (race['gene_i_number_stages'] as int) > 1;
    for (final year in years) {
      // Stage races of other years may have more or fewer stages than now.
      for (var n = 1; n <= (stageRace ? 30 : 1); n++) {
        final name = stageRace
            ? '${raceFile}_${'$n'.padLeft(2, '0')}_$year'
            : '${raceFile}_$year';
        final file = files[name];
        if (file == null) {
          if (stageRace && n < 3) continue; // a missing first file is no end
          break;
        }
        final StageFile s;
        try {
          s = StageFile.readFile(file.path);
        } on FormatException {
          continue;
        }
        id++;
        final start = s.startKm ?? 0;
        final profile = Float32List(s.profile.length * 2);
        for (var i = 0; i < s.profile.length; i++) {
          profile[i * 2] = s.profile[i].km;
          profile[i * 2 + 1] = s.profile[i].altitude;
        }
        route.execute([
          id, name, '$year', file.source, s.name, s.relief, s.raceDistanceKm,
          s.lengthKm, start, s.elevationGainM, s.maxAltitudeM,
          s.detailsDecoded ? 1 : 0, profile.buffer.asUint8List(), //
        ]);
        for (final (i, w) in s.waypoints.indexed) {
          waypoint
              .execute([id, i, w.km - start, w.type.name, w.detail, w.name]);
        }
        for (final (i, c) in s.climbs.indexed) {
          climb.execute([
            id, i, c.name, c.kind, c.fromKm - start, c.toKm - start, //
            _finite(c.avgGradient), _finite(c.minGradient),
            _finite(c.maxGradient),
          ]);
        }
        for (final (i, x) in s.sectors.indexed) {
          sector.execute([
            id, i, x.name, x.cobbled ? 1 : 0, x.difficulty, //
            x.fromKm - start, x.toKm - start,
          ]);
        }
        link.execute([race['IDrace'], n, year, id]);
        added++;
      }
    }
  }
  for (final st in [route, waypoint, climb, sector, link]) {
    st.dispose();
  }
  return added;
}
