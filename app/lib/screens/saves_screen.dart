import 'package:flutter/material.dart';

import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

String _stamp(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.'
    '${d.year} ${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Save games: store the running state under a name, load or delete named
/// saves.
class SavesScreen extends StatefulWidget {
  const SavesScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SavesScreen> createState() => _SavesScreenState();
}

/// State of the screen: the name field and the last feedback message.
class _SavesScreenState extends State<SavesScreen> {
  final _name = TextEditingController();
  String? _message;

  /// Team picked for a new career.

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Asks for confirmation and deletes a save.
  ///
  /// @param info The save to delete.
  /// @returns A future that completes when the dialog is closed.
  Future<void> _confirmDelete(SaveInfo info) async {
    final c = widget.state.colors;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.panel,
        title: Text(tr('Delete "{0}"?', [info.name])),
        content: Text(tr('The file is removed for good.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      widget.state.deleteSave(info);
      setState(() => _message = tr('"{0}" has been deleted.', [info.name]));
    }
  }

  /// Asks before a save replaces the running career.
  ///
  /// @param name Name of the save.
  /// @returns Whether the player wants to load it.
  Future<bool> _confirmLoad(String name) async {
    final c = widget.state.colors;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.panel,
        title: Text(tr('Load "{0}"?', [name])),
        content: Text(
          tr(
            'The running career is replaced by the save. Progress since the last save is lost.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Load')),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final saves = s.saves();

    Widget pill(String label, VoidCallback? onTap) => InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );

    void save() => setState(() {
      final name = _name.text.trim();
      _message = s.saveAs(name) ?? tr('"{0}" has been saved.', [name]);
    });

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Panel(
            colors: c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Label(tr('Save the current game')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 360,
                      child: TextField(
                        controller: _name,
                        maxLength: 40,
                        decoration: InputDecoration(
                          hintText: tr('Name, e.g. "{0} before the Tour"', [
                            s.team.abbr,
                          ]),
                          counterText: '',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: c.line),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => save(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: c.onAccent,
                        disabledBackgroundColor: c.panel2,
                      ),
                      onPressed: s.busy || _name.text.trim().isEmpty
                          ? null
                          : save,
                      child: Text(tr('SAVE')),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _message ??
                            tr(
                              'The running game is saved automatically after every action anyway. Named saves are .rmsave files in the folder data\\saves.',
                            ),
                        style: TextStyle(
                          fontSize: 12,
                          color: _message == null
                              ? TeamColors.muted
                              : TeamColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Panel(
              colors: c,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Label(tr('Saved games · {0}', [saves.length])),
                  const SizedBox(height: 6),
                  Expanded(
                    child: saves.isEmpty
                        ? Center(
                            child: Text(
                              tr('No named save yet.'),
                              style: TextStyle(color: TeamColors.muted),
                            ),
                          )
                        : DenseTable<SaveInfo>(
                            colors: c,
                            rows: saves,
                            columns: [
                              Col(
                                'Name',
                                300,
                                (x, _) => cellText(x.name, bold: true),
                                sortKey: (x) => x.name,
                              ),
                              Col(
                                'Team',
                                260,
                                (x, _) => cellText(x.team),
                                sortKey: (x) => x.team,
                              ),
                              Col(
                                tr('Game date'),
                                130,
                                (x, _) => cellText(_day(x.gameDate)),
                                sortKey: (x) => x.gameDate,
                              ),
                              Col(
                                tr('Saved'),
                                150,
                                (x, _) => cellText(
                                  _stamp(x.savedAt),
                                  color: TeamColors.muted,
                                ),
                                sortKey: (x) => x.savedAt,
                              ),
                              Col(
                                '',
                                80,
                                (x, _) => pill(
                                  tr('Load'),
                                  s.busy
                                      ? null
                                      : () async {
                                          if (!await _confirmLoad(x.name)) {
                                            return;
                                          }
                                          setState(
                                            () => _message = tr(
                                              'Loading "{0}" …',
                                              [x.name],
                                            ),
                                          );
                                          final answer = await s.loadSave(x);
                                          if (mounted) {
                                            setState(
                                              () => _message =
                                                  answer ??
                                                  tr('"{0}" has been loaded.', [
                                                    x.name,
                                                  ]),
                                            );
                                          }
                                        },
                                ),
                              ),
                              Col(
                                '',
                                90,
                                (x, _) => pill(
                                  tr('Delete'),
                                  s.busy ? null : () => _confirmDelete(x),
                                ),
                              ),
                            ],
                          ),
                  ),
                  Text(
                    tr(
                      'A save is a snapshot of the career; loading takes a few seconds.',
                    ),
                    style: TextStyle(fontSize: 12, color: TeamColors.muted),
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
