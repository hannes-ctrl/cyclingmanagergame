import 'dart:math';

import 'package:sim/sim.dart';
import 'career.dart';
import 'points.dart';

/// A team's licence.
enum Licence {
  worldTour('WorldTeam'),
  pro('ProTeam'),
  continental('Continental'),
  other('–');

  const Licence(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
}

/// One row of the three-year ranking.
class LicenceRow {
  LicenceRow(this.teamId, this.licence, this.perYear, this.total);
  final int teamId;
  final Licence licence;

  /// Points per year of the current cycle, the current year last.
  final List<double> perYear;
  final double total;
}

/// Team licences with promotion and relegation, after the UCI rules.
///
/// A team's points of a season are those of its 20 best riders. The points
/// of three years count: at the end of every cycle the best teams of the
/// ranking receive the WorldTour licences, the others continue as
/// ProTeams. Each year the two best ProTeams of the season are invited to
/// all WorldTour races of the following year. ProTeam licences are given
/// for a year, as a matter of money more than of points: a ProTeam deep in
/// debt or without the riders it needs drops to the Continental level, and
/// the best Continental teams that can afford it take the free places.
class Licences {
  Licences(this.c) : firstYear = c.year {
    var pro = 0;
    for (final t in c.teams.values) {
      if (t.division.startsWith('[2]')) pro++;
      _level[t.id] = t.division.startsWith('[1]')
          ? Licence.worldTour
          : t.division.startsWith('[2]')
              ? Licence.pro
              : t.division.startsWith('[3]')
                  ? Licence.continental
                  : Licence.other;
    }
    proPlaces = pro;
  }

  final Career c;
  int firstYear;
  final _level = <int, Licence>{};

  /// Team points of finished seasons per year.
  final seasons = <int, Map<int, double>>{};

  /// ProTeams invited to all WorldTour races this season.
  var wildcards = <int>{};

  /// @param teamId Team id.
  /// @returns Its current licence.
  Licence of(int teamId) => _level[teamId] ?? Licence.other;

  /// @param l A licence.
  /// @returns The ids of all teams holding it.
  List<int> teamsWith(Licence l) => [
        for (final e in _level.entries)
          if (e.value == l) e.key,
      ];

  /// First year of the current three-year cycle.
  int get cycleStart => firstYear + 3 * ((c.year - firstYear) ~/ 3);

  /// Last year of the current cycle.
  int get cycleEnd => cycleStart + 2;

  /// Riders whose points count for a team in a season.
  static const countingRiders = 20;

  /// A team's points of the running season: those of its 20 best riders.
  ///
  /// @param teamId Team id.
  /// @returns The points.
  double seasonPoints(int teamId) {
    final points = [
      for (final r in c.squads[teamId] ?? const <SimRider>[])
        c.riderPoints[r.id] ?? 0.0,
    ]..sort((a, b) => b.compareTo(a));
    return points.take(countingRiders).fold(0.0, (a, b) => a + b);
  }

  /// Budget a Continental team needs to step up to a ProTeam.
  static const proBudget = 3000000.0;

  /// Number of ProTeam licences, as in the WorldDB.
  late final int proPlaces;

  /// A team's points of the running season; once the season has been
  /// noted, the noted ones, because the transfers of the winter move riders
  /// between teams.
  double _current(int teamId) => seasons.containsKey(c.year)
      ? seasons[c.year]![teamId] ?? 0
      : seasonPoints(teamId);

  /// Notes the points of the season before the transfers of the turn of the
  /// year move riders between teams.
  void noteSeason() {
    seasons[c.year] = {
      for (final id in _level.keys)
        if (seasonPoints(id) > 0) id: seasonPoints(id),
    };
  }

  /// @param teamId Team id.
  /// @returns Its points in the current cycle including the running season.
  double _total(int teamId) {
    var sum = _current(teamId);
    for (var y = cycleStart; y < c.year; y++) {
      sum += seasons[y]?[teamId] ?? 0;
    }
    return sum;
  }

  /// Three-year ranking.
  ///
  /// @param of Licences to include.
  /// @returns One row per team, best first.
  List<LicenceRow> ranking(
      [Set<Licence> of = const {Licence.worldTour, Licence.pro}]) {
    final rows = [
      for (final e in _level.entries)
        if (of.contains(e.value))
          LicenceRow(
            e.key,
            e.value,
            [
              for (var y = cycleStart; y < c.year; y++) seasons[y]?[e.key] ?? 0,
              _current(e.key),
            ],
            _total(e.key),
          ),
    ];
    return rows..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Number of WorldTour licences; that many teams stay up.
  int get worldTourPlaces => teamsWith(Licence.worldTour).length;

  /// Field of a race under today's licences.
  ///
  /// @param invited Invitations of the WorldDB, which are right for the first
  ///   season.
  /// @param tier Tier of the race.
  /// @returns The invited teams.
  List<int> field(List<int> invited, RaceTier tier) {
    final top = tier == RaceTier.grandTour ||
        tier == RaceTier.monument ||
        tier == RaceTier.worldTour;
    if (!top) return invited;
    final wt = teamsWith(Licence.worldTour);
    final out = [
      for (final id in invited)
        // Relegated teams lose their guaranteed place.
        if (wt.contains(id) ||
            !(c.teams[id]?.division.startsWith('[1]') ?? false))
          id,
    ];
    for (final id in [...wt, ...wildcards]) {
      if (!out.contains(id)) out.add(id);
    }
    return out;
  }

  /// Closes the season: stores the points, determines next year's invitations
  /// and, at the end of a cycle, reassigns the licences. Must run before the
  /// career clears the points and advances the year.
  void closeSeason() {
    if (!seasons.containsKey(c.year)) noteSeason();
    final pro = teamsWith(Licence.pro)
      ..sort((a, b) => _current(b).compareTo(_current(a)));
    wildcards = pro.take(2).toSet();
    String names(Iterable<int> ids) =>
        ids.map((id) => c.teams[id]?.name ?? '?').join(', ');
    final (lost, gained) = _proLicences();
    final proNews = lost.isEmpty && gained.isEmpty
        ? ''
        : ' ${tr('ProTeam licences: lost by {0}; new: {1}.', [
                lost.isEmpty ? '–' : names(lost),
                gained.isEmpty ? '–' : names(gained),
              ])}';
    // With a ProTeam licence won or lost, what the sponsors pay changes.
    if (gained.contains(c.teamId)) c.economy.scaleSponsors(1.25);
    if (lost.contains(c.teamId)) c.economy.scaleSponsors(0.75);

