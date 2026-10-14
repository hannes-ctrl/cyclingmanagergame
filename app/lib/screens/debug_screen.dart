import 'package:flutter/material.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

/// Debug page, shown only in debug mode: the inner state of the career, the
/// tuning values of the simulation and a few actions that help testing.
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key, required this.state});
  final AppState state;

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

/// State of the page: the last feedback message.
class _DebugScreenState extends State<DebugScreen> {
  String? _message;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final eco = career.economy;
    final running = career.progress.values.where((p) => !p.finished).length;
    final injured = [
      for (final r in s.squad)
        if (career.isInjured(r.id, career.today)) r,
    ];

    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: TeamColors.muted)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    Widget action(String label, String hint, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 250,
            child: OutlinedButton(
              onPressed: s.busy ? null : onTap,
              child: Text(label),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(hint, style: const TextStyle(color: TeamColors.muted)),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                      Label(tr('Career')),
                      const SizedBox(height: 4),
                      fact(tr('Seed'), '${career.seed}'),
                      fact(tr('Team id'), '${s.team.id}'),
                      fact(
                        tr('Riders in the world'),
                        '${career.riderById.length}',
                      ),
                      fact(tr('Teams'), '${career.teams.length}'),
                      fact(
                        tr('Races in the calendar'),
                        '${career.calendar.length}',
                      ),
                      fact(
                        tr('Races started'),
                        '${career.progress.length} ($running ${tr('running')})',
                      ),
                      fact(tr('Messages'), '${career.inbox.length}'),
                      fact(tr('Balance'), '${eco.balance.round()} €'),
                      fact(
                        tr('Development team'),
                        '${career.devTeam.team?.abbr ?? '–'} · '
                        '${career.devTeam.links.length} ${tr('partnerships')}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Panel(
                    colors: c,
                    child: ListView(
                      children: [
                        Label(tr('Test actions')),
                        const SizedBox(height: 8),
                        action(
                          tr('Simulate to the end of the season'),
                          tr(
                            'Without stops; the sports director handles line-ups and radio.',
                          ),
                          () => s.simulateUntil(
                            DateTime.utc(career.year, 12, 31),
                            auto: true,
                          ),
                        ),
                        action(
                          tr('Simulate one month'),
                          tr('Without stops, 30 days.'),
                          () => s.simulateUntil(
                            career.today.add(const Duration(days: 30)),
                            auto: true,
                          ),
                        ),
                        action(
                          tr('Credit 1 m €'),
                          tr('Raises the balance, without a booking.'),
                          () => setState(() {
                            s.debugMoney(1000000);
                            _message = tr('Credited.');
                          }),
                        ),
                        action(
                          tr('Heal all riders'),
                          tr('{0} riders of the team are currently out.', [
                            injured.length,
                          ]),
                          () => setState(() {
                            s.debugHeal();
                            _message = tr('Everyone is available again.');
                          }),
                        ),
                        if (_message != null) Text(_message!),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            'In debug mode all rider values are exact as well (no scouting ranges), the rider page shows internal figures, and the race planner gives the wildcard chance in per cent.',
                          ),
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Panel(
              colors: c,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Label(
                    tr('Tuning values of the simulation · {0}', [
                      SimTuning.params.length,
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: DenseTable<TuningParam>(
                      colors: c,
                      rows: SimTuning.params,
                      columns: [
                        Col(
                          tr('Name'),
                          190,
                          (p, _) => cellText(p.name),
                          sortKey: (p) => p.name,
                        ),
                        Col(
                          tr('Value'),
                          80,
                          (p, _) => cellText(
                            (s.tuning.toMap()[p.name] ?? p.standard)
                                .toStringAsFixed(3),
                          ),
                          numeric: true,
                        ),
                        Col(
                          tr('Range'),
                          110,
                          (p, _) => cellText(
                            '${p.min} – ${p.max}',
                            color: TeamColors.muted,
                          ),
                          numeric: true,
                        ),
                        Col(
                          tr('Meaning'),
                          520,
                          (p, _) =>
                              cellText(tr(p.meaning), color: TeamColors.muted),
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
    );
  }
}
