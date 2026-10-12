import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';
import '../ui.dart';

String _d(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

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

    Widget fact(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: TeamColors.muted)),
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Panel(
                    colors: c,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        head('Nächste Rennen', 'planner'),
                        const SizedBox(height: 6),
                        if (upcoming.isEmpty)
                          const Text(
                            'Kein Rennen mehr in dieser Saison.',
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
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.info.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${r.tier.label} · ${r.info.country} · '
                                          '${r.isStageRace ? '${r.stages.length} Etappen' : 'Eintagesrennen'}',
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
                                        ? 'läuft'
                                        : r.start == today
                                        ? 'heute'
                                        : 'in ${r.start.difference(today).inDays} Tagen',
                                    style: TextStyle(
                                      color:
                                          r.start.difference(today).inDays <= 0
                                          ? TeamColors.green
                                          : TeamColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  flex: 4,
                  child: Panel(
                    colors: c,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Label(
                                s.unread > 0
                                    ? 'Neuigkeiten · ${s.unread} ungelesen'
                                    : 'Neuigkeiten',
                              ),
                            ),
                            InkWell(
                              onTap: onInbox,
                              child: const Text(
                                'Zum Postfach',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: TeamColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (s.inbox.isEmpty)
                          const Text(
                            '„Weiter" lässt die Saison laufen, bis etwas '
                            'dein Team betrifft.',
                            style: TextStyle(color: TeamColors.muted),
                          ),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final m in s.inbox.take(8))
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 54,
                                        child: Text(
                                          _d(m.date),
                                          style: const TextStyle(
                                            color: TeamColors.muted,
                                          ),
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
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(
                  colors: c,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      head('Saison ${career.year}', 'rankings'),
                      const SizedBox(height: 4),
                      fact('Lizenz', career.licences.of(s.team.id).label),
                      fact(
                        'Teamrangliste',
                        rank == 0
                            ? '–'
                            : 'Platz $rank · ${(career.teamPoints[s.team.id] ?? 0).round()} Punkte',
                      ),
                      if (cycle >= 0)
                        fact(
                          'Dreijahreswertung ${career.licences.cycleStart}–${career.licences.cycleEnd}',
                          'Platz ${cycle + 1}',
                          color: cycle < career.licences.worldTourPlaces
                              ? TeamColors.green
                              : TeamColors.red,
                        ),
                      fact('Siege', '${eco.wins}'),
                      fact(
                        'Kasse',
                        '${euro(eco.balance)} €',
                        color: eco.balance < 0 ? TeamColors.red : null,
                      ),
                      fact(
                        'Vertrauen der Teamleitung',
                        '${eco.confidence.round()} von 100',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Panel(
                    colors: c,
                    child: ListView(
                      children: [
                        head('Saisonziele', 'finance'),
                        const SizedBox(height: 4),
                        for (final g in eco.goals)
                          line(
                            g.text,
                            g.achieved() ? 'erreicht' : 'offen',
                            color: g.achieved()
                                ? TeamColors.green
                                : TeamColors.gold,
                          ),
                        const SizedBox(height: 12),
                        head('Im Rennen', 'races'),
                        const SizedBox(height: 4),
                        if (running.isEmpty)
                          const Text(
                            'Gerade fährt niemand.',
                            style: TextStyle(color: TeamColors.muted),
                          ),
                        for (final p in running)
                          InkWell(
                            onTap: () => onOpenRace(p.race.info.id),
                            child: line(
                              p.race.info.name,
                              p.race.isStageRace
                                  ? 'Etappe ${p.stagesDone} von ${p.race.stages.length}'
                                  : 'heute',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Panel(
              colors: c,
              child: ListView(
                children: [
                  head('Beste Form', 'squad:shape'),
                  const SizedBox(height: 4),
                  for (final r in inForm.take(5))
                    riderLine(
                      r,
                      '${((career.shapeOf(r.id).form - 1) * 100).toStringAsFixed(1).replaceAll('.', ',')} %',
                      color: career.shapeOf(r.id).form >= 1
                          ? TeamColors.green
                          : TeamColors.muted,
                    ),
                  const SizedBox(height: 12),
                  head('Punktesammler', 'squad:season'),
                  const SizedBox(height: 4),
                  if (scorers.isEmpty)
                    const Text(
                      'Noch keine Punkte.',
                      style: TextStyle(color: TeamColors.muted),
                    ),
                  for (final r in scorers.take(6))
                    riderLine(r, '${career.riderPoints[r.id]!.round()}'),
                  const SizedBox(height: 12),
                  head('Nicht einsatzbereit · ${out.length}', 'squad:shape'),
                  const SizedBox(height: 4),
                  if (out.isEmpty)
                    const Text(
                      'Alle gesund.',
                      style: TextStyle(color: TeamColors.muted),
                    ),
                  for (final r in out)
                    riderLine(
                      r,
                      'bis ${_d(career.shapeOf(r.id).injuredUntil!)}',
                      color: TeamColors.red,
                    ),
                  if (inCamp.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    head('Im Trainingslager · ${inCamp.length}', 'camps'),
                    const SizedBox(height: 4),
                    for (final r in inCamp)
                      riderLine(
                        r,
                        career.camps.campOf(r.id, today)!.type.label,
                        color: TeamColors.gold,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
