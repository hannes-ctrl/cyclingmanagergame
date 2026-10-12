import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'importer.dart';

/// Local database browser: serves `web/index.html` and a small JSON API on
/// top of the world database. Read-only.
///
/// @param worldPath Path of `world.sqlite`.
/// @param webDir Folder containing `index.html`.
/// @param port TCP port to listen on.
/// @returns A future that completes when the server stops.
Future<void> serveBrowser({
  required String worldPath,
  required String webDir,
  int port = 8765,
}) async {
  final db = openSqlite(worldPath);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  print('Datenbank-Browser: http://localhost:$port');

  await for (final request in server) {
    final response = request.response;
    try {
      final path = request.uri.path;
      final query = request.uri.queryParameters;
      if (path == '/' || path == '/index.html') {
        response.headers.contentType = ContentType.html;
        response.add(File('$webDir/index.html').readAsBytesSync());
      } else if (path.startsWith('/api/')) {
        final body = _api(db, path.substring(5), query);
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(body));
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    } on Object catch (e) {
      response.statusCode = HttpStatus.internalServerError;
      response.write('$e');
    }
    await response.close();
  }
}

/// Runs a query and converts the result into JSON-friendly maps.
///
/// @param db Open world database.
/// @param sql Query text.
/// @param params Positional query parameters.
/// @returns One map per row, keyed by column name.
List<Map<String, Object?>> _rows(Database db, String sql,
        [List<Object?> params = const []]) =>
    [for (final row in db.select(sql, params)) Map.of(row)];

/// Answers one API call of the browser.
///
/// @param db Open world database.
/// @param name Endpoint name, e.g. `teams` or `stage`.
/// @param q Query parameters of the request.
/// @returns A JSON-encodable value, or null for an unknown endpoint.
Object? _api(Database db, String name, Map<String, String> q) {
  int id() => int.parse(q['id'] ?? '0');
  switch (name) {
    case 'teams':
      return _rows(db, '''
        SELECT t.*, (SELECT count(*) FROM rider r WHERE r.team_id = t.id) AS riders
        FROM team t ORDER BY t.division, t.name''');
    case 'riders':
      if (q.containsKey('q')) {
        return _rows(db, '''
          SELECT r.*, t.abbr AS team FROM rider r LEFT JOIN team t ON t.id = r.team_id
          WHERE r.last_name || ' ' || r.first_name LIKE ? ORDER BY r.mountain + r.flat DESC
          LIMIT 200''', ['%${q['q']}%']);
      }
      return _rows(db, '''
        SELECT r.*, t.abbr AS team FROM rider r LEFT JOIN team t ON t.id = r.team_id
        WHERE r.team_id = ? ORDER BY r.last_name''', [id()]);
    case 'races':
      return _rows(db, 'SELECT * FROM race ORDER BY start_mmdd, name');
    case 'stages':
      return _rows(
          db, 'SELECT * FROM stage WHERE race_id = ? ORDER BY number', [id()]);
    case 'stage':
      final route =
          _rows(db, 'SELECT * FROM stage_route WHERE stage_id = ?', [id()]);
      if (route.isEmpty) return null;
      final r = route.first;
      final blob = r.remove('profile') as Uint8List;
      final raw = Float32List.sublistView(Uint8List.fromList(blob));
      final start = r['start_km'] as double;
      return {
        ...r,
        // Race kilometres instead of road kilometres, rounded to 10 m and 1 m.
        'profile': [
          for (var i = 0; i < raw.length; i += 2)
            [((raw[i] - start) * 100).round() / 100, raw[i + 1].round()],
        ],
        'waypoints': _rows(
            db,
            'SELECT * FROM stage_waypoint WHERE stage_id = ? ORDER BY seq',
            [id()]),
        'climbs': _rows(
            db,
            'SELECT * FROM stage_climb WHERE stage_id = ? ORDER BY seq',
            [id()]),
        'sectors': _rows(
            db,
            'SELECT * FROM stage_sector WHERE stage_id = ? ORDER BY seq',
            [id()]),
      };
  }
  throw ArgumentError('Unbekannte Abfrage $name');
}
