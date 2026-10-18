import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'rider_dialog.dart';

/// Development team: squad of the partner team, promoting riders, choosing
/// a partner.
class DevScreen extends StatefulWidget {
  const DevScreen({super.key, required this.state});
  final AppState state;

  @override
  State<DevScreen> createState() => _DevScreenState();
}

/// State of the screen: the last feedback message.
class _DevScreenState extends State<DevScreen> {
  String? _message;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final dev = career.devTeam;
    final eco = career.economy;
    final squad = dev.squad
      ..sort((a, b) => Economy.rating(b).compareTo(Economy.rating(a)));

    Col<SimRider> value(String title, double Function(SimRider) of) => Col(
      title,
      title.length > 4 ? 64 : 46,
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
                      dev.team?.name ?? tr('No development team'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _message ??
                          (dev.teamId == null
                              ? tr(
                                  'Your team has no development team. You can found one: eight young riders without a team, {0} € a year. The link is fixed afterwards.',
                                  [euro(DevTeam.yearlyCost)],
                                )
                              : tr(
                                  '{0} riders · subsidy {1} € a year · riders can be promoted from 1 August, at the market wage. Two talents join every year. The link to the professional team is fixed.',
                                  [squad.length, euro(dev.cost)],
                                )),
                      style: TextStyle(
                        color: _message == null
                            ? TeamColors.muted
                            : TeamColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (dev.canFound) ...[
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
              ),
              onPressed: s.busy
                  ? null
                  : () => setState(
                      () => _message =
                          s.foundDevTeam() ??
                          tr('The development team has been founded.'),
                    ),
              child: Text(tr('Found a development team')),
            ),
          ] else ...[
            const SizedBox(height: 6),
            InfoTip(
              tr(
                'Stagiaires: from 1 August up to {0} riders of the development team may start for the professional team, except in WorldTour races and championships. They stay in the development team. Currently: {1}.',
                [DevTeam.maxStagiaires, dev.stagiaires.length],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: Panel(
              colors: c,
              child: squad.isEmpty
                  ? Center(
                      child: Text(
                        tr(
                          'Without a development team young riders come through the transfer market.',
                        ),
                        style: TextStyle(color: TeamColors.muted),
                      ),
                    )
                  : DenseTable<SimRider>(
                      colors: c,
                      rows: squad,
                      highlight: (r) => dev.promoted(r.id),
                      onTap: (r) => showRiderDialog(context, s, r.id),
                      columns: [
                        Col(
                          tr('Rider'),
                          210,
                          (r, _) => cellText(career.fullName(r.id)),
                          sortKey: (r) => r.lastName,
                        ),
                        Col(
                          tr('Age'),
                          50,
                          (r, _) =>
                              cellText('${career.year - r.born ~/ 10000}'),
                          numeric: true,
                          sortKey: (r) => -r.born,
                        ),
                        Col(tr('Country'), 70, (r, _) => flagCell(r.country)),
                        value(tr('Strength'), Economy.rating),
                        Col(
                          'Pot.',
                          50,
                          (r, _) => cellText(
                            dec(r.potential, 1),
                            color: r.potential >= 5.5
                                ? TeamColors.gold
                                : TeamColors.text,
                          ),
                          numeric: true,
                          sortKey: (r) => r.potential,
                        ),
                        value('FL', (r) => r.attributes.flat),
                        value(tr('MTN'), (r) => r.attributes.mountain),
                        value(tr('HIL'), (r) => r.attributes.hill),
                        value(tr('TT'), (r) => r.attributes.timeTrial),
                        value(tr('COB'), (r) => r.attributes.cobble),
                        value(tr('SPR'), (r) => r.attributes.sprint),
                        Col(
                          tr('Wage in the pro team'),
                          100,
                          (r, _) => cellText(euro(eco.marketWage(r))),
                          numeric: true,
                          sortKey: (r) => eco.marketWage(r),
                        ),
                        Col(tr('Stagiaire'), 130, (r, _) {
                          if (dev.stagiaires.contains(r.id)) {
                            return cellText(
                              tr('Stagiaire'),
                              color: TeamColors.green,
                            );
                          }
                          if (!dev.window(career.today)) {
                            return cellText(
                              tr('from 1 August'),
                              color: TeamColors.muted,
                            );
                          }
                          if (dev.stagiaires.length >= DevTeam.maxStagiaires) {
                            return cellText('–', color: TeamColors.muted);
                          }
                          return InkWell(
                            onTap: s.busy
                                ? null
                                : () => setState(
                                    () => _message =
                                        s.takeStagiaire(r.id) ??
                                        tr(
                                          '{0} rides for the professional team as a stagiaire until the end of the season.',
                                          [career.fullName(r.id)],
                                        ),
                                  ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: c.line),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Text(
                                tr('Take as stagiaire'),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          );
                        }),
                        Col('', 150, (r, _) {
                          final k = eco.contracts[r.id];
                          if (dev.promoted(r.id)) {
                            return cellText(
                              tr('moves up in {0}', [career.year + 1]),
                              color: TeamColors.green,
                            );
                          }
                          if (k?.nextTeam != null) {
                            return cellText(
                              tr('moves to {0}', [
                                career.teams[k!.nextTeam]?.abbr ?? '?',
                              ]),
                              color: TeamColors.muted,
                            );
                          }
                          return InkWell(
                            onTap: s.busy
                                ? null
                                : () => setState(
                                    () => _message =
                                        s.promote(r.id) ??
                                        tr(
                                          '{0} moves up to the professional team next season.',
                                          [career.fullName(r.id)],
                                        ),
                                  ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: c.line),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Text(
                                tr('Promote'),
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
