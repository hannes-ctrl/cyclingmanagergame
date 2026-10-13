import 'package:sim/sim.dart';
import 'package:flutter/material.dart';
import 'package:game/game.dart';

import '../app_state.dart';
import '../ui.dart';
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
                tr('Kasse'),
                '${euro(eco.balance)} €',
                color: eco.balance < 0 ? TeamColors.red : null,
              ),
              const SizedBox(width: 12),
              figure(
                tr('Sponsorengeld {0}', [career.year]),
                '${euro(eco.budget)} €',
                note: tr('kommt in zwölf Monatsraten'),
              ),
              const SizedBox(width: 12),
              figure(
                tr('Gehälter {0}', [career.year]),
                '${euro(wages)} €',
                note: tr('{0} % des Sponsorengelds', [
                  (100 * wages / eco.budget).round(),
                ]),
              ),
              const SizedBox(width: 12),
              figure(
                tr('Vertrauen der Teamleitung'),
                tr('{0} von 100', [eco.confidence.round()]),
                note: tr('bestimmt, was Sponsoren künftig bieten'),
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
                        Label(tr('Saisonziele {0}', [career.year])),
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
                                    g.achieved() ? tr('ERREICHT') : tr('OFFEN'),
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
                                  tr('Gewicht {0}', [g.weight]),
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
                          tr(
                            'Stand heute: {0} Siege. Die Ziele werden am Jahresende bewertet; der Stand in der Teamrangliste kann sich bis dahin ändern.',
                            [eco.wins],
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            color: TeamColors.muted,
                          ),
                        ),
                        if (career.history.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Label(tr('Bisherige Saisons')),
                          const SizedBox(height: 4),
                          for (final h in career.history.reversed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                tr(
                                  '{0}: Platz {1} der Teamrangliste, {2} Punkte',
                                  [h.year, h.rank, h.points.round()],
                                ),
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
                        Label(tr('Monatsabrechnung')),
                        const SizedBox(height: 6),
                        Expanded(
                          child: eco.ledger.isEmpty
                              ? Center(
                                  child: Text(
                                    tr(
                                      'Die erste Abrechnung kommt am Monatsersten.',
                                    ),
                                    style: TextStyle(color: TeamColors.muted),
                                  ),
                                )
                              : DenseTable<MonthLine>(
                                  colors: c,
                                  rows: eco.ledger.reversed.toList(),
                                  columns: [
                                    Col(
                                      tr('Monat'),
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
                                      tr('Preisgeld'),
                                      80,
                                      (m, _) => cellText(euro(m.prize)),
                                      numeric: true,
                                    ),
                                    Col(
                                      tr('Gehälter'),
                                      80,
                                      (m, _) => cellText(euro(-m.wages)),
                                      numeric: true,
                                    ),
                                    Col(
                                      tr('Betrieb'),
                                      80,
                                      (m, _) => cellText(euro(-m.costs)),
                                      numeric: true,
                                    ),
                                    Col(
                                      tr('Ergebnis'),
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
        Label(tr('Sponsoren')),
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
                tr('{0} € · bis {1}', [
                  euro(sp.amount),
                  contractEnd(sp.endYear),
                ]),
                style: TextStyle(
                  color: sp.endYear == year ? TeamColors.gold : TeamColors.text,
                ),
              ),
            ],
          ),
          Text(
            '${i == 0 ? tr('Hauptsponsor') : tr('Co-Sponsor')}'
            '${sp.demandPlace == null ? '' : tr(' · verlangt Platz {0} der Teamrangliste, sonst ein Fünftel weniger', [sp.demandPlace])}',
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
          if (eco.signed[i] case final next?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('Nachfolge geregelt: {0}, {1} € für {2} Jahre.', [
                  next.name,
                  euro(next.amount),
                  next.years,
                ]),
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
                        '${o.years == 1 ? tr('Jahr') : tr('Jahre')}'
                        '${o.demandPlace == null ? '' : tr(' · verlangt Platz {0}', [o.demandPlace])}',
                      ),
                    ),
                    pill(
                      tr('Annehmen'),
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
                        ? tr(
                            'Die Teamleitung hört sich um; Antwort in einem Monat.',
                          )
                        : tr(
                            'Ohne Wahl schließt die Teamleitung am Jahresende mit dem ersten Angebot ab.',
                          ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: TeamColors.muted,
                    ),
                  ),
                ),
                if (!eco.searches.containsKey(i))
                  pill(
                    tr('Weiter suchen'),
                    s.busy ? null : () => s.searchSponsor(i),
                  ),
              ],
            ),
          ] else if (sp.endYear == year)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                tr('Läuft zum Jahresende aus. Angebote kommen am 1. Juni.'),
                style: TextStyle(fontSize: 12, color: TeamColors.gold),
              ),
            ),
          Divider(height: 18, color: c.line),
        ],
        Text(
          tr(
            'Zusammen {0} € im Jahr. Was neue Sponsoren bieten, hängt vom Vertrauen der Teamleitung ab.',
            [euro(eco.budget)],
          ),
          style: const TextStyle(fontSize: 12, color: TeamColors.muted),
        ),
      ],
    );
  }
}
