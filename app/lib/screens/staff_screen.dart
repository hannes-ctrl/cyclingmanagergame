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
        'Aufgabe',
        150,
        (m, _) => cellText(m.role.label),
        sortKey: (m) => m.role.index,
      ),
      Col('Name', 190, (m, _) => cellText(m.name), sortKey: (m) => m.name),
      skill('Können', (m) => m.skill),
      skill('Rennlesen', (m) => m.second, onlyDirector: true),
      skill('Motivation', (m) => m.third, onlyDirector: true),
      Col(
        'Schwerpunkt',
        110,
        (m, _) => cellText(
          m.role == StaffRole.director ? m.focus.label : '–',
          color: TeamColors.muted,
        ),
      ),
      Col(
        'Gehalt',
        80,
        (m, _) => cellText(euro(m.wage)),
        numeric: true,
        sortKey: (m) => m.wage,
      ),
      if (hired)
        Col('Einsatz', 170, (m, _) {
          if (m.busyUntil?.isAfter(career.today) ?? false) {
            final race = career.calendar
                .where((r) => r.info.id == m.atRace)
                .map((r) => r.info.name)
                .firstOrNull;
            return cellText(race ?? 'im Rennen', color: TeamColors.green);
          }
          if (book.jobs.any((j) => j.scoutId == m.id)) {
            return cellText('auf Beobachtung', color: TeamColors.green);
          }
          return cellText('frei', color: TeamColors.muted);
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
                          ? '${m.name} wurde entlassen.'
                          : '${m.name} gehört jetzt zum Team.');
                }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              hired ? 'Entlassen' : 'Einstellen',
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
                      'Personalkosten ${euro(book.wages(s.team.id))} € im Jahr · '
                          'Trainer beschleunigen die Entwicklung (einer je zehn '
                          'Fahrer, derzeit betreut: '
                          '${(book.coachCover(s.team.id) * 100).round()} %), Ärzte '
                          'verkürzen Ausfälle, Scouts machen fremde Fahrer '
                          'einschätzbar.',
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
                  Label('Eigenes Personal · ${own.length}'),
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
                        Label('Arbeitsmarkt · ${market.length}'),
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
                        const Label('Scouts unterwegs'),
                        const SizedBox(height: 6),
                        if (book.jobs.isEmpty)
                          const Text(
                            'Niemand. Im Transfermarkt einen Fahrer wählen '
                            'und „Beobachten lassen" drücken.',
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
                                  'bis ${j.until.day.toString().padLeft(2, '0')}.'
                                  '${j.until.month.toString().padLeft(2, '0')}.',
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
