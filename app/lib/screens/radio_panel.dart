import 'package:flutter/material.dart';

import '../app_state.dart';
import '../widgets.dart';

/// DS radio: the sports director calls in from the race and asks what to
/// do. Covers the page until the player has answered.
class RadioPanel extends StatelessWidget {
  const RadioPanel({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final r = state.radio!;
    final c = state.colors;
    final race = r.race.race;
    final route = state.world.route(race.stages[r.stageIndex].id);
    final director = r.race.ownDirector?.name ?? 'Teamwagen';

    return ColoredBox(
      color: TeamColors.ground.withValues(alpha: 0.86),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Panel(
            colors: c,
            padding: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'FUNK',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: c.onAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        race.isStageRace
                            ? '${race.info.name} · Etappe ${r.stageIndex + 1}'
                            : race.info.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'noch ${r.call.remainingKm.round()} von '
                      '${route.raceKm.round()} km',
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 96,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ProfileView(route: route, colors: c),
                      ),
                      // Where the race currently is.
                      Positioned.fill(
                        left: 40,
                        right: 10,
                        child: Align(
                          alignment: Alignment(
                            (r.call.km / route.raceKm).clamp(0.0, 1.0) * 2 - 1,
                            0,
                          ),
                          child: Container(width: 2, color: TeamColors.gold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$director:',
                  style: const TextStyle(fontSize: 12, color: TeamColors.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  '„${r.call.text}"',
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 16),
                for (final (i, option) in r.call.options.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TeamColors.text,
                          backgroundColor: i == 0 ? c.panel2 : null,
                          side: BorderSide(color: c.line),
                          alignment: Alignment.centerLeft,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        onPressed: state.busy
                            ? null
                            : () => state.answerRadio(i),
                        child: Text(option),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Die erste Antwort lässt den Sportlichen Leiter '
                        'nach Plan weiterfahren. Nach der letzten Rückfrage '
                        'des Tages öffnet sich das Ergebnis. Der Funk lässt '
                        'sich unter „Aufgabenverteilung" abschalten.',
                        style: TextStyle(fontSize: 12, color: TeamColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
