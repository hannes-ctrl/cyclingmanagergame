import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

/// Book training camps and review the camps booked this season.
class CampsScreen extends StatefulWidget {
  const CampsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<CampsScreen> createState() => _CampsScreenState();
}

/// State of the booking form.
class _CampsScreenState extends State<CampsScreen> {
  var _type = CampType.altitude;
  var _days = 14;

  /// Start in days from today.
  var _offset = 7;
  final _selected = <int>{};
  String? _message;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final start = career.today.add(Duration(days: _offset));
    final end = start.add(Duration(days: _days - 1));
    final cost = _type.costPerDay * _days * _selected.length;
    final squad = s.squad;

    // Own races that fall into the time of the camp.
    final clashes = [
      for (final r in career.ownRaces)
        if (!r.end.isBefore(start) && !r.start.isAfter(end)) r.info.name,
    ];

    Widget chips<T>(
      List<T> values,
      String Function(T) label,
      T current,
      void Function(T) onPick,
    ) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == current,
            showCheckmark: false,
            selectedColor: TeamColors.text,
            backgroundColor: c.panel,
            side: BorderSide(color: c.line),
            labelStyle: TextStyle(
              fontSize: 13,
              color: v == current ? TeamColors.ground : TeamColors.text,
            ),
            onSelected: (_) => setState(() => onPick(v)),
          ),
      ],
    );

    Widget step(String label, int delta) => TextButton(
      onPressed: _offset + delta < 0
          ? null
          : () => setState(() => _offset += delta),
      child: Text(label),
    );

    String status(SimRider r) {
      if (career.isInjured(r.id, start)) return 'verletzt';
      if (career.camps.blocks(r.id, start, end)) return 'im Lager';
      if (career.isBusy(r.id, start)) return 'im Rennen';
      return 'frei';
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: Panel(
              colors: c,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Label('Lager buchen'),
                  const SizedBox(height: 8),
                  chips(
                    CampType.values,
                    (t) => t.label,
                    _type,
                    (t) => _type = t,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fördert ${_type.focus.label} · ${_type.costPerDay} € je '
                    'Fahrer und Tag · Formgewinn danach '
                    '${(_type.peak * 100).toStringAsFixed(1).replaceAll('.', ',')} %',
                    style: const TextStyle(
                      fontSize: 12,
                      color: TeamColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(width: 60, child: Text('Beginn')),
                      step('−7', -7),
                      step('−1', -1),
                      SizedBox(
                        width: 130,
                        child: Text(
                          '${_date(start)} bis ${_date(end)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      step('+1', 1),
                      step('+7', 7),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const SizedBox(width: 60, child: Text('Dauer')),
                      chips(
                        const [7, 10, 14, 21],
                        (d) => '$d Tage',
                        _days,
                        (d) => _days = d,
                      ),
                    ],
                  ),
                  if (clashes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'In dieser Zeit fahren wir: ${clashes.join(', ')}. '
                        'Wer im Lager ist, fehlt dort.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: TeamColors.gold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: DenseTable<SimRider>(
                      colors: c,
                      rows: squad,
                      highlight: (r) => _selected.contains(r.id),
                      onTap: (r) => setState(() {
                        if (!_selected.remove(r.id) &&
                            _selected.length < Camps.maxRiders) {
                          _selected.add(r.id);
                        }
                      }),
                      columns: [
                        Col(
                          '',
                          34,
                          (r, _) => Icon(
                            _selected.contains(r.id)
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 17,
                            color: _selected.contains(r.id)
                                ? TeamColors.text
                                : TeamColors.muted,
                          ),
                        ),
                        Col(
                          'Fahrer',
                          200,
                          (r, _) => cellText(career.fullName(r.id)),
                          sortKey: (r) => r.lastName,
                        ),
                        Col(
                          'Alter',
                          50,
                          (r, _) =>
                              cellText('${career.year - r.born ~/ 10000}'),
                          numeric: true,
                          sortKey: (r) => -r.born,
                        ),
                        Col(
                          'Pot.',
                          50,
                          (r, _) => cellText(r.potential.toStringAsFixed(1)),
                          numeric: true,
                          sortKey: (r) => r.potential,
                        ),
                        Col(
                          'Frische',
                          70,
                          (r, _) {
                            final f = career.shapeOf(r.id).freshness;
                            return cellText(
                              f.round().toString(),
                              color: f < -20
                                  ? TeamColors.red
                                  : f > 5
                                  ? TeamColors.green
                                  : TeamColors.text,
                            );
                          },
                          numeric: true,
                          sortKey: (r) => career.shapeOf(r.id).freshness,
                        ),
                        Col('Am ${_date(start)}', 110, (r, _) {
                          final text = status(r);
                          return cellText(
                            text,
                            color: text == 'frei'
                                ? TeamColors.muted
                                : TeamColors.red,
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _message ??
                              '${_selected.length} von höchstens '
                                  '${Camps.maxRiders} Fahrern · Kosten '
                                  '${euro(cost)} €, fällig mit der nächsten '
                                  'Monatsabrechnung',
                          style: TextStyle(
                            color: _message == null
                                ? TeamColors.muted
                                : TeamColors.text,
                          ),
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: c.onAccent,
                          disabledBackgroundColor: c.panel,
                        ),
                        onPressed: s.busy || _selected.isEmpty
                            ? null
                            : () => setState(() {
                                _message =
                                    s.bookCamp(
                                      _type,
                                      start,
                                      _days,
                                      _selected.toList(),
                                    ) ??
                                    '${_type.label} ab ${_date(start)} ist gebucht.';
                                if (_message!.endsWith('gebucht.')) {
                                  _selected.clear();
                                }
                              }),
                        child: const Text('LAGER BUCHEN'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Panel(
              colors: c,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Label('Lager ${career.year}'),
                  const SizedBox(height: 6),
                  if (career.camps.all.isEmpty)
                    const Text(
                      'Noch keines gebucht. Ein Lager bindet die Fahrer für '
                      'seine Dauer, belastet sie hart und zahlt sich ein bis '
                      'vier Wochen später aus: Die geförderten Werte steigen '
                      '(bei jungen Fahrern am meisten), und die Form liegt '
                      'höher.',
                      style: TextStyle(color: TeamColors.muted),
                    ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final k in career.camps.all.reversed)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${k.type.label} · ${_date(k.start)} bis '
                                        '${_date(k.end.subtract(const Duration(days: 1)))}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      k.closed
                                          ? 'beendet'
                                          : k.covers(career.today)
                                          ? 'läuft'
                                          : 'gebucht',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: k.covers(career.today)
                                            ? TeamColors.green
                                            : TeamColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${k.riders.map(career.fullName).join(', ')} · '
                                  '${euro(k.cost)} €',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: TeamColors.muted,
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
        ],
      ),
    );
  }
}
