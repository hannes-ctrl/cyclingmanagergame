import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';

String _date(DateTime d) => dayText(d);

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
    // Riders ticked in the squad for a camp.
    if (s.campPreset case final preset?) {
      s.campPreset = null;
      _selected
        ..clear()
        ..addAll(preset.take(Camps.maxRiders));
    }
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
          Pill(
            label: label(v),
            selected: v == current,
            colors: c,
            onTap: () => setState(() => onPick(v)),
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
      if (career.isInjured(r.id, start)) return tr('injured');
      if (career.camps.blocks(r.id, start, end)) return tr('in camp');
      if (career.isBusy(r.id, start)) return tr('racing');
      return tr('free');
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
                  Label(tr('Book a camp')),
                  const SizedBox(height: 8),
                  chips(
                    CampType.values,
                    (t) => t.label,
                    _type,
                    (t) => _type = t,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(
                      'Trains {0} · {1} € per rider and day · form gain afterwards {2} %',
                      [
                        _type.focus.label,
                        _type.costPerDay,
                        dec(_type.peak * 100),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: TeamColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(width: 60, child: Text(tr('Begins'))),
                      step('−7', -7),
                      step('−1', -1),
                      SizedBox(
                        width: 130,
                        child: Text(
                          tr('{0} to {1}', [_date(start), _date(end)]),
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
                      SizedBox(width: 60, child: Text(tr('Duration'))),
                      chips(
                        const [7, 10, 14, 21],
                        (d) => trn(d, '{0} day', '{0} days'),
                        _days,
                        (d) => _days = d,
                      ),
                    ],
                  ),
                  if (clashes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        tr(
                          'During this time we race: {0}. Whoever is in camp misses them.',
                          [clashes.join(', ')],
                        ),
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
                          tr('Rider'),
                          200,
                          (r, _) => cellText(career.fullName(r.id)),
                          sortKey: (r) => r.lastName,
                        ),
                        Col(
                          tr('Age'),
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
                          tr('Freshness'),
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
                        Col(tr('On {0}', [_date(start)]), 110, (r, _) {
                          final text = status(r);
                          return cellText(
                            text,
                            color: text == tr('free')
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
                              tr(
                                '{0} of at most {1} riders · cost {2} €, due with the next monthly statement',
                                [_selected.length, Camps.maxRiders, euro(cost)],
                              ),
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
                                    tr('{0} from {1} is booked.', [
                                      _type.label,
                                      _date(start),
                                    ]);
                                if (_message!.endsWith('gebucht.')) {
                                  _selected.clear();
                                }
                              }),
                        child: Text(tr('BOOK CAMP')),
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
                  Label(tr('Camps {0}', [career.year])),
                  const SizedBox(height: 6),
                  if (career.camps.all.isEmpty)
                    Row(
                      children: [
                        Text(
                          tr('None booked yet.'),
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                        const SizedBox(width: 6),
                        InfoTip(
                          tr(
                            'A camp ties up the riders for its duration, loads them hard and pays off one to four weeks later: the trained attributes rise (most for young riders), and form is higher.',
                          ),
                        ),
                      ],
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
                                        tr('{0} · {1} to {2}', [
                                          k.type.label,
                                          _date(k.start),
                                          _date(
                                            k.end.subtract(
                                              const Duration(days: 1),
                                            ),
                                          ),
                                        ]),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      k.closed
                                          ? tr('finished')
                                          : k.covers(career.today)
                                          ? tr('running')
                                          : tr('booked'),
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
