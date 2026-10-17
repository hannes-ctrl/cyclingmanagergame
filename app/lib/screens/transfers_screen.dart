import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'presets.dart';
import 'scout_button.dart';
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

  /// What the offer promises the rider for its first season, or null.
  PromiseKind? _promise;
  String? _answer;
  final _wage = TextEditingController();

  @override
  void dispose() {
    _wage.dispose();
    super.dispose();
  }

  /// The market filters as a JSON-encodable map, for presets.
  Map<String, dynamic> get _filters => {
    'types': _types.toList(),
    'ageFrom': _ages.start,
    'ageTo': _ages.end,
    'contract': _contract,
  };

  /// Sets the market filters from a map written by [_filters], or the
  /// defaults for null.
  void _load(Map<String, dynamic>? v) {
    _types.clear();
    _ages = const RangeValues(17, 45);
    _contract = 0;
    if (v == null) return;
    try {
      _types.addAll((v['types'] as List).cast<String>());
      _ages = RangeValues(
        (v['ageFrom'] as num).toDouble(),
        (v['ageTo'] as num).toDouble(),
      );
      _contract = v['contract'] as int;
    } on Object {
      // Written by another version: keep the defaults.
    }
  }

  @override
  void initState() {
    super.initState();
    _load(FilterPresets.defaultOf(widget.state, 'market'));
  }

  void _select(SimRider r) => setState(() {
    _selected = r.id;
    _answer = null;
    _promise = null;
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
      final (low, high) = book.range(r.id, 'Strength', Economy.rating(r));
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
    // The wage limit: the share of the budget plus half of the savings.
    final frame = career.finances.wageLimit(s.team.id);
    final nextBill = eco.wageBill(s.team.id, nextSeason: true);

    String status(SimRider r) {
      final k = eco.contracts[r.id]!;
      if (k.nextTeam == s.team.id) {
        return r.teamId == s.team.id
            ? tr('renewed until {0}', [contractEnd(k.nextEnd)])
            : tr('joins in {0}', [year + 1]);
      }
      if (k.nextTeam != null) {
        return tr('leaves for {0}', [career.teams[k.nextTeam]?.abbr ?? '?']);
      }
      return k.endYear <= year
          ? tr('expires')
          : tr('until {0}', [contractEnd(k.endYear)]);
    }

    Color statusColor(SimRider r) {
      final k = eco.contracts[r.id]!;
      if (k.nextTeam == s.team.id) return TeamColors.green;
      if (k.nextTeam != null) return TeamColors.red;
      return k.endYear <= year ? TeamColors.gold : TeamColors.muted;
    }

    // The team only knows riders of other teams roughly: a range is shown
    // instead of the value until a scout has watched the rider.
    // The title is also the key of the scouting range, so it comes
    // untranslated and is translated for display only.
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

    final columns = <Col<SimRider>>[
      Col('', 30, (r, _) => watchStar(s, r)),
      Col(
        tr('Rider'),
        190,
        (r, _) => cellText(career.fullName(r.id)),
        sortKey: (r) => r.lastName,
      ),
      if (_market)
        Col(
          'Team',
          56,
          (r, _) =>
              cellText(r.team.isEmpty ? '–' : r.team, color: TeamColors.muted),
          sortKey: (r) => r.team,
        ),
      Col('Nat', 70, (r, _) => flagCell(r.country), sortKey: (r) => r.country),
      Col(
        tr('Age'),
        50,
        (r, _) => cellText('${year - r.born ~/ 10000}'),
        numeric: true,
        sortKey: (r) => -r.born,
      ),
      value('Strength', Economy.rating),
      Col(
        'Pot',
        44,
        (r, _) => cellText(
          book.knowledge(r.id) < 0.6 ? '?' : r.potential.toStringAsFixed(1),
        ),
        numeric: true,
        sortKey: (r) => r.potential,
      ),
      value('MTN', (r) => r.attributes.mountain),
      value('HIL', (r) => r.attributes.hill),
      value('TT', (r) => r.attributes.timeTrial),
      value('SPR', (r) => r.attributes.sprint),
      value('COB', (r) => r.attributes.cobble),
      Col(
        _market ? tr('Market value') : tr('Wage'),
        90,
        (r, _) => cellText(
          euro(_market ? eco.marketWage(r) : eco.contracts[r.id]!.wage),
        ),
        numeric: true,
        sortKey: (r) => _market ? eco.marketWage(r) : eco.contracts[r.id]!.wage,
      ),
      Col(
        tr('Contract'),
        150,
        (r, _) => cellText(status(r), color: statusColor(r)),
        sortKey: (r) => eco.contracts[r.id]!.endYear,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              tab(tr('Own contracts'), false),
              tab(tr('Market'), true),
              const SizedBox(width: 8),
              const Spacer(),
              Text(
                eco.windowOpen
                    ? tr('Contract talks for {0} are open', [year + 1])
                    : tr('Contract talks from 1 August'),
                style: TextStyle(
                  color: eco.windowOpen ? TeamColors.green : TeamColors.muted,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                tr('Board renews on its own'),
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
                            hint: tr('Name, team or country'),
                            colors: c,
                            width: null,
                            onChanged: (v) => setState(() => _search = v),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            children: [
                              FilterPresets(
                                state: s,
                                list: 'market',
                                current: () => _filters,
                                onApply: (f) => setState(() => _load(f)),
                              ),
                              ColumnPicker(
                                state: s,
                                list: 'market',
                                titles: [
                                  for (final col in columns.skip(1))
                                    if (col.title.isNotEmpty) col.title,
                                ],
                                onChanged: () => setState(() {}),
                              ),
                            ],
                          ),
                          FilterHead(tr('Contract')),
                          for (final (i, label) in [
                            tr('All'),
                            tr('Free agent'),
                            tr('Contract expires'),
                          ].indexed)
                            FilterOption(
                              label: label,
                              radio: true,
                              selected: _contract == i,
                              onTap: () => setState(() => _contract = i),
                            ),
                          FilterHead(
                            tr('Age · {0} to {1}', [
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
                          FilterHead(tr('Rider type')),
                          for (final t in const [
                            'Climber',
                            'Puncheur',
                            'Sprinter',
                            'Time trialist',
                            'Cobbles specialist',
                            'Rouleur',
                            'All-rounder',
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
                            tr('{0} riders', [
                              rows.length == 400
                                  ? tr('The best 400')
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
                      columns: ColumnPicker.visible(s, 'market', columns),
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
                            Label(tr('Planning {0}', [year + 1])),
                            const SizedBox(height: 6),
                            _line(
                              tr('Riders under contract'),
                              career.licences.of(s.team.id) == Licence.worldTour
                                  ? tr('{0} of 30, at least {1}', [
                                      eco.squadNextSeason(s.team.id),
                                      FoundingRules.minWorldTour,
                                    ])
                                  : tr('{0} of 30', [
                                      eco.squadNextSeason(s.team.id),
                                    ]),
                            ),
                            _line(tr('Wages'), euro(nextBill)),
                            _line(tr('Wage budget'), euro(frame)),
                            _line(
                              tr('Still free'),
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
                                    tr('Select a rider in the list'),
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
    final waiting = eco.pending[r.id];
    final open =
        waiting == null &&
        (eco.expiring(r) || own && eco.contracts[r.id]?.nextTeam == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          career.fullName(r.id),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        Text(
          tr('{0} · {1} years · {2}', [
            own
                ? s.team.name
                : (career.teams[r.teamId]?.name ?? tr('free agent')),
            career.year - r.born ~/ 10000,
            r.country,
          ]),
          style: const TextStyle(color: TeamColors.muted),
        ),
        const SizedBox(height: 10),
        _line(tr('Contract'), status),
        _line(tr('Current wage'), euro(eco.contracts[r.id]!.wage)),
        _line(tr('Market wage'), euro(eco.marketWage(r))),
        () {
          final (low, high) = career.staff.range(
            r.id,
            tr('Strength'),
            Economy.rating(r),
          );
          return _line(
            tr('Strength'),
            low == high ? '$low' : tr('{0} to {1}', [low, high]),
          );
        }(),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => showRiderDialog(context, s, r.id),
            child: Text(tr('Open profile')),
          ),
        ),
        const SizedBox(height: 8),
        ScoutButton(
          state: s,
          riderId: r.id,
          onAnswer: (text) => setState(() => _answer = text),
        ),
        const SizedBox(height: 14),
        if (waiting != null)
          Text(
            tr(
              'He is considering your offer of {0} € and answers by {1}.{2}.',
              [
                euro(waiting.wage),
                waiting.until.day.toString().padLeft(2, '0'),
                waiting.until.month.toString().padLeft(2, '0'),
              ],
            ),
          )
        else if (!open)
          Text(
            tr('There is nothing to negotiate for this rider.'),
            style: TextStyle(color: TeamColors.muted),
          )
        else ...[
          Label(own ? tr('Offer renewal') : tr('Offer contract')),
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
              Text(tr('a year for'), style: TextStyle(fontSize: 13)),
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(tr('Promise:'), style: const TextStyle(fontSize: 13)),
              for (final kind in <PromiseKind?>[null, ...PromiseKind.values])
                InkWell(
                  onTap: () => setState(() => _promise = kind),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _promise == kind ? TeamColors.text : null,
                      border: Border.all(color: c.line),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      kind == null ? tr('none') : People.seasonText(kind),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _promise == kind
                            ? TeamColors.ground
                            : TeamColors.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_promise != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr(
                  'With a promise for {0} he asks a little less. If you do not keep it, his morale falls far.',
                  [career.year + 1],
                ),
                style: const TextStyle(fontSize: 12, color: TeamColors.muted),
              ),
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
            onPressed: s.busy || !eco.windowOpen && !eco.isFreeAgent(r) && !own
                ? null
                : () {
                    final free = eco.isFreeAgent(r);
                    final thousands = int.tryParse(_wage.text.trim()) ?? 0;
                    final answer = s.offer(
                      r.id,
                      thousands * 1000,
                      _years,
                      promise: _promise,
                    );
                    setState(
                      () => _answer =
                          answer ??
                          (free
                              ? tr('Signed. He joins the team today.')
                              : eco.pending.containsKey(r.id)
                              ? tr(
                                  'Offer made. He answers within a week; other teams may bid too.',
                                )
                              : tr('Signed. The contract runs from {0}.', [
                                  career.year + 1,
                                ])),
                    );
                  },
            child: Text(
              tr('MAKE OFFER'),
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.6),
            ),
          ),
          // A young rider can also be signed for the development team.
          if (!own && career.devTeam.teamId != null && eco.devReason(r) == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: s.busy || !eco.windowOpen
                    ? null
                    : () => setState(
                        () => _answer =
                            s.offerDev(r.id, _years.clamp(1, 2)) ??
                            tr('Signed for the development team from {0}.', [
                              career.year + 1,
                            ]),
                      ),
                child: Text(
                  tr('Sign for the development team ({0})', [
                    career.devTeam.team?.name ?? '',
                  ]),
                ),
              ),
            ),
          if (eco.isFreeAgent(r))
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                tr(
                  'Without a team he can be signed at any time and joins at once.',
                ),
                style: TextStyle(fontSize: 12, color: TeamColors.muted),
              ),
            )
          else if (own && !eco.windowOpen)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                tr(
                  'Your own riders can be renewed at any time; the new terms apply from next season.',
                ),
                style: TextStyle(fontSize: 12, color: TeamColors.muted),
              ),
            )
          else if (!eco.windowOpen)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                tr('Contract talks are only possible from 1 August.'),
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
