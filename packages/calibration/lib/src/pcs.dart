import 'dart:convert';
import 'dart:io';

/// Slugs of the WorldTour races at ProCyclingStats, by race id of the world database.
const pcsSlugs = <int, String>{
  294: 'tour-down-under',
  551: 'great-ocean-road-race',
  297: 'uae-tour',
  24: 'omloop-het-nieuwsblad',
  43: 'strade-bianche',
  133: 'paris-nice',
  139: 'tirreno-adriatico',
  77: 'milano-sanremo',
  91: 'volta-a-catalunya',
  319: 'classic-brugge-de-panne',
  39: 'e3-harelbeke',
  13: 'gent-wevelgem',
  317: 'dwars-door-vlaanderen',
  11: 'ronde-van-vlaanderen',
  12: 'itzulia-basque-country',
  4: 'paris-roubaix',
  173: 'amstel-gold-race',
  15: 'la-fleche-wallonne',
  87: 'liege-bastogne-liege',
  19: 'tour-de-romandie',
  44: 'eschborn-frankfurt',
  135: 'giro-d-italia',
  74: 'tour-auvergne-rhone-alpes',
  29: 'copenhagen-sprint',
  5: 'tour-de-suisse',
  25: 'tour-de-france',
  49: 'san-sebastian',
  359: 'tour-de-pologne',
  26: 'cyclassics-hamburg',
  93: 'renewi-tour',
  18: 'vuelta-a-espana',
  28: 'bretagne-classic',
  405: 'gp-quebec',
  406: 'gp-montreal',
  172: 'il-lombardia',
};

/// One row of a real result table.
class RealRow {
  RealRow(this.rank, this.slug, this.name, this.team, this.timeS, this.inBreak,
      [this.gcGapS]);

  /// Place, or null for an abandon, time cut or non-starter.
  final int? rank;

  /// Rider slug at ProCyclingStats, e.g. `tadej-pogacar`.
  final String slug;

  /// "LASTNAME Firstname".
  final String name;
  final String team;

  /// Riding time in seconds, null without a placing.
  final double? timeS;

  /// According to the page the rider was in a group ahead of the field.
  final bool inBreak;

  /// Gap in the general classification after this stage in seconds, null for
  /// one-day races or if the page does not give it.
  final double? gcGapS;

  /// @returns The row as a JSON-encodable map.
  Map<String, Object?> toJson() => {
        'rank': rank,
        'slug': slug,
        'name': name,
        'team': team,
        'timeS': timeS,
        'inBreak': inBreak,
        'gcGapS': gcGapS,
      };

  /// @param j A map written by [toJson].
  /// @returns The row.
  static RealRow fromJson(Map<String, dynamic> j) => RealRow(
        j['rank'] as int?,
        j['slug'] as String,
        j['name'] as String,
        j['team'] as String,
        (j['timeS'] as num?)?.toDouble(),
        j['inBreak'] as bool,
        (j['gcGapS'] as num?)?.toDouble(),
      );
}

/// A real result of one race day.
class RealResult {
  RealResult(this.raceId, this.page, this.month, this.day, this.rows,
      {this.wonHow});

  /// The page's "Won how" field, e.g. "Bunchsprint" or "18.5 km solo"; null
  /// if the page has none.
  final String? wonHow;
  final int raceId;

  /// Page name at ProCyclingStats (`result`, `stage-12`, `prologue`).
  final String page;
  final int month;
  final int day;
  final List<RealRow> rows;

  /// @returns The result as a JSON-encodable map.
  Map<String, Object?> toJson() => {
        'raceId': raceId,
        'page': page,
        'month': month,
        'day': day,
        'rows': [for (final r in rows) r.toJson()],
        'wonHow': wonHow,
      };

  /// @param j A map written by [toJson].
  /// @returns The result.
  static RealResult fromJson(Map<String, dynamic> j) => RealResult(
        j['raceId'] as int,
        j['page'] as String,
        j['month'] as int,
        j['day'] as int,
        [
          for (final r in j['rows'] as List)
            RealRow.fromJson(r as Map<String, dynamic>)
        ],
        wonHow: j['wonHow'] as String?,
      );
}

const _months = [
  'january', 'february', 'march', 'april', 'may', 'june', 'july', //
  'august', 'september', 'october', 'november', 'december',
];

String _strip(String html) => html
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

double? _seconds(String text) {
  final m = RegExp(r'(\d+):(\d\d)(?::(\d\d))?').firstMatch(text);
  if (m == null) return null;
  final a = int.parse(m[1]!), b = int.parse(m[2]!);
  return m[3] == null ? a * 60.0 + b : a * 3600.0 + b * 60 + int.parse(m[3]!);
}

