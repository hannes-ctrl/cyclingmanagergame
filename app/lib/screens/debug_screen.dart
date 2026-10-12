import 'package:flutter/material.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

/// Debug page, shown only in debug mode: the inner state of the career, the
/// tuning values of the simulation and a few actions that help testing.
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key, required this.state});
  final AppState state;

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

/// State of the page: the last feedback message.
class _DebugScreenState extends State<DebugScreen> {
  String? _message;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final eco = career.economy;
    final running = career.progress.values.where((p) => !p.finished).length;
    final injured = [
      for (final r in s.squad)
        if (career.isInjured(r.id, career.today)) r,
    ];

    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: TeamColors.muted)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    Widget action(String label, String hint, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 250,
            child: OutlinedButton(
              onPressed: s.busy ? null : onTap,
              child: Text(label),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(hint, style: const TextStyle(color: TeamColors.muted)),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(
                  colors: c,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Label(tr('Karriere')),
                      const SizedBox(height: 4),
                      fact(tr('Startwert (Seed)'), '${career.seed}'),
                      fact(tr('Team-ID'), '${s.team.id}'),
                      fact(
                        tr('Fahrer in der Welt'),
                        '${career.riderById.length}',
                      ),
                      fact(tr('Teams'), '${career.teams.length}'),
                      fact(
                        tr('Rennen im Kalender'),
                        '${career.calendar.length}',
                      ),
                      fact(
                        tr('Gestartete Rennen'),
                        '${career.progress.length} ($running ${tr('läuft')})',
                      ),
                      fact(tr('Nachrichten'), '${career.inbox.length}'),
                      fact(tr('Kasse'), '${eco.balance.round()} €'),
                      fact(
                        tr('Nachwuchsteam'),
                        '${career.devTeam.team?.abbr ?? '–'} · '
                        '${career.devTeam.links.length} ${tr('Partnerschaften')}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Panel(
                    colors: c,
                    child: ListView(
                      children: [
                        Label(tr('Aktionen zum Testen')),
                        const SizedBox(height: 8),
                        action(
                          tr('Bis zum Saisonende simulieren'),
                          tr(
                            'Ohne Halt; der Sportliche Leiter übernimmt Aufgebote und Funk.',
                          ),
                          () => s.simulateUntil(
                            DateTime.utc(career.year, 12, 31),
                            auto: true,
                          ),
                        ),
                        action(
                          tr('Einen Monat simulieren'),
                          tr('Ohne Halt, 30 Tage.'),
                          () => s.simulateUntil(
                            career.today.add(const Duration(days: 30)),
                            auto: true,
                          ),
                        ),
                        action(
                          tr('1 Mio. € gutschreiben'),
                          tr('Erhöht die Kasse, ohne Buchung.'),
                          () => setState(() {
                            s.debugMoney(1000000);
                            _message = tr('Gutgeschrieben.');
                          }),
                        ),
                        action(
                          tr('Alle Fahrer gesund'),
                          tr('{0} Fahrer des Teams fallen derzeit aus.', [
                            injured.length,
                          ]),
                          () => setState(() {
                            s.debugHeal();
                            _message = tr('Alle wieder einsatzbereit.');
                          }),
                        ),
                        if (_message != null) Text(_message!),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            'Im Debug-Modus sind außerdem alle Fahrerwerte genau (keine Scouting-Spannen), das Fahrerprofil zeigt interne Größen, und der Rennplaner nennt die Wildcard-Chance in Prozent.',
                          ),
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
                  Label(
                    tr('Stellschrauben der Simulation · {0}', [
                      SimTuning.params.length,
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: DenseTable<TuningParam>(
                      colors: c,
                      rows: SimTuning.params,
                      columns: [
                        Col(
                          tr('Name'),
                          190,
                          (p, _) => cellText(p.name),
                          sortKey: (p) => p.name,
                        ),
                        Col(
                          tr('Wert'),
                          80,
                          (p, _) => cellText(
                            (s.tuning.toMap()[p.name] ?? p.standard)
                                .toStringAsFixed(3),
                          ),
                          numeric: true,
                        ),
                        Col(
                          tr('Bereich'),
                          110,
                          (p, _) => cellText(
                            '${p.min} – ${p.max}',
                            color: TeamColors.muted,
                          ),
                          numeric: true,
                        ),
                        Col(
                          tr('Bedeutung'),
                          520,
                          (p, _) =>
                              cellText(p.meaning, color: TeamColors.muted),
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
