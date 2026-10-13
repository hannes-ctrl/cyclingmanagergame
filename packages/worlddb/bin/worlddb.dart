import 'dart:io';
import 'dart:math';

import 'package:worlddb/worlddb.dart';

const _usage = '''
Aufruf: dart run worlddb <befehl> [--worlddb <ordner>]

  tables                      Tabellen mit Zeilen- und Spaltenzahl
  columns <tabelle>           Spalten einer Tabelle
  dump <tabelle> [n] [regex]  n Zeilen (Standard 10), optional gefiltert
  stage <datei>               Kopf und Profil einer Etappe (Name ohne .cds)
  pak <datei.pak> [regex]     Inhalt einer Pak-Datei des Grundspiels auflisten
  game-stages <datei.pak>     Etappendateien des Grundspiels nach worlddb/GameStages entpacken
  classifications             Punkteschemata in eine bestehende Weltdatenbank nachtragen
  jerseys <datei.pak>         Teamtrikots aus dem Grafikpaket nach data/jerseys schreiben
  import                      Weltdatenbank data/world.sqlite aus der WorldDB bauen
  sql "<abfrage>"             Abfrage gegen data/world.sqlite
  serve                       Datenbank-Browser auf http://localhost:8765
  check                       Liest alles ein und prüft bekannte Eckwerte
''';

