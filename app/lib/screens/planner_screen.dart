import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'plan_screen.dart';

/// Filter of the race list by the state of the team's entry.
enum _Filter {
  possible('Mögliche Rennen'),
  entered('Gemeldet'),
  open('Bewerbung möglich'),
  applied('Bewerbungen'),
  all('Alle');

  const _Filter(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
}

String _d(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

Color _statusColor(EntryStatus s) => switch (s) {
  EntryStatus.mandatory || EntryStatus.entered => TeamColors.green,
  EntryStatus.accepted => TeamColors.green,
  EntryStatus.pending || EntryStatus.open => TeamColors.gold,
  EntryStatus.declined || EntryStatus.rejected => TeamColors.red,
  _ => TeamColors.muted,
};

/// Race planner: all races of the season with the state of the team's
/// entry. Here the player declines invitations, applies for wildcards and
/// assigns riders per race. The second tab shows the same plan as a matrix
/// of riders and races.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key, required this.state});
  final AppState state;

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

/// State of the planner: tab, filter, search text and selected race.
class _PlannerScreenState extends State<PlannerScreen> {
  var _matrix = false;
  var _filter = _Filter.possible;
  var _search = '';
  var _groups = <TierGroup>{};

  /// Only races this rider is planned for; null shows all.
  int? _rider;
  int? _selected;
  String? _message;

  bool _matches(EntryStatus s) => switch (_filter) {
    _Filter.all => true,
    _Filter.possible => s != EntryStatus.ineligible,
    _Filter.entered => s.starts,
    _Filter.open => s == EntryStatus.open,
    _Filter.applied =>
      s == EntryStatus.pending ||
          s == EntryStatus.accepted ||
          s == EntryStatus.rejected,
  };

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final entries = career.entries;
    final status = {
      for (final r in career.calendar) r.info.id: entries.status(r),
    };
    final needle = _search.toLowerCase();
    // Everything but the group filter, so the groups can show their counts.
    final base = [
      for (final r in career.calendar)
        if (_matches(status[r.info.id]!) &&
            (needle.isEmpty ||
                r.info.name.toLowerCase().contains(needle) ||
                r.info.country.toLowerCase() == needle) &&
            (_rider == null ||
                (career.program[r.info.id]?.contains(_rider) ?? false)))
          r,
    ];
    final perGroup = <TierGroup, int>{};
    for (final r in base) {
      final g = TierGroup.of(r.tier);
      perGroup[g] = (perGroup[g] ?? 0) + 1;
    }
    final rows = [
      for (final r in base)
        if (_groups.isEmpty || _groups.contains(TierGroup.of(r.tier))) r,
    ];
    final squad = s.squad..sort((a, b) => a.lastName.compareTo(b.lastName));
    final entered = [
      for (final r in career.calendar)
        if (status[r.info.id]!.starts) r,
    ];
    final raceDays = entered.fold(0, (sum, r) => sum + r.stages.length);
    final pending = status.values.where((x) => x == EntryStatus.pending).length;
    final selected =
        career.calendar.where((r) => r.info.id == _selected).firstOrNull ??
        rows.firstOrNull;

    Widget tab(String label, bool matrix) => InkWell(
      onTap: () => setState(() => _matrix = matrix),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _matrix == matrix ? c.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: _matrix == matrix ? TeamColors.text : TeamColors.muted,
          ),
        ),
      ),
    );

    void act(RaceEntry r, String action, String done) => setState(() {
      _message = s.entry(r.info.id, action) ?? done;
    });

    Widget? action(RaceEntry r, {bool large = false}) {
      final (label, onTap) = switch (status[r.info.id]!) {
        EntryStatus.entered => (
          tr('Absagen'),
          () => act(r, 'decline', tr('{0}: abgesagt.', [r.info.name])),
        ),
        EntryStatus.declined => (
          tr('Wieder zusagen'),
          () => act(r, 'restore', tr('{0}: wieder gemeldet.', [r.info.name])),
        ),
        EntryStatus.open => (
          tr('Bewerben'),
          () => act(
            r,
            'apply',
            tr('{0}: Bewerbung ist raus, Antwort in zehn Tagen.', [
              r.info.name,
            ]),
          ),
        ),
        _ => (null, null),
      };
      if (label == null) return null;
      final busy = s.busy || !r.start.isAfter(career.today);
      return large
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: TeamColors.text,
                side: BorderSide(color: c.line),
              ),
              onPressed: busy ? null : onTap,
              child: Text(label),
            )
          : InkWell(
              onTap: busy ? null : onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
            );
    }

    String chanceLabel(RaceEntry r) {
      final p = entries.chance(r);
      if (s.debug) return '${(p * 100).round()} %';
      return p >= 0.7
          ? tr('gut')
          : p >= 0.4
          ? tr('mittel')
          : tr('gering');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              tab(tr('Rennen und Meldungen'), false),
              tab(tr('Fahrer-Matrix'), true),
              const Spacer(),
              Text(
                tr('{0} Rennen gemeldet · {1} Renntage{2}', [
                  entered.length,
                  raceDays,
                  pending == 0
                      ? ''
                      : pending == 1
                      ? tr(' · 1 Bewerbung offen')
                      : tr(' · {0} Bewerbungen offen', [pending]),
                ]),
                style: const TextStyle(color: TeamColors.muted),
              ),
            ],
          ),
        ),
        if (_matrix)
          Expanded(child: PlanScreen(state: s))
        else
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 208,
                    child: Panel(
                      colors: c,
                      child: ListView(
                        children: [
                          SearchBox(
                            hint: tr('Rennen oder Land'),
                            colors: c,
                            width: null,
                            onChanged: (v) => setState(() => _search = v),
                          ),
                          FilterHead(tr('Meldung')),
                          for (final f in _Filter.values)
                            FilterOption(
                              label: f.label,
                              radio: true,
                              selected: _filter == f,
                              onTap: () => setState(() => _filter = f),
                            ),
                          FilterHead(tr('Rennklasse')),
                          FilterOption(
                            label: tr('Alle Klassen'),
                            selected: _groups.isEmpty,
                            count: base.length,
                            onTap: () => setState(() => _groups = {}),
                          ),
                          for (final g in TierGroup.values)
                            FilterOption(
                              label: g.label,
                              dot: tierColor(g.tiers.first),
                              selected: _groups.contains(g),
                              count: perGroup[g] ?? 0,
                              onTap: () => setState(
                                () => _groups = _groups.contains(g)
                                    ? ({..._groups}..remove(g))
                                    : {..._groups, g},
                              ),
                            ),
                          FilterHead(tr('Fahrer im Aufgebot')),
                          DropdownButton<int?>(
                            value: _rider,
                            isExpanded: true,
                            isDense: true,
                            dropdownColor: c.panel2,
                            underline: Container(height: 1, color: c.line),
                            style: const TextStyle(
                              fontFamily: 'Barlow',
                              fontSize: 14,
                              color: TeamColors.text,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: null,
                                child: Text(tr('Alle Fahrer')),
                              ),
                              for (final r in squad)
                                DropdownMenuItem(
                                  value: r.id,
                                  child: Text(r.name),
                                ),
                            ],
                            onChanged: (v) => setState(() => _rider = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 7,
                    child: Panel(
                      colors: c,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DenseTable<RaceEntry>(
                              colors: c,
                              rows: rows,
                              highlight: (r) => r.info.id == selected?.info.id,
                              onTap: (r) =>
                                  setState(() => _selected = r.info.id),
                              columns: [
                                Col(
                                  tr('Datum'),
                                  104,
                                  (r, _) => cellText(
                                    r.isStageRace
                                        ? '${_d(r.start)}–${_d(r.end)}'
                                        : _d(r.start),
                                    color: r.end.isBefore(career.today)
                                        ? TeamColors.muted
                                        : TeamColors.text,
                                  ),
                                  sortKey: (r) => r.start,
                                ),
                                Col(
                                  '',
                                  30,
                                  (r, _) => RaceLogo(
                                    dataDir: s.dataDir,
                                    race: r.info,
                                    size: 24,
                                  ),
                                ),
                                Col(
                                  tr('Rennen'),
                                  230,
                                  (r, _) => cellText(r.info.name),
                                  sortKey: (r) => r.info.name,
                                ),
                                Col(
                                  tr('Klasse'),
                                  96,
                                  (r, _) => cellText(
                                    r.tier.label,
                                    color: tierColor(r.tier),
                                  ),
                                  sortKey: (r) => -r.tier.factor,
                                ),
                                Col(
                                  tr('Land'),
                                  70,
                                  (r, _) => flagCell(r.info.country),
                                  sortKey: (r) => r.info.country,
                                ),
                                Col(
                                  tr('Tage'),
                                  44,
                                  (r, _) => cellText('${r.stages.length}'),
                                  numeric: true,
                                  sortKey: (r) => r.stages.length,
                                ),
                                Col(tr('Meldung'), 160, (r, _) {
                                  final st = status[r.info.id]!;
                                  return cellText(
                                    st == EntryStatus.open
                                        ? tr('Wildcard: Chance {0}', [
                                            chanceLabel(r),
                                          ])
                                        : st.label,
                                    color: _statusColor(st),
                                  );
                                }, sortKey: (r) => status[r.info.id]!.index),
                                Col(
                                  tr('Fahrer'),
                                  66,
                                  (r, _) => cellText(
                                    status[r.info.id]!.starts
                                        ? '${career.program[r.info.id]?.length ?? 0}'
                                        : '',
                                    color: TeamColors.muted,
                                  ),
                                  numeric: true,
                                ),
                                Col(
                                  '',
                                  124,
                                  (r, _) => action(r) ?? const SizedBox(),
                                ),
                              ],
                            ),
                          ),
                          if (_message != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(_message!),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: selected == null
                        ? const SizedBox()
                        : _Detail(
                            state: s,
                            race: selected,
                            status: status[selected.info.id]!,
                            action: action(selected, large: true),
                          ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Detail panel of the selected race: route summary, entry state and the
/// riders to assign.
class _Detail extends StatelessWidget {
  const _Detail({
    required this.state,
    required this.race,
    required this.status,
    required this.action,
  });
  final AppState state;
  final RaceEntry race;
  final EntryStatus status;
  final Widget? action;

  static String _kind(SimRoute r) => r.kind != StageKind.road
      ? (r.kind == StageKind.teamTimeTrial
            ? tr('Teamzeitfahren')
            : tr('Zeitfahren'))
      : r.sprintStage
      ? tr('Flach')
      : r.selectivity > 2500
      ? tr('Berg')
      : tr('Hügelig');

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = s.colors;
    final career = s.career;
    final routes = s.routesOf(race.info);
    final id = race.info.id;
    final size = career.world.raceField(id).ridersPerTeam;
    final planned = career.program[id] ?? const <int>{};
    final started = career.progress.containsKey(id);
    final kinds = <String, int>{};
    for (final r in routes) {
      kinds[_kind(r)] = (kinds[_kind(r)] ?? 0) + 1;
    }
    final km = routes.fold(0.0, (sum, r) => sum + r.raceKm);

    double fit(SimRider r) {
      final fits = [
        for (final route in routes) suitability(route, r.attributes),
      ]..sort((a, b) => b.compareTo(a));
      final top = fits.take(fits.length < 3 ? fits.length : 3);
      return top.reduce((a, b) => a + b) / top.length;
    }

    final squad = s.squad..sort((a, b) => fit(b).compareTo(fit(a)));
    final explain = switch (status) {
      EntryStatus.mandatory => tr(
        'WorldTeams müssen alle WorldTour-Rennen fahren.',
      ),
      EntryStatus.entered => tr('Das Team ist eingeladen und startet.'),
      EntryStatus.declined => tr(
        'Abgesagt. Bis zum Vortag des Starts lässt sich das zurücknehmen.',
      ),
      EntryStatus.open => tr(
        'Nicht eingeladen. Eine Bewerbung muss {0} Tage vor dem Start eingehen; der Veranstalter antwortet nach zehn Tagen. Es zählen Stärke des Teams, Rang des Rennens und Heimvorteil.',
        [Entries.deadlineDays],
      ),
      EntryStatus.pending => tr(
        'Die Bewerbung liegt beim Veranstalter. Antwort am {0}',
        [_d(career.entries.applications[id]!.answer)],
      ),
      EntryStatus.accepted => tr('Wildcard erhalten, das Team startet.'),
      EntryStatus.rejected => tr('Der Veranstalter hat abgelehnt.'),
      EntryStatus.closed => tr('Ohne uns: Der Meldeschluss ist vorbei.'),
      EntryStatus.ineligible =>
        race.tier == RaceTier.championship
            ? tr(
                'Meisterschaft: Es starten Nationalauswahlen oder alle Fahrer des Landes; das Team meldet nicht.',
              )
            : tr('Mit unserer Lizenz dürfen wir hier nicht starten.'),
    };

    return Panel(
      colors: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RaceLogo(dataDir: s.dataDir, race: race.info, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(race.info.name, style: headStyle(21)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flag(race.info.country, width: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${race.tier.label} · '
                            '${race.isStageRace ? tr('{0} bis {1}', [_d(race.start), _d(race.end)]) : _d(race.start)} · '
                            '${km.round()} km',
                            style: const TextStyle(color: TeamColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 4),
          Text(
            kinds.entries.map((e) => '${e.value}× ${e.key}').join(' · '),
            style: TextStyle(color: tierColor(race.tier)),
          ),
          SizedBox(
            height: 92,
            child: ProfileView(
              route: routes.reduce(
                (a, b) => b.selectivity > a.selectivity ? b : a,
              ),
              colors: c,
            ),
          ),
          Text(
            status.label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _statusColor(status),
            ),
          ),
          Text(
            explain,
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
          if (status.starts) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Label(tr('Fahrer einplanen')),
                const Spacer(),
                Text(
                  tr('{0} von {1}', [planned.length, size]),
                  style: TextStyle(
                    fontSize: 12,
                    color: planned.length >= size
                        ? TeamColors.green
                        : TeamColors.gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: DenseTable<SimRider>(
                colors: c,
                rows: squad,
                highlight: (r) => planned.contains(r.id),
                onTap: started || s.busy
                    ? null
                    : (r) => s.toggleProgram(id, r.id),
                columns: [
                  Col(
                    '',
                    30,
                    (r, _) => Icon(
                      planned.contains(r.id)
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 17,
                      color: planned.contains(r.id)
                          ? TeamColors.text
                          : TeamColors.muted,
                    ),
                  ),
                  Col(tr('Fahrer'), 150, (r, _) => cellText(r.name)),
                  Col(tr('Eignung'), 70, (r, _) {
                    final v = fit(r);
                    return cellText(
                      v.round().toString(),
                      color: attributeColor(v),
                      bold: v >= 72,
                    );
                  }, numeric: true),
                  Col(tr('Frische'), 64, (r, _) {
                    final f = career.shapeOf(r.id).freshness;
                    return cellText(
                      f.round().toString(),
                      color: f < -20 ? TeamColors.red : TeamColors.muted,
                    );
                  }, numeric: true),
                  Col(
                    tr('Renntage'),
                    84,
                    (r, _) => cellText(
                      '${career.shapeOf(r.id).raceDays}',
                      color: TeamColors.muted,
                    ),
                    numeric: true,
                  ),
                ],
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}
