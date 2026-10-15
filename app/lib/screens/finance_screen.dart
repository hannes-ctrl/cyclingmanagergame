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
                tr('Balance'),
                '${euro(eco.balance)} €',
                color: eco.balance < 0 ? TeamColors.red : null,
              ),
              const SizedBox(width: 12),
              figure(
                tr('Sponsor money {0}', [career.year]),
                '${euro(eco.budget)} €',
                note: tr('arrives in twelve monthly instalments'),
              ),
              const SizedBox(width: 12),
              figure(
                tr('Wages {0}', [career.year]),
                '${euro(wages)} €',
                note: tr('{0} % of the sponsor money', [
                  (100 * wages / eco.budget).round(),
                ]),
              ),
              const SizedBox(width: 12),
              figure(
                tr('Board confidence'),
                tr('{0} of 100', [eco.confidence.round()]),
                note: tr('decides what sponsors will offer in future'),
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
                        Label(tr('Season goals {0}', [career.year])),
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
                                    g.achieved() ? tr('ACHIEVED') : tr('OPEN'),
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
                                  tr('Weight {0}', [g.weight]),
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
                            'As of today: {0} wins. The goals are assessed at the end of the year; the place in the team ranking can still change until then.',
                            [eco.wins],
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            color: TeamColors.muted,
                          ),
                        ),
                        if (career.history.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Label(tr('Past seasons')),
                          const SizedBox(height: 4),
                          for (final h in career.history.reversed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                tr(
                                  '{0}: place {1} in the team ranking, {2} points',
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
                        Label(tr('Monthly statement')),
                        const SizedBox(height: 6),
                        Expanded(
                          child: eco.ledger.isEmpty
                              ? Center(
                                  child: Text(
                                    tr(
                                      'The first statement arrives on the first of the month.',
                                    ),
                                    style: TextStyle(color: TeamColors.muted),
                                  ),
                                )
                              : DenseTable<MonthLine>(
                                  colors: c,
                                  rows: eco.ledger.reversed.toList(),
                                  columns: [
                                    Col(
                                      tr('Month'),
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
                                      tr('Prize money'),
                                      80,
                                      (m, _) => cellText(euro(m.prize)),
                                      numeric: true,
                                    ),
                                    Col(
                                      tr('Wages'),
                                      80,
                                      (m, _) => cellText(euro(-m.wages)),
                                      numeric: true,
                                    ),
                                    Col(
                                      tr('Operations'),
                                      80,
                                      (m, _) => cellText(euro(-m.costs)),
                                      numeric: true,
                                    ),
                                    Col(
                                      tr('Result'),
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
        Label(tr('Sponsors')),
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
                tr('{0} € · until {1}', [
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
            '${i == 0 ? tr('Main sponsor') : tr('Co-sponsor')}'
            '${sp.demandPlace == null ? '' : tr(' · requires place {0} in the team ranking, otherwise a fifth less', [sp.demandPlace])}',
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
          if (eco.signed[i] case final next?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('Successor settled: {0}, {1} € for {2} years.', [
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
                        '${o.years == 1 ? tr('Year') : tr('years')}'
                        '${o.demandPlace == null ? '' : tr(' · requires place {0}', [o.demandPlace])}',
                      ),
                    ),
                    pill(
                      tr('Accept'),
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
                        ? tr('The board is asking around; answer in a month.')
                        : tr(
                            'Without a choice the board signs the first offer at the end of the year.',
                          ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: TeamColors.muted,
                    ),
                  ),
                ),
                if (!eco.searches.containsKey(i))
                  pill(
                    tr('Keep searching'),
                    s.busy ? null : () => s.searchSponsor(i),
                  ),
              ],
            ),
          ] else if (sp.endYear == year)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                tr('Expires at the end of the year. Offers arrive on 1 June.'),
                style: TextStyle(fontSize: 12, color: TeamColors.gold),
              ),
            ),
          Divider(height: 18, color: c.line),
        ],
        Text(
          tr(
            '{0} € a year in total. What new sponsors offer depends on the board\'s confidence.',
            [euro(eco.budget)],
          ),
          style: const TextStyle(fontSize: 12, color: TeamColors.muted),
        ),
        const SizedBox(height: 18),
        _Equipment(state: s, pill: pill),
        const SizedBox(height: 6),
        _Facilities(state: s, pill: pill),
      ],
    );
  }
}

