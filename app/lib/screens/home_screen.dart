import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';
import '../ui.dart';

String _d(DateTime d) => dayText(d);

/// Overview: the essentials at a glance, like the home page in Football
/// Manager. Next races, news, state of the team, squad.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.state,
    required this.onOpenRace,
    required this.onInbox,
    required this.onNavigate,
  });
  final AppState state;
  final void Function(int raceId) onOpenRace;
  final VoidCallback onInbox;

  /// Opens another page of the shell, given by the name of its sidebar entry.
  final void Function(String page) onNavigate;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = s.colors;
    final career = s.career;
    final eco = career.economy;
    final today = career.today;
    final upcoming = [
      for (final r in career.ownRaces)
        if (!r.end.isBefore(today) &&
            !(career.progress[r.info.id]?.finished ?? false))
          r,
    ].take(7).toList();
    final ranking = career.teamPoints.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final rank = ranking.indexWhere((e) => e.key == s.team.id) + 1;
    final cycle = career.licences.ranking().indexWhere(
      (r) => r.teamId == s.team.id,
    );
    final squad = s.squad;
    final out = [
      for (final r in squad)
        if (career.isInjured(r.id, today)) r,
    ];
    final inCamp = [
      for (final r in squad)
        if (career.camps.campOf(r.id, today) != null) r,
    ];
    final inForm = [...squad]
      ..sort(
        (a, b) =>
            career.shapeOf(b.id).form.compareTo(career.shapeOf(a.id).form),
      );
    final scorers =
        [
          for (final r in squad)
            if ((career.riderPoints[r.id] ?? 0) > 0) r,
        ]..sort(
          (a, b) =>
              career.riderPoints[b.id]!.compareTo(career.riderPoints[a.id]!),
        );
    final running = [
      for (final p in career.progress.values)
        if (!p.finished && p.run.riders.any((r) => r.teamId == s.team.id)) p,
    ];

    // A figure with its explanation as a tooltip, by [help] or the label.
    Widget fact(String label, String value, {Color? color, String? help}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: withHelp(
                  help ?? label,
                  Text(label, style: const TextStyle(color: TeamColors.muted)),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color ?? TeamColors.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );

    Widget line(String left, String right, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(left, overflow: TextOverflow.ellipsis)),
          Text(right, style: TextStyle(color: color ?? TeamColors.muted)),
        ],
      ),
    );

    // Heading of a tile; a click opens the page the tile summarises.
    Widget head(String text, String page) => InkWell(
      onTap: () => onNavigate(page),
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Label(text),
            const Spacer(),
            const Icon(
              LucideIcons.chevronRight,
              size: 15,
              color: TeamColors.muted,
            ),
          ],
        ),
      ),
    );

    Widget riderLine(SimRider r, String right, {Color? color}) => InkWell(
      onTap: () => s.openRider(r.id),
      child: line(career.fullName(r.id), right, color: color),
    );

    // A tile of the grid; its content scrolls if it does not fit.
    Widget tile(List<Widget> children) => Panel(
      colors: c,
      child: ListView(children: children),
    );

    // Two rows of three tiles. The tiles of a row are equally high and the
    // columns equally wide, so that all edges line up.
    Widget row(List<Widget> tiles) => Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row([
            tile([
              head(tr('Next races'), 'planner'),
              const SizedBox(height: 6),
              if (upcoming.isEmpty)
                Text(
                  tr('No more races this season.'),
                  style: TextStyle(color: TeamColors.muted),
                ),
              for (final r in upcoming)
                InkWell(
                  onTap: () => onOpenRace(r.info.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        RaceLogo(
                          dataDir: state.dataDir,
                          race: r.info,
                          size: 32,
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 54,
                          child: Text(
                            _d(r.start),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.info.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${r.tier.label} · ${r.info.country} · '
                                '${r.isStageRace ? trn(r.stages.length, '{0} stage', '{0} stages') : tr('One-day race')}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: TeamColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          career.progress.containsKey(r.info.id)
                              ? tr('running')
                              : r.start == today
                              ? tr('today')
                              : tr('in {0} days', [
                                  r.start.difference(today).inDays,
                                ]),
                          style: TextStyle(
                            color: r.start.difference(today).inDays <= 0
                                ? TeamColors.green
                                : TeamColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ]),
            tile([
              head(tr('Season {0}', [career.year]), 'rankings'),
              const SizedBox(height: 4),
              fact(tr('Licence'), career.licences.of(s.team.id).label),
              fact(
                tr('Team ranking'),
                rank == 0
                    ? '–'
                    : tr('Place {0} · {1} points', [
                        rank,
                        (career.teamPoints[s.team.id] ?? 0).round(),
                      ]),
              ),
              if (cycle >= 0)
                fact(
                  tr('Three-year ranking {0}–{1}', [
                    career.licences.cycleStart,
                    career.licences.cycleEnd,
                  ]),
                  help: 'Three-year ranking',
                  tr('Place {0}', [cycle + 1]),
                  color: cycle < career.licences.worldTourPlaces
                      ? TeamColors.green
                      : TeamColors.red,
                ),
              fact(tr('Wins'), '${eco.wins}'),
              fact(
                tr('Balance'),
                '${euro(eco.balance)} €',
                color: eco.balance < 0 ? TeamColors.red : null,
              ),
              fact(
                tr('Board confidence'),
                tr('{0} of 100', [eco.confidence.round()]),
                color: career.manager.dismissed || career.manager.warned
                    ? TeamColors.red
                    : null,
              ),
              fact(
                tr('Your reputation'),
                help: 'Reputation',
                tr('{0} of 100 · {1}', [
                  career.manager.reputation.round(),
                  career.manager.standing,
                ]),
              ),
              if (career.manager.nextTeam case final next?)
                fact(
                  tr('From next season'),
                  career.teams[next]?.name ?? '',
                  color: TeamColors.green,
                ),
            ]),
            tile([
              head(tr('Best form'), 'squad:shape'),
              const SizedBox(height: 4),
              for (final r in inForm.take(5))
                riderLine(
                  r,
                  '${dec((career.shapeOf(r.id).form - 1) * 100)} %',
                  color: career.shapeOf(r.id).form >= 1
                      ? TeamColors.green
                      : TeamColors.muted,
                ),
            ]),
          ]),
          const SizedBox(height: 12),
          row([
            tile([
              Row(
                children: [
                  Expanded(
                    child: Label(
                      s.unread > 0
                          ? tr('News · {0} unread', [s.unread])
                          : tr('News'),
                    ),
                  ),
                  InkWell(
                    onTap: onInbox,
                    child: Text(
                      tr('To the inbox'),
                      style: TextStyle(fontSize: 12, color: TeamColors.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (s.inbox.isEmpty)
                Text(
                  tr(
                    '"Continue" lets the season run until something concerns your team.',
                  ),
                  style: TextStyle(color: TeamColors.muted),
                ),
              for (final m in s.inbox.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: Text(
                          _d(m.date),
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          m.subject,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: m.read
                                ? FontWeight.w400
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        m.from,
                        style: const TextStyle(
                          fontSize: 12,
                          color: TeamColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
            tile([
              head(tr('Season goals'), 'finance'),
              const SizedBox(height: 4),
              for (final g in eco.goals)
                line(
                  g.text,
                  g.achieved() ? tr('achieved') : tr('open'),
                  color: g.achieved() ? TeamColors.green : TeamColors.gold,
                ),
              const SizedBox(height: 12),
              head(tr('Racing now'), 'races'),
              const SizedBox(height: 4),
              if (running.isEmpty)
                Text(
                  tr('Nobody is racing right now.'),
                  style: TextStyle(color: TeamColors.muted),
                ),
              for (final p in running)
                InkWell(
                  onTap: () => onOpenRace(p.race.info.id),
                  child: line(
                    p.race.info.name,
                    p.race.isStageRace
                        ? tr('Stage {0} of {1}', [
                            p.stagesDone,
                            p.race.stages.length,
                          ])
                        : tr('today'),
                  ),
                ),
            ]),
            tile([
              head(tr('Points scorers'), 'squad:season'),
              const SizedBox(height: 4),
              if (scorers.isEmpty)
                Text(
                  tr('No points yet.'),
                  style: TextStyle(color: TeamColors.muted),
                ),
              for (final r in scorers.take(6))
                riderLine(r, '${career.riderPoints[r.id]!.round()}'),
              const SizedBox(height: 12),
              head(tr('Unavailable · {0}', [out.length]), 'squad:shape'),
              const SizedBox(height: 4),
              if (out.isEmpty)
                Text(
                  tr('Everyone is healthy.'),
                  style: TextStyle(color: TeamColors.muted),
                ),
              for (final r in out)
                riderLine(
                  r,
                  tr('until {0}', [_d(career.shapeOf(r.id).injuredUntil!)]),
                  color: TeamColors.red,
                ),
              if (inCamp.isNotEmpty) ...[
                const SizedBox(height: 12),
                head(tr('In a training camp · {0}', [inCamp.length]), 'camps'),
                const SizedBox(height: 4),
                for (final r in inCamp)
                  riderLine(
                    r,
                    career.camps.campOf(r.id, today)!.type.label,
                    color: TeamColors.gold,
                  ),
              ],
            ]),
          ]),
        ],
      ),
    );
  }
}
