import 'package:sim/sim.dart';
import 'package:flutter/material.dart';
import 'package:game/game.dart';

import '../app_state.dart';
import '../widgets.dart';

/// The two views of the staff page.
enum _Tab { staff, scouting }

/// Staff: the team's employees and the job market, and the scouting with
/// its assignments and reports.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.state});
  final AppState state;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

/// State of the screen: the view and the last feedback message.
class _StaffScreenState extends State<StaffScreen> {
  String? _message;
  var _tab = _Tab.staff;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final book = career.staff;
    final own = book.of(s.team.id).toList()
      ..sort(
        (a, b) => a.role.index != b.role.index
            ? a.role.index.compareTo(b.role.index)
            : b.skill.compareTo(a.skill),
      );
    final market = book.free.toList()
      ..sort(
        (a, b) => a.role.index != b.role.index
            ? a.role.index.compareTo(b.role.index)
            : b.skill.compareTo(a.skill),
      );

    Col<Staff> skill(
      String title,
      int Function(Staff) of, {
      bool onlyDirector = false,
    }) => Col(
      title,
      96,
      (m, _) {
        if (onlyDirector && m.role != StaffRole.director) {
          return cellText('–', color: TeamColors.muted);
        }
        final v = of(m);
        return cellText(
          '$v',
          color: v >= 16
              ? TeamColors.gold
              : v >= 12
              ? TeamColors.green
              : v < 8
              ? TeamColors.muted
              : TeamColors.text,
          bold: v >= 12,
        );
      },
      numeric: true,
      sortKey: of,
    );

