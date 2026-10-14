import 'package:sim/sim.dart';
import 'package:flutter/material.dart';
import 'package:game/game.dart';

import '../app_state.dart';
import '../widgets.dart';

/// Staff: the team's employees, the job market and the scouts' running
/// assignments.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.state});
  final AppState state;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

/// State of the screen: the last feedback message.
class _StaffScreenState extends State<StaffScreen> {
  String? _message;

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
          if (book.jobs.any((j) => j.scoutId == m.id)) {
            return cellText(tr('scouting'), color: TeamColors.green);
          }
          return cellText(tr('free'), color: TeamColors.muted);
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

    return Padding(
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
                  Label(tr('Own staff · {0}', [own.length])),
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
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Panel(
                    colors: c,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Label(tr('Scouts on assignment')),
                        const SizedBox(height: 6),
                        if (book.jobs.isEmpty)
                          Text(
                            tr(
                              'Nobody. Select a rider in the transfer market and press "Scout him".',
                            ),
                            style: TextStyle(color: TeamColors.muted),
                          ),
                        for (final j in book.jobs)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(career.fullName(j.riderId)),
                                ),
                                Text(
                                  tr('until {0}.{1}.', [
                                    j.until.day.toString().padLeft(2, '0'),
                                    j.until.month.toString().padLeft(2, '0'),
                                  ]),
                                  style: const TextStyle(
                                    color: TeamColors.muted,
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
    );
  }
}
