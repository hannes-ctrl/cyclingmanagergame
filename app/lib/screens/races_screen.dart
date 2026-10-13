import 'package:flutter/material.dart';

import 'rider_dialog.dart';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'race_chart.dart';
import 'tactics_dialog.dart';
import 'whatif_dialog.dart';

/// Grouping of the WorldDB race classes for the list.
const _groups = <(String pattern, String label)>[
  (r'^CWTGT', 'Grand Tours'),
  (r'^CWTMaj', 'Monumente'),
  (r'^CWT', 'WorldTour'),
  (r'HC$', 'ProSeries'),
  (r'^Cont[12]1$', 'Klasse 1'),
  (r'^Cont[12]2U$', 'U23'),
  (r'^Cont[12]2$', 'Klasse 2'),
  (r'ITT$', 'Meisterschaften Zeitfahren'),
  (r'Championship', 'Meisterschaften'),
];

/// @param race A race.
/// @returns The label of the group it is listed under.
String _groupOf(RaceInfo race) {
  for (final (pattern, label) in _groups) {
    if (RegExp(pattern).hasMatch(race.raceClass)) return label;
  }
  return 'Sonstige';
}

String _date(int day, int month) =>
    '${day.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}.';

/// Races: the list of all races on the left, the selected race with route,
/// report and classifications on the right.
class RacesScreen extends StatefulWidget {
  const RacesScreen({super.key, required this.state});
  final AppState state;

  @override
  State<RacesScreen> createState() => _RacesScreenState();
}

/// State of the screen: selected race, stage and search text.
class _RacesScreenState extends State<RacesScreen> {
  RaceInfo? _race;
  var _stage = 0;
  var _filter = '';
  var _onlyOwn = false;

  @override
  void initState() {
    super.initState();
    _race = widget.state.races
        .where((r) => r.name == 'Tour de France')
        .firstOrNull;
    _takeFocus();
  }

  @override
  void didUpdateWidget(RacesScreen old) {
    super.didUpdateWidget(old);
    _takeFocus();
  }

