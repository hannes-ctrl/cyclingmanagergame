import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'rider_dialog.dart';

/// The views of the rankings page.
enum _View { season, breakaways, licences, archive }

/// Rankings of the current season by points, and the three-year ranking by
/// which the licences are awarded.
class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

/// State of the screen: which of the two views is shown.
class _RankingsScreenState extends State<RankingsScreen> {
  var _view = _View.season;

  /// Season shown in the archive; null means the most recent.
  int? _archiveYear;

  /// Filters of the rider ranking: search text and a team picked in the
  /// team ranking.
  var _search = '';
  int? _team;

  @override
  Widget build(BuildContext context) {
    final c = widget.state.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TabStrip<_View>(
          colors: c,
          tabs: {
            _View.season: tr('Season'),
            _View.breakaways: tr('Breakaways'),
            _View.licences: tr('Licences'),
            _View.archive: tr('Archive'),
          },
          value: _view,
          onChanged: (v) => setState(() => _view = v),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: switch (_view) {
              _View.season => _season(),
              _View.breakaways => _breakaways(),
              _View.licences => _licences(),
              _View.archive => _archive(),
            },
          ),
        ),
      ],
    );
  }

  /// @returns Riders and teams by days in the break this season, with the
  ///   combativity awards: the rider of the break who did the most work in
  ///   front on each road stage.
  Widget _breakaways() {
    final state = widget.state;
    final c = state.colors;
    final career = state.career;
    final riders =
        [
          for (final e in career.breakDays.entries)
            if (career.riderById[e.key] case final r?) (r, e.value),
        ]..sort((a, b) {
          final d = b.$2.compareTo(a.$2);
          return d != 0
              ? d
              : (career.combative[b.$1.id] ?? 0).compareTo(
                  career.combative[a.$1.id] ?? 0,
                );
        });
    final teams = <int, int>{};
    for (final (r, days) in riders) {
      teams[r.teamId] = (teams[r.teamId] ?? 0) + days;
    }
    final teamRows = teams.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (riders.isEmpty) {
      return Center(
        child: Text(
          tr('No break has gone yet this season.'),
          style: TextStyle(color: TeamColors.muted),
        ),
      );
    }
    Col<T> place<T>() => Col<T>(
      '',
      40,
      (_, i) => cellText('${i + 1}', color: TeamColors.muted),
      numeric: true,
    );
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
                Label(tr('Riders')),
                const SizedBox(height: 6),
                Expanded(
                  child: DenseTable<(SimRider, int)>(
                    colors: c,
                    rows: riders.take(300).toList(),
                    onTap: (x) => state.openRider(x.$1.id),
                    highlight: (x) => x.$1.teamId == state.team.id,
                    columns: [
                      place(),
                      Col(
                        'Name',
                        200,
                        (x, _) => cellText(career.fullName(x.$1.id)),
                      ),
                      Col(
                        tr('Team'),
                        70,
                        (x, _) =>
                            cellText(career.teams[x.$1.teamId]?.abbr ?? ''),
                      ),
                      Col(
                        tr('Days in the break'),
                        120,
                        (x, _) => cellText('${x.$2}'),
                        numeric: true,
                        sortKey: (x) => x.$2,
                      ),
                      Col(
                        tr('Most combative'),
                        120,
                        (x, _) => cellText('${career.combative[x.$1.id] ?? 0}'),
                        numeric: true,
                        sortKey: (x) => career.combative[x.$1.id] ?? 0,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Label(tr('Teams')),
                const SizedBox(height: 6),
                Expanded(
                  child: DenseTable<MapEntry<int, int>>(
                    colors: c,
                    rows: teamRows,
                    highlight: (e) => e.key == state.team.id,
                    columns: [
                      place(),
                      Col(
                        tr('Team'),
                        220,
                        (e, _) => cellText(career.teams[e.key]?.name ?? ''),
                      ),
                      Col(
                        tr('Days in the break'),
                        120,
                        (e, _) => cellText('${e.value}'),
                        numeric: true,
                      ),
                      Col(
                        tr('Most combative'),
                        120,
                        (e, _) => cellText('${career.teamCombative(e.key)}'),
                        numeric: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// @returns Finished seasons: winners of the big races, final rankings and
  ///   the championship titles of the chosen year.
  Widget _archive() {
    final state = widget.state;
    final c = state.colors;
    final career = state.career;
    if (career.archive.isEmpty) {
      return Center(
        child: Text(
          tr('The archive fills at the end of the first season.'),
          style: TextStyle(color: TeamColors.muted),
        ),
      );
    }
    final season = career.archive.firstWhere(
      (s) => s['year'] == _archiveYear,
      orElse: () => career.archive.last,
    );
    final year = season['year'] as int;
    final own = season['own'] as Map<String, dynamic>;
    final winners = (season['winners'] as List).cast<List<dynamic>>();
    final teams = (season['teams'] as List).cast<List<dynamic>>();
    final riders = (season['riders'] as List).cast<List<dynamic>>();
    final titles = [
      for (final t in career.titles)
        if (t.year == year && !t.race.contains('National')) t,
    ];

    Col<List<dynamic>> text(
      String title,
      double width,
      int at, {
      bool muted = false,
    }) => Col(
      title,
      width,
      (r, _) => cellText(
        '${r[at]}',
        color: muted ? TeamColors.muted : TeamColors.text,
      ),
    );
    Col<List<dynamic>> place() => Col(
      '',
      40,
      (_, i) => cellText('${i + 1}', color: TeamColors.muted),
      numeric: true,
    );
    Col<List<dynamic>> points(int at) => Col(
      tr('Points'),
      76,
      (r, _) => cellText('${(r[at] as num).round()}'),
      numeric: true,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final s in career.archive.reversed)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Pill(
                  label: '${s['year']}',
                  selected: s['year'] == year,
                  colors: c,
                  onTap: () => setState(() => _archiveYear = s['year'] as int),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('Our team: place {0} with {1} points and {2} wins{3}', [
                  own['rank'],
                  (own['points'] as num).round(),
                  own['wins'],
                  titles.isEmpty
                      ? ''
                      : tr(' · titles: {0}', [
                          titles
                              .map(
                                (t) =>
                                    '${career.fullName(t.riderId)} (${t.race})',
                              )
                              .join(', '),
                        ]),
                ]),
                style: const TextStyle(color: TeamColors.muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: Panel(
                  colors: c,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Label(
                        tr('Winners {0} · {1} races', [year, winners.length]),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: DenseTable<List<dynamic>>(
                          colors: c,
                          rows: winners,
                          highlight: (r) => r[3] == state.team.abbr,
                          columns: [
                            text(tr('Races'), 250, 0),
                            text(tr('Class'), 100, 1, muted: true),
                            text(tr('Winner'), 190, 2),
                            text('Team', 60, 3, muted: true),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Label('Teams'),
                      const SizedBox(height: 6),
                      Expanded(
                        child: DenseTable<List<dynamic>>(
                          colors: c,
                          rows: teams,
                          highlight: (r) => r[0] == state.team.id,
                          onTap: (r) => state.openTeam(r[0] as int),
                          columns: [place(), text('Team', 230, 1), points(2)],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Label(tr('Rider')),
                      const SizedBox(height: 6),
                      Expanded(
                        child: DenseTable<List<dynamic>>(
                          colors: c,
                          rows: riders,
                          highlight: (r) => r[2] == state.team.abbr,
                          onTap: (r) =>
                              showRiderDialog(context, state, r[0] as int),
                          columns: [
                            place(),
                            text(tr('Rider'), 180, 1),
                            text('Team', 56, 2, muted: true),
                            points(3),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// @returns The three-year ranking with the licence places.
  Widget _licences() {
    final state = widget.state;
    final c = state.colors;
    final career = state.career;
    final l = career.licences;
    final rows = l.ranking();
    final places = l.worldTourPlaces;
    final years = [for (var y = l.cycleStart; y <= career.year; y++) y];
    final own = rows.indexWhere((r) => r.teamId == state.team.id);
    final ownLicence = l.of(state.team.id);
    final lower = l.ranking({Licence.continental}).take(40).toList();
    final ownLower = l
        .ranking({Licence.continental})
        .indexWhere((r) => r.teamId == state.team.id);

    Col<LicenceRow> team() => Col(
      'Team',
      270,
      (r, _) => cellText(career.teams[r.teamId]?.name ?? '?'),
    );
    List<Col<LicenceRow>> points() => [
      for (final (i, y) in years.indexed)
        Col(
          '$y',
          70,
          (r, _) =>
              cellText('${r.perYear[i].round()}', color: TeamColors.muted),
          numeric: true,
        ),
      Col(
        tr('Overall'),
        80,
        (r, _) => cellText('${r.total.round()}', bold: true),
        numeric: true,
      ),
    ];

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
                Label(
                  tr('Three-year ranking {0}–{1}', [l.cycleStart, l.cycleEnd]),
                ),
                const SizedBox(height: 2),
                Text(
                  tr(
                    'After the {0} season the first {1} get the WorldTour licences for three years. {2}',
                    [
                      l.cycleEnd,
                      places,
                      own < 0
                          ? ''
                          : tr('Our team: place {0}, {1} the licence places.', [
                              own + 1,
                              own < places ? tr('inside') : tr('outside'),
                            ]),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12, color: TeamColors.muted),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: DenseTable<LicenceRow>(
                    colors: c,
                    rows: rows,
                    highlight: (r) => r.teamId == state.team.id,
                    columns: [
                      Col(
                        '',
                        44,
                        (_, i) => cellText(
                          '${i + 1}',
                          color: i < places ? TeamColors.green : TeamColors.red,
                        ),
                        numeric: true,
                      ),
                      team(),
                      Col(
                        tr('Licence'),
                        90,
                        (r, _) =>
                            cellText(r.licence.label, color: TeamColors.muted),
                      ),
                      Col(tr('Situation'), 110, (r, i) {
                        final wt = r.licence == Licence.worldTour;
                        return i < places
                            ? cellText(
                                wt ? tr('stays') : tr('goes up'),
                                color: wt ? TeamColors.muted : TeamColors.green,
                              )
                            : cellText(
                                wt ? tr('goes down') : '–',
                                color: wt ? TeamColors.red : TeamColors.muted,
                              );
                      }),
                      ...points(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                colors: c,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Label(tr('Our team')),
                    const SizedBox(height: 4),
                    Text(
                      '${ownLicence.label} · '
                      '${ownLicence == Licence.worldTour
                          ? tr('Right to start in all WorldTour races.')
                          : l.wildcards.contains(state.team.id)
                          ? tr('Invited to all WorldTour races as one of the two best ProTeams of last season.')
                          : tr('WorldTour races by invitation only.')}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr(
                        'Invitations {0} to all WorldTour races: {1}. The two best ProTeams of this season get them for {2}.',
                        [
                          career.year,
                          l.wildcards.isEmpty
                              ? tr('as stored in the world database')
                              : l.wildcards
                                    .map((id) => career.teams[id]?.name ?? '?')
                                    .join(', '),
                          career.year + 1,
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: TeamColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Panel(
                  colors: c,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Label(tr('Continental teams')),
                      const SizedBox(height: 2),
                      Text(
                        tr(
                          'The best two become ProTeams in {0}, the two weakest ProTeams go down.{1}',
                          [
                            l.cycleEnd + 1,
                            ownLower < 0
                                ? ''
                                : tr(' Our team: place {0}.', [ownLower + 1]),
                          ],
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: TeamColors.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: DenseTable<LicenceRow>(
                          colors: c,
                          rows: lower,
                          highlight: (r) => r.teamId == state.team.id,
                          columns: [
                            Col(
                              '',
                              44,
                              (_, i) => cellText(
                                '${i + 1}',
                                color: i < 2
                                    ? TeamColors.green
                                    : TeamColors.muted,
                              ),
                              numeric: true,
                            ),
                            team(),
                            points().last,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// @returns The rider and team rankings of the season.
  Widget _season() {
    final state = widget.state;
    final c = state.colors;
    final career = state.career;
    if (career.riderPoints.isEmpty) {
      return Center(
        child: Text(
          tr('No points awarded yet. The season starts in January.'),
          style: TextStyle(color: TeamColors.muted),
        ),
      );
    }
    final byId = <int, SimRider>{
      for (final squad in career.squads.values)
        for (final r in squad) r.id: r,
    };
    final ranked = career.riderPoints.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // The place is the one in the whole ranking, also when filtered.
    final rank = {for (final (i, e) in ranked.indexed) e.key: i + 1};
    final needle = _search.toLowerCase();
    final riders = [
      for (final e in ranked)
        if ((_team == null || byId[e.key]?.teamId == _team) &&
            (needle.isEmpty ||
                (byId[e.key]?.name.toLowerCase().contains(needle) ?? false) ||
                byId[e.key]?.country.toLowerCase() == needle))
          e,
    ];
    final teams = career.teamPoints.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Col<MapEntry<int, double>> place({bool overall = false}) => Col(
      '',
      44,
      (e, i) =>
          cellText('${overall ? rank[e.key] : i + 1}', color: TeamColors.muted),
      numeric: true,
    );
    Col<MapEntry<int, double>> points() => Col(
      tr('Points'),
      80,
      (e, _) => cellText('${e.value.round()}'),
      numeric: true,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Panel(
            colors: c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Label(tr('Rider')),
                    const SizedBox(width: 10),
                    if (_team != null)
                      Pill(
                        label: '${career.teams[_team]?.name ?? '?'}  ×',
                        selected: true,
                        colors: c,
                        onTap: () => setState(() => _team = null),
                      )
                    else
                      Text(
                        tr('Click a team to show only its riders'),
                        style: TextStyle(fontSize: 12, color: TeamColors.muted),
                      ),
                    const Spacer(),
                    SearchBox(
                      hint: tr('Rider or country'),
                      colors: c,
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: DenseTable<MapEntry<int, double>>(
                    colors: c,
                    rows: riders,
                    highlight: (e) => byId[e.key]?.teamId == state.team.id,
                    onTap: (e) => showRiderDialog(context, state, e.key),
                    columns: [
                      place(overall: true),
                      Col(
                        '',
                        26,
                        (e, _) => Flag(byId[e.key]?.country ?? '', width: 18),
                      ),
                      Col(
                        tr('Rider'),
                        220,
                        (e, _) => cellText(byId[e.key]?.name ?? '?'),
                      ),
                      Col(
                        'Team',
                        70,
                        (e, _) => cellText(
                          byId[e.key]?.team ?? '',
                          color: TeamColors.muted,
                        ),
                      ),
                      points(),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Label('Teams'),
                const SizedBox(height: 6),
                Expanded(
                  child: DenseTable<MapEntry<int, double>>(
                    colors: c,
                    rows: teams,
                    onTap: (e) =>
                        setState(() => _team = _team == e.key ? null : e.key),
                    highlight: (e) => e.key == state.team.id,
                    columns: [
                      place(),
                      Col(
                        'Team',
                        280,
                        (e, _) => Row(
                          children: [
                            Jersey(
                              dataDir: state.dataDir,
                              abbr: state.jerseyOf(e.key),
                              size: 22,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: cellText(career.teams[e.key]?.name ?? '?'),
                            ),
                          ],
                        ),
                      ),
                      Col(
                        tr('Licence'),
                        90,
                        (e, _) => cellText(
                          career.licences.of(e.key).label,
                          color: TeamColors.muted,
                        ),
                      ),
                      points(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
