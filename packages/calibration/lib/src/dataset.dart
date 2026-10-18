import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sim/sim.dart';

import 'pcs.dart';

/// Season of the world database: its calendar carries the routes of this
/// year, earlier years come from the route variants.
const currentSeason = 2026;

/// First season the calibration compares against. Of the fields before it
/// the world database, which knows the riders of [currentSeason], covers
/// too little (58 % of the finishers of 2021, 67 % of 2022); with
/// `--from 2021` those seasons come back with anonymous riders in place of
/// the missing ones (see [loadDataset]).
const firstSeason = 2023;

/// An anonymous rider in place of a finisher the world database does not
/// know: a typical rider of his team in that race (the median of his
/// teammates who are known), or of the whole field without them. Strength
/// is never taken from where he finished, so the result does not leak into
/// the start.
///
/// @param id A negative id, unique in the race.
/// @param name His name from the result.
/// @param mates Known riders of his team in the race.
/// @param field All known riders of the race.
/// @returns The rider.
SimRider anonymousRider(
    int id, String name, List<SimRider> mates, List<SimRider> field) {
  final pool = mates.length >= 2 ? mates : field;
  double total(SimRider r) {
    final a = r.attributes;
    return a.flat + a.mountain + a.hill + a.timeTrial + a.sprint + a.cobble;
  }

  final typical = ([...pool]
    ..sort((a, b) => total(a).compareTo(total(b))))[pool.length ~/ 2];
  final team = mates.isNotEmpty ? mates.first : typical;
  return SimRider(
    id: id,
    name: name,
    teamId: team.teamId,
    team: team.team,
    attributes: typical.attributes,
    born: typical.born,
    potential: typical.potential,
    weightKg: typical.weightKg,
    heightCm: typical.heightCm,
  );
}

/// A real race with route and start list, as the simulation needs it.
class CalibrationCase {
  CalibrationCase(this.label, this.route, this.riders, this.realOrder,
      this.realTimes, this.winnerFromBreak,
      [this.gcGaps = const {}]);

  final String label;
  final SimRoute route;

  /// Riders who finished and were found in the world database.
  final List<SimRider> riders;

  /// Rider ids in the real finishing order.
  final List<int> realOrder;

  /// Real riding times in seconds, parallel to [realOrder].
  final List<double> realTimes;
  final bool winnerFromBreak;

  /// Real gap in the general classification before the stage per rider id;
  /// empty for one-day races and first stages.
  final Map<int, double> gcGaps;

  /// Riding times of all real finishers, sorted ascending, whether they are
  /// in the world database or not. The shape of the real race is measured on
  /// these, so that a winner who has since retired still counts.
  List<double> allTimes = const [];

  /// How the real race was decided according to ProCyclingStats, if known.
  String? wonHow;

  /// Country and month of the race: the frame its weather is drawn from.
  String country = '';
  int month = 6;

  /// Rough classification for the report.
  String get type {
    if (route.kind != StageKind.road) return 'Time trial';
    if (route.sectorRace) return 'Sectors';
    if (route.selectivity < 600 && route.finishGrade < 0.03) return 'Flat';
    if (route.selectivity > 1500) return 'Mountain';
    return 'Hilly';
  }
}

/// All races the calibration compares against.
class Dataset {
  Dataset(this.cases, this.notes);
  final List<CalibrationCase> cases;

  /// Whether a race belongs to the validation set: every fifth race, chosen
  /// by its label so that the split never changes.
  ///
  /// @param label Label of the race.
  /// @returns true for validation, false for training.
  static bool isValidation(String label) =>
      label.codeUnits.fold(7, (h, c) => (h * 31 + c) % 1000003) % 5 == 0;

  /// Races the search tunes on.
  List<CalibrationCase> get training => [
        for (final c in cases)
          if (!isValidation(c.label)) c,
      ];

  /// Races held back to check that the tuning generalises.
  List<CalibrationCase> get validation => [
        for (final c in cases)
          if (isValidation(c.label)) c,
      ];

  /// What was left out while building the dataset, and why.
  final List<String> notes;
}

const _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ą': 'a', //
  'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ę': 'e', 'ě': 'e', 'ė': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ı': 'i',
  'ł': 'l', 'ľ': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ő': 'o',
  'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ß': 'ss', 'ť': 't', 'ţ': 't',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ů': 'u', 'ű': 'u',
  'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z', 'æ': 'ae', 'œ': 'oe',
};

