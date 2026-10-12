import 'career.dart';
import 'points.dart';

/// A team's licence.
enum Licence {
  worldTour('WorldTeam'),
  pro('ProTeam'),
  continental('Continental'),
  other('–');

  const Licence(this.label);
  final String label;
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

/// Team licences with promotion and relegation.
///
/// As with the UCI, the points of three years count: at the end of every
/// cycle the best teams of the ranking receive the WorldTour licences, the
/// others continue as ProTeams. In addition, each year the two best ProTeams
/// of the season are invited to all WorldTour races of the following year.
/// Two ProTeams and two Continental teams swap places per cycle; in reality
/// that is a matter of money and application, not of points.
class Licences {
  Licences(this.c) : firstYear = c.year {
    for (final t in c.teams.values) {
      _level[t.id] = t.division.startsWith('[1]')
          ? Licence.worldTour
          : t.division.startsWith('[2]')
              ? Licence.pro
              : t.division.startsWith('[3]')
                  ? Licence.continental
                  : Licence.other;
    }
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

  /// @param teamId Team id.
  /// @returns Its points in the current cycle including the running season.
  double _total(int teamId) {
    var sum = c.teamPoints[teamId] ?? 0;
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
              c.teamPoints[e.key] ?? 0,
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
    seasons[c.year] = {...c.teamPoints};
    final pro = teamsWith(Licence.pro)
      ..sort((a, b) => (c.teamPoints[b] ?? 0).compareTo(c.teamPoints[a] ?? 0));
    wildcards = pro.take(2).toSet();
    String names(Iterable<int> ids) =>
        ids.map((id) => c.teams[id]?.name ?? '?').join(', ');

    if (c.year < cycleEnd) {
      c.inbox.add(Message(
        c.today,
        'UCI',
        'Einladungen ${c.year + 1}',
        'Als beste ProTeams der Saison dürfen ${names(wildcards)} im '
            'nächsten Jahr bei allen WorldTour-Rennen starten.'
            '${() {
          final at = ranking().indexWhere((r) => r.teamId == c.teamId);
          return at < 0
              ? ''
              : ' In der Dreijahreswertung $cycleStart–$cycleEnd liegt '
                  'unser Team auf Platz ${at + 1}.';
        }()}',
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
    // The two weakest ProTeams swap with the two best Continental teams;
    // freshly relegated teams are spared.
    final weakest = [
      for (final r in order.reversed)
        if (!down.contains(r.teamId) && _level[r.teamId] == Licence.pro)
          r.teamId,
    ].take(2).toList();
    final best = ranking({Licence.continental}).take(2).map((r) => r.teamId);
    for (final id in weakest) {
      _level[id] = Licence.continental;
    }
    for (final id in best.toList()) {
      _level[id] = Licence.pro;
    }
    final own = _level[c.teamId];
    final before = up.contains(c.teamId) || best.contains(c.teamId)
        ? 'Aufstieg'
        : down.contains(c.teamId) || weakest.contains(c.teamId)
            ? 'Abstieg'
            : null;
    // With the licence, what sponsors pay changes.
    if (before == 'Aufstieg') c.economy.scaleSponsors(1.25);
    if (before == 'Abstieg') c.economy.scaleSponsors(0.75);
    c.inbox.add(Message(
      c.today,
      'UCI',
      'Lizenzen ${c.year + 1}–${c.year + 3} vergeben',
      '${up.isEmpty ? 'In der WorldTour bleibt alles beim Alten.' : 'Neu in der WorldTour: ${names(up)}. Abgestiegen: ${names(down)}.'} '
          'Neue ProTeams: ${names(best)}; künftig Continental: ${names(weakest)}. '
          '${before == null ? 'Unser Team fährt weiter als ${own?.label}.' : '$before: Unser Team fährt ab jetzt als ${own?.label}, '
              'das Sponsorenbudget ${before == 'Aufstieg' ? 'steigt' : 'sinkt'} um ein Viertel.'}',
    ));
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
