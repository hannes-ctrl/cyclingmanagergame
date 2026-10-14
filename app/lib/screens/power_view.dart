import 'package:flutter/material.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

/// What the power meters of a stage showed: per rider average and
/// normalised power, work, the time in each power zone and the effort on
/// every climb. The player's riders come first, then the first ten.
class PowerView extends StatelessWidget {
  const PowerView({
    super.key,
    required this.result,
    required this.teamId,
    required this.colors,
  });

  final StageResult result;
  final int teamId;
  final TeamColors colors;

  /// Colours of the six zones, from easy to flat out.
  static const _zoneColors = [
    Color(0xFF6E7191),
    Color(0xFF4F8FD8),
    Color(0xFF3FAE73),
    Color(0xFFE2B33A),
    Color(0xFFE07A33),
    Color(0xFFD9423C),
  ];

  static const _zoneNames = [
    'Recovery',
    'Endurance',
    'Tempo',
    'Threshold',
    'VO2max',
    'Anaerobic',
  ];

  @override
  Widget build(BuildContext context) {
    final placeOf = {
      for (var i = 0; i < result.placings.length; i++)
        result.placings[i].rider.id: i,
    };
    final riders =
        [
          for (final p in result.placings)
            if (result.power.containsKey(p.rider.id)) p.rider,
        ]..sort((a, b) {
          final own =
              (b.teamId == teamId ? 1 : 0) - (a.teamId == teamId ? 1 : 0);
          return own != 0 ? own : placeOf[a.id]!.compareTo(placeOf[b.id]!);
        });
    String number(double v) => v.round().toString();
    String decimal(double v) => dec(v, 1);

    Widget zones(PowerStats p) {
      final total = p.zones.fold(0.0, (s, z) => s + z);
      if (total <= 0) return const SizedBox();
      return Tooltip(
        message: [
          for (var z = 0; z < 6; z++)
            '${tr(_zoneNames[z])}: ${(100 * p.zones[z] / total).round()} %',
        ].join('\n'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 6,
            child: Row(
              children: [
                for (var z = 0; z < 6; z++)
                  if (p.zones[z] > 0)
                    Expanded(
                      flex: (1000 * p.zones[z] / total).round().clamp(1, 1000),
                      child: Container(color: _zoneColors[z]),
                    ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(
            'What the power meters showed. NP is the normalised power, which weighs hard efforts as the body feels them; IF is NP relative to the threshold at the start. The bar shows the time in the six zones from recovery to anaerobic.',
          ),
          style: const TextStyle(fontSize: 12, color: TeamColors.muted),
        ),
        const SizedBox(height: 10),
        for (final r in riders)
          Builder(
            builder: (context) {
              final p = result.power[r.id]!;
              final place = placeOf[r.id]! + 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            '$place.',
                            style: const TextStyle(color: TeamColors.muted),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            r.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: r.teamId == teamId
                                  ? colors.accent
                                  : TeamColors.text,
                            ),
                          ),
                        ),
                        Text(
                          tr('{0} W · {1} W/kg · NP {2} W · IF {3} · {4} kJ', [
                            number(p.averageW),
                            decimal(p.averageWkg),
                            number(p.normalizedW),
                            dec(p.intensity, 2),
                            number(p.kilojoules),
                          ]),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 30),
                      child: zones(p),
                    ),
                    for (final climb in p.climbs)
                      Padding(
                        padding: const EdgeInsets.only(left: 30, top: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${climb.name} (km ${climb.topKm.round()})',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: TeamColors.muted,
                                ),
                              ),
                            ),
                            Text(
                              tr('{0} W/kg · VAM {1} · {2}', [
                                decimal(climb.averageWkg),
                                number(climb.vam),
                                clock(climb.seconds),
                              ]),
                              style: const TextStyle(
                                fontSize: 12,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
