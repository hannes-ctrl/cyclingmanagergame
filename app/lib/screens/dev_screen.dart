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
                      dev.team?.name ?? 'Kein Nachwuchsteam',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _message ??
                          (dev.teamId == null
                              ? 'Dein Team hat kein Nachwuchsteam. Die Zuordnung '
                                    'ist fest: Ein Nachwuchsteam gehört zu genau '
                                    'einem Profiteam.'
                              : '${squad.length} Fahrer · Zuschuss ${euro(dev.cost)} € im Jahr · '
                                    'Hochziehen geht ab dem 1. August, zum marktüblichen Gehalt. '
                                    'Jedes Jahr kommen zwei Talente dazu. Die Zuordnung zum '
                                    'Profiteam ist fest.'),
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
          const SizedBox(height: 12),
          Expanded(
            child: Panel(
              colors: c,
              child: squad.isEmpty
                  ? const Center(
                      child: Text(
                        'Ohne Nachwuchsteam kommen junge Fahrer über den Transfermarkt.',
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
                          'Fahrer',
                          210,
                          (r, _) => cellText(career.fullName(r.id)),
                          sortKey: (r) => r.lastName,
                        ),
                        Col(
                          'Alter',
                          50,
                          (r, _) =>
                              cellText('${career.year - r.born ~/ 10000}'),
                          numeric: true,
                          sortKey: (r) => -r.born,
                        ),
                        Col('Land', 70, (r, _) => flagCell(r.country)),
                        value('Stärke', Economy.rating),
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
                        value('BG', (r) => r.attributes.mountain),
                        value('HÜ', (r) => r.attributes.hill),
                        value('ZF', (r) => r.attributes.timeTrial),
                        value('KO', (r) => r.attributes.cobble),
                        value('SP', (r) => r.attributes.sprint),
                        Col(
                          'Gehalt oben',
                          100,
                          (r, _) => cellText(euro(eco.marketWage(r))),
                          numeric: true,
                          sortKey: (r) => eco.marketWage(r),
                        ),
                        Col('', 150, (r, _) {
                          final k = eco.contracts[r.id];
                          if (dev.promoted(r.id)) {
                            return cellText(
                              'rückt ${career.year + 1} auf',
                              color: TeamColors.green,
                            );
                          }
                          if (k?.nextTeam != null) {
                            return cellText(
                              'wechselt zu ${career.teams[k!.nextTeam]?.abbr ?? '?'}',
                              color: TeamColors.muted,
                            );
                          }
                          return InkWell(
                            onTap: s.busy
                                ? null
                                : () => setState(
                                    () => _message =
                                        s.promote(r.id) ??
                                        '${career.fullName(r.id)} rückt zur '
                                            'nächsten Saison ins Profiteam auf.',
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
                              child: const Text(
                                'Hochziehen',
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
