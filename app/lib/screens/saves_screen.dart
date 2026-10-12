import 'package:flutter/material.dart';

import 'package:sim/sim.dart';

import '../app_state.dart';
import 'found_screen.dart';
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
  int? _newTeam;

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
        title: Text('„${info.name}" löschen?'),
        content: const Text('Die Datei wird endgültig entfernt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      widget.state.deleteSave(info);
      setState(() => _message = '„${info.name}" wurde gelöscht.');
    }
  }

  /// Asks for confirmation and starts a new career with a team.
  ///
  /// @param team The team to take over.
  /// @returns A future that completes when the dialog is closed.
  Future<void> _startCareer(TeamInfo team) async {
    final c = widget.state.colors;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.panel,
        title: Text('Neue Karriere mit ${team.name}?'),
        content: const Text(
          'Die laufende Karriere wird ersetzt. Benannte Spielstände bleiben '
          'erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Starten'),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      widget.state.chooseTeam(team);
      setState(() => _message = 'Neue Karriere mit ${team.name} gestartet.');
    }
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
      _message = s.saveAs(name) ?? '„$name" ist gespeichert.';
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
                const Label('Neue Karriere'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 320,
                      child: DropdownButton<int>(
                        value: _newTeam,
                        isExpanded: true,
                        hint: const Text('Team wählen'),
                        dropdownColor: c.panel2,
                        underline: Container(height: 1, color: c.line),
                        style: const TextStyle(
                          fontFamily: 'Barlow',
                          fontSize: 14,
                          color: TeamColors.text,
                        ),
                        items: [
                          for (final t in s.teams.where(
                            (t) =>
                                t.division.startsWith('[1]') ||
                                t.division.startsWith('[2]'),
                          ))
                            DropdownMenuItem(value: t.id, child: Text(t.name)),
                        ],
                        onChanged: (v) => setState(() => _newTeam = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TeamColors.text,
                        side: BorderSide(color: c.line),
                      ),
                      onPressed: _newTeam == null || s.busy
                          ? null
                          : () => _startCareer(
                              s.teams.firstWhere((t) => t.id == _newTeam),
                            ),
                      child: const Text('Karriere starten'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TeamColors.text,
                        side: BorderSide(color: c.line),
                      ),
                      onPressed: s.busy
                          ? null
                          : () => showFoundScreen(context, s),
                      child: const Text('Eigenes Team gründen …'),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Die laufende Karriere wird dabei ersetzt. Sichere '
                        'sie vorher unter einem Namen, wenn du sie behalten '
                        'willst.',
                        style: TextStyle(fontSize: 12, color: TeamColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            colors: c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Label('Aktuellen Stand speichern'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 360,
                      child: TextField(
                        controller: _name,
                        maxLength: 40,
                        decoration: InputDecoration(
                          hintText: 'Name, z. B. „${s.team.abbr} vor der Tour"',
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
                      child: const Text('SPEICHERN'),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _message ??
                            'Der laufende Stand wird ohnehin nach jeder '
                                'Aktion automatisch gesichert. Benannte Stände '
                                'liegen als .rmsave-Dateien im Ordner '
                                'data\\saves.',
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
                  Label('Gespeicherte Stände · ${saves.length}'),
                  const SizedBox(height: 6),
                  Expanded(
                    child: saves.isEmpty
                        ? const Center(
                            child: Text(
                              'Noch kein benannter Spielstand.',
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
                                'Stand im Spiel',
                                130,
                                (x, _) => cellText(_day(x.gameDate)),
                                sortKey: (x) => x.gameDate,
                              ),
                              Col(
                                'Gespeichert',
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
                                  'Laden',
                                  s.busy
                                      ? null
                                      : () async {
                                          setState(
                                            () => _message =
                                                '„${x.name}" wird geladen …',
                                          );
                                          final answer = await s.loadSave(x);
                                          if (mounted) {
                                            setState(
                                              () => _message =
                                                  answer ??
                                                  '„${x.name}" ist geladen.',
                                            );
                                          }
                                        },
                                ),
                              ),
                              Col(
                                '',
                                90,
                                (x, _) => pill(
                                  'Löschen',
                                  s.busy ? null : () => _confirmDelete(x),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const Text(
                    'Ein Spielstand ist eine Momentaufnahme der Karriere; Laden '
                    'dauert wenige Sekunden.',
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
