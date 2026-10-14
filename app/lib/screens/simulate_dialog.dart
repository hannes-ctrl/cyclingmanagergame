import 'package:sim/sim.dart';
import 'package:flutter/material.dart';
import 'package:game/game.dart';

import '../app_state.dart';
import '../ui.dart';

const _weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

String _long(DateTime d) =>
    '${tr(_weekdays[d.weekday - 1])}, ${d.day.toString().padLeft(2, '0')}.'
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

  /// Topics of the inbox the run stops for.
  final _stops = <String>{};

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
              Text(tr('Simulate to …'), style: headStyle(22)),
              const SizedBox(height: 2),
              Text(
                tr('Today is {0}.', [_long(s.career.today)]),
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
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          tr(
                            'Without stops: until then the sports director picks the line-ups and decides in the race himself.',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_auto)
                Padding(
                  padding: EdgeInsets.only(left: 48, top: 2),
                  child: Text(
                    tr(
                      'Otherwise the simulation stops whenever a line-up or a radio answer is needed.',
                    ),
                    style: TextStyle(fontSize: 12, color: TeamColors.muted),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                tr('Stop as soon as a message on these topics arrives:'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final key in Message.topics)
                    Pill(
                      label: key == 'Scouting' ? key : tr(key),
                      selected: _stops.contains(key),
                      colors: c,
                      onTap: () => setState(
                        () => _stops.remove(key) ? null : _stops.add(key),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Cancel')),
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
                            s.simulateUntil(
                              _target,
                              auto: _auto,
                              stopTopics: {..._stops},
                            );
                          },
                    child: Text(
                      tr('UNTIL {0} · {1} {2}', [
                        _long(_target).substring(4, 10),
                        days,
                        days == 1 ? tr('DAY') : tr('DAYS'),
                      ]),
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
