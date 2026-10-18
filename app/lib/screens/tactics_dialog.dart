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

/// Opens the dialog for the team's tactics in the next stages of a running race.
///
/// @param context Build context.
/// @param state Application state.
/// @param progress The running race.
/// @returns A future that completes when the dialog is closed.
Future<void> showTacticsDialog(
  BuildContext context,
  AppState state,
  RaceProgress progress,
) => showDialog<void>(
  context: context,
  builder: (context) => _TacticsDialog(state: state, progress: progress),
);

/// Dialog body with role and instruction pickers.
class _TacticsDialog extends StatefulWidget {
  const _TacticsDialog({required this.state, required this.progress});
  final AppState state;
  final RaceProgress progress;

  @override
  State<_TacticsDialog> createState() => _TacticsDialogState();
}

/// State of the dialog: the roles and instructions being edited.
class _TacticsDialogState extends State<_TacticsDialog> {
  late final List<SimRider> _own;
  late Map<int, Role> _roles;
  late Approach _approach;
  late BreakPolicy _breakPolicy;
  late final SimRoute _next;

  /// Riders whose role is pinned, and whether approach and breakaway policy
  /// are.
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

  PlanWish get _wish => PlanWish(
    roles: {
      for (final id in _pinned)
        if (_wanted.containsKey(id)) id: _wanted[id]!,
    },
    approach: _pinApproach ? _approach : null,
    breakPolicy: _pinBreak ? _breakPolicy : null,
  );

  /// The sports director's plan for the next stage with the pins on top.
  void _replan() {
    if (_fixAll) {
      _roles = {for (final r in _own) r.id: _wanted[r.id] ?? Role.domestique};
      return;
    }
    final s = widget.state;
    final p = widget.progress;
    final plan = _wish.applyTo(
      s.career.suggestPlan(_next, _own, [
        for (final r in p.run.riders)
          if (r.teamId != s.team.id) r,
      ], gcGaps: p.run.gcGaps),
      _next,
      {for (final r in _own) r.id},
    );
    _roles = {for (final r in _own) r.id: plan.roleOf(r.id)};
    _approach = plan.approach;
    _breakPolicy = plan.breakPolicy;
  }

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    final p = widget.progress;
    final raceId = p.race.info.id;
    _own = [
      for (final r in p.run.riders)
        if (r.teamId == s.team.id) r,
    ];
    _next = s.world.route(p.race.stages[p.stagesDone].id);
    // Starting point: what the player has pinned so far, over the sports
    // director's plan for the next stage given the current standings. A
    // complete plan from an older save counts as everything pinned.
    final full = s.career.ownPlans[raceId];
    final wish = s.career.ownWishes[raceId];
    if (full != null) {
      _roles = {for (final r in _own) r.id: full.roleOf(r.id)};
      _approach = full.approach;
      _breakPolicy = full.breakPolicy;
      _pinned.addAll(_roles.keys);
      _wanted.addAll(_roles);
      _pinApproach = _pinBreak = true;
      _fixAll = true;
    } else {
      _wanted.addAll(wish?.roles ?? const {});
      _pinned.addAll(_wanted.keys);
      _roles = {};
      _pinApproach = wish?.approach != null;
      _pinBreak = wish?.breakPolicy != null;
      _approach = wish?.approach ?? Approach.wait;
      _breakPolicy = wish?.breakPolicy ?? BreakPolicy.ignore;
      _replan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final p = widget.progress;
    final raceId = p.race.info.id;

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
                  onTap: () => setState(() => onPick(e.key)),
                ),
              ),
          ],
        ),
      ],
    );

    return Dialog(
      backgroundColor: c.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('Tactics from stage {0}', [p.stagesDone + 1]),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${p.race.info.name} · ${_next.name} · '
                '${_next.raceKm.toStringAsFixed(1)} km',
                style: const TextStyle(color: TeamColors.muted),
              ),
              const SizedBox(height: 4),
              InfoTip(
                tr(
                  'What you change is pinned and applies to the remaining stages. Everything else the sports director plans anew for every stage; shown is his plan for the next one. A click on the pin releases it again.',
                ),
              ),
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
                      _replan();
                    }),
                  ),
                  Pill(
                    label: tr('Fix everything'),
                    selected: _fixAll,
                    colors: c,
                    onTap: () => setState(() => _setFixAll(true)),
                  ),
                ],
              ),
              if (_fixAll)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    tr(
                      'Everything applies exactly as set for the remaining stages; the sports director changes nothing.',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: TeamColors.muted,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in _own)
                      SizedBox(
                        height: 30,
                        child: Row(
                          children: [
                            Expanded(child: cellText(r.name)),
                            if (_pinned.contains(r.id))
                              InkWell(
                                onTap: () => setState(() {
                                  _fixAll = false;
                                  _pinned.remove(r.id);
                                  _wanted.remove(r.id);
                                  _replan();
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
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
                              value: _roles[r.id] ?? Role.domestique,
                              isDense: true,
                              underline: const SizedBox(),
                              dropdownColor: c.panel2,
                              style: const TextStyle(
                                fontFamily: 'Barlow',
                                fontSize: 13,
                                color: TeamColors.text,
                              ),
                              onChanged: (v) => setState(() {
                                _wanted[r.id] = v!;
                                _pinned.add(r.id);
                                _replan();
                              }),
                              items: [
                                for (final role in Role.values)
                                  DropdownMenuItem(
                                    value: role,
                                    child: Tooltip(
                                      message: role.help,
                                      child: Text(role.label),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    choice(tr('Race approach'), _approachLabels, _approach, (
                      v,
                    ) {
                      _approach = v;
                      _pinApproach = true;
                    }),
                    const SizedBox(height: 8),
                    choice(tr('The break'), _breakLabels, _breakPolicy, (v) {
                      _breakPolicy = v;
                      _pinBreak = true;
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Cancel')),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () {
                      s.setWish(raceId, null);
                      Navigator.pop(context);
                    },
                    child: Text(tr('Sports director decides')),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.onAccent,
                    ),
                    onPressed: () {
                      if (_fixAll) {
                        s.setPlan(
                          raceId,
                          TeamPlan(
                            roles: _roles,
                            approach: _approach,
                            breakPolicy: _breakPolicy,
                          ),
                        );
                      } else {
                        s.setWish(raceId, _wish);
                      }
                      Navigator.pop(context);
                    },
                    child: Text(tr('Apply')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
