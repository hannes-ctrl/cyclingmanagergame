import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'rider_dialog.dart';

/// Attributes a minimum can be asked for: German name (the key of the
/// translation), code (the key of the scouting ranges) and value.
const _minimums = <(String, String, double Function(Attributes))>[
  ('Berg', 'BG', _mountain),
  ('Mittelgebirge', 'MB', _medium),
  ('Hügel', 'HÜ', _hill),
  ('Flach', 'FL', _flat),
  ('Zeitfahren', 'ZF', _timeTrial),
  ('Prolog', 'PR', _prologue),
  ('Kopfsteinpflaster', 'KO', _cobble),
  ('Sprint', 'SP', _sprint),
  ('Antritt', 'ANT', _acceleration),
  ('Abfahrt', 'ABF', _downhill),
  ('Ausreißer', 'AUS', _breakaway),
  ('Ausdauer', 'AD', _endurance),
  ('Widerstand', 'WID', _resistance),
  ('Regeneration', 'REG', _recovery),
];

double _mountain(Attributes a) => a.mountain;
double _medium(Attributes a) => a.mediumMountain;
double _hill(Attributes a) => a.hill;
double _flat(Attributes a) => a.flat;
double _timeTrial(Attributes a) => a.timeTrial;
double _prologue(Attributes a) => a.prologue;
double _cobble(Attributes a) => a.cobble;
double _sprint(Attributes a) => a.sprint;
double _acceleration(Attributes a) => a.acceleration;
double _downhill(Attributes a) => a.downhill;
double _breakaway(Attributes a) => a.breakaway;
double _endurance(Attributes a) => a.endurance;
double _resistance(Attributes a) => a.resistance;
double _recovery(Attributes a) => a.recovery;

/// Levels a rider's team can have, as filter options.
const _levels = [
  'WorldTeam',
  'ProTeam',
  'Continental',
  'Nachwuchsteam',
  'Vereinslos',
];

/// Rider search: every rider of the database, filtered by name, team,
/// country, age, type, strength, potential, one attribute and contract.
/// Riders of other teams show ranges until a scout has watched them.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

/// State of the search: all filters.
class _SearchScreenState extends State<SearchScreen> {
  var _text = '';
  int? _team;
  String? _country;
  final _level = <String>{};
  final _types = <String>{};
  var _ages = const RangeValues(17, 45);
  var _strength = 50.0;
  var _potential = 1.0;
  String? _attribute;
  var _minimum = 70.0;
  var _expiring = false;
  var _watched = false;

  @override
  void initState() {
    super.initState();
    // The filters as the player left them, also after a restart.
    final v = widget.state.viewOf('search');
    if (v == null) return;
    try {
      _team = v['team'] as int?;
      _country = v['country'] as String?;
      _level.addAll((v['level'] as List).cast<String>());
      _types.addAll((v['types'] as List).cast<String>());
      _ages = RangeValues(
        (v['ageFrom'] as num).toDouble(),
        (v['ageTo'] as num).toDouble(),
      );
      _strength = (v['strength'] as num).toDouble();
      _potential = (v['potential'] as num).toDouble();
      _attribute = v['attribute'] as String?;
      _minimum = (v['minimum'] as num).toDouble();
      _expiring = v['expiring'] as bool;
      _watched = v['watched'] as bool;
    } on Object {
      // Written by another version: start with the defaults.
    }
  }

  /// A link elsewhere asked for the riders of a country: show them, with
  /// the other filters open.
  void _takeCountry() {
    final s = widget.state;
    final country = s.searchCountry;
    if (country == null) return;
    s.searchCountry = null;
    _text = '';
    _team = null;
    _country = country;
    _level.clear();
    _types.clear();
    _ages = const RangeValues(17, 45);
    _strength = 50;
    _potential = 1;
    _attribute = null;
    _expiring = false;
    _watched = false;
  }

  /// @param r A rider.
  /// @returns The level of his team, one of [_levels].
  String _levelOf(SimRider r) {
    final career = widget.state.career;
    final division = career.teams[r.teamId]?.division ?? 'Free';
    if (division == 'Free') return 'Vereinslos';
    if (division == 'Under23') return 'Nachwuchsteam';
    return switch (career.licences.of(r.teamId)) {
      Licence.worldTour => 'WorldTeam',
      Licence.pro => 'ProTeam',
      _ => 'Continental',
    };
  }

