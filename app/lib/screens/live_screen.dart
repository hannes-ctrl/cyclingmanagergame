import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'race_replay.dart';
import 'view3d_button.dart';

/// A stage of the player's team as it happens: the stage in fast motion
/// runs before the result is shown, with the riders of the team and the
/// favourites named in their groups. At the finish, or on "to the result",
/// the race report opens.
class LiveScreen extends StatefulWidget {
  const LiveScreen({
    super.key,
    required this.state,
    required this.race,
    required this.index,
  });
  final AppState state;
  final RaceInfo race;

  /// Index of the stage within the race.
  final int index;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

/// State of the live view: whether the head of the race has finished.
class _LiveScreenState extends State<LiveScreen> {
  var _finished = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final run = s.runOf(widget.race);
    final index = widget.index;
    if (run == null || index >= run.result.stages.length) {
      return const SizedBox();
    }
    final result = run.result.stages[index];
    final route = run.routes[index];
    final stageRace = run.stages.length > 1;
    final own = {
      for (final r in run.riders)
        if (r.teamId == s.team.id) r.id: r.name,
    };
    // The favourites of the day: whoever the simulation counted as one.
    final stars = <int>{
      for (final sample in result.timeline)
        for (final g in sample.groups) ...g.stars,
    };
    final others = {
      for (final r in run.riders)
        if (stars.contains(r.id) && !own.containsKey(r.id)) r.id: r.name,
    };
    final winner = result.placings.first.rider;
    // Who wears the jerseys at the start of the day.
    final before =
        stageRace && index > 0 && run.result.standings.length >= index
        ? run.result.standings[index - 1]
        : null;
    final colours = jerseyColors(grandTourOf(widget.race));
    final names = jerseyNames(grandTourOf(widget.race));
    final holders = before == null
        ? const <(Color, String, String)>[]
        : [
            if (before.general.isNotEmpty)
              (
                colours.general,
                tr(names.general),
                before.general.first.rider.name,
              ),
            if (before.points.isNotEmpty)
              (
                colours.points,
                tr(names.points),
                before.points.first.rider.name,
              ),
            if (before.mountains.isNotEmpty)
              (
                colours.mountains,
                tr(names.mountains),
                before.mountains.first.rider.name,
              ),
          ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Panel(
        colors: c,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RaceLogo(dataDir: s.dataDir, race: widget.race, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stageRace
                            ? tr('{0}, stage {1}', [
                                widget.race.name,
                                index + 1,
                              ])
                            : widget.race.name,
                        style: headStyle(22),
                      ),
                      Text(
                        tr('Live · {0} km', [route.raceKm.round()]),
                        style: const TextStyle(color: TeamColors.muted),
                      ),
                    ],
                  ),
                ),
                if (_finished)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      tr('{0} wins', [career.fullName(winner.id)]),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: TeamColors.gold,
                      ),
                    ),
                  ),
                View3dButton(state: s, run: run, index: index),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                  ),
                  onPressed: s.closeLive,
                  child: Text(tr('To the result')),
                ),
              ],
            ),
            if (holders.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 16,
                  children: [
                    for (final (colour, jersey, name) in holders)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.shirt, size: 16, color: colour),
                          const SizedBox(width: 5),
                          Text(
                            '$name · $jersey',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                children: [
                  RaceReplay(
                    result: result,
                    route: route,
                    names: own,
                    others: others,
                    colors: c,
                    autoplay: true,
                    onFinished: () => setState(() => _finished = true),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(
                      'Your riders in the team colour, the favourites by name. The result follows at the finish.',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: TeamColors.muted,
                    ),
                  ),
                ),
                Text(
                  tr('Watch our stages live'),
                  style: const TextStyle(fontSize: 13),
                ),
                Switch(
                  value: s.watchLive,
                  activeThumbColor: c.accent,
                  onChanged: (v) => setState(() => s.setWatchLive(v)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
