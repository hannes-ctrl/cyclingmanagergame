import 'package:flutter/material.dart';
import 'package:game/game.dart';
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

/// Opens "what if": a ridden stage once more with the same randomness, the
/// same opponents and the same form of the day, but with different tactics
/// and radio instructions. Does not change the game state.
///
/// @param context Build context.
/// @param state Application state.
/// @param progress The race.
/// @param stageIndex Zero-based index of the ridden stage.
/// @returns A future that completes when the dialog is closed.
Future<void> showWhatIfDialog(
  BuildContext context,
  AppState state,
  RaceProgress progress,
  int stageIndex,
) => showDialog<void>(
  context: context,
  builder: (context) =>
      _WhatIfDialog(state: state, progress: progress, stageIndex: stageIndex),
);

/// Dialog with three steps: edit tactics, answer radio questions, compare.
class _WhatIfDialog extends StatefulWidget {
  const _WhatIfDialog({
    required this.state,
    required this.progress,
    required this.stageIndex,
  });
  final AppState state;
  final RaceProgress progress;
  final int stageIndex;

  @override
  State<_WhatIfDialog> createState() => _WhatIfDialogState();
}

/// State of the dialog: edited tactics, radio answers and the second result.
class _WhatIfDialogState extends State<_WhatIfDialog> {
  late final List<SimRider> _own;
  late Map<int, Role> _roles;
  late Approach _approach;
  late BreakPolicy _breakPolicy;

  /// Radio answers of the second run.
  final _radio = <RadioKind, int>{};
  RadioCall? _call;
  StageResult? _result;

  /// Id of the race.
  int get _raceId => widget.progress.race.info.id;

