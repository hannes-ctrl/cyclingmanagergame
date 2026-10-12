import 'package:flutter/material.dart';
import 'package:game/game.dart';

import '../app_state.dart';
import '../widgets.dart';

/// Finances and season goals: balance, budget, monthly statement, confidence.
class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = state.colors;
    final career = state.career;
    final eco = career.economy;
    final wages = eco.wageBill(state.team.id);

    Widget figure(String label, String value, {String? note, Color? color}) =>
        Expanded(
          child: Panel(
            colors: c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Label(label),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: color ?? TeamColors.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (note != null)
                  Text(
                    note,
                    style: const TextStyle(
                      fontSize: 12,
                      color: TeamColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              figure(
                'Kasse',
                '${euro(eco.balance)} €',
                color: eco.balance < 0 ? TeamColors.red : null,
              ),
              const SizedBox(width: 12),
              figure(
                'Sponsorengeld ${career.year}',
                '${euro(eco.budget)} €',
                note: 'kommt in zwölf Monatsraten',
              ),
              const SizedBox(width: 12),
              figure(
                'Gehälter ${career.year}',
                '${euro(wages)} €',
                note:
                    '${(100 * wages / eco.budget).round()} % des Sponsorengelds',
              ),
              const SizedBox(width: 12),
              figure(
                'Vertrauen der Teamleitung',
                '${eco.confidence.round()} von 100',
                note: 'bestimmt, was Sponsoren künftig bieten',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Panel(
                    colors: c,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Label('Saisonziele ${career.year}'),
                        const SizedBox(height: 8),
                        for (final g in eco.goals)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Container(
                                  width: 78,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 1,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: g.achieved()
                                          ? TeamColors.green
                                          : TeamColors.gold,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    g.achieved() ? 'ERREICHT' : 'OFFEN',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.6,
                                      color: g.achieved()
                                          ? TeamColors.green
                                          : TeamColors.gold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(g.text)),
                                Text(
                                  'Gewicht ${g.weight}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: TeamColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          'Stand heute: ${eco.wins} Siege. '
                          'Die Ziele werden am Jahresende bewertet; der Stand '
                          'in der Teamrangliste kann sich bis dahin ändern.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: TeamColors.muted,
                          ),
                        ),
                        if (career.history.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Label('Bisherige Saisons'),
                          const SizedBox(height: 4),
                          for (final h in career.history.reversed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '${h.year}: Platz ${h.rank} der Teamrangliste, '
                                '${h.points.round()} Punkte',
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Panel(
                    colors: c,
                    child: _Sponsors(state: state),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Panel(
                    colors: c,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Label('Monatsabrechnung'),
                        const SizedBox(height: 6),
                        Expanded(
                          child: eco.ledger.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Die erste Abrechnung kommt am Monatsersten.',
                                    style: TextStyle(color: TeamColors.muted),
                                  ),
                                )
                              : DenseTable<MonthLine>(
                                  colors: c,
                                  rows: eco.ledger.reversed.toList(),
                                  columns: [
                                    Col(
                                      'Monat',
                                      80,
                                      (m, _) => cellText(
                                        '${m.month.month.toString().padLeft(2, '0')}.${m.month.year}',
                                      ),
                                    ),
                                    Col(
                                      'Sponsor',
                                      80,
                                      (m, _) => cellText(euro(m.sponsor)),
                                      numeric: true,
                                    ),
                                    Col(
                                      'Preisgeld',
                                      80,
                                      (m, _) => cellText(euro(m.prize)),
                                      numeric: true,
                                    ),
                                    Col(
                                      'Gehälter',
                                      80,
                                      (m, _) => cellText(euro(-m.wages)),
                                      numeric: true,
                                    ),
                                    Col(
                                      'Betrieb',
                                      80,
                                      (m, _) => cellText(euro(-m.costs)),
                                      numeric: true,
                                    ),
                                    Col(
                                      'Ergebnis',
                                      100,
                                      (m, _) => cellText(
                                        euro(m.result),
                                        color: m.result < 0
                                            ? TeamColors.red
                                            : TeamColors.green,
                                        bold: true,
                                      ),
                                      numeric: true,
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

/// Sponsor contracts and, when one runs out, the offers for what follows.
class _Sponsors extends StatelessWidget {
  const _Sponsors({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = s.colors;
    final eco = s.career.economy;
    final year = s.career.year;

    Widget pill(String label, VoidCallback? onTap) => InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );

    return ListView(
      children: [
        const Label('Sponsoren'),
        const SizedBox(height: 6),
        for (final (i, sp) in eco.sponsors.indexed) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  sp.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${euro(sp.amount)} € · bis ${sp.endYear}',
                style: TextStyle(
                  color: sp.endYear == year ? TeamColors.gold : TeamColors.text,
                ),
              ),
            ],
          ),
          Text(
            '${i == 0 ? 'Hauptsponsor' : 'Co-Sponsor'}'
            '${sp.demandPlace == null ? '' : ' · verlangt Platz ${sp.demandPlace} der Teamrangliste, sonst ein Fünftel weniger'}',
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
          if (eco.signed[i] case final next?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Nachfolge geregelt: ${next.name}, ${euro(next.amount)} € '
                'für ${next.years} Jahre.',
                style: const TextStyle(color: TeamColors.green),
              ),
            )
          else if (eco.offers[i] case final list?) ...[
            const SizedBox(height: 4),
            for (final (k, o) in list.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${o.name}: ${euro(o.amount)} € · ${o.years} '
                        '${o.years == 1 ? 'Jahr' : 'Jahre'}'
                        '${o.demandPlace == null ? '' : ' · verlangt Platz ${o.demandPlace}'}',
                      ),
                    ),
                    pill(
                      'Annehmen',
                      s.busy ? null : () => s.acceptSponsor(i, k),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    eco.searches.containsKey(i)
                        ? 'Die Teamleitung hört sich um; Antwort in einem Monat.'
                        : 'Ohne Wahl schließt die Teamleitung am Jahresende '
                              'mit dem ersten Angebot ab.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: TeamColors.muted,
                    ),
                  ),
                ),
                if (!eco.searches.containsKey(i))
                  pill(
                    'Weiter suchen',
                    s.busy ? null : () => s.searchSponsor(i),
                  ),
              ],
            ),
          ] else if (sp.endYear == year)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Läuft zum Jahresende aus. Angebote kommen am 1. Juni.',
                style: TextStyle(fontSize: 12, color: TeamColors.gold),
              ),
            ),
          Divider(height: 18, color: c.line),
        ],
        Text(
          'Zusammen ${euro(eco.budget)} € im Jahr. Was neue Sponsoren '
          'bieten, hängt vom Vertrauen der Teamleitung ab.',
          style: const TextStyle(fontSize: 12, color: TeamColors.muted),
        ),
      ],
    );
  }
}