    if (c.year < cycleEnd) {
      c.inbox.add(Message(
        c.today,
        'UCI',
        tr('Invitations {0}', [c.year + 1]),
        tr('As the best ProTeams of the season, {0} may start in every WorldTour race next year.{1}', [
              names(wildcards),
              () {
                final at = ranking().indexWhere((r) => r.teamId == c.teamId);
                return at < 0
                    ? ''
                    : tr(
                        ' In the three-year ranking {0}–{1} our team is in place {2}.',
                        [cycleStart, cycleEnd, at + 1]);
              }()
            ]) +
            proNews,
      ));
      return;
    }

    // End of the cycle: the best of the ranking receive the WorldTour licences.
    final places = worldTourPlaces;
    final order = ranking();
    final up = <int>[], down = <int>[];
    for (var i = 0; i < order.length; i++) {
      final id = order[i].teamId;
      final next = i < places ? Licence.worldTour : Licence.pro;
      if (next != _level[id]) (next == Licence.worldTour ? up : down).add(id);
      _level[id] = next;
    }
    final own = _level[c.teamId];
    final before = up.contains(c.teamId)
        ? 'Promotion'
        : down.contains(c.teamId)
            ? 'Relegation'
            : null;
    // With the licence, what sponsors pay changes.
    if (before == 'Promotion') c.economy.scaleSponsors(1.25);
    if (before == 'Relegation') c.economy.scaleSponsors(0.75);
    c.inbox.add(Message(
      c.today,
      'UCI',
      tr('Licences {0}–{1} awarded', [c.year + 1, c.year + 3]),
      '${up.isEmpty ? tr('Nothing changes in the WorldTour.') : tr('New in the WorldTour: {0}. Relegated: {1}.', [names(up), names(down)])} ${before == null ? tr('Our team continues as a {0}.', [
              own?.label
            ]) : tr('{0}: Our team now rides as a {1}; the sponsor budget {2} by a quarter.', [
              tr(before),
              own?.label,
              before == 'Promotion' ? tr('rises') : tr('falls')
            ])}$proNews',
    ));
  }

  /// The yearly ProTeam licences: a ProTeam deep in debt, or with fewer
  /// riders than a ProTeam must have, drops to the Continental level; the
  /// free places go to the Continental teams with the most points of the
  /// season that have the budget for it.
  ///
  /// @returns The teams that lost and those that gained a ProTeam licence.
  (List<int>, List<int>) _proLicences() {
    final lost = [
      for (final id in teamsWith(Licence.pro))
        if (c.finances.balanceOf(id) < -0.25 * c.finances.budgetOf(id) ||
            (c.squads[id]?.length ?? 0) < 20)
          id,
    ];
    for (final id in lost) {
      _level[id] = Licence.continental;
    }
    final free = proPlaces - teamsWith(Licence.pro).length;
    final candidates = [
      for (final id in teamsWith(Licence.continental))
        if (!lost.contains(id) &&
            c.finances.budgetOf(id) >= proBudget &&
            _current(id) > 0)
          id,
    ]..sort((a, b) => _current(b).compareTo(_current(a)));
    final gained = candidates.take(max(0, free)).toList();
    for (final id in gained) {
      _level[id] = Licence.pro;
    }
    return (lost, gained);
  }

  /// @returns Licences, past seasons and invitations as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'firstYear': firstYear,
        'level': {for (final e in _level.entries) '${e.key}': e.value.index},
        'seasons': {
          for (final s in seasons.entries)
            '${s.key}': {
              for (final e in s.value.entries) '${e.key}': e.value,
            },
        },
        'wildcards': wildcards.toList(),
      };

  /// Replaces the state with that of a snapshot.
  ///
  /// @param j A map written by [toJson].
  void restore(Map<String, dynamic> j) {
    firstYear = j['firstYear'] as int;
    _level
      ..clear()
      ..addAll({
        for (final e in (j['level'] as Map<String, dynamic>).entries)
          int.parse(e.key): Licence.values[e.value as int],
      });
    seasons
      ..clear()
      ..addAll({
        for (final s in (j['seasons'] as Map<String, dynamic>).entries)
          int.parse(s.key): {
            for (final e in (s.value as Map<String, dynamic>).entries)
              int.parse(e.key): (e.value as num).toDouble(),
          },
      });
    wildcards = (j['wildcards'] as List).cast<int>().toSet();
  }
}
