import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

/// How far the scouting of a rider has come, and the button for its next
/// stage: a first impression, a detailed report, a test at the base.
class ScoutButton extends StatelessWidget {
  /// Creates the control.
  ///
  /// @param state Application state.
  /// @param riderId Id of the rider.
  /// @param onAnswer Receives the answer to show after a click.
  const ScoutButton({
    super.key,
    required this.state,
    required this.riderId,
    required this.onAnswer,
  });
  final AppState state;
  final int riderId;
  final void Function(String) onAnswer;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final book = s.career.staff;
    final stage = book.stageOf(riderId);
    final job = book.jobs.where((j) => j.riderId == riderId).firstOrNull;
    final known = book.knowledge(riderId) >= 1;
    final status = job != null
        ? tr('Being scouted until {0}.{1}.', [
            job.until.day.toString().padLeft(2, '0'),
            job.until.month.toString().padLeft(2, '0'),
          ])
        : known
        ? tr('Everything about him is known.')
        : switch (stage) {
            0 => tr('The values are estimates.'),
            1 => tr('A first impression is in.'),
            _ => tr('A detailed report is in.'),
          };
    final (label, action, done) = switch (stage) {
      0 => (
        tr('First impression'),
        () => s.scout(riderId),
        tr('A scout is on his way. The report will arrive in the inbox.'),
      ),
      1 => (
        tr('Detailed report'),
        () => s.scout(riderId),
        tr('A scout is on his way. The report will arrive in the inbox.'),
      ),
      _ => (
        tr('Test at the base ({0} €)', [euro(StaffBook.testCost)]),
        () => s.testRider(riderId),
        tr(
          'He is coming to the base for a test. The result follows in five days.',
        ),
      ),
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            status,
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
        ),
        if (!known && job == null)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: TeamColors.text,
              side: BorderSide(color: s.colors.line),
            ),
            onPressed: s.busy ? null : () => onAnswer(action() ?? done),
            child: Text(label),
          ),
      ],
    );
  }
}
