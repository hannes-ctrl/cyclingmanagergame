import 'package:flutter/material.dart';

import 'rider_dialog.dart';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'power_view.dart';
import 'race_replay.dart';
import 'race_chart.dart';
import 'tactics_dialog.dart';
import 'view3d_button.dart';
import 'whatif_dialog.dart';

/// Grouping of the WorldDB race classes for the list.
const _groups = <(String pattern, String label)>[
  (r'^CWTGT', 'Grand Tours'),
  (r'^CWTMaj', 'Monuments'),
  (r'^CWT', 'WorldTour'),
  (r'HC$', 'ProSeries'),
  (r'^Cont[12]1$', 'Class 1'),
  (r'^Cont[12]2U$', 'U23'),
  (r'^Cont[12]2$', 'Class 2'),
  (r'ITT$', 'Time trial championships'),
  (r'Championship', 'Championships'),
];

/// @param race A race.
/// @returns The label of the group it is listed under.
String _groupOf(RaceInfo race) {
  for (final (pattern, label) in _groups) {
    if (RegExp(pattern).hasMatch(race.raceClass)) return label;
  }
  return 'Other';
}

String _date(int day, int month) => dayText(DateTime.utc(2000, month, day));

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

  /// Sorting of the list, each switchable on its own: grouped by
  /// importance, and by date (otherwise by name).
  var _byImportance = true;
  var _byDate = false;

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
    final starts = {for (final r in s.career.calendar) r.info.id: r.start};
    final never = DateTime.utc(9999);
    int order(RaceInfo a, RaceInfo b) {
      if (_byDate) {
        final d = (starts[a.id] ?? never).compareTo(starts[b.id] ?? never);
        if (d != 0) return d;
      }
      return a.name.compareTo(b.name);
    }

    for (final list in byGroup.values) {
      list.sort(order);
    }
    final entries = <Object>[
      if (_byImportance) ...[
        for (final (_, label) in _groups)
          if (byGroup[label] != null) ...[label, ...byGroup[label]!],
        if (byGroup['Other'] != null) ...['Other', ...byGroup['Other']!],
      ] else
        ...(<RaceInfo>[for (final list in byGroup.values) ...list]
          ..sort(order)),
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
                  hint: tr('Race or country'),
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
                      label: tr('All races'),
                      selected: !_onlyOwn,
                      colors: c,
                      onTap: () => setState(() => _onlyOwn = false),
                    ),
                    const SizedBox(width: 6),
                    Pill(
                      label: tr('Ours only'),
                      selected: _onlyOwn,
                      colors: c,
                      onTap: () => setState(() => _onlyOwn = true),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                child: Row(
                  children: [
                    Text(
                      tr('Sort:'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: TeamColors.muted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Pill(
                      label: tr('Importance'),
                      selected: _byImportance,
                      colors: c,
                      onTap: () =>
                          setState(() => _byImportance = !_byImportance),
                    ),
                    const SizedBox(width: 6),
                    Pill(
                      label: tr('Date'),
                      selected: _byDate,
                      colors: c,
                      onTap: () => setState(() => _byDate = !_byDate),
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
                            if (_byDate && starts[race.id] != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  _date(
                                    starts[race.id]!.day,
                                    starts[race.id]!.month,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: TeamColors.muted,
                                  ),
                                ),
                              ),
                            if (s.career.progress[race.id] case final p?)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  p.finished ? tr('finished') : tr('running'),
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
              ? Center(child: Text(tr('Select a race on the left')))
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
                          tr('{0} · {1} · from {2}', [
                            tr(_groupOf(race)),
                            stages.length > 1
                                ? trn(stages.length, '{0} stage', '{0} stages')
                                : tr('One-day race'),
                            _date(race.startDay, race.startMonth),
                          ]),
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (run != null) ...[
                View3dButton(state: state, run: run, index: index),
                const SizedBox(width: 10),
              ],
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
                  child: Text(tr('What if?')),
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
                  child: Text(tr('Tactics for the next stage')),
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
                            ? tr('Stage {0} · {1}', [
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
                      tr('{0} km · {1} m climbing · {2}', [
                        dec(route.raceKm, 1),
                        meters.round(),
                        switch (route.kind) {
                          StageKind.road =>
                            route.sprintStage
                                ? tr('Flat stage')
                                : tr('Road race'),
                          StageKind.timeTrial => tr('Individual time trial'),
                          StageKind.teamTimeTrial => tr('Team time trial'),
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
                        'Not ridden yet. Result, report and classifications appear here after the race.',
                      ),
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                  )
                : index >= run.result.stages.length
                ? Center(
                    child: Text(
                      tr('This stage has not been ridden yet.'),
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
  stage('Stage', null),
  general('Overall', TeamColors.gold),
  points('Points', Color(0xFF2FA866)),
  mountains('Mountain', Color(0xFFE2333A)),
  youth('Youth', Colors.white),
  teams('Teams', TeamColors.muted);

  const _Tab(this._label, this.jersey);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
  final Color? jersey;
}

/// Views of the report panel next to the result tables.
enum _Side {
  article('Report'),
  course('Course'),
  team('Our team'),
  power('Power'),
  replay('Fast motion');

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
    final jerseys = jerseyColors(grandTourOf(widget.run.race));
    final single = widget.run.routes.length == 1;
    final tab = single ? _Tab.stage : _tab;
    bool own(SimRider r) => r.teamId == s.team.id;
    final hasOwn = result.placings.any((p) => own(p.rider));
    final hasPower = result.power.isNotEmpty;
    final hasReplay = result.timeline.any((x) => x.groups.isNotEmpty);
    final side =
        _side == _Side.team && !hasOwn ||
            _side == _Side.power && !hasPower ||
            _side == _Side.replay && !hasReplay
        ? _Side.article
        : _side;
    final article = writeArticle(
      route: widget.run.routes[widget.index],
      result: result,
      standings: single ? null : standings,
      before: single || widget.index == 0
          ? null
          : widget.run.result.standings[widget.index - 1],
      grandTour: grandTourOf(widget.run.race),
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
        Col(tr('Rider'), 200, (r, _) => cellText(of(r).name));
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
            tr('Time'),
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
              tr('Time'),
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
            tr('Points'),
            70,
            (e, _) => cellText('${e.points}'),
            numeric: true,
            // Points of the classification, not UCI points.
            help: '',
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
            tr('Time'),
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
                      if ((v != _Side.team || hasOwn) &&
                          (v != _Side.power || hasPower) &&
                          (v != _Side.replay || hasReplay))
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
                        Label(tr('Gaps during the race')),
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
                      if (side == _Side.replay)
                        RaceReplay(
                          key: ValueKey(widget.index),
                          result: result,
                          route: widget.run.routes[widget.index],
                          names: {for (final r in s.squad) r.id: r.name},
                          colors: c,
                        ),
                      if (side == _Side.power)
                        PowerView(result: result, teamId: s.team.id, colors: c),
                      if (side == _Side.course) ...[
                        const SizedBox(height: 14),
                        Label(tr('Events')),
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
                                    'km ${dec(e.km, 1)}',
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
                  Label(tr('Result'))
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
                                        color: switch (t) {
                                          _Tab.general => jerseys.general,
                                          _Tab.points => jerseys.points,
                                          _Tab.mountains => jerseys.mountains,
                                          _Tab.youth => jerseys.youth,
                                          _ => t.jersey,
                                        },
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
