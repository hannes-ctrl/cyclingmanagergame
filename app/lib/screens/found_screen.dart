import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';

const _palette = [
  '14234B', '0B4FA8', '1E88C8', '0E7C61', '2E9E3F', 'F0C000', //
  'F28C00', 'D62828', '8E1B3A', '6A2C91', '111111', 'FFFFFF',
];

/// Filter for the rider list by the division of a rider's current team.
enum _Pool {
  all('All'),
  worldTour('WorldTour'),
  pro('ProTeams'),
  continental('Continental'),
  under23('U23'),
  free('Free agent');

  const _Pool(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
}

/// Opens the team builder: set name and colours and assemble the squad from
/// all riders of the database. The licence follows from the squad's strength.
///
/// @param context Build context to push the page on.
/// @param state Application state.
/// @returns A future that completes when the page is closed.
Future<void> showFoundScreen(BuildContext context, AppState state) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => FoundScreen(state: state)),
    );

/// Full-page team builder.
class FoundScreen extends StatefulWidget {
  const FoundScreen({super.key, required this.state});
  final AppState state;

  @override
  State<FoundScreen> createState() => _FoundScreenState();
}

/// State of the builder: identity, filters and the picked riders.
class _FoundScreenState extends State<FoundScreen> {
  final _name = TextEditingController();
  final _abbr = TextEditingController();
  late String _country = widget.state.team.country;
  var _color = _palette[1], _color2 = _palette[5];
  var _pool = _Pool.all;
  var _search = '';
  final _picked = <int>{};

  late final List<SimRider> _riders;
  late final Map<int, String> _names;
  late final Map<int, TeamInfo> _teams;
  late final FoundingRules _rules;

  @override
  void initState() {
    super.initState();
    final world = widget.state.world;
    _riders = world.riders()
      ..sort((a, b) => Economy.rating(b).compareTo(Economy.rating(a)));
    _names = {
      for (final r in world.allRiders())
        r.rider.id: '${r.first} ${r.last}'.trim(),
    };
    _teams = {for (final t in world.teams()) t.id: t};
    _rules = FoundingRules(world.teams(), _riders);
  }

  @override
  void dispose() {
    _name.dispose();
    _abbr.dispose();
    super.dispose();
  }