  @override
  Widget build(BuildContext context) {
    _takeCountry();
    widget.state.rememberView('search', {
      'team': _team,
      'country': _country,
      'level': _level.toList(),
      'types': _types.toList(),
      'ageFrom': _ages.start,
      'ageTo': _ages.end,
      'strength': _strength,
      'potential': _potential,
      'attribute': _attribute,
      'minimum': _minimum,
      'expiring': _expiring,
      'watched': _watched,
    });
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final eco = career.economy;
    final book = career.staff;
    final year = career.year;
    final needle = _text.toLowerCase();
    final pick = _minimums.where((m) => m.$1 == _attribute).firstOrNull;

    // Filters work on what the team knows: the middle of the range.
    double known(SimRider r, String code, double value) {
      final (low, high) = book.range(r.id, code, value);
      return (low + high) / 2;
    }

    final all = career.riderById.values;
    final countries = {for (final r in all) r.country}.toList()..sort();
    final teams = [
      for (final t in career.teams.values)
        if (t.division != 'Free' && (career.squads[t.id]?.isNotEmpty ?? false))
          t,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final found =
        [
          for (final r in all)
            if ((needle.isEmpty ||
                    career.fullName(r.id).toLowerCase().contains(needle)) &&
                (_team == null || r.teamId == _team) &&
                (_country == null || r.country == _country) &&
                (_level.isEmpty || _level.contains(_levelOf(r))) &&
                (_types.isEmpty || _types.contains(riderType(r))) &&
                year - r.born ~/ 10000 >= _ages.start &&
                year - r.born ~/ 10000 <= _ages.end &&
                known(r, 'Stärke', Economy.rating(r)) >= _strength &&
                (_potential <= 1 ||
                    book.knowledge(r.id) >= 0.6 && r.potential >= _potential) &&
                (pick == null ||
                    known(r, pick.$2, pick.$3(r.attributes)) >= _minimum) &&
                (!_expiring ||
                    (eco.contracts[r.id]?.endYear ?? 9999) <= year) &&
                (!_watched || career.watch.contains(r.id)))
              r,
        ]..sort(
          (a, b) => known(
            b,
            'Stärke',
            Economy.rating(b),
          ).compareTo(known(a, 'Stärke', Economy.rating(a))),
        );
    final rows = found.take(500).toList();

    Col<SimRider> value(String code, double Function(SimRider) of) => Col(
      tr(code),
      code.length > 4 ? 66 : 62,
      (r, _) {
        final v = of(r);
        final (low, high) = book.range(r.id, code, v);
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
      sortKey: (r) => known(r, code, of(r)),
    );

    Widget slider(
      double current,
      double min,
      double max,
      int divisions,
      void Function(double) onChanged,
    ) => SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: TeamColors.text,
        inactiveTrackColor: c.line,
        thumbColor: TeamColors.text,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Slider(
          value: current,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: (v) => setState(() => onChanged(v)),
        ),
      ),
    );

    DropdownButton<T> dropdown<T>(
      T current,
      List<DropdownMenuItem<T>> items,
      void Function(T?) onChanged,
    ) => DropdownButton<T>(
      value: current,
      isExpanded: true,
      isDense: true,
      underline: Container(height: 1, color: c.line),
      style: const TextStyle(
        fontFamily: 'Barlow',
        fontSize: 14,
        color: TeamColors.text,
      ),
      items: items,
      onChanged: (v) => setState(() => onChanged(v)),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 232,
            child: Panel(
              colors: c,
              child: ListView(
                children: [
                  SearchBox(
                    hint: tr('Name'),
                    colors: c,
                    width: null,
                    onChanged: (v) => setState(() => _text = v),
                  ),
                  FilterHead(tr('Team')),
                  dropdown<int?>(_team, [
                    DropdownMenuItem(
                      value: null,
                      child: Text(tr('Alle Teams')),
                    ),
                    for (final t in teams)
                      DropdownMenuItem(
                        value: t.id,
                        child: Text(t.name, overflow: TextOverflow.ellipsis),
                      ),
                  ], (v) => _team = v),
                  FilterHead(tr('Land')),
                  dropdown<String?>(_country, [
                    DropdownMenuItem(
                      value: null,
                      child: Text(tr('Alle Länder')),
                    ),
                    for (final x in countries)
                      if (x.isNotEmpty)
                        DropdownMenuItem(
                          value: x,
                          child: Row(
                            children: [
                              Flag(x, width: 18),
                              const SizedBox(width: 8),
                              Text(x),
                            ],
                          ),
                        ),
                  ], (v) => _country = v),
                  FilterHead(tr('Ebene')),
                  for (final l in _levels)
                    FilterOption(
                      label: tr(l),
                      selected: _level.contains(l),
                      onTap: () => setState(
                        () => _level.contains(l)
                            ? _level.remove(l)
                            : _level.add(l),
                      ),
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
                  FilterHead(tr('Stärke ab {0}', [_strength.round()])),
                  slider(_strength, 50, 85, 35, (v) => _strength = v),
                  FilterHead(
                    _potential <= 1
                        ? tr('Potenzial beliebig')
                        : tr('Potenzial ab {0}', [dec(_potential)]),
                  ),
                  slider(_potential, 1, 6, 10, (v) => _potential = v),
                  FilterHead(tr('Einzelner Wert')),
                  dropdown<String?>(_attribute, [
                    DropdownMenuItem(value: null, child: Text(tr('Keiner'))),
                    for (final (name, _, _) in _minimums)
                      DropdownMenuItem(value: name, child: Text(tr(name))),
                  ], (v) => _attribute = v),
                  if (pick != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      tr('{0} ab {1}', [tr(pick.$1), _minimum.round()]),
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                    slider(_minimum, 50, 85, 35, (v) => _minimum = v),
                  ],
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
                  FilterHead(tr('Beobachtung')),
                  FilterOption(
                    label: tr('Nur Beobachtungsliste'),
                    selected: _watched,
                    onTap: () => setState(() => _watched = !_watched),
                  ),
                  FilterHead(tr('Vertrag')),
                  FilterOption(
                    label: tr('Vertrag läuft aus'),
                    selected: _expiring,
                    onTap: () => setState(() => _expiring = !_expiring),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Panel(
              colors: c,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Label(
                        found.length > rows.length
                            ? tr(
                                '{0} Fahrer gefunden · die besten {1} gezeigt',
                                [found.length, rows.length],
                              )
                            : tr('{0} Fahrer gefunden', [found.length]),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: () {
                          final path = s.exportCsv(
                            'fahrersuche',
                            [
                              tr('Fahrer'),
                              'Team',
                              tr('Nat'),
                              tr('Alter'),
                              tr('Stärke'),
                              tr('Vertrag'),
                            ],
                            [
                              for (final r in found)
                                [
                                  career.fullName(r.id),
                                  r.team,
                                  r.country,
                                  '${year - r.born ~/ 10000}',
                                  () {
                                    final (low, high) = book.range(
                                      r.id,
                                      'Stärke',
                                      Economy.rating(r),
                                    );
                                    return low == high ? '$low' : '$low–$high';
                                  }(),
                                  '${eco.contracts[r.id]?.endYear ?? ''}',
                                ],
                            ],
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                path == null
                                    ? tr('Die Datei ließ sich nicht schreiben.')
                                    : tr('Gespeichert: {0}', [path]),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(LucideIcons.download, size: 16),
                        label: Text(tr('Als CSV')),
                      ),
                      const Spacer(),
                      Text(
                        tr(
                          'Spannen statt Zahlen: Diesen Fahrer hat noch kein Scout beobachtet.',
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: TeamColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: DenseTable<SimRider>(
                      colors: c,
                      rows: rows,
                      highlight: (r) => r.teamId == s.team.id,
                      onTap: (r) => showRiderDialog(context, s, r.id),
                      columns: [
                        Col('', 30, (r, _) => watchStar(s, r)),
                        Col(
                          tr('Fahrer'),
                          190,
                          (r, _) => cellText(career.fullName(r.id)),
                          sortKey: (r) => r.lastName,
                        ),
                        Col(
                          tr('Team'),
                          58,
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
                        Col(
                          tr('Typ'),
                          120,
                          (r, _) => cellText(
                            book.knowledge(r.id) >= 1 ? tr(riderType(r)) : '?',
                            color: TeamColors.muted,
                          ),
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
                        value('FL', (r) => r.attributes.flat),
                        value('BG', (r) => r.attributes.mountain),
                        value('MB', (r) => r.attributes.mediumMountain),
                        value('HÜ', (r) => r.attributes.hill),
                        value('ZF', (r) => r.attributes.timeTrial),
                        value('KO', (r) => r.attributes.cobble),
                        value('SP', (r) => r.attributes.sprint),
                        value('ANT', (r) => r.attributes.acceleration),
                        value('AD', (r) => r.attributes.endurance),
                        Col(
                          tr('Vertrag bis'),
                          92,
                          (r, _) =>
                              cellText(switch (eco.contracts[r.id]?.endYear) {
                                final year?
                                    when career.teams[r.teamId]?.division !=
                                        'Free' =>
                                  contractEnd(year),
                                _ => '–',
                              }, color: TeamColors.muted),
                          numeric: true,
                          sortKey: (r) => eco.contracts[r.id]?.endYear ?? 0,
                        ),
                        Col(
                          tr('Marktwert'),
                          96,
                          (r, _) => cellText(
                            book.knowledge(r.id) >= 1
                                ? euro(eco.marketWage(r))
                                : '?',
                          ),
                          numeric: true,
                          sortKey: (r) => eco.marketWage(r),
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