/// Makes names comparable: lower case, no accents, letters only.
///
/// @param name A rider name in any spelling.
/// @returns The normalised name.
String normalizeName(String name) {
  final out = StringBuffer();
  for (final ch in name.toLowerCase().split('')) {
    final c = _fold[ch] ?? ch;
    out.write(RegExp(r'[a-z]').hasMatch(c) || c.length > 1 ? c : ' ');
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Builds the comparison races from the stored results.
///
/// Left out are races without a route of that year, team time trials and
/// races where too few riders could be matched.
///
/// @param world The world database.
/// @param resultsDir Folder with the stored result files.
/// @param year Season.
/// @param exclude Labels of races to leave out, each with the reason.
/// @returns The dataset with notes about what was skipped.
Dataset loadDataset(World world, String resultsDir, int year,
    {Map<String, String> exclude = const {}, bool fill = false}) {
  final notes = <String>[];
  final variants = <int, Map<int, int>>{};
  final byName = <String, SimRider>{};
  final byLastInitial = <String, List<SimRider>>{};
  final tokenSets = <(Set<String>, SimRider)>[];
  for (final r in world.allRiders()) {
    byName['${normalizeName(r.last)} ${normalizeName(r.first)}'] = r.rider;
    final first = normalizeName(r.first);
    tokenSets.add((
      {...normalizeName(r.last).split(' '), ...first.split(' ')}..remove(''),
      r.rider,
    ));
    if (first.isNotEmpty) {
      byLastInitial
          .putIfAbsent('${normalizeName(r.last)} ${first[0]}', () => [])
          .add(r.rider);
    }
  }

  /// Finds the rider of the world database for a ProCyclingStats name.
  ///
  /// @param pcsName Name in the form "LASTNAME Firstname".
  /// @returns The rider, or null if there is no unambiguous match.
  SimRider? match(String pcsName) {
    // ProCyclingStats writes "LASTNAME Firstname", the last name in capitals.
    final parts = pcsName.split(' ');
    final lastParts = parts.where((p) => p == p.toUpperCase() && p.length > 1);
    final firstParts = parts.where((p) => !lastParts.contains(p));
    final last = normalizeName(lastParts.join(' '));
    final first = normalizeName(firstParts.join(' '));
    final exact = byName['$last $first'];
    if (exact != null) return exact;
    if (first.isEmpty) return null;
    final loose = byLastInitial['$last ${first[0]}'];
    if (loose != null && loose.length == 1) return loose.first;
    // Double names differ between the sources ("CORT Magnus" and
    // "Cort Nielsen, Magnus"): an unambiguous subset of the name parts is enough.
    final tokens = {...last.split(' '), ...first.split(' ')}..remove('');
    if (tokens.length < 2) return null;
    final hits = [
      for (final (set, rider) in tokenSets)
        if (set.length >= 2 &&
            (set.containsAll(tokens) || tokens.containsAll(set)))
          rider,
    ];
    return hits.length == 1 ? hits.first : null;
  }

  final cases = <CalibrationCase>[];
  final info = {for (final r in world.races()) r.id: r};
  var unmatched = 0, rows = 0;
  final files = Directory(resultsDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final prologues = {
    for (final f in files)
      if (f.path.endsWith('-prologue.json'))
        (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['raceId']
            as int,
  };
  for (final file in files) {
    final real = RealResult.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    final label = file.uri.pathSegments.last.replaceAll('.json', '');
    if (exclude[year == currentSeason ? label : '$year/$label']
        case final reason?) {
      notes.add('$label: excluded ($reason)');
      continue;
    }
    // Standings before the stage = standings after the stage before it.
    final gcGaps = <int, double>{};
    if (real.page.startsWith('stage-')) {
      final n = int.parse(real.page.split('-').last);
      final base = label.substring(0, label.length - real.page.length);
      final before = File(
          '$resultsDir/$base${n > 1 ? 'stage-${n - 1}' : 'prologue'}.json');
      if (before.existsSync()) {
        final previous = RealResult.fromJson(
            jsonDecode(before.readAsStringSync()) as Map<String, dynamic>);
        for (final row in previous.rows) {
          final rider = row.gcGapS == null ? null : match(row.name);
          if (rider != null) gcGaps[rider.id] = row.gcGapS!;
        }
      }
    }
    // Matched by stage number; the dates in the WorldDB are off by a day in
    // places. A prologue counts as stage 1 in the database.
    final offset = prologues.contains(real.raceId) ? 1 : 0;
    final number = real.page == 'result' || real.page == 'prologue'
        ? 1
        : int.parse(real.page.split('-').last) + offset;
    // The current season uses the routes of the calendar; earlier seasons
    // the route files of their year.
    final int routeId;
    if (year == currentSeason) {
      final stage = world.stageNumber(real.raceId, number);
      if (stage == null) {
        notes.add('$label: no stage $number in the database');
        continue;
      }
      if (stage.variant != '$year') {
        notes.add('$label: route only in the year ${stage.variant}');
        continue;
      }
      routeId = stage.id;
    } else {
      final id = (variants[real.raceId] ??=
          world.variantStages(real.raceId, year))[number];
      if (id == null) {
        notes.add('$label: no route of the year $year');
        continue;
      }
      routeId = id;
    }
    final route = world.route(routeId);
    if (route.kind == StageKind.teamTimeTrial) {
      notes.add('$label: team time trial');
      continue;
    }
    final riders = <SimRider>[];
    final order = <int>[];
    final times = <double>[];
    final seen = <int>{};
    // Finishers the database does not know, with their team, for [fill].
    final missing = <(int, RealRow)>[];
    final teamOf = <String, List<SimRider>>{};
    for (final row in real.rows) {
      if (row.rank == null || row.timeS == null) continue;
      rows++;
      final rider = match(row.name);
      if (rider == null || !seen.add(rider.id)) {
        unmatched++;
        if (rider == null && fill) missing.add((order.length, row));
        continue;
      }
      riders.add(rider);
      order.add(rider.id);
      times.add(row.timeS!);
      teamOf.putIfAbsent(row.team, () => []).add(rider);
    }
    if (fill && missing.isNotEmpty && riders.isNotEmpty) {
      // Inserted from the back so that the earlier positions stay valid.
      for (final (k, (at, row)) in missing.indexed.toList().reversed) {
        final anon = anonymousRider(
            -1 - k, row.name, teamOf[row.team] ?? const [], [...riders]);
        riders.insert(at, anon);
        order.insert(at, anon.id);
        times.insert(at, row.timeS!);
      }
    }
    if (riders.length < 60) {
      notes.add('$label: only ${riders.length} riders matched');
      continue;
    }
    // Who won does not matter for the calibration, so the winner need not
    // be in the database; the shape of the race comes from all finishers.
    final winner = real.rows.first;
    final allTimes = [
      for (final row in real.rows)
        if (row.rank != null && row.timeS != null) row.timeS!,
    ]..sort();
    if (allTimes.isEmpty) continue;
    // Shortened or rerouted stages do not match the route in the database.
    final kmh = route.raceKm / (allTimes.first / 3600);
    final plausible = route.kind == StageKind.road
        ? kmh > 30 && kmh < 53
        : kmh > 35 && kmh < 62;
    if (!plausible) {
      notes.add(
          '$label: an average of ${kmh.toStringAsFixed(1)} km/h does not fit the route');
      continue;
    }
    cases.add(CalibrationCase(year == currentSeason ? label : '$year/$label',
        route, riders, order, times, winner.inBreak, gcGaps)
      ..wonHow = real.wonHow
      ..allTimes = allTimes
      ..country = info[real.raceId]?.country ?? ''
      ..month = info[real.raceId]?.startMonth ?? 6);
  }
  notes.add('$unmatched of $rows finishers not matched '
      '(${(100 * unmatched / max(rows, 1)).toStringAsFixed(1)} %)');
  return Dataset(cases, notes);
}

/// Reads the list of races to leave out of the calibration. One race per
/// line: the label, then `#` and the reason. Empty lines and lines starting
/// with `#` are ignored.
///
/// @param path Path of the file; a missing file means no exclusions.
/// @returns Label to reason.
Map<String, String> loadExclusions(String path) {
  final file = File(path);
  if (!file.existsSync()) return const {};
  final out = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith('#')) continue;
    final at = text.indexOf('#');
    out[(at < 0 ? text : text.substring(0, at)).trim()] =
        at < 0 ? 'no reason given' : text.substring(at + 1).trim();
  }
  return out;
}