/// Bike and tyre suppliers of the team, and the offers while the contracts
/// run out.
class _Equipment extends StatelessWidget {
  const _Equipment({required this.state, required this.pill});
  final AppState state;
  final Widget Function(String label, VoidCallback? onTap) pill;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = s.colors;
    final career = s.career;
    final eq = career.equipment;
    final supply = eq.supplyOf(career.teamId);
    String stars(double q) =>
        '★' * (1 + (q * 4).round()) + '☆' * (4 - (q * 4).round());
    String bike(BikeBrand b) => tr('{0} bikes {1}', [b.name, stars(b.quality)]);
    String tyres(TyreBrand b) =>
        tr('{0} tyres {1}', [b.name, stars(b.quality)]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Label(tr('Material')),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                '${bike(supply.bike)} · ${tyres(supply.tyres)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              tr('{0} € · until {1}', [
                euro(supply.fee),
                contractEnd(supply.until),
              ]),
              style: TextStyle(
                color: supply.until == career.year
                    ? TeamColors.gold
                    : TeamColors.text,
              ),
            ),
          ],
        ),
        Text(
          tr(
            'The suppliers pay for being on the team\'s bikes and lower the cost of material. Better bikes are more aerodynamic or lighter, better tyres roll more easily or puncture less; the difference between the best and the weakest is about a second per kilometre in a time trial.',
          ),
          style: const TextStyle(fontSize: 12, color: TeamColors.muted),
        ),
        if (eq.accepted case final o?)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr('From next season: {0} and {1}, {2} € a year for {3} years.', [
                o.bike.name,
                o.tyres.name,
                euro(o.fee),
                o.years,
              ]),
              style: const TextStyle(color: TeamColors.green),
            ),
          )
        else if (eq.offers.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final (i, o) in eq.offers.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${bike(o.bike)} · ${tyres(o.tyres)} · ${euro(o.fee)} € · ${o.years} '
                      '${o.years == 1 ? tr('Year') : tr('years')}',
                    ),
                  ),
                  pill(tr('Accept'), s.busy ? null : () => s.acceptSupply(i)),
                ],
              ),
            ),
          Text(
            tr('Without a choice the board renews with the current suppliers.'),
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
        ] else if (supply.until == career.year)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr(
                'Expires at the end of the year. Offers arrive on 1 September.',
              ),
              style: const TextStyle(fontSize: 12, color: TeamColors.gold),
            ),
          ),
        Divider(height: 18, color: c.line),
      ],
    );
  }
}

/// The team's facilities: levels, what they do, and building them up.
class _Facilities extends StatefulWidget {
  const _Facilities({required this.state, required this.pill});
  final AppState state;
  final Widget Function(String label, VoidCallback? onTap) pill;

  @override
  State<_Facilities> createState() => _FacilitiesState();
}

class _FacilitiesState extends State<_Facilities> {
  String? _answer;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final fac = career.facilities;
    final building = fac.building;
    String day(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Label(tr('Facilities')),
        const SizedBox(height: 6),
        // Name, level as five dots and the action on one line, what a
        // level does below it.
        for (final f in Facility.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        f.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    for (var i = 1; i <= Facilities.maxLevel; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i <= fac.level(career.teamId, f)
                                ? TeamColors.gold
                                : null,
                            border: Border.all(color: c.line),
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    if (building?.facility == f)
                      Text(
                        tr('ready on {0}', [day(building!.ready)]),
                        style: const TextStyle(
                          fontSize: 12,
                          color: TeamColors.green,
                        ),
                      )
                    else if (fac.upgradeCost(f) case final cost?)
                      widget.pill(
                        tr('Expand · {0} €', [euro(cost)]),
                        s.busy || building != null
                            ? null
                            : () => setState(
                                () => _answer = s.upgradeFacility(f),
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  f.effect,
                  style: const TextStyle(fontSize: 12, color: TeamColors.muted),
                ),
              ],
            ),
          ),
        Text(
          _answer ??
              tr(
                'Level 3 is the average of the peloton. Running all facilities costs {0} € a year; a new level takes some months to build.',
                [euro(fac.upkeep(career.teamId))],
              ),
          style: TextStyle(
            fontSize: 12,
            color: _answer == null ? TeamColors.muted : TeamColors.gold,
          ),
        ),
        Divider(height: 18, color: c.line),
      ],
    );
  }
}