  /// Handles a jump from another screen: shows the race named there and its
  /// last ridden stage.
  void _takeFocus() {
    final s = widget.state;
    final id = s.focusRace;
    if (id == null) return;
    s.focusRace = null;
    _race = s.races.where((r) => r.id == id).firstOrNull ?? _race;
    final done = s.career.progress[id]?.stagesDone ?? 1;
    _stage = done > 0 ? done - 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final byGroup = <String, List<RaceInfo>>{};
    final needle = _filter.toLowerCase();
    final ownIds = {for (final r in s.career.ownRaces) r.info.id};
    for (final r in s.races) {
      if (needle.isNotEmpty &&
          !r.name.toLowerCase().contains(needle) &&
          r.country.toLowerCase() != needle) {
        continue;
      }
      if (_onlyOwn && !ownIds.contains(r.id)) continue;
      byGroup.putIfAbsent(_groupOf(r), () => []).add(r);
    }
    final entries = <Object>[
      for (final (_, label) in _groups)
        if (byGroup[label] != null) ...[label, ...byGroup[label]!],
      if (byGroup['Sonstige'] != null) ...['Sonstige', ...byGroup['Sonstige']!],
    ];

    return Row(
      children: [
        Container(
          width: 300,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: c.line)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: SearchBox(
                  hint: tr('Rennen oder Land'),
                  colors: c,
                  width: null,
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Pill(
                      label: tr('Alle Rennen'),
                      selected: !_onlyOwn,
                      colors: c,
                      onTap: () => setState(() => _onlyOwn = false),
                    ),
                    const SizedBox(width: 6),
                    Pill(
                      label: tr('Nur unsere'),
                      selected: _onlyOwn,
                      colors: c,
                      onTap: () => setState(() => _onlyOwn = true),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    if (e is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
                        child: Label('${tr(e)} · ${byGroup[e]!.length}'),
                      );
                    }
                    final race = e as RaceInfo;
                    final selected = race.id == _race?.id;
                    return InkWell(
                      onTap: () => setState(() {
                        _race = race;
                        _stage = 0;
                      }),
                      child: Container(
                        color: selected ? c.panel2 : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            RaceLogo(dataDir: s.dataDir, race: race, size: 24),
                            const SizedBox(width: 8),
                            Flag(race.country, width: 16),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                race.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (s.career.progress[race.id] case final p?)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  p.finished ? tr('beendet') : tr('läuft'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: p.finished
                                        ? TeamColors.muted
                                        : TeamColors.green,
                                  ),
                                ),
                              ),
                            Text(
                              _date(race.startDay, race.startMonth),
                              style: const TextStyle(
                                fontSize: 12,
                                color: TeamColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _race == null
              ? Center(child: Text(tr('Links ein Rennen wählen')))
              : _RaceDetail(
                  key: ValueKey(_race!.id),
                  state: s,
                  race: _race!,
                  stage: _stage,
                  onStage: (i) => setState(() => _stage = i),
                ),
        ),
      ],
    );
  }
}

/// Header, profile and report of one race.
class _RaceDetail extends StatelessWidget {
  const _RaceDetail({
    super.key,
    required this.state,
    required this.race,
    required this.stage,
    required this.onStage,
  });
  final AppState state;
  final RaceInfo race;
  final int stage;
  final void Function(int) onStage;

  @override
  Widget build(BuildContext context) {
    final c = state.colors;
    final stages = state.stagesOf(race);
    final routes = state.routesOf(race);
    final run = state.runOf(race);
    final index = stage.clamp(0, routes.length - 1);
    final route = routes[index];
    final meters = route.segments
        .where((s) => s.grade > 0)
        .fold<double>(0, (sum, s) => sum + s.grade * s.lengthM);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RaceLogo(dataDir: state.dataDir, race: race, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(race.name, style: headStyle(25)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flag(race.country, width: 18),
                        const SizedBox(width: 6),
                        Text(
                          tr('{0} · {1} · ab {2}', [
                            tr(_groupOf(race)),
                            stages.length > 1
                                ? tr('{0} Etappen', [stages.length])
                                : tr('Eintagesrennen'),
                            _date(race.startDay, race.startMonth),
                          ]),
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Ridden road stage with our riders: simulate it again with different tactics.
              if (state.career.progress[race.id] case final p?
                  when index < p.stagesDone &&
                      route.kind == StageKind.road &&
                      p.run
                          .ridersBefore(index)
                          .any((r) => r.teamId == state.team.id)) ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TeamColors.text,
                    side: BorderSide(color: c.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  onPressed: state.busy
                      ? null
                      : () => showWhatIfDialog(context, state, p, index),
                  child: Text(tr('Was wäre wenn?')),
                ),
                const SizedBox(width: 10),
              ],
              // Stage race in progress with our riders: tactics for the next stage.
              if (state.career.progress[race.id] case final p?
                  when !p.finished &&
                      p.run.riders.any((r) => r.teamId == state.team.id)) ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TeamColors.text,
                    side: BorderSide(color: c.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  onPressed: state.busy
                      ? null
                      : () => showTacticsDialog(context, state, p),
                  child: Text(tr('Taktik für die nächste Etappe')),
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
          if (stages.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: stages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, i) {
                  final selected = i == index;
                  return Material(
                    color: selected ? TeamColors.text : c.panel,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: c.line),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: InkWell(
                      customBorder: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      onTap: () => onStage(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Center(
                          child: Text(
                            '${stages[i].number}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? TeamColors.ground
                                  : TeamColors.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 10),
          Panel(
            colors: c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stages.length > 1
                            ? tr('Etappe {0} · {1}', [
                                stages[index].number,
                                route.name,
                              ])
                            : route.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      tr('{0} km · {1} Hm · {2}', [
                        route.raceKm.toStringAsFixed(1),
                        meters.round(),
                        switch (route.kind) {
                          StageKind.road =>
                            route.sprintStage
                                ? tr('Flachetappe')
                                : tr('Straßenrennen'),
                          StageKind.timeTrial => tr('Einzelzeitfahren'),
                          StageKind.teamTimeTrial => tr('Teamzeitfahren'),
                        },
                      ]),
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ProfileView(route: route, colors: c),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: run == null
                ? Center(
                    child: Text(
                      tr(
                        'Noch nicht gefahren. Ergebnis, Bericht und Wertungen erscheinen hier nach dem Rennen.',
                      ),
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                  )
                : index >= run.result.stages.length
                ? Center(
                    child: Text(
                      tr('Diese Etappe ist noch nicht gefahren.'),
                      style: TextStyle(color: TeamColors.muted),
                    ),
                  )
                : _Report(state: state, run: run, index: index),
          ),
        ],
      ),
    );
  }
}

/// Tabs of the result panel: stage result and the classifications.
enum _Tab {
  stage('Etappe', null),
  general('Gesamt', TeamColors.gold),
  points('Punkte', Color(0xFF2FA866)),
  mountains('Berg', Color(0xFFE2333A)),
  youth('Nachwuchs', Colors.white),
  teams('Teams', TeamColors.muted);

  const _Tab(this._label, this.jersey);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
  final Color? jersey;
}

/// Views of the report panel next to the result tables.
enum _Side {
  article('Bericht'),
  course('Verlauf'),
  team('Unser Team');

  const _Side(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
}

/// Result of a stage: the course of the race on the left, the
/// classifications as switchable tables on the right.
class _Report extends StatefulWidget {
  const _Report({required this.state, required this.run, required this.index});
  final AppState state;
  final RaceRun run;
  final int index;

  @override
  State<_Report> createState() => _ReportState();
}

/// State of the report: the selected tab.
class _ReportState extends State<_Report> {
  var _tab = _Tab.stage;
  var _side = _Side.article;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final result = widget.run.result.stages[widget.index];
    final standings = widget.run.result.standings[widget.index];
    final single = widget.run.routes.length == 1;
    final tab = single ? _Tab.stage : _tab;
    bool own(SimRider r) => r.teamId == s.team.id;
    final hasOwn = result.placings.any((p) => own(p.rider));
    final side = _side == _Side.team && !hasOwn ? _Side.article : _side;
    final article = writeArticle(
      route: widget.run.routes[widget.index],
      result: result,
      standings: single ? null : standings,
      teamId: s.team.id,
      raceName: widget.run.race.name,
      finalStage: widget.index == widget.run.routes.length - 1,
    );

    Col<T> place<T>() => Col(
      '',
      40,
      (_, i) => cellText('${i + 1}', color: TeamColors.muted),
      numeric: true,
    );
    Col<T> rider<T>(SimRider Function(T) of) =>
        Col(tr('Fahrer'), 200, (r, _) => cellText(of(r).name));
    Col<T> team<T>(SimRider Function(T) of) => Col(
      'Team',
      60,
      // The abbreviation leads to the team; a national selection has none.
      (r, _) => s.career.teams.containsKey(of(r).teamId)
          ? InkWell(
              onTap: () => s.openTeam(of(r).teamId),
              child: cellText(of(r).team, color: TeamColors.muted),
            )
          : cellText(of(r).team, color: TeamColors.muted),
    );

    final Widget table = switch (tab) {
      _Tab.stage => DenseTable<Placing>(
        colors: c,
        rows: result.placings,
        highlight: (p) => own(p.rider),
        onTap: (p) => showRiderDialog(
          context,
          s,
          p.rider.id,
          among: [for (final x in result.placings) x.rider.id],
        ),
        columns: [
          place(),
          rider((p) => p.rider),
          team((p) => p.rider),
          Col(
            tr('Zeit'),
            90,
            (p, i) => cellText(
              i == 0
                  ? clock(p.timeS)
                  : gap(
                      p.timeS.roundToDouble() -
                          result.winnerTimeS.roundToDouble(),
                    ),
            ),
            numeric: true,
          ),
        ],
      ),
      _Tab.general || _Tab.youth => () {
        final rows = tab == _Tab.general ? standings.general : standings.youth;
        return DenseTable<TimeEntry>(
          colors: c,
          rows: rows,
          highlight: (e) => own(e.rider),
          onTap: (e) => showRiderDialog(
            context,
            s,
            e.rider.id,
            among: [for (final x in rows) x.rider.id],
          ),
          columns: [
            place(),
            rider((e) => e.rider),
            team((e) => e.rider),
            Col(
              tr('Zeit'),
              90,
              (e, i) => cellText(
                i == 0 ? clock(e.timeS) : gap(e.timeS - rows.first.timeS),
              ),
              numeric: true,
            ),
          ],
        );
      }(),
      _Tab.points || _Tab.mountains => DenseTable<PointsEntry>(
        colors: c,
        rows: tab == _Tab.points ? standings.points : standings.mountains,
        highlight: (e) => own(e.rider),
        onTap: (e) => showRiderDialog(context, s, e.rider.id),
        columns: [
          place(),
          rider((e) => e.rider),
          team((e) => e.rider),
          Col(
            tr('Punkte'),
            70,
            (e, _) => cellText('${e.points}'),
            numeric: true,
          ),
        ],
      ),
      _Tab.teams => DenseTable<TeamEntry>(
        colors: c,
        rows: standings.teams,
        highlight: (e) => e.teamId == s.team.id,
        columns: [
          place(),
          Col('Team', 260, (e, _) {
            final name = s.teams
                .where((t) => t.id == e.teamId)
                .map((t) => t.name)
                .firstOrNull;
            return cellText(name ?? e.team);
          }),
          Col(
            tr('Zeit'),
            100,
            (e, i) => cellText(
              i == 0
                  ? clock(e.timeS)
                  : gap(e.timeS - standings.teams.first.timeS),
            ),
            numeric: true,
          ),
        ],
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: Panel(
            colors: c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    for (final v in _Side.values)
                      if (v != _Side.team || hasOwn)
                        Material(
                          color: v == side
                              ? TeamColors.text
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: c.line),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: InkWell(
                            customBorder: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            onTap: () => setState(() => _side = v),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: Text(
                                v.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: v == side
                                      ? TeamColors.ground
                                      : TeamColors.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: [
                      if (side == _Side.article) ...[
                        Text(
                          article.headline,
                          style: const TextStyle(
                            fontSize: 17,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        for (final paragraph in article.paragraphs)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              paragraph,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ),
                      ],
                      if (side == _Side.course &&
                          result.timeline.length > 1) ...[
                        Label(tr('Abstände im Rennen')),
                        const SizedBox(height: 6),
                        RaceChart(
                          result: result,
                          route: widget.run.routes[widget.index],
                          colors: c,
                        ),
                      ],
                      if (side == _Side.team) ...[
                        OwnRiders(
                          result: result,
                          route: widget.run.routes[widget.index],
                          teamId: s.team.id,
                        ),
                      ],
                      if (side == _Side.course) ...[
                        const SizedBox(height: 14),
                        Label(tr('Ereignisse')),
                        const SizedBox(height: 4),
                      ],
                      if (side == _Side.course)
                        for (final e in result.events)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 66,
                                  child: Text(
                                    'km ${e.km.toStringAsFixed(1)}',
                                    style: const TextStyle(
                                      color: TeamColors.muted,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(child: Text(e.text)),
                              ],
                            ),
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
          flex: 5,
          child: Panel(
            colors: c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (single)
                  Label(tr('Ergebnis'))
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in _Tab.values)
                        Material(
                          color: t == tab
                              ? TeamColors.text
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: c.line),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: InkWell(
                            customBorder: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            onTap: () => setState(() => _tab = t),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (t.jersey != null) ...[
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: t.jersey,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: c.line),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    t.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: t == tab
                                          ? TeamColors.ground
                                          : TeamColors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Expanded(child: table),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
