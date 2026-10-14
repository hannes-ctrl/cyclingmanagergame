import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'power_view.dart';

/// A race on its own, outside the career: choose a race, the team you lead
/// and how it races, then watch the result. The world is that of the start
/// of the season, with fresh riders; nothing reaches the running career.
class SingleRacePanel extends StatefulWidget {
  const SingleRacePanel({super.key, required this.state});
  final AppState state;

  @override
  State<SingleRacePanel> createState() => _SingleRacePanelState();
}

class _SingleRacePanelState extends State<SingleRacePanel> {
  /// The career that serves the single race; made when it is first needed.
  Career? _career;
  int? _teamId;
  int? _raceId;
  var _seed = 1;
  Approach? _approach;
  BreakPolicy? _breakPolicy;
  Tyres? _tyres;
  SingleRace? _race;
  var _running = false;
  var _stage = 0;
  var _tab = 0;

  static const _approaches = {
    null: 'Sports director',
    Approach.wait: 'Wait',
    Approach.control: 'Control the pace',
    Approach.makeHard: 'Make the race hard',
    Approach.echelon: 'Split in the crosswind',
  };
  static const _breaks = {
    null: 'Sports director',
    BreakPolicy.ignore: 'Ignore',
    BreakPolicy.join: 'Join',
    BreakPolicy.chase: 'Chase down',
  };

  AppState get _s => widget.state;

  /// Teams that can be led: WorldTeams and ProTeams.
  List<TeamInfo> get _teams => [
    for (final t in _s.career.teams.values)
      if (t.division.startsWith('[1]') || t.division.startsWith('[2]')) t,
  ]..sort((a, b) => a.name.compareTo(b.name));

  /// Races of the season except championships.
  List<RaceEntry> get _races => [
    for (final r in _s.career.calendar)
      if (r.tier != RaceTier.championship) r,
  ]..sort((a, b) => a.start.compareTo(b.start));

