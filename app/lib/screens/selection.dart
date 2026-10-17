import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';
import 'compare_dialog.dart';

/// Several riders chosen with checkboxes, for one action on all of them.
/// The lists keep one each; it lasts as long as the page.
class RiderSelection {
  final ids = <int>{};

  /// @returns A narrow first column with a checkbox per row.
  ///
  /// @param changed Called after a box was ticked or cleared.
  Col<SimRider> column(VoidCallback changed) => Col<SimRider>(
    '',
    30,
    (r, _) => SizedBox(
      width: 22,
      height: 22,
      child: Checkbox(
        value: ids.contains(r.id),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: (v) {
          v == true ? ids.add(r.id) : ids.remove(r.id);
          changed();
        },
      ),
    ),
    sortKey: (r) => ids.contains(r.id) ? 0 : 1,
  );
}

/// The bar above a list while riders are ticked: how many, select all
/// shown, clear, and the actions of the list.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.state,
    required this.selection,
    required this.shown,
    required this.actions,
    required this.changed,
  });
  final AppState state;
  final RiderSelection selection;

  /// The riders the list shows now, for "select all".
  final List<SimRider> shown;

  /// Buttons for what can be done with the ticked riders.
  final List<Widget> actions;
  final VoidCallback changed;

  @override
  Widget build(BuildContext context) {
    final c = state.colors;
    final n = selection.ids.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.panel2,
        border: Border.all(color: n > 0 ? c.accent : c.line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            n == 0
                ? tr('Tick riders for an action on all of them')
                : tr('{0} selected', [n]),
            style: TextStyle(
              fontSize: 13,
              color: n == 0 ? TeamColors.muted : TeamColors.text,
            ),
          ),
          TextButton(
            onPressed: () {
              selection.ids.addAll(shown.map((r) => r.id));
              changed();
            },
            child: Text(tr('Select all shown')),
          ),
          if (n > 0) ...[
            TextButton(
              onPressed: () {
                selection.ids.clear();
                changed();
              },
              child: Text(tr('Clear')),
            ),
            Container(width: 1, height: 20, color: c.line),
            ...actions,
          ],
        ],
      ),
    );
  }
}

/// Puts the ticked riders into the comparison table and opens it.
///
/// @param context Context for the dialog.
/// @param s Application state.
/// @param ids Ticked riders.
Future<void> compareSelected(
  BuildContext context,
  AppState s,
  Iterable<int> ids,
) {
  s.compareList.clear();
  for (final id in ids.take(4)) {
    s.toggleCompare(id);
  }
  return showComparison(context, s);
}

/// Puts the ticked riders on the shortlist, or takes them off when all of
/// them are on it already.
///
/// @param s Application state.
/// @param ids Ticked riders.
void shortlistSelected(AppState s, Iterable<int> ids) {
  final all = ids.every(s.career.watch.contains);
  for (final id in ids) {
    if (s.career.watch.contains(id) == all) s.toggleWatch(id);
  }
}

/// Asks for a race of the team's coming programme and pencils the ticked
/// riders in for it.
///
/// @param context Context for the dialog.
/// @param s Application state.
/// @param ids Ticked riders of the own team.
Future<void> programmeSelected(
  BuildContext context,
  AppState s,
  Iterable<int> ids,
) async {
  final career = s.career;
  final races = [
    for (final r in career.ownRaces)
      if (r.start.isAfter(career.today) &&
          !career.progress.containsKey(r.info.id))
        r,
  ];
  final race = await showDialog<RaceEntry>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('Pencil in for which race?')),
      children: [
        SizedBox(
          width: 460,
          height: 420,
          child: ListView(
            children: [
              for (final r in races)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, r),
                  child: Text(
                    '${r.start.day}.${r.start.month}. · ${r.info.name}',
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  if (race == null) return;
  var added = 0;
  for (final id in ids) {
    if (career.program[race.info.id]?.contains(id) ?? false) continue;
    s.toggleProgram(race.info.id, id);
    added++;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr('{0} riders pencilled in for {1}.', [added, race.info.name]),
        ),
      ),
    );
  }
}

/// A menu button for one choice applied to all ticked riders.
///
/// @param label Text of the button.
/// @param items The choices and their labels.
/// @param onSelected What a choice does.
/// @returns The button.
Widget choiceButton<T>(
  String label,
  Map<T, String> items,
  void Function(T) onSelected,
) => PopupMenuButton<T>(
  tooltip: '',
  onSelected: onSelected,
  itemBuilder: (_) => [
    for (final e in items.entries)
      PopupMenuItem(value: e.key, child: Text(e.value)),
  ],
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        const Icon(Icons.arrow_drop_down, size: 18),
      ],
    ),
  ),
);