/// Reads the first result table of a result page.
///
/// @param html Page source.
/// @param raceId Race id of the world database.
/// @param page Page name, see [RealResult.page].
/// @param year Season.
/// @returns The result, or null if the page holds no individual result
///   (race not ridden yet, team time trial, unknown page).
RealResult? parseResultPage(String html, int raceId, String page, int year) {
  final dateMatch =
      RegExp('(\\d{1,2}) (${_months.join('|')}) $year', caseSensitive: false)
          .firstMatch(html);
  if (dateMatch == null) return null;
  final day = int.parse(dateMatch[1]!);
  final month = _months.indexOf(dateMatch[2]!.toLowerCase()) + 1;

  final tableStart = html.indexOf('<table class="unit results');
  if (tableStart < 0) return null;
  final tableEnd = html.indexOf('</table>', tableStart);
  final table = html.substring(tableStart, tableEnd);
  final headers = [
    for (final m in RegExp(r'<th[^>]*data-code="([^"]*)"').allMatches(table))
      m[1]!,
  ];
  final rankCol = headers.indexOf('rnk');
  final riderCol = headers.indexOf('rider');
  final teamCol = headers.indexOf('riderteam');
  final timeCol = headers.lastIndexOf('timelag');
  final gcRankCol = headers.indexOf('gc');
  final gcGapCol = headers.indexOf('gc_timelag');
  if (rankCol < 0 || riderCol < 0 || timeCol < 0) return null;

  final rows = <RealRow>[];
  double? winner, previous;
  for (final tr in RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true)
      .allMatches(table.substring(table.indexOf('<tbody')))) {
    final cells = [
      for (final m
          in RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true).allMatches(tr[1]!))
        m[1]!,
    ];
    if (cells.length <= timeCol) continue;
    final rider = RegExp(r'href="rider/([^"]+)"[^>]*>([^<]+)<')
        .firstMatch(cells[riderCol]);
    if (rider == null) continue;
    final rank = int.tryParse(_strip(cells[rankCol]));
    double? time;
    if (rank != null) {
      final text = _strip(cells[timeCol]);
      final parsed = _seconds(text);
      if (winner == null) {
        winner = parsed;
        time = parsed;
      } else if (parsed == null) {
        time = previous; // ",," means the same time as the rider before
      } else {
        time = winner + parsed;
      }
      previous = time;
    }
    rows.add(RealRow(
      rank,
      rider[1]!,
      rider[2]!.trim(),
      teamCol >= 0 ? _strip(cells[teamCol]) : '',
      time,
      cells[riderCol].contains('svg_shield'),
      gcRankCol < 0 || gcGapCol < 0
          ? null
          : _strip(cells[gcRankCol]) == '1'
              ? 0
              : _seconds(_strip(cells[gcGapCol])),
    ));
  }
  if (rows.length < 20 || winner == null) return null;
  final how = RegExp(r'Won how:\s*</div>\s*<div[^>]*>([^<]*)').firstMatch(html);
  final wonHow = how?[1]?.trim();
  return RealResult(raceId, page, month, day, rows,
      wonHow: wonHow == null || wonHow.isEmpty ? null : wonHow);
}

/// Fetches a page through curl, with a cache on disk and a pause between two
/// network requests. The site rejects Dart's own HTTP client but not curl
/// with an honest user agent.
class PcsClient {
  PcsClient(this.cacheDir) {
    Directory(cacheDir).createSync(recursive: true);
  }

  final String cacheDir;
  static const _agent = 'radmanager-calibration/0.1 (privates Hobbyprojekt)';
  static const _pause = Duration(seconds: 2);
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Fetches one result page.
  ///
  /// @param slug Race slug, see [pcsSlugs].
  /// @param year Season.
  /// @param page Page name, e.g. `stage-3`.
  /// @returns The page source, or null if it could not be fetched.
  Future<String?> page(String slug, int year, String page) async {
    final file = File('$cacheDir/$slug-$year-$page.html');
    if (file.existsSync()) return file.readAsStringSync();
    final wait = _pause - DateTime.now().difference(_last);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final result = await Process.run(
      'curl',
      [
        '-s', '-L', '--max-time', '40', '-A', _agent, //
        '-w', r'\n%{http_code}',
        'https://www.procyclingstats.com/race/$slug/$year/$page',
      ],
      stdoutEncoding: utf8,
    );
    final out = result.stdout as String;
    final cut = out.lastIndexOf('\n');
    if (result.exitCode != 0 ||
        cut < 0 ||
        out.substring(cut + 1).trim() != '200') {
      return null;
    }
    final body = out.substring(0, cut);
    file.writeAsStringSync(body);
    return body;
  }

  /// Nothing to release; kept for symmetry with other clients.
  void close() {}
}