/// Command-line entry point of the WorldDB tools.
///
/// @param argv Command name followed by its arguments; see the usage text.
/// @returns A future that completes when the command has finished.
Future<void> main(List<String> argv) async {
  final args = [...argv];
  var root = Platform.script.resolve('../../../worlddb/').toFilePath();
  final i = args.indexOf('--worlddb');
  if (i >= 0) {
    root = args[i + 1];
    args.removeRange(i, i + 2);
  }
  if (args.isEmpty) {
    stdout.write(_usage);
    return;
  }
  final dbPath = '$root/OfficialRelease.cdb';
  final stageDir = '$root/Stages';
  final worldPath =
      Platform.script.resolve('../../../data/world.sqlite').toFilePath();

  switch (args[0]) {
    case 'tables':
      for (final t in CdbDatabase.readFile(dbPath).tables) {
        print('${t.name.padRight(42)} ${'${t.rowCount}'.padLeft(6)} Zeilen '
            '${'${t.columns.length}'.padLeft(4)} Spalten');
      }
    case 'columns':
      for (final c in _table(dbPath, args[1]).columns) {
        print('${c.name.padRight(36)} ${c.type.name}');
      }
    case 'dump':
      final t = _table(dbPath, args[1]);
      final limit = args.length > 2 ? int.parse(args[2]) : 10;
      final filter =
          args.length > 3 ? RegExp(args[3], caseSensitive: false) : null;
      var shown = 0;
      for (final row in t.rows) {
        // Drop empty fields, otherwise wide tables are unreadable.
        row.removeWhere(
            (_, v) => v == 0 || v == '' || (v is List && v.isEmpty));
        final line = row.toString();
        if (filter != null && !filter.hasMatch(line)) continue;
        print(line);
        if (++shown >= limit) break;
      }
    case 'stage':
      // Mod folder first, then the files extracted from the base game.
      final inMod = File('$stageDir/${args[1]}.cds');
      _printStage(StageFile.readFile(
          inMod.existsSync() ? inMod.path : '$root/GameStages/${args[1]}.cds'));
    case 'pak':
      final pak = PakFile.open(args[1]);
      final filter =
          args.length > 2 ? RegExp(args[2], caseSensitive: false) : null;
      var shown = 0, bytes = 0;
      final methods = <String, int>{};
      for (final e in pak.entries) {
        if (filter != null && !filter.hasMatch(e.path)) continue;
        if (shown++ < 15) print('${e.size.toString().padLeft(10)}  ${e.path}');
        bytes += e.size;
        final m = e.compression ?? 'unkomprimiert';
        methods[m] = (methods[m] ?? 0) + 1;
      }
      print(
          '$shown Dateien, ${(bytes / 1048576).toStringAsFixed(1)} MB, $methods');
      pak.close();
    case 'jerseys':
      // Exports the small team jerseys of the graphics pack as PNG files.
      final pak = PakFile.open(args[1]);
      final outDir = Directory('${File(worldPath).parent.path}/jerseys')
        ..createSync(recursive: true);
      final name = RegExp(r'MiniJersey/Team/([^/]+)_minimaillot\.uexp$');
      final ooz = Ooz(Platform.script
          .resolve('../../../native/build/ooz.dll')
          .toFilePath());
      var written = 0, skipped = 0;
      for (final e in pak.entries) {
        final m = name.firstMatch(e.path);
        if (m == null) continue;
        final texture = Texture.fromUexp(pak.read(e, decoder: ooz.decode));
        if (texture == null) {
          skipped++;
          continue;
        }
        // 128 px is plenty for the user interface.
        File('${outDir.path}/${m[1]!.toLowerCase()}.png')
            .writeAsBytesSync(texture.shrink(1).toPng());
        written++;
      }
      pak.close();
      print('$written Trikots nach ${outDir.path}, $skipped nicht lesbar');
    case 'logos':
      // Exports the race logos of the graphics pack as PNG files, named
      // after the id of the race they belong to.
      final pak = PakFile.open(args[1]);
      final outDir = Directory('${File(worldPath).parent.path}/logos')
        ..createSync(recursive: true);
      final db = openSqlite(worldPath);
      final ids = <String, List<int>>{};
      for (final r in db.select('SELECT IDrace, CONSTANT FROM raw_STA_race')) {
        ids
            .putIfAbsent((r['CONSTANT'] as String).toLowerCase(), () => [])
            .add(r['IDrace'] as int);
      }
      db.dispose();
      final name = RegExp(r'RaceLogo/([^/]+)\.uexp$');
      final ooz = Ooz(Platform.script
          .resolve('../../../native/build/ooz.dll')
          .toFilePath());
      var written = 0, skipped = 0, unknown = 0;
      for (final e in pak.entries) {
        final m = name.firstMatch(e.path);
        if (m == null) continue;
        final races = ids[m[1]!.toLowerCase()];
        if (races == null) {
          unknown++;
          continue;
        }
        final texture = Texture.fromUexp(pak.read(e, decoder: ooz.decode));
        if (texture == null) {
          skipped++;
          continue;
        }
        // 128 px is plenty for the user interface.
        final png = (texture.width > 128 ? texture.shrink(1) : texture).toPng();
        for (final id in races) {
          File('${outDir.path}/$id.png').writeAsBytesSync(png);
          written++;
        }
      }
      pak.close();
      print('$written Rennlogos nach ${outDir.path}, $skipped nicht lesbar, '
          '$unknown ohne Rennen');
    case 'photos':
      // Exports the rider photos of the graphics pack as PNG files, named
      // after the id of the rider.
      final pak = PakFile.open(args[1]);
      final outDir = Directory('${File(worldPath).parent.path}/photos')
        ..createSync(recursive: true);
      final db = openSqlite(worldPath);
      final ids = <String, List<int>>{};
      for (final r in db.select(
          "SELECT IDcyclist, gene_sz_photo FROM raw_DYN_cyclist WHERE gene_sz_photo <> ''")) {
        ids
            .putIfAbsent((r['gene_sz_photo'] as String).toLowerCase(), () => [])
            .add(r['IDcyclist'] as int);
      }
      db.dispose();
      final name = RegExp(r'ProCyclistPhoto/([^/]+)\.uexp$');
      final ooz = Ooz(Platform.script
          .resolve('../../../native/build/ooz.dll')
          .toFilePath());
      var written = 0, skipped = 0;
      for (final e in pak.entries) {
        final m = name.firstMatch(e.path);
        if (m == null) continue;
        final riders = ids[m[1]!.toLowerCase()];
        if (riders == null) continue;
        final texture = Texture.fromUexp(pak.read(e, decoder: ooz.decode));
        if (texture == null) {
          skipped++;
          continue;
        }
        // 128 px is plenty for the rider page.
        var t = texture;
        while (t.width > 128) {
          t = t.shrink(1);
        }
        final png = t.toPng();
        for (final id in riders) {
          File('${outDir.path}/$id.png').writeAsBytesSync(png);
          written++;
        }
      }
      pak.close();
      print('$written Fahrerfotos nach ${outDir.path}, $skipped nicht lesbar');
    case 'game-stages':
      final pak = PakFile.open(args[1]);
      final ooz = Ooz(Platform.script
          .resolve('../../../native/build/ooz.dll')
          .toFilePath());
      final outDir = Directory('$root/GameStages')..createSync();
      var written = 0, failed = 0;
      for (final e in pak.entries) {
        if (!e.path.toLowerCase().endsWith('.cds')) continue;
        try {
          final bytes = pak.read(e, decoder: ooz.decode);
          StageFile.parse(bytes); // only write what can also be read back
          File('${outDir.path}/${e.path.split('/').last}')
              .writeAsBytesSync(bytes);
          written++;
        } on Object catch (err) {
          if (failed++ < 5) stderr.writeln('${e.path}: $err');
        }
      }
      pak.close();
      print(
          '$written Etappen entpackt nach ${outDir.path}, $failed fehlgeschlagen');
      if (failed > 0) exitCode = 1;
    case 'import':
      final watch = Stopwatch()..start();
      final s = importWorld(worlddbDir: root, outPath: worldPath);
      print('${s.tables} Tabellen, ${s.rows} Zeilen gespiegelt');
      print('${s.stagesWithRoute} von ${s.stages} Etappen mit Strecke, '
          'davon ${s.stagesCurrentRoute} im Jahrgang 2026, '
          '${s.stagesWithoutDetails} nur mit Profil');
      print(
          '$worldPath (${(File(worldPath).lengthSync() / 1048576).toStringAsFixed(1)} MB, '
          '${watch.elapsed.inSeconds} s)');
    case 'variants':
      // Adds the routes of earlier seasons for the calibration.
      final db = openSqlite(worldPath);
      db.execute('BEGIN;');
      final added = importVariants(db, root, [2021, 2022, 2023, 2024, 2025]);
      db.execute('COMMIT;');
      db.dispose();
      print('$added Strecken der Jahrgänge 2021 bis 2025 ergänzt');
    case 'classifications':
      // Adds the points schemes to an existing world database.
      final db = openSqlite(worldPath);
      db.execute('BEGIN;');
      final rows = importClassifications(db, root);
      db.execute('COMMIT;');
      db.dispose();
      print('$rows Einträge aus den Classifications-Dateien');
    case 'sql':
      final db = openSqlite(worldPath);
      final result = db.select(args[1]);
      print(result.columnNames.join(' | '));
      for (final row in result) {
        print(row.values
            .map((v) => v is List ? '<${v.length} Bytes>' : '$v')
            .join(' | '));
      }
      db.dispose();
    case 'serve':
      await serveBrowser(
        worldPath: worldPath,
        webDir: Platform.script.resolve('../web').toFilePath(),
      );
    case 'check':
      exitCode = _check(dbPath, stageDir) ? 0 : 1;
    default:
      stdout.write(_usage);
  }
}