  /// Simulates the whole race, stage by stage on another isolate.
  Future<void> _start() async {
    final teamId = _teamId ?? _s.team.id;
    final raceId = _raceId ?? _races.first.info.id;
    setState(() {
      _running = true;
      _race = null;
    });
    // A fresh career of the chosen team: the world at the start of the
    // season, nothing of the running one.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (_career?.teamId != teamId) {
      _career = Career(_s.career.world, teamId: teamId, seed: _seed);
    }
    final career = _career!;
    final race = career.calendar.firstWhere((r) => r.info.id == raceId);
    if (_tyres != null) {
      career.equipment.ownTyres[race.info.id] = _tyres!;
    } else {
      career.equipment.ownTyres.remove(race.info.id);
    }
    final single = SingleRace(
      career,
      race,
      seed: _seed,
      wish: PlanWish(approach: _approach, breakPolicy: _breakPolicy),
    );
    setState(() => _race = single);
    while (!single.finished && mounted) {
      final job = single.nextJob();
      final result = await Isolate.run(job.run);
      single.take(job, result);
      if (mounted) setState(() => _stage = single.stagesDone - 1);
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = _s.colors;
    final teams = _teams;
    final races = _races;
    final teamId = _teamId ?? _s.team.id;
    final raceId = _raceId ?? races.first.info.id;
    Widget dropdown<T>(
      T value,
      List<(T, String)> items,
      void Function(T) onPick,
    ) => DropdownButton<T>(
      value: value,
      isDense: true,
      isExpanded: true,
      underline: const SizedBox(),
      dropdownColor: c.panel2,
      style: const TextStyle(
        fontFamily: 'Barlow',
        fontSize: 14,
        color: TeamColors.text,
      ),
      onChanged: _running ? null : (v) => setState(() => onPick(v as T)),
      items: [
        for (final (v, label) in items)
          DropdownMenuItem(
            value: v,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
    Widget pills<T>(Map<T, String> labels, T current, void Function(T) pick) =>
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in labels.entries)
              Pill(
                label: tr(e.value),
                selected: e.key == current,
                colors: c,
                onTap: _running ? null : () => setState(() => pick(e.key)),
              ),
          ],
        );
    Widget field(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(title, style: const TextStyle(color: TeamColors.muted)),
          ),
          Expanded(child: child),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(
            'A race on its own, as a playground: the field as the season would send it, fresh riders, the same simulation as in the career. Nothing of it reaches your career.',
          ),
          style: const TextStyle(color: TeamColors.muted),
        ),
        const SizedBox(height: 12),
        field(
          tr('Race'),
          dropdown<int>(raceId, [
            for (final r in races)
              (
                r.info.id,
                '${r.start.day.toString().padLeft(2, '0')}.${r.start.month.toString().padLeft(2, '0')}. · ${r.info.name} · ${r.tier.label}',
              ),
          ], (v) => _raceId = v),
        ),
        field(
          tr('Your team'),
          dropdown<int>(teamId, [
            for (final t in teams) (t.id, t.name),
          ], (v) => _teamId = v),
        ),
        field(
          tr('Race approach'),
          pills<Approach?>(_approaches, _approach, (v) => _approach = v),
        ),
        field(
          tr('The break'),
          pills<BreakPolicy?>(_breaks, _breakPolicy, (v) => _breakPolicy = v),
        ),
        field(
          tr('Tyres'),
          pills<Tyres?>(
            {
              null: 'Sports director',
              Tyres.narrow: 'Narrow',
              Tyres.standard: 'Standard',
              Tyres.wide: 'Wide',
            },
            _tyres,
            (v) => _tyres = v,
          ),
        ),
        field(
          tr('Seed'),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextFormField(
                  initialValue: '$_seed',
                  enabled: !_running,
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _seed = int.tryParse(v) ?? 1,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: c.panel2,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: c.line),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('The same seed gives the same race.'),
                  style: const TextStyle(fontSize: 12, color: TeamColors.muted),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                ),
                onPressed: _running ? null : _start,
                child: Text(
                  _running
                      ? tr('simulating …')
                      : _race == null
                      ? tr('Start the race')
                      : tr('Ride it again'),
                ),
              ),
            ],
          ),
        ),
        if (_race case final race?) ...[
          const SizedBox(height: 6),
          Expanded(child: _results(race)),
        ],
      ],
    );
  }

  /// The result of the stages ridden so far.
  Widget _results(SingleRace race) {
    final c = _s.colors;
    final done = race.stagesDone;
    if (done == 0) {
      return Center(
        child: Text(
          tr('Stage 1 is being simulated …'),
          style: const TextStyle(color: TeamColors.muted),
        ),
      );
    }
    final index = _stage.clamp(0, done - 1);
    final result = race.run.results[index];
    final standings = race.run.standings[index];
    final teamId = race.career.teamId;
    Col<T> place<T>() => Col(
      '',
      36,
      (_, i) => cellText('${i + 1}', color: TeamColors.muted),
      numeric: true,
    );
    final table = _tab == 0 || !race.race.isStageRace
        ? DenseTable<Placing>(
            colors: c,
            rows: result.placings,
            highlight: (p) => p.rider.teamId == teamId,
            columns: [
              place(),
              Col(tr('Rider'), 190, (p, _) => cellText(p.rider.name)),
              Col(
                'Team',
                56,
                (p, _) => cellText(p.rider.team, color: TeamColors.muted),
              ),
              Col(
                tr('Time'),
                86,
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
          )
        : DenseTable<TimeEntry>(
            colors: c,
            rows: standings.general,
            highlight: (e) => e.rider.teamId == teamId,
            columns: [
              place(),
              Col(tr('Rider'), 190, (e, _) => cellText(e.rider.name)),
              Col(
                'Team',
                56,
                (e, _) => cellText(e.rider.team, color: TeamColors.muted),
              ),
              Col(
                tr('Time'),
                86,
                (e, i) => cellText(
                  i == 0
                      ? clock(e.timeS)
                      : gap(e.timeS - standings.general.first.timeS),
                ),
                numeric: true,
              ),
            ],
          );
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
                if (race.routes.length > 1)
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < race.routes.length; i++)
                        Pill(
                          label: '${i + 1}',
                          selected: i == index,
                          colors: c,
                          onTap: i < done
                              ? () => setState(() => _stage = i)
                              : null,
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
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
                                  ),
                                ),
                              ),
                              Expanded(child: Text(e.text)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 14),
                      if (result.power.isNotEmpty)
                        PowerView(
                          result: _ownAndTop(result, teamId),
                          teamId: teamId,
                          colors: c,
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
                if (race.race.isStageRace)
                  Wrap(
                    spacing: 6,
                    children: [
                      Pill(
                        label: tr('Stage'),
                        selected: _tab == 0,
                        colors: c,
                        onTap: () => setState(() => _tab = 0),
                      ),
                      Pill(
                        label: tr('Overall'),
                        selected: _tab == 1,
                        colors: c,
                        onTap: () => setState(() => _tab = 1),
                      ),
                    ],
                  )
                else
                  Label(tr('Result')),
                const SizedBox(height: 8),
                Expanded(child: table),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// A copy of the result whose power figures are those of the led team
  /// and the first ten, as in the career.
  StageResult _ownAndTop(StageResult r, int teamId) {
    final top = {for (final p in r.placings.take(10)) p.rider.id};
    return StageResult(r.placings, r.events, r.breakSurvived, r.awards)
      ..power = {
        for (final e in r.power.entries)
          if (top.contains(e.key) ||
              r.placings.any(
                (p) => p.rider.id == e.key && p.rider.teamId == teamId,
              ))
            e.key: e.value,
      };
  }
}
