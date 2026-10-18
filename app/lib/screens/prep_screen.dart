import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';

const _approachLabels = {
  Approach.wait: 'Wait',
  Approach.control: 'Control the pace',
  Approach.makeHard: 'Make the race hard',
  Approach.echelon: 'Split in the crosswind',
};
const _breakLabels = {
  BreakPolicy.ignore: 'Ignore',
  BreakPolicy.join: 'Join',
  BreakPolicy.chase: 'Chase down',
};

/// Race preparation: choose the line-up, set roles and team tactics. Shown
/// as soon as a race with the player's team starts.
class PrepScreen extends StatefulWidget {
  const PrepScreen({super.key, required this.state, required this.pending});
  final AppState state;
  final PendingRace pending;

  @override
  State<PrepScreen> createState() => _PrepScreenState();
}

/// State of the preparation: chosen riders, roles, tactics and the forecast.
class _PrepScreenState extends State<PrepScreen> {
  late Set<int> _selected;
  late Map<int, Role> _roles;
  late Approach _approach;
  late BreakPolicy _breakPolicy;

  /// Off: the sports director plans every stage himself. On: what the
  /// player changes here is pinned for the whole race, and the sports
  /// director plans the rest stage by stage.
  var _ownTactics = false;

  /// Riders whose role the player has pinned, and whether he has pinned the
  /// approach and the breakaway policy.
  final _pinned = <int>{};

  /// The role as the player chose it; a stage may show it differently (a
  /// sprinter is a protected rider in the mountains).
  final _wanted = <int, Role>{};
  var _pinApproach = false, _pinBreak = false;

  /// On: the complete plan applies exactly as set, on every stage, and the
  /// sports director changes nothing. Off: only the pins are fixed.
  var _fixAll = false;

  /// Switches between pinning single choices and fixing the whole plan.
  void _setFixAll(bool on) {
    _fixAll = on;
    if (on) {
      // Everything that is shown now becomes the plan.
      _wanted
        ..clear()
        ..addAll(_roles);
      _pinned
        ..clear()
        ..addAll(_roles.keys);
      _pinApproach = _pinBreak = true;
    }
  }

  /// What the player has pinned, as the career stores it.
  PlanWish get _wish => PlanWish(
    roles: {
      for (final id in _pinned)
        if (_wanted.containsKey(id)) id: _wanted[id]!,
    },
    approach: _pinApproach ? _approach : null,
    breakPolicy: _pinBreak ? _breakPolicy : null,
  );

  /// Sports director in the car; preset to the best free one.
  int? _director;

  /// Road captain; null leaves the choice to the sports director.
  int? _captain;

  /// In a team time trial the line waits for the leader.
  var _waitForLeader = false;

  /// Earlier states of the line-up and the tactics, for "undo".
  final _undo = <_Choice>[];

  _Choice get _choice => _Choice(
    {..._selected},
    {..._roles},
    {..._wanted},
    {..._pinned},
    _approach,
    _breakPolicy,
    _pinApproach,
    _pinBreak,
    _fixAll,
    _ownTactics,
  );

  /// Every change of the line-up or the tactics can be taken back.
  @override
  void setState(VoidCallback fn) {
    final before = _choice;
    super.setState(fn);
    if (!before.same(_choice)) {
      _undo.add(before);
      if (_undo.length > 30) _undo.removeAt(0);
    }
  }

  /// Goes back to the line-up and tactics before the last change.
  void _takeBack() {
    if (_undo.isEmpty) return;
    final c = _undo.removeLast();
    super.setState(() {
      _selected = c.selected;
      _roles = c.roles;
      _wanted
        ..clear()
        ..addAll(c.wanted);
      _pinned
        ..clear()
        ..addAll(c.pinned);
      _approach = c.approach;
      _breakPolicy = c.breakPolicy;
      _pinApproach = c.pinApproach;
      _pinBreak = c.pinBreak;
      _fixAll = c.fixAll;
      _ownTactics = c.ownTactics;
      _forecast = null;
    });
  }

  /// Forecast for the current line-up; discarded as soon as it changes.
  Forecast? _forecast;
  var _forecasting = false;