/// Loads one table of the .cdb database.
///
/// @param dbPath Path of the .cdb file.
/// @param name Table name, e.g. `DYN_cyclist`.
/// @returns The table; exits the process if it does not exist.
CdbTable _table(String dbPath, String name) {
  final t = CdbDatabase.readFile(dbPath).table(name);
  if (t == null) {
    stderr.writeln('Tabelle $name gibt es nicht.');
    exit(2);
  }
  return t;
}

/// Prints header data, waypoints, climbs and a coarse text profile of a stage.
///
/// @param s The parsed stage file.
void _printStage(StageFile s) {
  print(
      '${s.name}  (Format 0x${s.version.toRadixString(16)}, Gelände ${s.relief})');
  print('${s.lengthKm.toStringAsFixed(1)} km, '
      '${s.elevationGainM.round()} Hm, höchster Punkt ${s.maxAltitudeM.round()} m, '
      '${s.profile.length} Profilpunkte');
  print(
      'Rennen: km ${s.startKm?.toStringAsFixed(1)} bis ${s.finishKm?.toStringAsFixed(1)} '
      'der Straße, ${s.raceDistanceKm.toStringAsFixed(1)} km');
  final start = s.startKm ?? 0;
  for (final w in s.waypoints) {
    if (w.type == WaypointType.feedZone) continue;
    print('  Rennkm ${(w.km - start).toStringAsFixed(1).padLeft(6)}  '
        '${w.type.name.padRight(14)} ${w.detail.toString().padLeft(2)}  ${w.name}');
  }
  for (final c in s.climbs) {
    print('  Anstieg ${c.name}: ${(c.toKm - c.fromKm).toStringAsFixed(1)} km, '
        '${c.avgGradient.toStringAsFixed(1)} % (max ${c.maxGradient.toStringAsFixed(1)} %)');
  }
  for (final x in s.sectors) {
    print('  ${x.cobbled ? 'Pflaster' : 'Unbefestigt'} ${'*' * x.difficulty} '
        '${x.name}: ${((x.toKm - x.fromKm) * 1000).round()} m');
  }
  // Coarse text profile: one line every 5 km.
  final top = s.profile.map((p) => p.altitude).reduce(max);
  var next = 0.0;
  for (final p in s.profile) {
    if (p.km < next) continue;
    next += 5;
    final bar = '#' * (p.altitude / max(top, 1) * 60).round();
    print('${p.km.toStringAsFixed(0).padLeft(4)} km '
        '${p.altitude.round().toString().padLeft(5)} m $bar');
  }
}