    List<Col<Staff>> columns({required bool hired}) => [
      Col(
        tr('Role'),
        150,
        (m, _) => cellText(m.role.label),
        sortKey: (m) => m.role.index,
      ),
      Col('Name', 190, (m, _) => cellText(m.name), sortKey: (m) => m.name),
      Col(
        tr('Age'),
        50,
        (m, _) => cellText('${career.year - m.born}'),
        numeric: true,
        sortKey: (m) => -m.born,
      ),
      skill(tr('Skill'), (m) => m.skill),
      skill(tr('Race reading'), (m) => m.second, onlyDirector: true),
      skill('Motivation', (m) => m.third, onlyDirector: true),
      Col(
        tr('Focus'),
        110,
        (m, _) => cellText(
          m.role == StaffRole.director ? m.focus.label : '–',
          color: TeamColors.muted,
        ),
      ),
      Col(
        tr('Wage'),
        80,
        (m, _) => cellText(euro(m.wage)),
        numeric: true,
        sortKey: (m) => m.wage,
      ),
      if (hired)
        Col(tr('Assignment'), 170, (m, _) {
          if (m.busyUntil?.isAfter(career.today) ?? false) {
            final race = career.calendar
                .where((r) => r.info.id == m.atRace)
                .map((r) => r.info.name)
                .firstOrNull;
            return cellText(race ?? tr('racing'), color: TeamColors.green);
          }
          if (book.jobs.any((j) => j.scoutId == m.id) ||
              book.assignments.any((a) => a.scoutId == m.id)) {
            return cellText(tr('scouting'), color: TeamColors.green);
          }
          return cellText(tr('free'), color: TeamColors.muted);
        }),
      if (hired)
        Col(tr('Other offer'), 190, (m, _) {
          final lure = book.lures[m.id];
          if (lure == null) return cellText('–', color: TeamColors.muted);
          return InkWell(
            onTap: s.busy
                ? null
                : () => setState(() {
                    _message =
                        s.keepStaff(m.id) ??
                        tr('{0} stays for {1} a year.', [
                          m.name,
                          '${euro(lure.wage)} €',
                        ]);
                  }),
            child: Text(
              tr('{0}: match {1}', [
                career.teams[lure.teamId]?.abbr ?? '',
                '${euro(lure.wage)} €',
              ]),
              style: const TextStyle(
                fontSize: 12.5,
                color: TeamColors.gold,
                decoration: TextDecoration.underline,
              ),
            ),
          );
        }),
      Col('', 110, (m, _) {
        return InkWell(
          onTap: s.busy
              ? null
              : () => setState(() {
                  final answer = hired ? s.fire(m.id) : s.hire(m.id);
                  _message =
                      answer ??
                      (hired
                          ? tr('{0} has been dismissed.', [m.name])
                          : tr('{0} has joined the team.', [m.name]));
                }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              hired ? tr('Dismiss') : tr('Hire'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );
      }),
    ];

    final staffView = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _message ??
                      tr(
                        'Staff costs {0} € a year · coaches speed up development (one per ten riders, currently covered: {1} %), doctors shorten lay-offs, scouts make other teams\' riders assessable, mechanics change wheels faster and prevent defects (quality {2} %), physiotherapists help the riders recover in stage races (quality {3} %).',
                        [
                          euro(book.wages(s.team.id)),
                          (book.coachCover(s.team.id) * 100).round(),
                          (book.mechanicQuality(s.team.id) * 100).round(),
                          (book.physioQuality(s.team.id) * 100).round(),
                        ],
                      ),
                  style: TextStyle(
                    color: _message == null
                        ? TeamColors.muted
                        : TeamColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            flex: 5,
            child: Panel(
              colors: c,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Label(tr('Own staff · {0}', [own.length])),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          [
                            for (final role in StaffRole.values)
                              '${role.plural} ${book.of(s.team.id, role).length}/${StaffBook.limits[role]}',
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: TeamColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: DenseTable<Staff>(
                      colors: c,
                      rows: own,
                      columns: columns(hired: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 4,
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
                        Label(tr('Job market · {0}', [market.length])),
                        const SizedBox(height: 6),
                        Expanded(
                          child: DenseTable<Staff>(
                            colors: c,
                            rows: market,
                            columns: columns(hired: false),
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
    );

    return Column(
      children: [
        TabStrip<_Tab>(
          colors: c,
          tabs: {_Tab.staff: tr('Staff'), _Tab.scouting: 'Scouting'},
          value: _tab,
          onChanged: (t) => setState(() => _tab = t),
        ),
        Expanded(child: _tab == _Tab.staff ? staffView : _Scouting(state: s)),
      ],
    );
  }
}

/// Scouting: standing assignments of the scouts, riders being watched and
/// the reports so far.
class _Scouting extends StatefulWidget {
  const _Scouting({required this.state});
  final AppState state;

  @override
  State<_Scouting> createState() => _ScoutingState();
}

/// State of the assignment form.
class _ScoutingState extends State<_Scouting> {
  int? _scout;
  String? _country;
  var _maxAge = 23;
  String? _kind;
  String? _message;

  static const _kinds = [
    'mountain',
    'hill',
    'timeTrial',
    'sprint',
    'cobble',
    'flat',
  ];

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final book = career.staff;
    final idle = book.idleScouts;
    if (_scout != null && !idle.any((x) => x.id == _scout)) _scout = null;
    _scout ??= idle.firstOrNull?.id;
    final countries = {
      for (final r in career.riderById.values)
        if (r.country.isNotEmpty) r.country,
    }.toList()..sort();
    String date(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
    String stage(int n) => switch (n) {
      1 => tr('first impression'),
      2 => tr('detailed report'),
      _ => tr('tested at the base'),
    };
    final reported = [
      for (final e in book.reports.entries)
        if (career.riderById[e.key] case final r?)
          if (r.teamId != s.team.id) (r, book.stageOf(r.id)),
      for (final id in book.scouted)
        if (career.riderById[id] case final r?)
          if (r.teamId != s.team.id && !book.reports.containsKey(id)) (r, 3),
    ]..sort((a, b) => Economy.rating(b.$1).compareTo(Economy.rating(a.$1)));

    Widget dropdown<T>(
      T value,
      List<(T, String)> items,
      void Function(T) onChanged,
    ) => DropdownButton<T>(
      value: value,
      isDense: true,
      underline: const SizedBox(),
      dropdownColor: c.panel2,
      style: const TextStyle(
        fontFamily: 'Barlow',
        fontSize: 13,
        color: TeamColors.text,
      ),
      onChanged: s.busy ? null : (v) => setState(() => onChanged(v as T)),
      items: [
        for (final (v, label) in items)
          DropdownMenuItem<T>(value: v, child: Text(label)),
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: Panel(
              colors: c,
              child: ListView(
                children: [
                  Label(tr('New assignment')),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      'A scout looks for two months for riders of a country, an age and a kind, and reports on the most promising ones every one to three weeks. How good his choice is depends on his skill.',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: TeamColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (idle.isEmpty)
                    Text(
                      tr('All scouts are on assignment.'),
                      style: const TextStyle(color: TeamColors.muted),
                    )
                  else ...[
                    Row(
                      children: [
                        SizedBox(width: 110, child: Text('Scout')),
                        dropdown<int?>(_scout, [
                          for (final x in idle)
                            (x.id, '${x.name} (${x.skill})'),
                        ], (v) => _scout = v),
                      ],
                    ),
                    Row(
                      children: [
                        SizedBox(width: 110, child: Text(tr('Country'))),
                        dropdown<String?>(_country, [
                          (null, tr('anywhere')),
                          for (final x in countries) (x, x),
                        ], (v) => _country = v),
                      ],
                    ),
                    Row(
                      children: [
                        SizedBox(width: 110, child: Text(tr('Kind'))),
                        dropdown<String?>(_kind, [
                          (null, tr('any')),
                          for (final k in _kinds) (k, tr(Economy.kindLabel(k))),
                        ], (v) => _kind = v),
                      ],
                    ),
                    Row(
                      children: [
                        SizedBox(width: 110, child: Text(tr('Up to age'))),
                        Expanded(
                          child: Slider(
                            value: _maxAge.toDouble(),
                            min: 19,
                            max: 36,
                            divisions: 17,
                            activeColor: c.accent,
                            label: '$_maxAge',
                            onChanged: (v) =>
                                setState(() => _maxAge = v.round()),
                          ),
                        ),
                        SizedBox(width: 30, child: Text('$_maxAge')),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: c.onAccent,
                        ),
                        onPressed: s.busy || _scout == null
                            ? null
                            : () => setState(
                                () => _message =
                                    s.assignScout(
                                      _scout!,
                                      _country,
                                      _maxAge,
                                      _kind,
                                    ) ??
                                    tr('The scout sets out.'),
                              ),
                        child: Text(tr('Send out')),
                      ),
                    ),
                  ],
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_message!),
                    ),
                  const SizedBox(height: 18),
                  Label(tr('Assignments')),
                  const SizedBox(height: 4),
                  if (book.assignments.isEmpty)
                    Text(
                      tr('None.'),
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                  for (final a in book.assignments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('{0}: {1}, up to {2}, {3} · until {4}', [
                                book.all
                                        .where((x) => x.id == a.scoutId)
                                        .firstOrNull
                                        ?.name ??
                                    '',
                                a.country ?? tr('anywhere'),
                                a.maxAge,
                                a.kind == null
                                    ? tr('any')
                                    : tr(Economy.kindLabel(a.kind!)),
                                date(a.until),
                              ]),
                            ),
                          ),
                          TextButton(
                            onPressed: s.busy
                                ? null
                                : () => setState(
                                    () => _message = s.recallScout(a.scoutId),
                                  ),
                            child: Text(tr('Recall')),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  Label(tr('Riders being watched')),
                  const SizedBox(height: 4),
                  if (book.jobs.isEmpty)
                    Text(
                      tr(
                        'Nobody. On the rider page or in the transfer market a scout can be sent to a rider.',
                      ),
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                  for (final j in book.jobs)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(child: Text(career.fullName(j.riderId))),
                          Text(
                            '${stage(j.stage)} · ${tr('until {0}', [date(j.until)])}',
                            style: const TextStyle(color: TeamColors.muted),
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
            flex: 6,
            child: Panel(
              colors: c,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Label(tr('Reports · {0}', [reported.length])),
                  const SizedBox(height: 6),
                  Expanded(
                    child: DenseTable<(SimRider, int)>(
                      colors: c,
                      rows: reported,
                      onTap: (x) => s.openRider(x.$1.id),
                      columns: [
                        Col(
                          'Name',
                          190,
                          (x, _) => cellText(career.fullName(x.$1.id)),
                          sortKey: (x) => x.$1.lastName,
                        ),
                        Col(
                          tr('Age'),
                          46,
                          (x, _) =>
                              cellText('${career.year - x.$1.born ~/ 10000}'),
                          numeric: true,
                          sortKey: (x) => -x.$1.born,
                        ),
                        Col(
                          tr('Team'),
                          70,
                          (x, _) =>
                              cellText(career.teams[x.$1.teamId]?.abbr ?? ''),
                        ),
                        Col(
                          tr('Kind'),
                          120,
                          (x, _) => cellText(
                            tr(Economy.kindLabel(Economy.kindOf(x.$1))),
                          ),
                        ),
                        Col('Strength', 80, (x, _) {
                          final (low, high) = book.range(
                            x.$1.id,
                            'Strength',
                            Economy.rating(x.$1),
                          );
                          return cellText(low == high ? '$low' : '$low–$high');
                        }, sortKey: (x) => Economy.rating(x.$1)),
                        Col(
                          tr('Stage'),
                          150,
                          (x, _) => cellText(
                            stage(x.$2),
                            color: x.$2 >= 3
                                ? TeamColors.green
                                : TeamColors.muted,
                          ),
                          sortKey: (x) => x.$2,
                        ),
                        Col(
                          tr('Contract'),
                          70,
                          (x, _) => cellText(
                            career.economy.expiring(x.$1)
                                ? tr('ending')
                                : '${career.economy.contracts[x.$1.id]?.endYear ?? ''}',
                            color: career.economy.expiring(x.$1)
                                ? TeamColors.gold
                                : null,
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
