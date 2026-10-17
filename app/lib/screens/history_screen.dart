import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

/// The views of the history page.
enum _View { trophies, seasons, records, retired }

/// The history of the career: the team's trophies and seasons, the records
/// of all riders, and the careers of those who have retired.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.state});
  final AppState state;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

/// State of the page: the view and the retired rider shown in detail.
class _HistoryScreenState extends State<HistoryScreen> {
  var _view = _View.trophies;
  int? _retired;

  @override
  Widget build(BuildContext context) {
    final c = widget.state.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TabStrip<_View>(
          colors: c,
          tabs: {
            _View.trophies: tr('Trophy room'),
            _View.seasons: tr('Seasons'),
            _View.records: tr('Records'),
            _View.retired: tr('Retired riders'),
          },
          value: _view,
          onChanged: (v) => setState(() => _view = v),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: switch (_view) {
              _View.trophies => _trophies(),
              _View.seasons => _seasons(),
              _View.records => _records(),
              _View.retired => _retiredView(),
            },
          ),
        ),
      ],
    );
  }

  /// The team's wins of big races: those of finished seasons from the
  /// archive and those of the running season.
  List<(int year, String race, String tier, String rider)> _trophyRows() {
    final s = widget.state;
    final career = s.career;
    final abbr = s.team.abbr;
    final rows = <(int, String, String, String)>[
      for (final season in career.archive)
        for (final w in (season['winners'] as List).cast<List<dynamic>>())
          if (w[3] == abbr)
            (
              season['year'] as int,
              w[0] as String,
              w[1] as String,
              w[2] as String,
            ),
    ];
    for (final p in career.progress.values) {
      final national = p.race.info.raceClass.startsWith('National');
      final big =
          p.race.tier.factor >= 5 ||
          (p.race.tier == RaceTier.championship && !national);
      if (!p.finished || !big) continue;
      final w = p.race.isStageRace
          ? p.run.standings.last.general.first.rider
          : p.run.results.last.placings.first.rider;
      if ((career.riderById[w.id]?.teamId ?? w.teamId) != s.team.id) continue;
      rows.add((
        career.year,
        p.race.info.name,
        p.race.tier.label,
        career.fullName(w.id),
      ));
    }
    return rows..sort((a, b) => b.$1.compareTo(a.$1));
  }

  Widget _trophies() {
    final s = widget.state;
    final c = s.colors;
    final rows = _trophyRows();
    if (rows.isEmpty) {
      return Center(
        child: Text(
          tr(
            'No big race won yet. Monuments, Grand Tours, WorldTour races and championships come here.',
          ),
          style: const TextStyle(color: TeamColors.muted),
        ),
      );
    }
    return Panel(
      colors: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Label(tr('Trophy room · {0}', [rows.length])),
          const SizedBox(height: 6),
          Expanded(
            child: DenseTable<(int, String, String, String)>(
              colors: c,
              rows: rows,
              columns: [
                Col(
                  tr('Year'),
                  60,
                  (r, _) => cellText('${r.$1}'),
                  numeric: true,
                  sortKey: (r) => r.$1,
                ),
                Col(
                  tr('Race'),
                  280,
                  (r, _) => cellText(r.$2, bold: true),
                  sortKey: (r) => r.$2,
                ),
                Col(
                  tr('Category'),
                  140,
                  (r, _) => cellText(r.$3, color: TeamColors.muted),
                ),
                Col(
                  tr('Winner'),
                  220,
                  (r, _) => cellText(r.$4),
                  sortKey: (r) => r.$4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seasons() {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final wins = {
      for (final a in career.archive)
        a['year'] as int: ((a['own'] as Map<String, dynamic>)['wins'] as num)
            .toInt(),
    };
    final trophies = <int, int>{};
    for (final t in _trophyRows()) {
      trophies[t.$1] = (trophies[t.$1] ?? 0) + 1;
    }
    // The team the player ran in each season.
    int teamOf((int, int, double, int, bool) r) =>
        r.$5 ? career.teamId : career.manager.seasons[r.$1] ?? career.startTeam;
    final rows = <(int, int, double, int, bool)>[
      (
        career.year,
        career.economy.ownRank,
        career.teamPoints[s.team.id] ?? 0,
        career.economy.wins,
        true,
      ),
      for (final h in career.history.reversed)
        (h.year, h.rank, h.points, wins[h.year] ?? 0, false),
    ];
    return Panel(
      colors: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Label(
            career.manager.seasons.values.any((t) => t != career.teamId)
                ? tr('Your seasons as a manager')
                : tr('Seasons of {0}', [s.team.name]),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: DenseTable<(int, int, double, int, bool)>(
              colors: c,
              rows: rows,
              highlight: (r) => r.$5,
              columns: [
                Col(
                  tr('Year'),
                  70,
                  (r, _) =>
                      cellText(r.$5 ? tr('{0} (running)', [r.$1]) : '${r.$1}'),
                  sortKey: (r) => r.$1,
                ),
                Col(
                  tr('Team'),
                  70,
                  (r, _) => cellText(career.teams[teamOf(r)]?.abbr ?? ''),
                  sortKey: (r) => career.teams[teamOf(r)]?.abbr ?? '',
                ),
                Col(
                  tr('Place'),
                  70,
                  (r, _) => cellText('${r.$2}'),
                  numeric: true,
                  sortKey: (r) => r.$2,
                ),
                Col(
                  tr('Points'),
                  90,
                  (r, _) => cellText('${r.$3.round()}'),
                  numeric: true,
                  sortKey: (r) => r.$3,
                ),
                Col(
                  tr('Wins'),
                  70,
                  (r, _) => cellText('${r.$4}'),
                  numeric: true,
                  sortKey: (r) => r.$4,
                ),
                Col(
                  tr('Big races'),
                  90,
                  (r, _) => cellText('${trophies[r.$1] ?? 0}'),
                  numeric: true,
                  sortKey: (r) => trophies[r.$1] ?? 0,
                ),
                // The manager's reputation at the end of the season.
                Col(
                  tr('Reputation'),
                  90,
                  (r, _) => cellText(switch (r.$5
                      ? career.manager.reputation
                      : career.manager.marks[r.$1]) {
                    final v? => '${v.round()}',
                    null => '–',
                  }),
                  numeric: true,
                  sortKey: (r) =>
                      (r.$5
                          ? career.manager.reputation
                          : career.manager.marks[r.$1]) ??
                      -1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _records() {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final names = {for (final r in career.retired) r[0] as int: r[1] as String};
    String name(int id) => names[id] ?? career.fullName(id);
    // Best seasons of all riders, finished seasons only.
    (int, List<dynamic>)? best(num Function(List<dynamic>) by) {
      (int, List<dynamic>)? top;
      for (final e in career.riderSeasons.entries) {
        for (final line in e.value) {
          if (top == null || by(line) > by(top.$2)) top = (e.key, line);
        }
      }
      return top;
    }

    final points = best((l) => l[2] as num);
    final wins = best((l) => l[3] as num);
    final days = best((l) => l[4] as num);
    // Most wins over a career.
    final career0 = <int, int>{};
    for (final e in career.palmares.entries) {
      career0[e.key] = e.value
          .where((p) => !(p[2] as String).contains('overall'))
          .length;
    }
    final mostWins = career0.entries.isEmpty
        ? null
        : career0.entries.reduce((a, b) => b.value > a.value ? b : a);
    final own = career.history.isEmpty
        ? null
        : career.history.reduce((a, b) => b.points > a.points ? b : a);
    final lines = <(String, String)>[
      if (points != null)
        (
          tr('Most points in a season'),
          tr('{0}: {1} ({2}, {3})', [
            name(points.$1),
            (points.$2[2] as num).round(),
            points.$2[0],
            points.$2[1],
          ]),
        ),
      if (wins != null && (wins.$2[3] as num) > 0)
        (
          tr('Most wins in a season'),
          tr('{0}: {1} ({2}, {3})', [
            name(wins.$1),
            wins.$2[3],
            wins.$2[0],
            wins.$2[1],
          ]),
        ),
      if (days != null)
        (
          tr('Most race days in a season'),
          tr('{0}: {1} ({2}, {3})', [
            name(days.$1),
            days.$2[4],
            days.$2[0],
            days.$2[1],
          ]),
        ),
      if (mostWins != null && mostWins.value > 0)
        (
          tr('Most wins since the start of the career'),
          tr('{0}: {1}', [name(mostWins.key), mostWins.value]),
        ),
      if (own != null)
        (
          tr('Best season of {0}', [s.team.name]),
          tr('{0}: place {1}, {2} points', [
            own.year,
            own.rank,
            own.points.round(),
          ]),
        ),
    ];
    if (lines.isEmpty) {
      return Center(
        child: Text(
          tr('The records fill at the end of the first season.'),
          style: const TextStyle(color: TeamColors.muted),
        ),
      );
    }
    return Panel(
      colors: c,
      child: ListView(
        children: [
          Label(tr('Records since {0}', [career.licences.firstYear])),
          const SizedBox(height: 8),
          for (final (what, who) in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 300,
                    child: Text(
                      what,
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      who,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _retiredView() {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    int winsOf(int id) => (career.palmares[id] ?? const [])
        .where((p) => !(p[2] as String).contains('overall'))
        .length;
    num bestPoints(int id) => (career.riderSeasons[id] ?? const []).fold<num>(
      0,
      (m, l) => (l[2] as num) > m ? l[2] as num : m,
    );
    final rows = [...career.retired.reversed];
    if (rows.isEmpty) {
      return Center(
        child: Text(
          tr(
            'Riders who end their careers appear here from the first turn of the year.',
          ),
          style: const TextStyle(color: TeamColors.muted),
        ),
      );
    }
    final shown = rows.where((r) => r[0] == _retired).firstOrNull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: Panel(
            colors: c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Label(tr('Retired riders · {0}', [rows.length])),
                const SizedBox(height: 6),
                Expanded(
                  child: DenseTable<List<dynamic>>(
                    colors: c,
                    rows: rows,
                    highlight: (r) => r[0] == _retired,
                    onTap: (r) => setState(() => _retired = r[0] as int),
                    columns: [
                      Col(
                        'Name',
                        200,
                        (r, _) => cellText(r[1] as String),
                        sortKey: (r) => r[1] as String,
                      ),
                      Col(
                        tr('Country'),
                        60,
                        (r, _) => cellText(r[2] as String),
                      ),
                      Col(
                        tr('Last team'),
                        70,
                        (r, _) => cellText(r[4] as String),
                      ),
                      Col(
                        tr('Retired'),
                        70,
                        (r, _) => cellText('${r[5]}'),
                        numeric: true,
                        sortKey: (r) => r[5] as int,
                      ),
                      Col(
                        tr('Age'),
                        50,
                        (r, _) => cellText('${(r[5] as int) - (r[3] as int)}'),
                        numeric: true,
                      ),
                      Col(
                        tr('Wins'),
                        60,
                        (r, _) => cellText('${winsOf(r[0] as int)}'),
                        numeric: true,
                        sortKey: (r) => winsOf(r[0] as int),
                      ),
                      Col(
                        tr('Best season'),
                        100,
                        (r, _) => cellText(
                          tr('{0} points', [bestPoints(r[0] as int).round()]),
                        ),
                        numeric: true,
                        sortKey: (r) => bestPoints(r[0] as int),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: Panel(
            colors: c,
            child: shown == null
                ? Center(
                    child: Text(
                      tr('Click a rider to see his career.'),
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                  )
                : ListView(
                    children: [
                      Text(
                        shown[1] as String,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        tr('{0} · born {1} · retired {2}', [
                          shown[2],
                          shown[3],
                          shown[5],
                        ]),
                        style: const TextStyle(color: TeamColors.muted),
                      ),
                      const SizedBox(height: 12),
                      Label(tr('Seasons')),
                      for (final l in career.riderSeasons[shown[0]] ?? const [])
                        Text(
                          tr(
                            '{0} · {1} · {2} points, {3} wins, {4} race days',
                            [l[0], l[1], (l[2] as num).round(), l[3], l[4]],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Label(tr('Honours')),
                      for (final p
                          in (career.palmares[shown[0]] ?? const []).reversed)
                        Text('${p[0]} · ${p[1]} · ${tr(p[2] as String)}'),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
