import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

/// Saved filters of a list: apply one, save the current filters under a
/// name, delete one, or make one the default that "reset" returns to. They
/// are kept with the player's view settings, apart from the save games.
class FilterPresets extends StatelessWidget {
  /// Creates the menu.
  ///
  /// @param state Application state.
  /// @param list Name of the list, e.g. `search`.
  /// @param current The filters as they are set now.
  /// @param onApply Sets the filters of a preset; null restores the
  ///   built-in defaults.
  const FilterPresets({
    super.key,
    required this.state,
    required this.list,
    required this.current,
    required this.onApply,
  });
  final AppState state;
  final String list;
  final Map<String, dynamic> Function() current;
  final void Function(Map<String, dynamic>? filters) onApply;

  String get _key => '$list.presets';

  Map<String, dynamic> get _presets =>
      (state.viewOf(_key)?['presets'] as Map<String, dynamic>?) ?? {};

  String? get _default => state.viewOf(_key)?['default'] as String?;

  void _store(Map<String, dynamic> presets, String? standard) =>
      state.rememberView(_key, {'presets': presets, 'default': standard});

  /// The default filters of the list, or null for the built-in ones.
  static Map<String, dynamic>? defaultOf(AppState state, String list) {
    final v = state.viewOf('$list.presets');
    final name = v?['default'] as String?;
    if (name == null) return null;
    return (v!['presets'] as Map<String, dynamic>?)?[name]
        as Map<String, dynamic>?;
  }

  @override
  Widget build(BuildContext context) {
    final presets = _presets;
    final standard = _default;
    return PopupMenuButton<String>(
      tooltip: tr('Saved filters'),
      onSelected: (choice) async {
        if (choice == '+save') {
          final name = await askName(context, state, tr('Save filters'));
          if (name == null || name.trim().isEmpty) return;
          _store({...presets, name.trim(): current()}, standard);
        } else if (choice == '+reset') {
          onApply(defaultOf(state, list));
        } else if (choice.startsWith('*')) {
          final name = choice.substring(1);
          _store(presets, standard == name ? null : name);
        } else if (choice.startsWith('-')) {
          final name = choice.substring(1);
          _store(
            {...presets}..remove(name),
            standard == name ? null : standard,
          );
        } else if (presets[choice] case final Map<String, dynamic> f) {
          onApply(f);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: '+reset',
          child: Text(
            standard == null
                ? tr('Reset filters')
                : tr('Reset to the default ({0})', [standard]),
          ),
        ),
        for (final name in presets.keys)
          PopupMenuItem(
            value: name,
            child: Text(name == standard ? tr('{0} (default)', [name]) : name),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: '+save',
          child: Text(tr('Save the current filters …')),
        ),
        for (final name in presets.keys)
          PopupMenuItem(
            value: '*$name',
            child: Text(
              name == standard
                  ? tr('No longer the default: {0}', [name])
                  : tr('Make the default: {0}', [name]),
              style: const TextStyle(color: TeamColors.muted),
            ),
          ),
        for (final name in presets.keys)
          PopupMenuItem(
            value: '-$name',
            child: Text(
              tr('Delete: {0}', [name]),
              style: const TextStyle(color: TeamColors.muted),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.bookmark, size: 15, color: TeamColors.muted),
            const SizedBox(width: 5),
            Text(tr('Filters ▾'), style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Which columns of a list are shown, and named column sets to switch
/// between. The first column and those without a title always stay.
class ColumnPicker extends StatelessWidget {
  /// Creates the menu.
  ///
  /// @param state Application state.
  /// @param list Name of the list.
  /// @param titles Titles of all columns that can be hidden.
  /// @param onChanged Called after a change, so that the list redraws.
  const ColumnPicker({
    super.key,
    required this.state,
    required this.list,
    required this.titles,
    required this.onChanged,
  });
  final AppState state;
  final String list;
  final List<String> titles;
  final VoidCallback onChanged;

  /// @param state Application state.
  /// @param list Name of the list.
  /// @returns The titles of the hidden columns.
  static Set<String> hiddenOf(AppState state, String list) => {
    ...?(state.viewOf('$list.columns')?['hidden'] as List?)?.cast<String>(),
  };

  /// @param state Application state.
  /// @param list Name of the list.
  /// @param columns All columns of the list.
  /// @returns The columns that are shown.
  static List<Col<T>> visible<T>(
    AppState state,
    String list,
    List<Col<T>> columns,
  ) {
    final hidden = hiddenOf(state, list);
    return [
      for (final (i, col) in columns.indexed)
        if (i == 0 || col.title.isEmpty || !hidden.contains(col.title)) col,
    ];
  }

  Map<String, dynamic> get _sets =>
      (state.viewOf('$list.columns')?['sets'] as Map<String, dynamic>?) ?? {};

  void _store(Set<String> hidden, Map<String, dynamic> sets) {
    state.rememberView('$list.columns', {
      'hidden': hidden.toList(),
      'sets': sets,
    });
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final hidden = hiddenOf(state, list);
    final sets = _sets;
    return PopupMenuButton<String>(
      tooltip: tr('Columns'),
      onSelected: (choice) async {
        if (choice == '+save') {
          final name = await askName(context, state, tr('Save column set'));
          if (name == null || name.trim().isEmpty) return;
          _store(hidden, {...sets, name.trim(): hidden.toList()});
        } else if (choice == '+all') {
          _store({}, sets);
        } else if (choice.startsWith('=')) {
          final set = sets[choice.substring(1)] as List?;
          _store({...?set?.cast<String>()}, sets);
        } else if (choice.startsWith('-')) {
          _store(hidden, {...sets}..remove(choice.substring(1)));
        } else {
          final now = {...hidden};
          now.contains(choice) ? now.remove(choice) : now.add(choice);
          _store(now, sets);
        }
      },
      itemBuilder: (context) => [
        for (final t in titles)
          CheckedPopupMenuItem(
            value: t,
            checked: !hidden.contains(t),
            child: Text(t),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(value: '+all', child: Text(tr('Show all columns'))),
        for (final name in sets.keys)
          PopupMenuItem(
            value: '=$name',
            child: Text(tr('Column set: {0}', [name])),
          ),
        PopupMenuItem(
          value: '+save',
          child: Text(tr('Save as a column set …')),
        ),
        for (final name in sets.keys)
          PopupMenuItem(
            value: '-$name',
            child: Text(
              tr('Delete: {0}', [name]),
              style: const TextStyle(color: TeamColors.muted),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.columns3, size: 15, color: TeamColors.muted),
            const SizedBox(width: 5),
            Text(tr('Columns ▾'), style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Asks for a name.
///
/// @param context Where the dialog opens.
/// @param state Application state.
/// @param title Title of the dialog.
/// @returns The name, or null if the player cancelled.
Future<String?> askName(BuildContext context, AppState state, String title) {
  final field = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: state.colors.panel,
      title: Text(title),
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
