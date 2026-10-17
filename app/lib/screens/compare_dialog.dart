import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

/// Up to four riders side by side: age, strength, potential, every
/// attribute and the contract, the best value of each line in green. What
/// the scouts do not know shows as a range.
///
/// @param context Where the dialog opens.
/// @param s Application state.
/// @returns A future that completes when the dialog is closed.
Future<void> showComparison(BuildContext context, AppState s) => showDialog(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) => _Comparison(state: s),
  ),
);

class _Comparison extends StatelessWidget {
  const _Comparison({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = s.colors;
    final career = s.career;
    final book = career.staff;
    final riders = [for (final id in s.compareList) ?career.riderById[id]];
    // Lines: label, value of a rider, whether higher is better.
    final lines = <(String, String, double? Function(SimRider), bool)>[
      (
        tr('Age'),
        'age',
        (r) => (career.year - r.born ~/ 10000).toDouble(),
        false,
      ),
      (tr('Strength'), 'Strength', Economy.rating, true),
      (tr('Potential'), 'Potential', (r) => r.potential * 10, true),
      ('FL', 'FL', (r) => r.attributes.flat, true),
      (tr('MTN'), 'MTN', (r) => r.attributes.mountain, true),
      (tr('MED'), 'MED', (r) => r.attributes.mediumMountain, true),
      (tr('HIL'), 'HIL', (r) => r.attributes.hill, true),
      (tr('TT'), 'TT', (r) => r.attributes.timeTrial, true),
      (tr('PRL'), 'PRL', (r) => r.attributes.prologue, true),
      (tr('COB'), 'COB', (r) => r.attributes.cobble, true),
      (tr('SPR'), 'SPR', (r) => r.attributes.sprint, true),
      (tr('ACC'), 'ACC', (r) => r.attributes.acceleration, true),
      (tr('DH'), 'DH', (r) => r.attributes.downhill, true),
      (tr('BRK'), 'BRK', (r) => r.attributes.breakaway, true),
      (tr('STA'), 'STA', (r) => r.attributes.endurance, true),
      (tr('RES'), 'RES', (r) => r.attributes.resistance, true),
      (tr('REC'), 'REC', (r) => r.attributes.recovery, true),
    ];
    bool known(SimRider r) =>
        r.teamId == s.team.id || book.knowledge(r.id) >= 1;
    String show(SimRider r, String code, double v) {
      if (code == 'age') return '${v.round()}';
      if (code == 'Potential') {
        if (book.knowledge(r.id) < 0.6) return '?';
        return known(r) ? dec(v / 10) : '~${dec(v / 10)}';
      }
      final (low, high) = book.range(r.id, code, v);
      return low == high ? '$low' : '$low–$high';
    }

    Widget cell(String text, {bool best = false, bool head = false}) =>
        SizedBox(
          width: 150,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: head || best ? FontWeight.w600 : FontWeight.w400,
              color: best ? TeamColors.green : TeamColors.text,
            ),
          ),
        );

    return AlertDialog(
      backgroundColor: c.panel,
      title: Text(tr('Comparison')),
      content: riders.isEmpty
          ? Text(
              tr(
                'No rider chosen yet. On a rider page, "add to the comparison" puts him here, up to four.',
              ),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 110),
                      for (final r in riders)
                        SizedBox(
                          width: 150,
                          child: Row(
                            children: [
                              Expanded(child: cell(r.name, head: true)),
                              IconButton(
                                tooltip: tr('Remove from the comparison'),
                                iconSize: 15,
                                onPressed: () => s.toggleCompare(r.id),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 110),
                      for (final r in riders)
                        cell(
                          '${career.teams[r.teamId]?.abbr ?? ''} · ${tr(Economy.kindLabel(Economy.kindOf(r)))}',
                        ),
                    ],
                  ),
                  const Divider(),
                  for (final (label, code, of, higher) in lines)
                    Builder(
                      builder: (context) {
                        final values = [for (final r in riders) of(r) ?? 0];
                        // Only values the scouts know take part in "best".
                        final comparable = [
                          for (var i = 0; i < riders.length; i++)
                            if (code == 'age' || known(riders[i])) values[i],
                        ];
                        final best = comparable.isEmpty
                            ? null
                            : higher
                            ? comparable.reduce((a, b) => a > b ? a : b)
                            : comparable.reduce((a, b) => a < b ? a : b);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 110,
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    color: TeamColors.muted,
                                  ),
                                ),
                              ),
                              for (var i = 0; i < riders.length; i++)
                                cell(
                                  show(riders[i], code, values[i]),
                                  best:
                                      riders.length > 1 &&
                                      (code == 'age' || known(riders[i])) &&
                                      values[i] == best,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  const Divider(),
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          tr('Contract'),
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                      ),
                      for (final r in riders)
                        cell(
                          '${career.economy.contracts[r.id]?.endYear ?? '–'} · ${euro(career.economy.marketWage(r))} €',
                        ),
                    ],
                  ),
                ],
              ),
            ),
      actions: [
        if (riders.isNotEmpty)
          TextButton(
            onPressed: () {
              for (final r in riders) {
                s.toggleCompare(r.id);
              }
            },
            child: Text(tr('Clear')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Close')),
        ),
      ],
    );
  }
}
