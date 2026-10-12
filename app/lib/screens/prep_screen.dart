import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';

const _approachLabels = {
  Approach.wait: 'Abwarten',
  Approach.control: 'Tempo kontrollieren',
  Approach.makeHard: 'Rennen schwer machen',
};
const _breakLabels = {
  BreakPolicy.ignore: 'Ignorieren',
  BreakPolicy.join: 'Besetzen',
  BreakPolicy.chase: 'Zurückholen',
};

/// Race preparation: choose the line-up, set roles and team tactics. Shown
/// as soon as a race with the player's team starts.
class PrepScreen extends StatefulWidget {
  const PrepScreen({super.key, required this.state, required this.pending});
  final AppState state;
  final PendingRace pending;

  @override
  State<PrepScreen> createState() => _PrepScreenState();
}

/// State of the preparation: chosen riders, roles, tactics and the forecast.
class _PrepScreenState extends State<PrepScreen> {
  late Set<int> _selected;
  late Map<int, Role> _roles;
  late Approach _approach;
  late BreakPolicy _breakPolicy;

  /// Off: the sports director plans every stage himself. On: the roles and
  /// instructions chosen here apply to the whole race.
  var _ownTactics = false;

  /// Sports director in the car; preset to the best free one.
  int? _director;

  /// Forecast for the current line-up; discarded as soon as it changes.
  Forecast? _forecast;
  var _forecasting = false;

  /// Computes the forecast for the current line-up and tactics.
  ///
  /// @returns A future that completes when the forecast is shown.
  Future<void> _runForecast() async {
    final lineup = _lineup;
    setState(() => _forecasting = true);
    final result = await widget.state.forecast(
      _p,
      lineup,
      _ownTactics
          ? TeamPlan(
              roles: _roles,
              approach: _approach,
              breakPolicy: _breakPolicy,
            )
          : null,
    );
    if (!mounted) return;
    setState(() {
      _forecasting = false;
      _forecast = result;
    });
  }

  /// The race being prepared.
  PendingRace get _p => widget.pending;

  /// Route of the first stage.
  SimRoute get _first => _p.routes.first;

  /// Chosen riders in squad order.
  List<SimRider> get _lineup => [
    for (final r in _p.available)
      if (_selected.contains(r.id)) r,
  ];

  @override
  void initState() {
    super.initState();
    _selected = {for (final r in _p.suggestedLineup) r.id};
    _director = _p.directors.firstOrNull?.id;
    _takeSuggestion();
  }

  /// Takes over the roles and instructions the sports director would choose
  /// for the first stage with the current line-up.
  void _takeSuggestion() {
    final lineup = _lineup;
    if (lineup.isEmpty) {
      _roles = {};
      _approach = Approach.wait;
      _breakPolicy = BreakPolicy.ignore;
      return;
    }
    final plan = widget.state.career.suggestPlan(_first, lineup, _p.others);
    _roles = {for (final r in lineup) r.id: plan.roleOf(r.id)};
    _approach = plan.approach;
    _breakPolicy = plan.breakPolicy;
  }

  /// @param r A rider.
  /// @returns His mean suitability for the three stages that suit him best.
  double _fit(SimRider r) {
    final fits = [
      for (final route in _p.routes) suitability(route, r.attributes),
    ]..sort((a, b) => b.compareTo(a));
    final top = fits.take(fits.length < 3 ? fits.length : 3);
    return top.reduce((a, b) => a + b) / top.length;
  }

  void _toggle(SimRider r) => setState(() {
    _forecast = null;
    if (!_selected.remove(r.id)) {
      if (_selected.length >= _p.size) return;
      _selected.add(r.id);
    }
    if (_ownTactics) {
      // Keep the chosen roles; new riders start as domestiques.
      _roles = {for (final x in _lineup) x.id: _roles[x.id] ?? Role.domestique};
    } else {
      _takeSuggestion();
    }
  });

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final race = _p.race;
    final lineup = _lineup;
    final available = [..._p.available]
      ..sort((a, b) => _fit(b).compareTo(_fit(a)));
    final rivals = [..._p.others]
      ..sort(
        (a, b) => suitability(
          _first,
          b.attributes,
        ).compareTo(suitability(_first, a.attributes)),
      );
    final meters = _first.segments
        .where((x) => x.grade > 0)
        .fold<double>(0, (sum, x) => sum + x.grade * x.lengthM);

