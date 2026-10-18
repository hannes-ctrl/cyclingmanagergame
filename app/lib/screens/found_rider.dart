import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';

/// The profile of a rider as the world database has him, for the team
/// builder: photo, body, potential, attributes and what he would cost.
///
/// @param context Build context.
/// @param s Application state.
/// @param r The rider as the world database has him.
/// @param name His full name.
/// @param team His team in the database, or null without one.
/// @returns A future that completes when the dialog is closed.
Future<void> showFoundRider(
  BuildContext context,
  AppState s,
  SimRider r,
  String name,
  TeamInfo? team,
) {
  final c = s.colors;
  final a = r.attributes;
  final age = s.career.year - r.born ~/ 10000;
  final values = <(String, double)>[
    (tr('Flat'), a.flat),
    (tr('Mountain'), a.mountain),
    (tr('Medium mountain'), a.mediumMountain),
    (tr('Hill'), a.hill),
    (tr('Time trial'), a.timeTrial),
    (tr('Prologue'), a.prologue),
    (tr('Cobbles'), a.cobble),
    (tr('Sprint'), a.sprint),
    (tr('Acceleration'), a.acceleration),
    (tr('Downhill'), a.downhill),
    (tr('Breakaway'), a.breakaway),
    (tr('Stamina'), a.endurance),
    (tr('Resistance'), a.resistance),
    (tr('Recovery'), a.recovery),
  ];
  Widget fact(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: TeamColors.muted)),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: c.panel,
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  RiderPhoto(dataDir: s.dataDir, riderId: r.id, size: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: headStyle(22)),
                        Row(
                          children: [
                            Flag(r.country, width: 20),
                            const SizedBox(width: 6),
                            Text(
                              '${team?.name ?? tr('Free agent')} · '
                              '${tr(riderType(r))}',
                              style: const TextStyle(color: TeamColors.muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        fact(tr('Age'), '$age'),
                        fact(tr('Height'), '${r.heightCm.round()} cm'),
                        fact(tr('Weight'), '${r.weightKg.round()} kg'),
                        fact(tr('Strength'), dec(Economy.rating(r))),
                        fact(tr('Potential'), dec(r.potential)),
                        fact(
                          tr('Wage'),
                          '${euro(s.career.economy.marketWage(r))} €',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      children: [
                        for (final (label, v) in values)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: TeamColors.muted,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${v.round()}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: attributeColor(v),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Close')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
