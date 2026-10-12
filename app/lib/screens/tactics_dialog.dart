import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

const _approachLabels = {
  Approach.wait: 'Abwarten',
  Approach.control: 'Tempo kontrollieren',
  Approach.makeHard: 'Rennen schwer machen',
};
const _breakLabels = {
  BreakPolicy.ignore: 'Ignorieren',
  BreakPolicy.join: 'Besetzen',
  BreakPolicy.chase: 'Zurückholen',
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
    // Starting point: the player's current tactics, otherwise the sports
    // director's suggestion for the next stage given the current standings.
    final gc = p.run.standings.last.general;
    final plan =
        s.career.ownPlans[raceId] ??
        s.career.suggestPlan(
          _next,
          _own,
          [
            for (final r in p.run.riders)
              if (r.teamId != s.team.id) r,
          ],
          gcGaps: {for (final e in gc) e.rider.id: e.timeS - gc.first.timeS},
        );
    _roles = {for (final r in _own) r.id: plan.roleOf(r.id)};
    _approach = plan.approach;
    _breakPolicy = plan.breakPolicy;
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
              ChoiceChip(
                label: Text(e.value),
                selected: e.key == current,
                showCheckmark: false,
                selectedColor: TeamColors.text,
                backgroundColor: c.panel,
                side: BorderSide(color: c.line),
                labelStyle: TextStyle(
                  fontSize: 13,
                  color: e.key == current ? TeamColors.ground : TeamColors.text,
                ),
                onSelected: (_) => setState(() => onPick(e.key)),
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
                'Taktik ab Etappe ${p.stagesDone + 1}',
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
              Text(
                s.career.ownPlans.containsKey(raceId)
                    ? 'Es gilt deine eigene Taktik.'
                    : 'Bisher plant der Sportliche Leiter jede Etappe selbst. '
                          'Das ist sein Vorschlag für die nächste.',
                style: const TextStyle(fontSize: 12, color: TeamColors.muted),
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
                              onChanged: (v) =>
                                  setState(() => _roles[r.id] = v!),
                              items: [
                                for (final role in Role.values)
                                  DropdownMenuItem(
                                    value: role,
                                    child: Text(role.label),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    choice(
                      'Rennverlauf',
                      _approachLabels,
                      _approach,
                      (v) => _approach = v,
                    ),
                    const SizedBox(height: 8),
                    choice(
                      'Ausreißergruppe',
                      _breakLabels,
                      _breakPolicy,
                      (v) => _breakPolicy = v,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () {
                      s.setPlan(raceId, null);
                      Navigator.pop(context);
                    },
                    child: const Text('Sportlicher Leiter entscheidet'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.onAccent,
                    ),
                    onPressed: () {
                      s.setPlan(
                        raceId,
                        TeamPlan(
                          roles: _roles,
                          approach: _approach,
                          breakPolicy: _breakPolicy,
                        ),
                      );
                      Navigator.pop(context);
                    },
                    child: const Text('Übernehmen'),
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