  /// Computes the forecast for the current line-up and tactics.
  ///
  /// @returns A future that completes when the forecast is shown.
  Future<void> _runForecast() async {
    final lineup = _lineup;
    setState(() => _forecasting = true);
    final result = await widget.state.forecast(
      _p,
      lineup,
      _ownTactics
          ? TeamPlan(
              roles: _roles,
              approach: _approach,
              breakPolicy: _breakPolicy,
            )
          : null,
    );
    if (!mounted) return;
    setState(() {
      _forecasting = false;
      _forecast = result;
    });
  }

  /// The race being prepared.
  PendingRace get _p => widget.pending;

  /// Route of the first stage.
  SimRoute get _first => _p.routes.first;

  /// Chosen riders in squad order.
  List<SimRider> get _lineup => [
    for (final r in _p.available)
      if (_selected.contains(r.id)) r,
  ];

  @override
  void initState() {
    super.initState();
    _selected = {for (final r in _p.suggestedLineup) r.id};
    _director = _p.directors.firstOrNull?.id;
    _takeSuggestion();
  }

  /// Takes over the roles and instructions the sports director would choose
  /// for the first stage with the current line-up.
  void _takeSuggestion() {
    final lineup = _lineup;
    if (lineup.isEmpty) {
      _roles = {};
      _approach = Approach.wait;
      _breakPolicy = BreakPolicy.ignore;
      return;
    }
    if (_fixAll) {
      // The plan stands; riders new to the line-up start as helpers.
      for (final r in lineup) {
        _wanted.putIfAbsent(r.id, () => Role.domestique);
        _pinned.add(r.id);
      }
      _roles = {for (final r in lineup) r.id: _wanted[r.id]!};
      return;
    }
    // The suggestion for the first stage, with the player's pins on top.
    final wish = _ownTactics ? _wish : const PlanWish();
    final plan = wish.applyTo(
      widget.state.career.suggestPlan(
        _first,
        lineup,
        _p.others,
        crosswindKm:
            widget.state.career.forecastOf(_p.race)?.crosswindDistance ?? 0,
      ),
      _first,
      {for (final r in lineup) r.id},
    );
    _roles = {for (final r in lineup) r.id: plan.roleOf(r.id)};
    _approach = plan.approach;
    _breakPolicy = plan.breakPolicy;
  }

  /// @param r A rider.
  /// @returns His mean suitability for the three stages that suit him best.
  double _fit(SimRider r) {
    final fits = [
      for (final route in _p.routes) suitability(route, r.attributes),
    ]..sort((a, b) => b.compareTo(a));
    final top = fits.take(fits.length < 3 ? fits.length : 3);
    return top.reduce((a, b) => a + b) / top.length;
  }