  /// @param r A rider.
  /// @returns Whether he passes the current division filter.
  bool _inPool(SimRider r) {
    final division = _teams[r.teamId]?.division ?? 'Free';
    return switch (_pool) {
      _Pool.all => true,
      _Pool.worldTour => division.startsWith('[1]'),
      _Pool.pro => division.startsWith('[2]'),
      _Pool.continental => division.startsWith('[3]'),
      _Pool.under23 => division == 'Under23',
      _Pool.free => division == 'Free',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final eco = s.career.economy;
    final year = s.career.year;
    final query = _search.toLowerCase();
    final rows = [
      for (final r in _riders)
        if (_inPool(r) &&
            (query.isEmpty ||
                (_names[r.id] ?? r.name).toLowerCase().contains(query) ||
                r.team.toLowerCase() == query))
          r,
    ];
    final picked = [
      for (final r in _riders)
        if (_picked.contains(r.id)) r,
    ];
    final strength = FoundingRules.strength(picked);
    final division = _rules.divisionFor(picked);
    final wages = picked.fold(0, (sum, r) => sum + eco.marketWage(r));
    final countries = {
      for (final t in s.teams)
        if (t.country.isNotEmpty) t.country,
    }.toList()..sort();
    final enough =
        picked.length >= FoundingRules.minRiders &&
        picked.length <= FoundingRules.maxRiders;
    final named =
        _name.text.trim().length >= 3 && _abbr.text.trim().length >= 2;

    void toggle(SimRider r) => setState(() {
      if (!_picked.remove(r.id) && _picked.length < FoundingRules.maxRiders) {
        _picked.add(r.id);
      }
    });

    Col<SimRider> value(String title, double Function(SimRider) of) => Col(
      title,
      title.length > 4 ? 62 : 42,
      (r, _) {
        final v = of(r);
        return cellText(
          v.round().toString(),
          color: attributeColor(v),
          bold: v >= 72,
        );
      },
      numeric: true,
      sortKey: of,
    );

    Widget swatches(String current, void Function(String) onPick) => Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final hex in _palette)
          InkWell(
            onTap: () => setState(() => onPick(hex)),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: TeamColors.parse(hex),
                border: Border.all(
                  color: hex == current ? TeamColors.gold : c.line,
                  width: hex == current ? 3 : 1,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );

    InputDecoration field(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      counterText: '',
      border: OutlineInputBorder(borderSide: BorderSide(color: c.line)),
    );

    Widget fact(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: TeamColors.muted)),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color ?? TeamColors.text,
            ),
          ),
        ],
      ),
    );

    String one(double v) => dec(v);

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: c.panel2,
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Text(
                  tr('Found your own team'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    tr(
                      'Starts a new career on 1 January. Selected riders move at once; their old teams fill up from the free agents.',
                    ),
                    style: TextStyle(fontSize: 12, color: TeamColors.muted),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Cancel')),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 7,
                    child: Panel(
                      colors: c,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              for (final p in _Pool.values)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Pill(
                                    label: p.label,
                                    selected: _pool == p,
                                    colors: c,
                                    onTap: () => setState(() => _pool = p),
                                  ),
                                ),
                              const Spacer(),
                              SizedBox(
                                width: 220,
                                height: 32,
                                child: TextField(
                                  key: const ValueKey('suche'),
                                  style: const TextStyle(fontSize: 13),
                                  decoration:
                                      field(
                                        tr('Name or team abbreviation …'),
                                      ).copyWith(
                                        contentPadding: const EdgeInsets.all(8),
                                      ),
                                  onChanged: (v) =>
                                      setState(() => _search = v.trim()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: DenseTable<SimRider>(
                              colors: c,
                              rows: rows,
                              highlight: (r) => _picked.contains(r.id),
                              onTap: toggle,
                              columns: [
                                Col(
                                  '',
                                  30,
                                  (r, _) => Icon(
                                    _picked.contains(r.id)
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    size: 17,
                                    color: _picked.contains(r.id)
                                        ? TeamColors.text
                                        : TeamColors.muted,
                                  ),
                                ),
                                Col(
                                  tr('Rider'),
                                  190,
                                  (r, _) => cellText(_names[r.id] ?? r.name),
                                  sortKey: (r) => r.lastName,
                                ),
                                Col(
                                  'Team',
                                  52,
                                  (r, _) => cellText(
                                    (_teams[r.teamId]?.division ?? 'Free') ==
                                            'Free'
                                        ? '–'
                                        : r.team,
                                    color: TeamColors.muted,
                                  ),
                                  sortKey: (r) => r.team,
                                ),
                                Col(
                                  tr('Country'),
                                  70,
                                  (r, _) => flagCell(r.country),
                                  sortKey: (r) => r.country,
                                ),
                                Col(
                                  tr('Age'),
                                  54,
                                  (r, _) =>
                                      cellText('${year - r.born ~/ 10000}'),
                                  numeric: true,
                                  sortKey: (r) => -r.born,
                                ),
                                value(tr('Strength'), Economy.rating),
                                value('FL', (r) => r.attributes.flat),
                                value(tr('MTN'), (r) => r.attributes.mountain),
                                value(tr('HIL'), (r) => r.attributes.hill),
                                value(tr('TT'), (r) => r.attributes.timeTrial),
                                value(tr('COB'), (r) => r.attributes.cobble),
                                value(tr('SPR'), (r) => r.attributes.sprint),
                                Col(
                                  'Pot.',
                                  44,
                                  (r, _) => cellText(
                                    r.potential.toStringAsFixed(1),
                                    color: r.potential >= 5.5
                                        ? TeamColors.gold
                                        : TeamColors.muted,
                                  ),
                                  numeric: true,
                                  sortKey: (r) => r.potential,
                                ),
                                Col(
                                  tr('Wage'),
                                  76,
                                  (r, _) => cellText(euro(eco.marketWage(r))),
                                  numeric: true,
                                  sortKey: (r) => eco.marketWage(r),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            tr(
                              '{0} riders · click to select or deselect · column heading sorts',
                              [rows.length],
                            ),
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
                  Expanded(
                    flex: 4,
                    child: Panel(
                      colors: c,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Label('Team'),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  key: const ValueKey('name'),
                                  controller: _name,
                                  maxLength: 34,
                                  decoration: field(tr('Team name')),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('kuerzel'),
                                  controller: _abbr,
                                  maxLength: 3,
                                  decoration: field(tr('Abbreviation')),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // The country by its flag: a click opens all of them.
                              Tooltip(
                                message: tr('Country of the team'),
                                child: InkWell(
                                  onTap: () async {
                                    final picked = await showDialog<String>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(tr('Country of the team')),
                                        content: SizedBox(
                                          width: 560,
                                          child: SingleChildScrollView(
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                for (final k in countries)
                                                  Tooltip(
                                                    message: k,
                                                    child: InkWell(
                                                      onTap: () =>
                                                          Navigator.pop(
                                                            context,
                                                            k,
                                                          ),
                                                      child: Container(
                                                        width: 62,
                                                        padding:
                                                            const EdgeInsets.all(
                                                              4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          border: Border.all(
                                                            color: k == _country
                                                                ? TeamColors
                                                                      .text
                                                                : c.line,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                        child: Column(
                                                          children: [
                                                            Flag(k, width: 36),
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            Text(
                                                              k,
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                    if (picked != null) {
                                      setState(() => _country = picked);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: c.line),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flag(_country, width: 28),
                                        const SizedBox(width: 6),
                                        Text(_country),
                                        const Icon(
                                          Icons.arrow_drop_down,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: swatches(_color, (v) => _color = v),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: swatches(_color2, (v) => _color2 = v),
                              ),
                            ],
                          ),
                          Divider(height: 20, color: c.line),
                          fact(
                            tr('Rider'),
                            tr(
                              '{0} ({1} to {2}; a WorldTeam needs {3}, a ProTeam {4})',
                              [
                                picked.length,
                                FoundingRules.minRiders,
                                FoundingRules.maxRiders,
                                FoundingRules.minWorldTour,
                                FoundingRules.minPro,
                              ],
                            ),
                            color: enough ? TeamColors.green : TeamColors.gold,
                          ),
                          fact(
                            tr('Strength (mean of the best eight)'),
                            picked.isEmpty ? '–' : one(strength),
                          ),
                          fact(
                            tr('Licence'),
                            FoundingRules.label(division),
                            color: division.startsWith('[1]')
                                ? TeamColors.gold
                                : division.startsWith('[2]')
                                ? TeamColors.green
                                : TeamColors.text,
                          ),
                          Text(
                            tr(
                              'WorldTeam from {0}, ProTeam from {1}: that is how strong the weakest teams of these licences are.',
                              [one(_rules.worldTour), one(_rules.pro)],
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: TeamColors.muted,
                            ),
                          ),
                          fact(tr('Wages per year'), '${euro(wages)} €'),
                          fact(
                            tr('Sponsor money per year'),
                            '${euro(wages * 1.45 < 1000000 ? 1000000 : wages * 1.45)} €',
                          ),
                          Divider(height: 20, color: c.line),
                          Label(tr('Squad')),
                          const SizedBox(height: 4),
                          Expanded(
                            child: picked.isEmpty
                                ? Text(
                                    tr(
                                      'Select at least 16 riders on the left.',
                                    ),
                                    style: TextStyle(color: TeamColors.muted),
                                  )
                                : ListView(
                                    children: [
                                      for (final r in picked)
                                        InkWell(
                                          onTap: () => toggle(r),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 2,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    _names[r.id] ?? r.name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Text(
                                                  '${Economy.rating(r).round()}',
                                                  style: TextStyle(
                                                    color: attributeColor(
                                                      Economy.rating(r),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                const Text(
                                                  '×',
                                                  style: TextStyle(
                                                    color: TeamColors.muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: !named
                                      ? null
                                      : () {
                                          s.foundTeam(
                                            name: _name.text.trim(),
                                            abbr: _abbr.text
                                                .trim()
                                                .toUpperCase(),
                                            country: _country,
                                            color: _color,
                                            color2: _color2,
                                          );
                                          Navigator.pop(context);
                                        },
                                  child: Text(
                                    tr(
                                      'Without a selection: Continental team of free agents',
                                    ),
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: c.accent,
                                  foregroundColor: c.onAccent,
                                  disabledBackgroundColor: c.panel2,
                                ),
                                onPressed: !named || !enough
                                    ? null
                                    : () {
                                        s.foundTeam(
                                          name: _name.text.trim(),
                                          abbr: _abbr.text.trim().toUpperCase(),
                                          country: _country,
                                          color: _color,
                                          color2: _color2,
                                          riders: picked,
                                        );
                                        Navigator.pop(context);
                                      },
                                child: Text(tr('FOUND TEAM')),
                              ),
                            ],
                          ),
                        ],
                      ),
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
