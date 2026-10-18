import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';

/// Opens a stage in the 3D viewer. Shown only for stages whose track was
/// recorded: the stages of the player's team in the race that is running.
class View3dButton extends StatelessWidget {
  const View3dButton({
    super.key,
    required this.state,
    required this.run,
    required this.index,
  });
  final AppState state;
  final RaceRun run;

  /// Index of the stage within the race.
  final int index;

  @override
  Widget build(BuildContext context) {
    final stages = run.result.stages;
    if (index >= stages.length || stages[index].track == null) {
      return const SizedBox();
    }
    return Tooltip(
      message: tr('Watch the stage in 3D, in a window of its own.'),
      child: OutlinedButton.icon(
        icon: const Icon(LucideIcons.box, size: 16),
        label: const Text('3D'),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final error = await state.showIn3D(run, index);
          if (error != null) {
            messenger.showSnackBar(SnackBar(content: Text(error)));
          }
        },
      ),
    );
  }
}