    Col<SimRider> value(String title, double Function(SimRider) of) => Col(
      title,
      title.length > 4 ? 74 : 44,
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

    Widget choice<T>(
      String title,
      Map<T, String> labels,
      T current,
      void Function(T) onPick,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: TeamColors.muted),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in labels.entries)
              Pill(
                label: tr(e.value),
                selected: e.key == current,
                colors: c,
                onTap: _ownTactics ? () => setState(() => onPick(e.key)) : null,
              ),
          ],
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      race.info.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      tr('{0} · {1} · {2} · {3} Fahrer am Start', [
                        race.tier.label,
                        race.info.country,
                        race.isStageRace
                            ? tr('{0} Etappen', [race.stages.length])
                            : tr('Eintagesrennen'),
                        _p.others.length + lineup.length,
                      ]),
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: TeamColors.text,
                  side: BorderSide(color: c.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                onPressed: () => setState(() {
                  _selected = {for (final r in _p.suggestedLineup) r.id};
                  _ownTactics = false;
                  _takeSuggestion();
                }),
                child: Text(tr('Vorschlag des Sportlichen Leiters')),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  disabledBackgroundColor: c.panel,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                ),
                onPressed: lineup.length < 4
                    ? null
                    : () => s.confirmLineup(
                        _p,
                        lineup,
                        plan: _ownTactics
                            ? TeamPlan(
                                roles: _roles,
                                approach: _approach,
                                breakPolicy: _breakPolicy,
                              )
                            : null,
                        directorId: _director,
                      ),
                child: Text(
                  tr('BESTÄTIGEN UND STARTEN'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Panel(
                    colors: c,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Label(tr('Verfügbare Fahrer')),
                            const Spacer(),
                            Text(
                              tr('{0} von {1} gewählt', [
                                lineup.length,
                                _p.size,
                              ]),
                              style: TextStyle(
                                fontSize: 12,
                                color: lineup.length == _p.size
                                    ? TeamColors.green
                                    : TeamColors.gold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: DenseTable<SimRider>(
                            colors: c,
                            rows: available,
                            highlight: (r) => _selected.contains(r.id),
                            onTap: _toggle,
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
                                tr('Fahrer'),
                                170,
                                (r, _) => cellText(
                                  s.career.devTeam.stagiaires.contains(r.id)
                                      ? '${r.name} · Stagiaire'
                                      : r.name,
                                ),
                                sortKey: (r) => r.lastName,
                              ),
                              value(tr('Eignung'), _fit),
                              value('FL', (r) => r.attributes.flat),
                              value(tr('BG'), (r) => r.attributes.mountain),
                              value(tr('HÜ'), (r) => r.attributes.hill),
                              value(tr('ZF'), (r) => r.attributes.timeTrial),
                              value(tr('KO'), (r) => r.attributes.cobble),
                              value(tr('SP'), (r) => r.attributes.sprint),
                              value(tr('AUS'), (r) => r.attributes.breakaway),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      Panel(
                        colors: c,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    race.isStageRace
                                        ? tr('Etappe 1 · {0}', [_first.name])
                                        : _first.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  tr('{0} km · {1} Hm', [
                                    _first.raceKm.toStringAsFixed(1),
                                    meters.round(),
                                  ]),
                                  style: const TextStyle(
                                    color: TeamColors.muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 150,
                              child: ProfileView(route: _first, colors: c),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Panel(
                                colors: c,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Label(tr('Rollen und Taktik')),
                                        const Spacer(),
                                        Text(
                                          tr('Eigene Taktik'),
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(width: 4),
                                        SizedBox(
                                          height: 24,
                                          child: Switch(
                                            value: _ownTactics,
                                            activeThumbColor: c.accent,
                                            onChanged: (v) => setState(() {
                                              _ownTactics = v;
                                              if (!v) _takeSuggestion();
                                            }),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _ownTactics
                                          ? tr(
                                              'Deine Vorgaben gelten für das ganze Rennen.',
                                            )
                                          : tr(
                                              'Der Sportliche Leiter plant jede Etappe selbst. Das hier ist sein Plan für den Auftakt.',
                                            ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: TeamColors.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (_p.directors.isNotEmpty)
                                      Row(
                                        children: [
                                          Text(
                                            tr('Im Wagen:'),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: TeamColors.muted,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: DropdownButton<int>(
                                              value: _director,
                                              isDense: true,
                                              isExpanded: true,
                                              underline: const SizedBox(),
                                              dropdownColor: c.panel2,
                                              style: const TextStyle(
                                                fontFamily: 'Barlow',
                                                fontSize: 13,
                                                color: TeamColors.text,
                                              ),
                                              onChanged: (v) =>
                                                  setState(() => _director = v),
                                              items: [
                                                for (final d in _p.directors)
                                                  DropdownMenuItem(
                                                    value: d.id,
                                                    child: Text(
                                                      tr(
                                                        '{0} · Taktik {1}, Rennlesen {2}, Motivation {3} · {4}',
                                                        [
                                                          d.name,
                                                          d.skill,
                                                          d.second,
                                                          d.third,
                                                          d.focus.label,
                                                        ],
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    else
                                      Text(
                                        tr(
                                          'Kein Sportlicher Leiter frei: ein Mechaniker fährt den Wagen.',
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: TeamColors.red,
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                    Expanded(
                                      child: ListView(
                                        children: [
                                          for (final r in lineup)
                                            SizedBox(
                                              height: 30,
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: cellText(r.name),
                                                  ),
                                                  DropdownButton<Role>(
                                                    value:
                                                        _roles[r.id] ??
                                                        Role.domestique,
                                                    isDense: true,
                                                    underline: const SizedBox(),
                                                    dropdownColor: c.panel2,
                                                    style: const TextStyle(
                                                      fontFamily: 'Barlow',
                                                      fontSize: 13,
                                                      color: TeamColors.text,
                                                    ),
                                                    onChanged: _ownTactics
                                                        ? (v) => setState(
                                                            () => _roles[r.id] =
                                                                v!,
                                                          )
                                                        : null,
                                                    items: [
                                                      for (final role
                                                          in Role.values)
                                                        DropdownMenuItem(
                                                          value: role,
                                                          child: Text(
                                                            role.label,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          const SizedBox(height: 10),
                                          choice(
                                            tr('Rennverlauf'),
                                            _approachLabels,
                                            _approach,
                                            (v) => _approach = v,
                                          ),
                                          const SizedBox(height: 8),
                                          choice(
                                            tr('Ausreißergruppe'),
                                            _breakLabels,
                                            _breakPolicy,
                                            (v) => _breakPolicy = v,
                                          ),
                                        ],
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
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Label(
                                            _forecast != null
                                                ? tr('Prognose · {0} Läufe', [
                                                    _forecast!.runs,
                                                  ])
                                                : race.isStageRace
                                                ? tr(
                                                    'Stärkste Gegner am ersten Tag',
                                                  )
                                                : tr('Stärkste Gegner'),
                                          ),
                                        ),
                                        InkWell(
                                          onTap:
                                              _forecasting || lineup.length < 4
                                              ? null
                                              : _forecast != null
                                              ? () => setState(
                                                  () => _forecast = null,
                                                )
                                              : _runForecast,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: c.line),
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                            ),
                                            child: Text(
                                              _forecasting
                                                  ? tr('rechnet …')
                                                  : _forecast != null
                                                  ? tr('Gegner zeigen')
                                                  : tr('Prognose'),
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    if (_forecast case final f?)
                                      Expanded(
                                        child: DenseTable<ForecastRow>(
                                          colors: c,
                                          // The first 15 and all of our own.
                                          rows: [
                                            for (final (i, row)
                                                in f.rows.indexed)
                                              if (i < 15 ||
                                                  row.rider.teamId == s.team.id)
                                                row,
                                          ],
                                          highlight: (row) =>
                                              row.rider.teamId == s.team.id,
                                          columns: [
                                            Col(
                                              tr('Fahrer'),
                                              124,
                                              (row, _) =>
                                                  cellText(row.rider.name),
                                            ),
                                            Col(
                                              'Team',
                                              46,
                                              (row, _) => cellText(
                                                row.rider.team,
                                                color: TeamColors.muted,
                                              ),
                                            ),
                                            Col(
                                              tr('Sieg'),
                                              44,
                                              (row, _) => cellText(
                                                row.wins == 0
                                                    ? '–'
                                                    : '${row.wins}×',
                                                color: TeamColors.gold,
                                              ),
                                              numeric: true,
                                            ),
                                            Col(
                                              'Top 3',
                                              50,
                                              (row, _) => cellText(
                                                row.podiums == 0
                                                    ? '–'
                                                    : '${row.podiums}×',
                                              ),
                                              numeric: true,
                                            ),
                                            Col(
                                              'Ø',
                                              44,
                                              (row, _) => cellText(
                                                row.meanRank.toStringAsFixed(1),
                                              ),
                                              numeric: true,
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Expanded(
                                        child: DenseTable<SimRider>(
                                          colors: c,
                                          rows: rivals.take(25).toList(),
                                          columns: [
                                            Col(
                                              tr('Fahrer'),
                                              150,
                                              (r, _) => cellText(r.name),
                                            ),
                                            Col(
                                              'Team',
                                              50,
                                              (r, _) => cellText(
                                                r.team,
                                                color: TeamColors.muted,
                                              ),
                                            ),
                                            value(
                                              tr('Eignung'),
                                              (r) => suitability(
                                                _first,
                                                r.attributes,
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
}
