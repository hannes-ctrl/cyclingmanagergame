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
                      dev.team?.name ?? tr('Kein Nachwuchsteam'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _message ??
                          (dev.teamId == null
                              ? tr(
                                  'Dein Team hat kein Nachwuchsteam. Du kannst eines gründen: acht junge Fahrer ohne Team, {0} € im Jahr. Die Zuordnung ist danach fest.',
                                  [euro(DevTeam.yearlyCost)],
                                )
                              : tr(
                                  '{0} Fahrer · Zuschuss {1} € im Jahr · Hochziehen geht ab dem 1. August, zum marktüblichen Gehalt. Jedes Jahr kommen zwei Talente dazu. Die Zuordnung zum Profiteam ist fest.',
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
                          tr('Das Nachwuchsteam ist gegründet.'),
                    ),
              child: Text(tr('Nachwuchsteam gründen')),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              tr(
                'Stagiaires: Ab dem 1. August dürfen bis zu {0} Fahrer des Nachwuchsteams für das Profiteam starten, außer bei WorldTour-Rennen und Meisterschaften. Sie bleiben im Nachwuchsteam. Derzeit: {1}.',
                [DevTeam.maxStagiaires, dev.stagiaires.length],
              ),
              style: const TextStyle(fontSize: 12, color: TeamColors.muted),
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
                          'Ohne Nachwuchsteam kommen junge Fahrer über den Transfermarkt.',
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
                          tr('Fahrer'),
                          210,
                          (r, _) => cellText(career.fullName(r.id)),
                          sortKey: (r) => r.lastName,
                        ),
                        Col(
                          tr('Alter'),
                          50,
                          (r, _) =>
                              cellText('${career.year - r.born ~/ 10000}'),
                          numeric: true,
                          sortKey: (r) => -r.born,
                        ),
                        Col(tr('Land'), 70, (r, _) => flagCell(r.country)),
                        value(tr('Stärke'), Economy.rating),
                        Col(
                          'Pot.',
                          50,
                          (r, _) => cellText(
                            r.potential.toStringAsFixed(1),
                            color: r.potential >= 5.5
                                ? TeamColors.gold
                                : TeamColors.text,
                          ),
                          numeric: true,
                          sortKey: (r) => r.potential,
                        ),
                        value('FL', (r) => r.attributes.flat),
                        value(tr('BG'), (r) => r.attributes.mountain),
                        value(tr('HÜ'), (r) => r.attributes.hill),
                        value(tr('ZF'), (r) => r.attributes.timeTrial),
                        value(tr('KO'), (r) => r.attributes.cobble),
                        value(tr('SP'), (r) => r.attributes.sprint),
                        Col(
                          tr('Gehalt oben'),
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
                              tr('ab 1. August'),
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
                                          '{0} fährt bis zum Saisonende als Stagiaire für das Profiteam.',
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
                                tr('Als Stagiaire holen'),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          );
                        }),
                        Col('', 150, (r, _) {
                          final k = eco.contracts[r.id];
                          if (dev.promoted(r.id)) {
                            return cellText(
                              tr('rückt {0} auf', [career.year + 1]),
                              color: TeamColors.green,
                            );
                          }
                          if (k?.nextTeam != null) {
                            return cellText(
                              tr('wechselt zu {0}', [
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
                                          '{0} rückt zur nächsten Saison ins Profiteam auf.',
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
                                tr('Hochziehen'),
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