  /// Confirms the line-up; first shows what speaks against it, if anything.
  ///
  /// @param s Application state.
  /// @param lineup The chosen riders.
  Future<void> _confirm(AppState s, List<SimRider> lineup) async {
    final warnings = s.career.lineupWarnings(_p.race, lineup, _p.size);
    if (warnings.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Before the start')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final w in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2, right: 8),
                          child: Icon(
                            LucideIcons.triangleAlert,
                            size: 15,
                            color: TeamColors.gold,
                          ),
                        ),
                        Expanded(child: Text(w)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Back to the line-up')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Confirm anyway')),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    await s.confirmLineup(
      _p,
      lineup,
      plan: _ownTactics && _fixAll
          ? TeamPlan(
              roles: _roles,
              approach: _approach,
              breakPolicy: _breakPolicy,
            )
          : null,
      wish: _ownTactics && !_fixAll ? _wish : null,
      directorId: _director,
      captainId: _captain,
      waitForLeader: _waitForLeader,
    );
  }

  /// Takes over who rode the race for the team last year, as far as they
  /// are still in the team and available.
  void _lastYear(List<int> ids) => setState(() {
    _forecast = null;
    final available = {for (final r in _p.available) r.id};
    _selected = {
      for (final id in ids)
        if (available.contains(id)) id,
    };
    _pinned.removeWhere((id) => !_selected.contains(id));
    _takeSuggestion();
  });

  /// The player's saved line-ups: apply one, save the current one, or
  /// delete one.
  Widget _templates(AppState s) {
    final c = s.colors;
    final saved = s.career.lineupTemplates;
    return PopupMenuButton<String>(
      tooltip: tr('Line-up templates'),
      onSelected: (choice) async {
        if (choice == '+save') {
          final name = await _askName(context, s);
          if (name == null || name.trim().isEmpty) return;
          s.saveLineupTemplate(name.trim(), [for (final r in _lineup) r.id]);
          setState(() {});
        } else if (choice.startsWith('-')) {
          s.saveLineupTemplate(choice.substring(1), null);
          setState(() {});
        } else if (saved[choice] case final ids?) {
          _lastYear(ids);
        }
      },
      itemBuilder: (context) => [
        for (final name in saved.keys)
          PopupMenuItem(value: name, child: Text(tr('Apply: {0}', [name]))),
        if (saved.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem(
          value: '+save',
          child: Text(tr('Save this line-up as a template …')),
        ),
        for (final name in saved.keys)
          PopupMenuItem(
            value: '-$name',
            child: Text(
              tr('Delete: {0}', [name]),
              style: const TextStyle(color: TeamColors.muted),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(tr('Templates ▾')),
      ),
    );
  }

  /// Asks for the name of a new line-up template.
  static Future<String?> _askName(BuildContext context, AppState s) {
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: s.colors.panel,
        title: Text(tr('Save as template')),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('Name')),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
  }

  /// The road captain: who carries the plan out on the road. A good one
  /// makes the team carry out the plan better.
  Widget _roadCaptain(AppState s, List<SimRider> lineup) {
    final people = s.career.people;
    if (lineup.isEmpty) return const SizedBox();
    final best = people.bestCaptain(lineup)!;
    final chosen = lineup.any((r) => r.id == _captain) ? _captain : null;
    String label(SimRider r) => tr('{0} · leadership {1}, race sense {2}', [
      r.name,
      (people.leadership(r.id) * 20).round(),
      (people.raceSense(r.id) * 20).round(),
    ]);
    return Row(
      children: [
        Text(
          tr('Road captain:'),
          style: const TextStyle(fontSize: 13, color: TeamColors.muted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<int?>(
            value: chosen,
            isDense: true,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: s.colors.panel2,
            style: const TextStyle(
              fontFamily: 'Barlow',
              fontSize: 13,
              color: TeamColors.text,
            ),
            onChanged: (v) => setState(() => _captain = v),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text(
                  tr('Sports director\'s choice: {0}', [label(best)]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final r in lineup)
                DropdownMenuItem<int?>(
                  value: r.id,
                  child: Text(label(r), overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The sprint train as the roles make it: the lead-out men before the
  /// sprinter, shown when the race has stages for the sprinters.
  Widget _sprintTrain(List<SimRider> lineup) {
    if (!_p.routes.any((r) => r.sprintStage)) return const SizedBox();
    final sprinter = lineup
        .where((r) => _roles[r.id] == Role.sprinter)
        .firstOrNull;
    final leadOut = [
      for (final r in lineup)
        if (_roles[r.id] == Role.leadOut) r,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        sprinter == null
            ? tr('Sprint train: no sprinter in the roles.')
            : tr('Sprint train: {0} → {1}{2}', [
                leadOut.isEmpty ? '–' : leadOut.map((r) => r.name).join(' → '),
                sprinter.name,
                leadOut.length > 2 ? tr(' (two lead-out men count)') : '',
              ]),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  /// Tyres and bikes of the day, with the suppliers of the team.
  Widget _material(AppState s) {
    final c = s.colors;
    final race = _p.race;
    final career = s.career;
    final eq = career.equipment;
    final supply = eq.supplyOf(career.teamId);
    final forecast = career.forecastOf(race);
    final suggested = suggestTyres(
      _first,
      forecast?.expected ?? const Weather(),
    );
    final own = eq.ownTyres[race.info.id];
    final trials = [
      for (final st in race.stages)
        if (career.world.route(st.id).kind != StageKind.road)
          career.world.route(st.id),
    ];
    final ownBike = eq.ownTimeTrialBike[race.info.id];
    String tyre(Tyres t) => switch (t) {
      Tyres.narrow => tr('Narrow'),
      Tyres.standard => tr('Standard'),
      Tyres.wide => tr('Wide'),
    };
    Widget row(String title, List<Widget> pills) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              title,
              style: const TextStyle(fontSize: 12, color: TeamColors.muted),
            ),
          ),
          ...pills,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(tr('Tyres'), [
          Pill(
            label: race.isStageRace
                ? tr('Sports director, per stage')
                : tr('Sports director: {0}', [tyre(suggested)]),
            selected: own == null,
            colors: c,
            onTap: () => s.setTyres(race.info.id, null),
          ),
          for (final t in Tyres.values)
            Pill(
              label: tyre(t),
              selected: own == t,
              colors: c,
              onTap: () => s.setTyres(race.info.id, t),
            ),
        ]),
        if (trials.isNotEmpty)
          row(tr('Time trials'), [
            Pill(
              label: tr('Sports director: {0}', [
                suggestTimeTrialBike(trials.first)
                    ? tr('Time trial bike')
                    : tr('Road bike'),
              ]),
              selected: ownBike == null,
              colors: c,
              onTap: () => s.setTimeTrialBike(race.info.id, null),
            ),
            Pill(
              label: tr('Time trial bike'),
              selected: ownBike == true,
              colors: c,
              onTap: () => s.setTimeTrialBike(race.info.id, true),
            ),
            Pill(
              label: tr('Road bike'),
              selected: ownBike == false,
              colors: c,
              onTap: () => s.setTimeTrialBike(race.info.id, false),
            ),
          ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            tr(
              'Material: {0} bikes, {1} tyres. Wide tyres roll better and puncture less on cobbles and gravel, narrow ones are faster on smooth roads.',
              [supply.bike.name, supply.tyres.name],
            ),
            style: const TextStyle(fontSize: 11.5, color: TeamColors.muted),
          ),
        ),
      ],
    );
  }

  void _toggle(SimRider r) => setState(() {
    _forecast = null;
    if (!_selected.remove(r.id)) {
      if (_selected.length >= _p.size) return;
      _selected.add(r.id);
    }
    // Pins stay; around them the sports director plans the new line-up.
    _pinned.removeWhere((id) => !_selected.contains(id));
    _takeSuggestion();
  });

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final race = _p.race;
    final lineup = _lineup;
    final available = [..._p.available]
      ..sort((a, b) => _fit(b).compareTo(_fit(a)));
    final rivals = [..._p.others]
      ..sort(
        (a, b) => suitability(
          _first,
          b.attributes,
        ).compareTo(suitability(_first, a.attributes)),
      );
    final meters = _first.segments
        .where((x) => x.grade > 0)
        .fold<double>(0, (sum, x) => sum + x.grade * x.lengthM);

    Col<SimRider> value(String title, double Function(SimRider) of) => Col(
      title,
      title.length > 4 ? 74 : 44,
      (r, _) {
        final v = of(r);
        return cellText(
          v.round().toString(),
          color: attributeColor(v),
          bold: v >= 72,
        );
      },
      numeric: true,
      sortKey: of,
    );

    Widget choice<T>(
      String title,
      Map<T, String> labels,
      T current,
      void Function(T) onPick,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: TeamColors.muted),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in labels.entries)
              withHelp(
                e.value,
                Pill(
                  label: tr(e.value),
                  selected: e.key == current,
                  colors: c,
                  onTap: _ownTactics
                      ? () => setState(() => onPick(e.key))
                      : null,
                ),
              ),
          ],
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      race.info.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      tr('{0} · {1} · {2} · {3} riders at the start', [
                        race.tier.label,
                        race.info.country,
                        race.isStageRace
                            ? trn(race.stages.length, '{0} stage', '{0} stages')
                            : tr('One-day race'),
                        _p.others.length + lineup.length,
                      ]),
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                  ],
                ),
              ),
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
                onPressed: () => setState(() {
                  _selected = {for (final r in _p.suggestedLineup) r.id};
                  _ownTactics = false;
                  _pinned.clear();
                  _pinApproach = _pinBreak = false;
                  _fixAll = false;
                  _takeSuggestion();
                }),
                child: Text(tr('Sports director\'s suggestion')),
              ),
              const SizedBox(width: 10),
              if (s.career.lastLineups[race.info.id] case final ids?
                  when ids.isNotEmpty) ...[
                Tooltip(
                  message: tr(
                    'The riders who rode this race for the team last year, as far as they are available.',
                  ),
                  child: OutlinedButton(
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
                    onPressed: () => _lastYear(ids),
                    child: Text(tr('Line-up of last year')),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              _templates(s),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _undo.isEmpty ? null : _takeBack,
                child: Text(tr('Undo')),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  disabledBackgroundColor: c.panel,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                ),
                onPressed: lineup.length < 4 ? null : () => _confirm(s, lineup),
                child: Text(
                  tr('CONFIRM AND START'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
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
                            Label(tr('Available riders')),
                            const Spacer(),
                            Text(
                              tr('{0} of {1} selected', [
                                lineup.length,
                                _p.size,
                              ]),
                              style: TextStyle(
                                fontSize: 12,
                                color: lineup.length == _p.size
                                    ? TeamColors.green
                                    : TeamColors.gold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: DenseTable<SimRider>(
                            colors: c,
                            rows: available,
                            highlight: (r) => _selected.contains(r.id),
                            onTap: _toggle,
                            columns: [
                              Col(
                                '',
                                34,
                                (r, _) => Icon(
                                  _selected.contains(r.id)
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size: 17,
                                  color: _selected.contains(r.id)
                                      ? TeamColors.text
                                      : TeamColors.muted,
                                ),
                              ),
                              Col(
                                tr('Rider'),
                                170,
                                (r, _) => cellText(
                                  s.career.devTeam.stagiaires.contains(r.id)
                                      ? '${r.name} · Stagiaire'
                                      : r.name,
                                ),
                                sortKey: (r) => r.lastName,
                              ),
                              value(tr('Fit'), _fit),
                              value('FL', (r) => r.attributes.flat),
                              value(tr('MTN'), (r) => r.attributes.mountain),
                              value(tr('HIL'), (r) => r.attributes.hill),
                              value(tr('TT'), (r) => r.attributes.timeTrial),
                              value(tr('COB'), (r) => r.attributes.cobble),
                              value(tr('SPR'), (r) => r.attributes.sprint),
                              value(tr('BRK'), (r) => r.attributes.breakaway),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      Panel(
                        colors: c,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    race.isStageRace
                                        ? tr('Stage 1 · {0}', [_first.name])
                                        : _first.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  tr('{0} km · {1} m climbing', [
                                    dec(_first.raceKm, 1),
                                    meters.round(),
                                  ]),
                                  style: const TextStyle(
                                    color: TeamColors.muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            // What the weather service expects; the real
                            // weather of the day can differ.
                            Builder(
                              builder: (context) {
                                final f = s.career.forecastOf(race);
                                return Text(
                                  f == null
                                      ? tr('Forecast: –')
                                      : f.echelonRisk
                                      ? '${tr('Forecast: {0}', [f.describe()])} · ${tr('echelons possible')}'
                                      : tr('Forecast: {0}', [f.describe()]),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: f?.echelonRisk ?? false
                                        ? TeamColors.gold
                                        : TeamColors.muted,
                                  ),
                                );
                              },
                            ),
                            _material(s),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 150,
                              child: ProfileView(route: _first, colors: c),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
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
                                        Label(tr('Roles and tactics')),
                                        const Spacer(),
                                        Text(
                                          tr('Own tactics'),
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(width: 4),
                                        SizedBox(
                                          height: 24,
                                          child: Switch(
                                            value: _ownTactics,
                                            activeThumbColor: c.accent,
                                            onChanged: (v) => setState(() {
                                              _ownTactics = v;
                                              if (!v) {
                                                _pinned.clear();
                                                _pinApproach = false;
                                                _pinBreak = false;
                                                _fixAll = false;
                                                _takeSuggestion();
                                              }
                                            }),
                                          ),
                                        ),
                                      ],
                                    ),
                                    InfoTip(
                                      _ownTactics
                                          ? tr(
                                              'What you change is pinned and applies to the whole race. Everything else the sports director plans anew for every stage. A click on the pin releases it again.',
                                            )
                                          : tr(
                                              'The sports director plans every stage himself. This is his plan for the opener.',
                                            ),
                                    ),
                                    if (_ownTactics) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          Pill(
                                            label: tr('Pin only what I change'),
                                            selected: !_fixAll,
                                            colors: c,
                                            onTap: () => setState(() {
                                              _setFixAll(false);
                                              _pinned.clear();
                                              _wanted.clear();
                                              _pinApproach = _pinBreak = false;
                                              _takeSuggestion();
                                            }),
                                          ),
                                          Pill(
                                            label: tr('Fix everything'),
                                            selected: _fixAll,
                                            colors: c,
                                            onTap: () => setState(
                                              () => _setFixAll(true),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_fixAll)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Text(
                                            tr(
                                              'Everything applies exactly as set for the whole race, on every stage; the sports director changes nothing.',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: TeamColors.muted,
                                            ),
                                          ),
                                        ),
                                    ],
                                    const SizedBox(height: 6),
                                    if (_p.directors.isNotEmpty)
                                      Row(
                                        children: [
                                          Text(
                                            tr('In the car:'),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: TeamColors.muted,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: DropdownButton<int>(
                                              value: _director,
                                              isDense: true,
                                              isExpanded: true,
                                              underline: const SizedBox(),
                                              dropdownColor: c.panel2,
                                              style: const TextStyle(
                                                fontFamily: 'Barlow',
                                                fontSize: 13,
                                                color: TeamColors.text,
                                              ),
                                              onChanged: (v) =>
                                                  setState(() => _director = v),
                                              items: [
                                                for (final d in _p.directors)
                                                  DropdownMenuItem(
                                                    value: d.id,
                                                    child: Text(
                                                      tr(
                                                        '{0} · tactics {1}, race reading {2}, motivation {3} · {4}',
                                                        [
                                                          d.name,
                                                          d.skill,
                                                          d.second,
                                                          d.third,
                                                          d.focus.label,
                                                        ],
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    else
                                      Text(
                                        tr(
                                          'No sports director free: a mechanic drives the car.',
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: TeamColors.red,
                                        ),
                                      ),
                                    _roadCaptain(s, lineup),
                                    _sprintTrain(lineup),
                                    if (_p.routes.any(
                                      (r) => r.kind == StageKind.teamTimeTrial,
                                    ))
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              tr(
                                                'Team time trial: the line waits for the leader',
                                              ),
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          Switch(
                                            value: _waitForLeader,
                                            activeThumbColor: c.accent,
                                            onChanged: (v) => setState(
                                              () => _waitForLeader = v,
                                            ),
                                          ),
                                        ],
                                      ),
                                    const SizedBox(height: 6),
                                    Expanded(
                                      child: ListView(
                                        children: [
                                          for (final r in lineup)
                                            SizedBox(
                                              height: 30,
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: cellText(r.name),
                                                  ),
                                                  if (_pinned.contains(r.id))
                                                    InkWell(
                                                      onTap: () => setState(() {
                                                        _fixAll = false;
                                                        _pinned.remove(r.id);
                                                        _wanted.remove(r.id);
                                                        _takeSuggestion();
                                                      }),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                            ),
                                                        child: Icon(
                                                          LucideIcons.pin,
                                                          size: 14,
                                                          color: c.accent,
                                                        ),
                                                      ),
                                                    ),
                                                  DropdownButton<Role>(
                                                    value:
                                                        _roles[r.id] ??
                                                        Role.domestique,
                                                    isDense: true,
                                                    underline: const SizedBox(),
                                                    dropdownColor: c.panel2,
                                                    style: const TextStyle(
                                                      fontFamily: 'Barlow',
                                                      fontSize: 13,
                                                      color: TeamColors.text,
                                                    ),
                                                    onChanged: _ownTactics
                                                        ? (v) => setState(() {
                                                            _wanted[r.id] = v!;
                                                            _pinned.add(r.id);
                                                            _takeSuggestion();
                                                          })
                                                        : null,
                                                    items: [
                                                      for (final role
                                                          in Role.values)
                                                        DropdownMenuItem(
                                                          value: role,
                                                          child: Tooltip(
                                                            message: role.help,
                                                            child: Text(
                                                              role.label,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          const SizedBox(height: 10),
                                          choice(
                                            tr('Race approach'),
                                            _approachLabels,
                                            _approach,
                                            (v) {
                                              _approach = v;
                                              _pinApproach = true;
                                            },
                                          ),
                                          const SizedBox(height: 8),
                                          choice(
                                            tr('The break'),
                                            _breakLabels,
                                            _breakPolicy,
                                            (v) {
                                              _breakPolicy = v;
                                              _pinBreak = true;
                                            },
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
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Label(
                                            _forecast != null
                                                ? tr('Forecast · {0} runs', [
                                                    _forecast!.runs,
                                                  ])
                                                : race.isStageRace
                                                ? tr(
                                                    'Strongest rivals on day one',
                                                  )
                                                : tr('Strongest rivals'),
                                          ),
                                        ),
                                        InkWell(
                                          onTap:
                                              _forecasting || lineup.length < 4
                                              ? null
                                              : _forecast != null
                                              ? () => setState(
                                                  () => _forecast = null,
                                                )
                                              : _runForecast,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: c.line),
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                            ),
                                            child: Text(
                                              _forecasting
                                                  ? tr('simulating …')
                                                  : _forecast != null
                                                  ? tr('Show rivals')
                                                  : tr('Forecast'),
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    if (_forecast case final f?)
                                      Expanded(
                                        child: DenseTable<ForecastRow>(
                                          colors: c,
                                          // The first 15 and all of our own.
                                          rows: [
                                            for (final (i, row)
                                                in f.rows.indexed)
                                              if (i < 15 ||
                                                  row.rider.teamId == s.team.id)
                                                row,
                                          ],
                                          highlight: (row) =>
                                              row.rider.teamId == s.team.id,
                                          columns: [
                                            Col(
                                              tr('Rider'),
                                              124,
                                              (row, _) =>
                                                  cellText(row.rider.name),
                                            ),
                                            Col(
                                              'Team',
                                              46,
                                              (row, _) => cellText(
                                                row.rider.team,
                                                color: TeamColors.muted,
                                              ),
                                            ),
                                            Col(
                                              tr('Win'),
                                              44,
                                              (row, _) => cellText(
                                                row.wins == 0
                                                    ? '–'
                                                    : '${row.wins}×',
                                                color: TeamColors.gold,
                                              ),
                                              numeric: true,
                                            ),
                                            Col(
                                              'Top 3',
                                              50,
                                              (row, _) => cellText(
                                                row.podiums == 0
                                                    ? '–'
                                                    : '${row.podiums}×',
                                              ),
                                              numeric: true,
                                            ),
                                            Col(
                                              'Ø',
                                              44,
                                              (row, _) => cellText(
                                                dec(row.meanRank, 1),
                                              ),
                                              numeric: true,
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Expanded(
                                        child: DenseTable<SimRider>(
                                          colors: c,
                                          rows: rivals.take(25).toList(),
                                          columns: [
                                            Col(
                                              tr('Rider'),
                                              150,
                                              (r, _) => cellText(r.name),
                                            ),
                                            Col(
                                              'Team',
                                              50,
                                              (r, _) => cellText(
                                                r.team,
                                                color: TeamColors.muted,
                                              ),
                                            ),
                                            value(
                                              tr('Fit'),
                                              (r) => suitability(
                                                _first,
                                                r.attributes,
                                              ),
                                            ),
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The line-up and the tactics at one moment of the preparation.
class _Choice {
  _Choice(
    this.selected,
    this.roles,
    this.wanted,
    this.pinned,
    this.approach,
    this.breakPolicy,
    this.pinApproach,
    this.pinBreak,
    this.fixAll,
    this.ownTactics,
  );
  final Set<int> selected;
  final Map<int, Role> roles;
  final Map<int, Role> wanted;
  final Set<int> pinned;
  final Approach approach;
  final BreakPolicy breakPolicy;
  final bool pinApproach, pinBreak, fixAll, ownTactics;

  /// @param o Another moment.
  /// @returns Whether nothing differs.
  bool same(_Choice o) =>
      selected.length == o.selected.length &&
      selected.containsAll(o.selected) &&
      _mapSame(roles, o.roles) &&
      _mapSame(wanted, o.wanted) &&
      pinned.length == o.pinned.length &&
      pinned.containsAll(o.pinned) &&
      approach == o.approach &&
      breakPolicy == o.breakPolicy &&
      pinApproach == o.pinApproach &&
      pinBreak == o.pinBreak &&
      fixAll == o.fixAll &&
      ownTactics == o.ownTactics;

  static bool _mapSame(Map<int, Role> a, Map<int, Role> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}
