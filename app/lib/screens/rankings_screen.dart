import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'rider_dialog.dart';

/// The views of the rankings page.
enum _View { season, licences, archive }

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
          tabs: const {
            _View.season: 'Saison',
            _View.licences: 'Lizenzen',
            _View.archive: 'Archiv',
          },
          value: _view,
          onChanged: (v) => setState(() => _view = v),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: switch (_view) {
              _View.season => _season(),
              _View.licences => _licences(),
              _View.archive => _archive(),
            },
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
      return const Center(
        child: Text(
          'Das Archiv füllt sich mit dem Ende der ersten Saison.',
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
      'Punkte',
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
                child: ChoiceChip(
                  label: Text('${s['year']}'),
                  selected: s['year'] == year,
                  showCheckmark: false,
                  selectedColor: TeamColors.text,
                  backgroundColor: c.panel,
                  side: BorderSide(color: c.line),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: s['year'] == year
                        ? TeamColors.ground
                        : TeamColors.text,
                  ),
                  onSelected: (_) =>
                      setState(() => _archiveYear = s['year'] as int),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Unser Team: Platz ${own['rank']} mit '
                '${(own['points'] as num).round()} Punkten und '
                '${own['wins']} Siegen'
                '${titles.isEmpty ? '' : ' · Titel: ${titles.map((t) => '${career.fullName(t.riderId)} (${t.race})').join(', ')}'}',
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
                      Label('Sieger $year · ${winners.length} Rennen'),
                      const SizedBox(height: 6),
                      Expanded(
                        child: DenseTable<List<dynamic>>(
                          colors: c,
                          rows: winners,
                          highlight: (r) => r[3] == state.team.abbr,
                          columns: [
                            text('Rennen', 250, 0),
                            text('Klasse', 100, 1, muted: true),
                            text('Sieger', 190, 2),
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
                      const Label('Fahrer'),
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
                            text('Fahrer', 180, 1),
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
        'Gesamt',
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
                Label('Dreijahreswertung ${l.cycleStart}–${l.cycleEnd}'),
                const SizedBox(height: 2),
                Text(
                  'Nach der Saison ${l.cycleEnd} bekommen die ersten $places '
                  'die WorldTour-Lizenzen für drei Jahre. '
                  '${own < 0 ? '' : 'Unser Team: Platz ${own + 1}, ${own < places ? 'innerhalb' : 'außerhalb'} der Lizenzplätze.'}',
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
                        'Lizenz',
                        90,
                        (r, _) =>
                            cellText(r.licence.label, color: TeamColors.muted),
                      ),
                      Col('Lage', 110, (r, i) {
                        final wt = r.licence == Licence.worldTour;
                        return i < places
                            ? cellText(
                                wt ? 'bleibt' : 'steigt auf',
                                color: wt ? TeamColors.muted : TeamColors.green,
                              )
                            : cellText(
                                wt ? 'steigt ab' : '–',
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
                    const Label('Unser Team'),
                    const SizedBox(height: 4),
                    Text(
                      '${ownLicence.label} · '
                      '${ownLicence == Licence.worldTour
                          ? 'Startrecht bei allen WorldTour-Rennen.'
                          : l.wildcards.contains(state.team.id)
                          ? 'Als eines der zwei besten ProTeams der Vorsaison zu allen WorldTour-Rennen eingeladen.'
                          : 'WorldTour-Rennen nur auf Einladung.'}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Einladungen ${career.year} für alle WorldTour-Rennen: '
                      '${l.wildcards.isEmpty ? 'wie in der Weltdatenbank hinterlegt' : l.wildcards.map((id) => career.teams[id]?.name ?? '?').join(', ')}. '
                      'Die zwei besten ProTeams dieser Saison bekommen sie '
                      'für ${career.year + 1}.',
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
                      const Label('Continental-Teams'),
                      const SizedBox(height: 2),
                      Text(
                        'Die zwei besten werden ${l.cycleEnd + 1} ProTeam, die '
                        'zwei schwächsten ProTeams gehen zurück.'
                        '${ownLower < 0 ? '' : ' Unser Team: Platz ${ownLower + 1}.'}',
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
      return const Center(
        child: Text(
          'Noch keine Punkte vergeben. Die Saison beginnt im Januar.',
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
      'Punkte',
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
                    const Label('Fahrer'),
                    const SizedBox(width: 10),
                    if (_team != null)
                      Pill(
                        label: '${career.teams[_team]?.name ?? '?'}  ×',
                        selected: true,
                        colors: c,
                        onTap: () => setState(() => _team = null),
                      )
                    else
                      const Text(
                        'Klick auf ein Team zeigt nur dessen Fahrer',
                        style: TextStyle(fontSize: 12, color: TeamColors.muted),
                      ),
                    const Spacer(),
                    SearchBox(
                      hint: 'Fahrer oder Land',
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
                        'Fahrer',
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
                        'Lizenz',
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
