import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'rider_dialog.dart';

/// Contracts and transfer market. Riders move at the turn of the year; talks
/// are possible from 1 August.
class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key, required this.state});
  final AppState state;

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

/// State of the screen: view, selected rider and the offer being drafted.
class _TransfersScreenState extends State<TransfersScreen> {
  var _market = false;
  var _search = '';
  final _types = <String>{};

  /// Age range and contract state (0 shows all) of the market filter.
  var _ages = const RangeValues(17, 45);
  var _contract = 0;
  int? _selected;
  var _years = 2;
  String? _answer;
  final _wage = TextEditingController();

  @override
  void dispose() {
    _wage.dispose();
    super.dispose();
  }

  void _select(SimRider r) => setState(() {
    _selected = r.id;
    _answer = null;
    // Preset to the market wage; the rider's demand is not known.
    _wage.text = '${widget.state.career.economy.marketWage(r) ~/ 1000}';
  });

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final eco = career.economy;
    final book = career.staff;
    final year = career.year;
    // Sorted by the estimate, not by the true value.
    double estimate(SimRider r) {
      final (low, high) = book.range(r.id, 'Stärke', Economy.rating(r));
      return (low + high) / 2;
    }

    final needle = _search.toLowerCase();
    bool free(SimRider r) => career.teams[r.teamId]?.division == 'Free';
    bool wanted(SimRider r) {
      final age = year - r.born ~/ 10000;
      return (needle.isEmpty ||
              career.fullName(r.id).toLowerCase().contains(needle) ||
              r.team.toLowerCase() == needle ||
              r.country.toLowerCase() == needle) &&
          (_types.isEmpty || _types.contains(riderType(r))) &&
          age >= _ages.start &&
          age <= _ages.end &&
          switch (_contract) {
            1 => free(r),
            2 => !free(r) && (eco.contracts[r.id]?.endYear ?? 9999) <= year,
            _ => true,
          };
    }

    final rows = _market
        ? (eco.market().where(wanted).toList()
                ..sort((a, b) => estimate(b).compareTo(estimate(a))))
              .take(400)
              .toList()
        : s.squad;
    final selected = _selected == null ? null : career.riderById[_selected];
    final frame = eco.budget * 0.72;
    final nextBill = eco.wageBill(s.team.id, nextSeason: true);

    String status(SimRider r) {
      final k = eco.contracts[r.id]!;
      if (k.nextTeam == s.team.id) {
        return r.teamId == s.team.id
            ? tr('verlängert bis {0}', [k.nextEnd])
            : tr('kommt {0}', [year + 1]);
      }
      if (k.nextTeam != null) {
        return tr('geht zu {0}', [career.teams[k.nextTeam]?.abbr ?? '?']);
      }
      return k.endYear <= year ? tr('läuft aus') : tr('bis {0}', [k.endYear]);
    }

    Color statusColor(SimRider r) {
      final k = eco.contracts[r.id]!;
      if (k.nextTeam == s.team.id) return TeamColors.green;
      if (k.nextTeam != null) return TeamColors.red;
      return k.endYear <= year ? TeamColors.gold : TeamColors.muted;
    }

    // The team only knows riders of other teams roughly: a range is shown
    // instead of the value until a scout has watched the rider.
    // The title is also the key of the scouting range, so it comes in
    // German and is translated for display only.
    Col<SimRider> value(String title, double Function(SimRider) of) => Col(
      tr(title),
      _market ? 66 : (title.length > 4 ? 64 : 46),
      (r, _) {
        final v = of(r);
        final (low, high) = book.range(r.id, title, v);
        if (low != high) {
          return cellText('$low–$high', color: TeamColors.muted);
        }
        return cellText(
          v.round().toString(),
          color: attributeColor(v),
          bold: v >= 72,
        );
      },
      numeric: true,
      sortKey: (r) {
        final (low, high) = book.range(r.id, title, of(r));
        return (low + high) / 2;
      },
    );