/// Reads everything and compares known reference values.
///
/// @param dbPath Path of the .cdb file.
/// @param stageDir Folder with the mod's stage files.
/// @returns true if every check passed.
bool _check(String dbPath, String stageDir) {
  var ok = true;

  /// Compares one value and prints the outcome.
  ///
  /// @param what Label of the check.
  /// @param actual Value that was read.
  /// @param wanted Expected value.
  void expect(String what, Object actual, Object wanted) {
    final good = actual == wanted;
    ok &= good;
    print(
        '${good ? 'ok  ' : 'FEHL'} $what: $actual${good ? '' : ' (erwartet $wanted)'}');
  }

  final db = CdbDatabase.readFile(dbPath);
  expect('Tabellen', db.tables.length, 145);
  final riders = db.table('DYN_cyclist')!;
  expect('Fahrer', riders.rowCount, 8078);
  final names = riders.column('gene_sz_lastname')!.values;
  // The WorldDB stores names without diacritics.
  expect('Pogacar vorhanden', names.contains('Pogacar'), true);
  final races = db.table('STA_race')!;
  final tdf =
      races.rows.firstWhere((r) => r['gene_sz_race_name'] == 'Tour de France');
  expect('Tour de France Etappen', tdf['gene_i_number_stages']!, 21);

  // Tour 2023, stage 17: Col de la Loze (2,304 m) is a known reference value.
  final loze = StageFile.readFile('$stageDir/top_tdf_17_2023.cds');
  expect('Loze höchster Punkt', loze.maxAltitudeM.round(), 2304);
  // The profile only has a point every 200 m, the summit lies in between.
  final lozeTop = loze.profile.map((p) => p.altitude).reduce(max);
  expect('Loze Profilmaximum auf 5 m genau', (lozeTop - 2304).abs() <= 5, true);

  // Stages extracted from the base game (command game-stages), if present.
  final gameDir = Directory('${File(dbPath).parent.path}/GameStages');
  if (gameDir.existsSync()) {
    var n = 0, noDetails = 0, bad = 0;
    for (final f in gameDir.listSync().whereType<File>()) {
      n++;
      final s = StageFile.readFile(f.path);
      if (!s.detailsDecoded) {
        noDetails++;
      } else if (s.startKm == null ||
          s.finishKm == null ||
          (s.finishKm! - s.startKm! - s.raceDistanceKm).abs() > 0.3) {
        bad++;
      }
    }
    expect('Grundspiel-Etappen', n, 1132);
    expect('davon ohne Wegpunkte/Anstiege', noDetails, 3);
    expect('davon Start bis Ziel unstimmig', bad, 0);
    final huez = StageFile.readFile('${gameDir.path}/top_tdf_20_2026.cds');
    expect('Tour 2026 Etappe 20 Ziel', huez.waypoints.last.name, "Alpe d'Huez");
  }

  // Read every stage and check the header against the profile.
  var files = 0,
      failed = 0,
      lengthOff = 0,
      maxOff = 0,
      noDetails = 0,
      raceOff = 0;
  final versions = <int, int>{};
  for (final f in Directory(stageDir).listSync().whereType<File>()) {
    if (!f.path.endsWith('.cds')) continue;
    files++;
    try {
      final s = StageFile.readFile(f.path);
      versions[s.version] = (versions[s.version] ?? 0) + 1;
      if ((s.profile.last.km - s.lengthKm).abs() > 1) lengthOff++;
      final top = s.profile.map((p) => p.altitude).reduce(max);
      if ((top - s.maxAltitudeM).abs() > 15) maxOff++;
      if (!s.detailsDecoded) {
        noDetails++;
      } else if (s.startKm == null ||
          s.finishKm == null ||
          (s.finishKm! - s.startKm! - s.raceDistanceKm).abs() > 0.3) {
        raceOff++;
      }
    } on Object catch (e) {
      failed++;
      if (failed <= 5) print('     ${f.uri.pathSegments.last}: $e');
    }
  }
  expect('Etappendateien', files, 3328);
  expect('nicht lesbar', failed, 0);
  expect('ohne Wegpunkte/Anstiege', noDetails, 21);
  expect('Start bis Ziel weicht von der Renndistanz ab', raceOff, 0);
  final roubaix = StageFile.readFile('$stageDir/topclas_roubaix_2026.cds');
  expect('Roubaix Pflastersektoren',
      roubaix.sectors.where((x) => x.cobbled).length, 30);
  expect('Roubaix Fünf-Sterne-Sektoren',
      roubaix.sectors.where((x) => x.difficulty == 5).length, 3);
  print('     Profilende weicht > 1 km von der Länge ab: $lengthOff');
  print('     Profilmaximum weicht > 15 m vom Kopfwert ab: $maxOff');
  print(
      '     Formatversionen: ${(versions.keys.toList()..sort()).map((v) => '0x${v.toRadixString(16)}×${versions[v]}').join(', ')}');
  return ok;
}