  /// Result of the stage as it was ridden.
  StageResult get _real => widget.progress.run.results[widget.stageIndex];

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    _own = [
      for (final r in widget.progress.run.ridersBefore(widget.stageIndex))
        if (r.teamId == s.team.id) r,
    ];
    final plan = s.career.planUsed(_raceId, widget.stageIndex);
    _roles = {for (final r in _own) r.id: plan.roleOf(r.id)};
    _approach = plan.approach;
    _breakPolicy = plan.breakPolicy;
  }

  /// Simulates up to the next open question or to the finish.
  void _run() {
    final result = widget.state.career.whatIf(
      _raceId,
      widget.stageIndex,
      plan: TeamPlan(
        roles: _roles,
        approach: _approach,
        breakPolicy: _breakPolicy,
      ),
      radio: _radio,
      askRadio: true,
    );
    setState(() {
      _call = result.openCall;
      _result = result.openCall == null ? result : null;
    });
  }

  void _reset() => setState(() {
    _radio.clear();
    _call = null;
    _result = null;
  });

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final p = widget.progress;
    final route = s.world.route(p.race.stages[widget.stageIndex].id);

    return Dialog(
      backgroundColor: c.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('What if?'),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
              ),
              Text(
                '${p.race.info.name}'
                '${p.race.isStageRace ? tr(' · stage {0}', [widget.stageIndex + 1]) : ''}'
                ' · ${route.name} · ${route.raceKm.toStringAsFixed(1)} km',
                style: const TextStyle(color: TeamColors.muted),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: _result != null
                    ? _comparison(c, _result!)
                    : _call != null
                    ? _question(c, _call!)
                    : _editor(c),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Close')),
                  ),
                  const SizedBox(width: 6),
                  if (_result != null || _call != null)
                    OutlinedButton(
                      onPressed: _reset,
                      child: Text(tr('Different tactics')),
                    )
                  else
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: c.onAccent,
                      ),
                      onPressed: _run,
                      child: Text(tr('Simulate')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// @param c Colours.
  /// @returns The editor for roles and instructions.
  Widget _editor(TeamColors c) {
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
              Pill(
                label: tr(e.value),
                selected: e.key == current,
                colors: c,
                onTap: () => setState(() => onPick(e.key)),
              ),
          ],
        ),
      ],
    );

    return ListView(
      shrinkWrap: true,
      children: [
        Text(
          tr(
            'This is how the team rode. Change roles or instructions; the radio asks again in the second run.',
          ),
          style: TextStyle(fontSize: 12, color: TeamColors.muted),
        ),
        const SizedBox(height: 8),
        for (final r in _own)
          SizedBox(
            height: 30,
            child: Row(
              children: [
                Expanded(child: cellText(r.name)),
                DropdownButton<Role>(
                  value: _roles[r.id] ?? Role.domestique,
                  isDense: true,
                  underline: const SizedBox(),
                  dropdownColor: c.panel2,
                  style: const TextStyle(
                    fontFamily: 'Barlow',
                    fontSize: 13,
                    color: TeamColors.text,
                  ),
                  onChanged: (v) => setState(() => _roles[r.id] = v!),
                  items: [
                    for (final role in Role.values)
                      DropdownMenuItem(value: role, child: Text(role.label)),
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
          (v) => _approach = v,
        ),
        const SizedBox(height: 8),
        choice(
          tr('The break'),
          _breakLabels,
          _breakPolicy,
          (v) => _breakPolicy = v,
        ),
      ],
    );
  }

  Widget _question(TeamColors c, RadioCall call) => ListView(
    shrinkWrap: true,
    children: [
      Text(
        tr('Radio · {0} km to go', [call.remainingKm.round()]),
        style: const TextStyle(fontSize: 12, color: TeamColors.muted),
      ),
      const SizedBox(height: 2),
      Text('„${call.text}"', style: const TextStyle(fontSize: 15, height: 1.4)),
      const SizedBox(height: 12),
      for (final (i, option) in call.options.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: TeamColors.text,
              side: BorderSide(color: c.line),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            onPressed: () {
              _radio[call.kind] = i;
              _run();
            },
            child: Text(option),
          ),
        ),
    ],
  );

  /// @param c Colours.
  /// @param other Result of the second run.
  /// @returns The side-by-side comparison of both runs.
  Widget _comparison(TeamColors c, StageResult other) {
    String summary(StageResult r) {
      final first = r.placings.where((x) => x.group == 0).length;
      final w = r.placings.first.rider;
      return '${w.name} (${w.team}) · '
          '${first == 1 ? 'Solo' : tr('Group of {0}', [first])}'
          '${r.breakSurvived ? tr(' · from the breakaway') : ''}';
    }

    ({int place, double gap})? of(StageResult r, int riderId) {
      final at = r.placings.indexWhere((x) => x.rider.id == riderId);
      if (at < 0) return null;
      return (place: at + 1, gap: r.placings[at].timeS - r.winnerTimeS);
    }

    final rows = [..._own]
      ..sort(
        (a, b) =>
            (of(other, a.id)?.place ?? 999) - (of(other, b.id)?.place ?? 999),
      );
    Widget head(String text) => Expanded(
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: TeamColors.muted),
      ),
    );
    Widget cell(({int place, double gap})? x, {int? against}) => Expanded(
      child: Text(
        x == null ? '–' : '${x.place}.  ${gap(x.gap)}',
        style: TextStyle(
          fontFeatures: const [FontFeature.tabularFigures()],
          color: x == null || against == null || x.place == against
              ? TeamColors.text
              : x.place < against
              ? TeamColors.green
              : TeamColors.red,
        ),
      ),
    );

    return ListView(
      shrinkWrap: true,
      children: [
        Row(
          children: [
            const SizedBox(width: 170),
            head(tr('RIDDEN')),
            head(tr('WHAT IF')),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 170, child: Text(tr('Winner'))),
            Expanded(child: Text(summary(_real))),
            Expanded(child: Text(summary(other))),
          ],
        ),
        Divider(color: c.line),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 170, child: cellText(r.name)),
                cell(of(_real, r.id)),
                cell(of(other, r.id), against: of(_real, r.id)?.place),
              ],
            ),
          ),
        Divider(color: c.line),
        Text(
          tr('COURSE OF THE SECOND RUN'),
          style: TextStyle(fontSize: 12, color: TeamColors.muted),
        ),
        const SizedBox(height: 4),
        for (final e in other.events.where((e) => e.type != EventType.points))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    'km ${e.km.round()}',
                    style: const TextStyle(color: TeamColors.muted),
                  ),
                ),
                Expanded(child: Text(e.text)),
              ],
            ),
          ),
      ],
    );
  }
}
