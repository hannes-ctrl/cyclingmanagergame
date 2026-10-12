import 'package:flutter/material.dart';
import 'package:game/game.dart';

import '../app_state.dart';
import '../widgets.dart';

/// Season plan as a matrix of riders and the team's races. A click pencils
/// a rider in for a race; the sports director suggests pencilled-in riders
/// first when a line-up is due.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.state});
  final AppState state;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

/// State of the matrix: scroll position and the tier filter.
class _PlanScreenState extends State<PlanScreen> {
  final _horizontal = ScrollController();
  var _onlyBig = true;

  static const _cell = 26.0;
  static const _rowHeight = 24.0;
  static const _nameWidth = 190.0;
  static const _headHeight = 150.0;

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  Color _tierColor(RaceTier tier) => switch (tier) {
    RaceTier.grandTour => TeamColors.gold,
    RaceTier.monument => TeamColors.red,
    RaceTier.worldTour => const Color(0xFF6DB3FF),
    _ => TeamColors.muted,
  };

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final races = [
      for (final r in career.ownRaces)
        if (!_onlyBig || r.tier.factor >= 5) r,
    ];
    final squad = s.squad;
    int size(RaceEntry r) => career.world.raceField(r.info.id).ridersPerTeam;
    final sizes = {for (final r in races) r.info.id: size(r)};

    int plannedDays(int riderId) {
      var days = 0;
      for (final r in career.ownRaces) {
        if (career.progress.containsKey(r.info.id)) continue;
        if (career.program[r.info.id]?.contains(riderId) ?? false) {
          days += r.stages.length;
        }
      }
      return days;
    }

    Widget header(RaceEntry r) {
      final planned = career.program[r.info.id]?.length ?? 0;
      final started = career.progress.containsKey(r.info.id);
      final full = planned >= sizes[r.info.id]!;
      return SizedBox(
        width: _cell,
        height: _headHeight,
        child: Column(
          children: [
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${r.start.day.toString().padLeft(2, '0')}.'
                    '${r.start.month.toString().padLeft(2, '0')}.  ${r.info.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: started ? TeamColors.muted : TeamColors.text,
                    ),
                  ),
                ),
              ),
            ),
            Container(height: 3, width: _cell - 4, color: _tierColor(r.tier)),
            SizedBox(
              height: 20,
              child: Center(
                child: Text(
                  started ? '–' : '$planned',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: started
                        ? TeamColors.muted
                        : full
                        ? TeamColors.green
                        : planned > 0
                        ? TeamColors.gold
                        : TeamColors.muted,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget cell(RaceEntry r, int riderId) {
      final id = r.info.id;
      final p = career.progress[id];
      final rode = p?.riders.any((x) => x.id == riderId) ?? false;
      final planned = career.program[id]?.contains(riderId) ?? false;
      final locked = p != null;
      return InkWell(
        onTap: locked ? null : () => s.toggleProgram(id, riderId),
        child: Container(
          width: _cell,
          height: _rowHeight,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: c.line, width: 0.5),
              bottom: BorderSide(color: c.line, width: 0.5),
            ),
            color: rode
                ? c.panel2
                : planned
                ? _tierColor(r.tier).withValues(alpha: 0.85)
                : null,
          ),
          child: rode
              ? const Center(
                  child: Text(
                    '•',
                    style: TextStyle(color: TeamColors.muted, fontSize: 14),
                  ),
                )
              : null,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Klick auf ein Feld trägt den Fahrer für das Rennen ein. '
                  'Beim Aufgebot schlägt der Sportliche Leiter eingetragene Fahrer zuerst vor. '
                  'Die Zahl unter dem Rennen zeigt, wie viele eingetragen sind.',
                  style: const TextStyle(color: TeamColors.muted),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Nur WorldTour', style: TextStyle(fontSize: 13)),
              Switch(
                value: _onlyBig,
                activeThumbColor: c.accent,
                onChanged: (v) => setState(() => _onlyBig = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Panel(
              colors: c,
              padding: 0,
              child: SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _nameWidth + 60,
                      child: Column(
                        children: [
                          SizedBox(
                            height: _headHeight,
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 0, 8, 4),
                                child: Row(
                                  children: const [
                                    Expanded(child: Label('Fahrer')),
                                    Label('Tage'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          for (final r in squad)
                            Container(
                              height: _rowHeight,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: c.line, width: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: cellText(career.fullName(r.id)),
                                  ),
                                  // Race days ridden plus race days planned.
                                  Builder(
                                    builder: (context) {
                                      final days =
                                          career.shapeOf(r.id).raceDays +
                                          plannedDays(r.id);
                                      return cellText(
                                        '$days',
                                        color: days > 80
                                            ? TeamColors.red
                                            : days > 65
                                            ? TeamColors.gold
                                            : TeamColors.muted,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: _horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [for (final r in races) header(r)]),
                              for (final rider in squad)
                                Row(
                                  children: [
                                    for (final r in races) cell(r, rider.id),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gelb: Grand Tour · Rot: Monument · Blau: WorldTour · Grau: kleinere Rennen. '
            'Punkt: Rennen gefahren. Tage über 65 werden gelb, über 80 rot.',
            style: TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
        ],
      ),
    );
  }
}
