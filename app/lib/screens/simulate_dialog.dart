import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ui.dart';

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

String _long(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Opens a small calendar to let the days run up to a chosen date.
///
/// @param context Build context.
/// @param state Application state.
/// @param initial Day preselected in the calendar; defaults to one week on.
/// @returns A future that completes when the dialog is closed.
Future<void> showSimulateDialog(
  BuildContext context,
  AppState state, {
  DateTime? initial,
}) => showDialog<void>(
  context: context,
  builder: (context) => _SimulateDialog(state: state, initial: initial),
);

class _SimulateDialog extends StatefulWidget {
  const _SimulateDialog({required this.state, this.initial});
  final AppState state;
  final DateTime? initial;

  @override
  State<_SimulateDialog> createState() => _SimulateDialogState();
}

/// State of the dialog: the chosen day and whether the staff takes over.
class _SimulateDialogState extends State<_SimulateDialog> {
  late DateTime _target;
  var _auto = false;

  DateTime get _first => widget.state.career.today.add(const Duration(days: 1));
  DateTime get _last => DateTime.utc(widget.state.career.year, 12, 31);

  @override
  void initState() {
    super.initState();
    final wanted =
        widget.initial ??
        widget.state.career.today.add(const Duration(days: 7));
    _target = wanted.isBefore(_first)
        ? _first
        : wanted.isAfter(_last)
        ? _last
        : wanted;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final days = _target.difference(s.career.today).inDays;
    return Dialog(
      backgroundColor: c.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Simulieren bis …', style: headStyle(22)),
              const SizedBox(height: 2),
              Text(
                'Heute ist ${_long(s.career.today)}.',
                style: const TextStyle(color: TeamColors.muted),
              ),
              Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: c.accent,
                    onPrimary: c.onAccent,
                    surface: c.panel,
                    onSurface: TeamColors.text,
                  ),
                ),
                child: CalendarDatePicker(
                  initialDate: _target,
                  firstDate: _first,
                  lastDate: _last,
                  onDateChanged: (d) => setState(
                    () => _target = DateTime.utc(d.year, d.month, d.day),
                  ),
                ),
              ),
              InkWell(
                onTap: () => setState(() => _auto = !_auto),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _auto,
                      activeColor: c.accent,
                      checkColor: c.onAccent,
                      onChanged: (v) => setState(() => _auto = v ?? false),
                    ),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Ohne Halt: Der Sportliche Leiter stellt bis dahin '
                          'die Aufgebote auf und entscheidet im Rennen selbst.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_auto)
                const Padding(
                  padding: EdgeInsets.only(left: 48, top: 2),
                  child: Text(
                    'Sonst hält die Simulation an, sobald ein Aufgebot oder '
                    'eine Funkantwort gebraucht wird.',
                    style: TextStyle(fontSize: 12, color: TeamColors.muted),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.onAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    onPressed: s.busy
                        ? null
                        : () {
                            Navigator.pop(context);
                            s.simulateUntil(_target, auto: _auto);
                          },
                    child: Text(
                      'BIS ${_long(_target).substring(4, 10)} · '
                      '$days ${days == 1 ? 'TAG' : 'TAGE'}',
                      style: const TextStyle(
                        fontFamily: headFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
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