    Widget tab(String label, bool market) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() {
          _market = market;
          _selected = null;
          _answer = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: _market == market ? TeamColors.text : null,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: _market == market ? TeamColors.ground : TeamColors.text,
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              tab(tr('Eigene Verträge'), false),
              tab(tr('Markt'), true),
              const SizedBox(width: 8),
              const Spacer(),
              Text(
                eco.windowOpen
                    ? tr('Vertragsgespräche für {0} laufen', [year + 1])
                    : tr('Vertragsgespräche ab 1. August'),
                style: TextStyle(
                  color: eco.windowOpen ? TeamColors.green : TeamColors.muted,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                tr('Teamleitung verlängert selbst'),
                style: TextStyle(fontSize: 13),
              ),
              Switch(
                value: eco.autoRenew,
                activeThumbColor: c.accent,
                onChanged: s.busy ? null : s.setAutoRenew,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_market) ...[
                  SizedBox(
                    width: 200,
                    child: Panel(
                      colors: c,
                      child: ListView(
                        children: [
                          SearchBox(
                            hint: tr('Name, Team oder Land'),
                            colors: c,
                            width: null,
                            onChanged: (v) => setState(() => _search = v),
                          ),
                          FilterHead(tr('Vertrag')),
                          for (final (i, label) in [
                            tr('Alle'),
                            tr('Vereinslos'),
                            tr('Vertrag läuft aus'),
                          ].indexed)
                            FilterOption(
                              label: label,
                              radio: true,
                              selected: _contract == i,
                              onTap: () => setState(() => _contract = i),
                            ),
                          FilterHead(
                            tr('Alter · {0} bis {1}', [
                              _ages.start.round(),
                              _ages.end.round(),
                            ]),
                          ),
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              activeTrackColor: TeamColors.text,
                              inactiveTrackColor: c.line,
                              thumbColor: TeamColors.text,
                              overlayShape: SliderComponentShape.noOverlay,
                              rangeThumbShape: const RoundRangeSliderThumbShape(
                                enabledThumbRadius: 7,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 6,
                              ),
                              child: RangeSlider(
                                values: _ages,
                                min: 17,
                                max: 45,
                                divisions: 28,
                                onChanged: (v) => setState(() => _ages = v),
                              ),
                            ),
                          ),
                          FilterHead(tr('Fahrertyp')),
                          for (final t in const [
                            'Kletterer',
                            'Puncheur',
                            'Sprinter',
                            'Zeitfahrer',
                            'Pflasterfahrer',
                            'Rouleur',
                            'Allrounder',
                          ])
                            FilterOption(
                              label: tr(t),
                              selected: _types.contains(t),
                              onTap: () => setState(
                                () => _types.contains(t)
                                    ? _types.remove(t)
                                    : _types.add(t),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            tr('{0} Fahrer', [
                              rows.length == 400
                                  ? tr('Die besten 400')
                                  : '${rows.length}',
                            ]),
                            style: const TextStyle(
                              fontSize: 12,
                              color: TeamColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 7,
                  child: Panel(
                    colors: c,
                    child: DenseTable<SimRider>(
                      key: ValueKey(_market),
                      colors: c,
                      rows: rows,
                      highlight: (r) => r.id == _selected,
                      onTap: _select,
                      columns: [
                        Col(
                          tr('Fahrer'),
                          190,
                          (r, _) => cellText(career.fullName(r.id)),
                          sortKey: (r) => r.lastName,
                        ),
                        if (_market)
                          Col(
                            'Team',
                            56,
                            (r, _) => cellText(
                              r.team.isEmpty ? '–' : r.team,
                              color: TeamColors.muted,
                            ),
                            sortKey: (r) => r.team,
                          ),
                        Col(
                          'Nat',
                          70,
                          (r, _) => flagCell(r.country),
                          sortKey: (r) => r.country,
                        ),
                        Col(
                          tr('Alter'),
                          50,
                          (r, _) => cellText('${year - r.born ~/ 10000}'),
                          numeric: true,
                          sortKey: (r) => -r.born,
                        ),
                        value('Stärke', Economy.rating),
                        Col(
                          'Pot',
                          44,
                          (r, _) => cellText(
                            book.knowledge(r.id) < 0.6
                                ? '?'
                                : r.potential.toStringAsFixed(1),
                          ),
                          numeric: true,
                          sortKey: (r) => r.potential,
                        ),
                        value('BG', (r) => r.attributes.mountain),
                        value('HÜ', (r) => r.attributes.hill),
                        value('ZF', (r) => r.attributes.timeTrial),
                        value('SP', (r) => r.attributes.sprint),
                        value('KO', (r) => r.attributes.cobble),
                        Col(
                          _market ? tr('Marktwert') : tr('Gehalt'),
                          90,
                          (r, _) => cellText(
                            euro(
                              _market
                                  ? eco.marketWage(r)
                                  : eco.contracts[r.id]!.wage,
                            ),
                          ),
                          numeric: true,
                          sortKey: (r) => _market
                              ? eco.marketWage(r)
                              : eco.contracts[r.id]!.wage,
                        ),
                        Col(
                          tr('Vertrag'),
                          150,
                          (r, _) => cellText(status(r), color: statusColor(r)),
                          sortKey: (r) => eco.contracts[r.id]!.endYear,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 360,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Panel(
                        colors: c,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Label(tr('Planung {0}', [year + 1])),
                            const SizedBox(height: 6),
                            _line(
                              tr('Fahrer unter Vertrag'),
                              tr('{0} von 30', [
                                eco.squadNextSeason(s.team.id),
                              ]),
                            ),
                            _line(tr('Gehälter'), euro(nextBill)),
                            _line(tr('Gehaltsrahmen'), euro(frame)),
                            _line(
                              tr('Noch frei'),
                              euro(frame - nextBill),
                              color: frame - nextBill < 0
                                  ? TeamColors.red
                                  : TeamColors.green,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Panel(
                          colors: c,
                          child: selected == null
                              ? Center(
                                  child: Text(
                                    tr('Fahrer in der Liste wählen'),
                                    style: TextStyle(color: TeamColors.muted),
                                  ),
                                )
                              : _offerForm(selected, status(selected)),
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
    );
  }

  Widget _line(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: TeamColors.muted)),
        ),
        Text(
          value,
          style: TextStyle(
            color: color ?? TeamColors.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );

  /// Builds the offer form for the selected rider.
  ///
  /// @param r The rider.
  /// @param status Text describing his contract situation.
  /// @returns The form.
  Widget _offerForm(SimRider r, String status) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final eco = career.economy;
    final own = r.teamId == s.team.id;
    final open = eco.expiring(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          career.fullName(r.id),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        Text(
          tr('{0} · {1} Jahre · {2}', [
            own
                ? s.team.name
                : (career.teams[r.teamId]?.name ?? tr('vereinslos')),
            career.year - r.born ~/ 10000,
            r.country,
          ]),
          style: const TextStyle(color: TeamColors.muted),
        ),
        const SizedBox(height: 10),
        _line(tr('Vertrag'), status),
        _line(tr('Aktuelles Gehalt'), euro(eco.contracts[r.id]!.wage)),
        _line(tr('Marktüblich'), euro(eco.marketWage(r))),
        () {
          final (low, high) = career.staff.range(
            r.id,
            tr('Stärke'),
            Economy.rating(r),
          );
          return _line(
            tr('Stärke'),
            low == high ? '$low' : tr('{0} bis {1}', [low, high]),
          );
        }(),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => showRiderDialog(context, s, r.id),
            child: Text(tr('Profil öffnen')),
          ),
        ),
        if (career.staff.knowledge(r.id) < 1) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Die Werte sind geschätzt.'),
                  style: TextStyle(fontSize: 12, color: TeamColors.muted),
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: TeamColors.text,
                  side: BorderSide(color: c.line),
                ),
                onPressed: s.busy
                    ? null
                    : () => setState(
                        () => _answer =
                            s.scout(r.id) ??
                            tr(
                              'Ein Scout ist unterwegs. Der Bericht kommt ins Postfach.',
                            ),
                      ),
                child: Text(tr('Beobachten lassen')),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (!open)
          Text(
            tr('Für diesen Fahrer ist nichts zu verhandeln.'),
            style: TextStyle(color: TeamColors.muted),
          )
        else ...[
          Label(own ? tr('Verlängerung anbieten') : tr('Vertrag anbieten')),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _wage,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: 'T €',
                    filled: true,
                    fillColor: c.panel2,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: c.line),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(tr('im Jahr für'), style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              for (var y = 1; y <= 4; y++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => setState(() => _years = y),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _years == y ? TeamColors.text : null,
                        border: Border.all(color: c.line),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '$y',
                        style: TextStyle(
                          fontSize: 13,
                          color: _years == y
                              ? TeamColors.ground
                              : TeamColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
              const Text(' J.', style: TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              disabledBackgroundColor: c.panel2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            onPressed: s.busy || !eco.windowOpen
                ? null
                : () {
                    final thousands = int.tryParse(_wage.text.trim()) ?? 0;
                    final answer = s.offer(r.id, thousands * 1000, _years);
                    setState(
                      () => _answer =
                          answer ??
                          tr('Unterschrieben. Der Vertrag gilt ab {0}.', [
                            career.year + 1,
                          ]),
                    );
                  },
            child: Text(
              tr('ANGEBOT ABGEBEN'),
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.6),
            ),
          ),
          if (!eco.windowOpen)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                tr('Vertragsgespräche sind erst ab dem 1. August möglich.'),
                style: TextStyle(fontSize: 12, color: TeamColors.muted),
              ),
            ),
        ],
        if (_answer != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_answer!, style: const TextStyle(height: 1.4)),
          ),
      ],
    );
  }
}
