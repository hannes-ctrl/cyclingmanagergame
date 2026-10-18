import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

/// A list the debug page can write as CSV: its file name, headings and
/// lines.
typedef CsvList = ({
  String name,
  List<String> headers,
  List<List<String>> rows,
});

/// The lists of the career as tables for a spreadsheet, for testing and
/// balancing: every rider, every team, the rankings, the calendar, the
/// results of the season and all staff.
///
/// @param s Application state.
/// @returns The lists.
List<CsvList> careerLists(AppState s) {
  final c = s.career;
  final eco = c.economy;
  String n(double v, [int digits = 1]) => v.toStringAsFixed(digits);
  String team(int id) => c.teams[id]?.abbr ?? '';
  final places = c.rankingPlaces();

  final riders = <List<String>>[
    for (final r in c.riderById.values)
      [
        '${r.id}',
        c.fullName(r.id),
        team(r.teamId),
        r.country,
        '${c.year - r.born ~/ 10000}',
        n(r.potential),
        n(Economy.rating(r)),
        riderType(r),
        for (final v in _attributes(r.attributes)) n(v, 0),
        n(r.massKg, 0),
        '${eco.contracts[r.id]?.wage ?? 0}',
        '${eco.contracts[r.id]?.endYear ?? ''}',
        team(eco.contracts[r.id]?.nextTeam ?? -1),
        n(c.people.moraleOf(r.id), 2),
        c.people.of(r.id).label,
        n(c.riderPoints[r.id] ?? 0, 0),
        '${c.winsOf(r.id, c.year)}',
        '${c.shapeOf(r.id).raceDays}',
      ],
  ];

  final teams = <List<String>>[
    for (final t in c.teams.values)
      if (t.division != 'Free')
        [
          '${t.id}',
          t.name,
          t.abbr,
          t.division,
          c.licences.of(t.id).label,
          '${c.squads[t.id]?.length ?? 0}',
          n(c.teamStrength(t.id)),
          n(c.finances.budgetOf(t.id), 0),
          n(c.finances.balanceOf(t.id), 0),
          '${eco.wageBill(t.id)}',
          n(c.finances.wageLimit(t.id), 0),
          for (final f in Facility.values) '${c.facilities.level(t.id, f)}',
          n(c.teamPoints[t.id] ?? 0, 0),
          '${places[t.id] ?? ''}',
        ],
  ];

  final calendar = <List<String>>[
    for (final r in c.calendar)
      [
        '${r.info.id}',
        r.info.name,
        r.tier.name,
        r.info.country,
        _date(r.start),
        _date(r.end),
        '${r.stages.length}',
        c.ownRaces.contains(r) ? 'x' : '',
        '${c.program[r.info.id]?.length ?? 0}',
      ],
  ];

  final results = <List<String>>[
    for (final p in c.progress.values)
      for (final (i, res) in p.run.results.indexed)
        if (res.placings.isNotEmpty)
          [
            p.race.info.name,
            '${i + 1}',
            c.fullName(res.placings.first.rider.id),
            team(res.placings.first.rider.teamId),
            n(res.winnerTimeS, 0),
            '${res.placings.length}',
          ],
  ];

  final staff = <List<String>>[
    for (final x in c.staff.all)
      [
        '${x.id}',
        x.name,
        x.role.name,
        team(x.teamId),
        '${x.skill}',
        '${x.wage}',
      ],
  ];

  return [
    (
      name: 'riders',
      headers: [
        'id', 'name', 'team', 'country', 'age', 'potential', 'rating', 'type',
        ..._attributeNames, 'kg', 'wage', 'contract', 'next team', 'morale',
        'personality', 'points', 'wins', 'race days', //
      ],
      rows: riders,
    ),
    (
      name: 'teams',
      headers: [
        'id', 'name', 'abbr', 'division', 'licence', 'riders', 'strength',
        'budget', 'balance', 'wages', 'wage limit',
        for (final f in Facility.values) f.name,
        'points', 'place', //
      ],
      rows: teams,
    ),
    (
      name: 'calendar',
      headers: [
        'id', 'race', 'tier', 'country', 'start', 'end', 'stages', 'own',
        'pencilled in', //
      ],
      rows: calendar,
    ),
    (
      name: 'results',
      headers: ['race', 'stage', 'winner', 'team', 'time s', 'finishers'],
      rows: results,
    ),
    (
      name: 'staff',
      headers: ['id', 'name', 'role', 'team', 'skill', 'wage'],
      rows: staff,
    ),
  ];
}

const _attributeNames = [
  'flat', 'mountain', 'medium mountain', 'hill', 'time trial', 'prologue',
  'cobbles', 'sprint', 'acceleration', 'downhill', 'stamina', 'resistance',
  'recovery', 'breakaway', //
];

List<double> _attributes(Attributes a) => [
  a.flat, a.mountain, a.mediumMountain, a.hill, a.timeTrial, a.prologue,
  a.cobble, a.sprint, a.acceleration, a.downhill, a.endurance, a.resistance,
  a.recovery, a.breakaway, //
];

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
