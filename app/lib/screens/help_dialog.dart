import 'package:flutter/material.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';

/// How a season is played, in a few steps.
const _steps = <(String, String)>[
  (
    'Continue',
    'The button at the top right (or the space bar) lets the days run until something concerns your team: a race, a message, a question from the race.',
  ),
  (
    'Season plan',
    'The sports director has planned every race of the season. In the race planner you change single entries; on the rider page the target sets season goals a rider builds his form towards.',
  ),
  (
    'Race preparation',
    'Before every race you confirm the line-up. With your own tactics you pin single roles or fix everything; the sports director plans the rest stage by stage.',
  ),
  (
    'Radio',
    'During a race the sports director calls in when it matters: the break, the finale, an attack of a rival, a crash or puncture of a leader. The marked answer is his recommendation. The radio can be switched off under "Delegation".',
  ),
  (
    'Rider',
    'Morale, promises and personality are on the rider page. The star puts riders of other teams on the shortlist, the scales compare two riders.',
  ),
  (
    'Keyboard',
    'Space: continue. Esc or Alt+←: back. Ctrl+F: rider search. Ctrl+S: quick save. 1 to 9: the pages of the sidebar. F1: this help. Arrow keys and Enter: through lists and from rider to rider.',
  ),
];

/// Opens the help: a short introduction and the glossary of all figures.
///
/// @param context Build context.
/// @param state Application state.
/// @returns A future that completes when the dialog is closed.
Future<void> showHelpDialog(BuildContext context, AppState state) {
  final c = state.colors;
  final terms =
      statHelp.entries.where((e) => !helpInPlaceOnly.contains(e.key)).toList()
        ..sort(
          (a, b) => tr(a.key).toLowerCase().compareTo(tr(b.key).toLowerCase()),
        );
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: c.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(tr('Help'), style: headStyle(23))),
                  Tooltip(
                    message: tr(
                      'Packs the running save, the settings and a note with version and seed into a ZIP file in data/export, to send along with a bug report.',
                    ),
                    child: TextButton(
                      onPressed: () {
                        final path = state.bugReport();
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              path == null
                                  ? tr('The file could not be written.')
                                  : tr('Saved: {0}', [path]),
                            ),
                          ),
                        );
                      },
                      child: Text(tr('Create bug report')),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Close')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    Label(tr('How a season goes')),
                    const SizedBox(height: 6),
                    for (final (title, text) in _steps)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 150,
                              child: Text(
                                tr(title),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                tr(text),
                                style: const TextStyle(height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Label(tr('Glossary')),
                    const SizedBox(height: 6),
                    for (final e in terms)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 150,
                              child: Text(
                                tr(e.key),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                tr(e.value),
                                style: const TextStyle(
                                  height: 1.4,
                                  color: TeamColors.muted,
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
      ),
    ),
  );
}
