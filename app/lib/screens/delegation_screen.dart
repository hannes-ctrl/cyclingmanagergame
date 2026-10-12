import 'package:flutter/material.dart';
import 'package:game/game.dart';

import '../app_state.dart';
import '../widgets.dart';

/// Delegation: what the player decides himself and what his staff handles
/// without asking.
class DelegationScreen extends StatelessWidget {
  const DelegationScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = s.colors;
    final career = s.career;
    final d = career.delegation;
    final book = career.staff;

    String best(StaffRole role) {
      final people = book.of(s.team.id, role).toList()
        ..sort((a, b) => b.skill.compareTo(a.skill));
      return people.isEmpty
          ? 'niemand im Team'
          : '${people.first.name} (${people.first.skill})';
    }

    Widget row(
      String title,
      String who,
      String self,
      String delegated,
      bool on,
      void Function(bool) onChanged,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 230,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  who,
                  style: const TextStyle(fontSize: 12, color: TeamColors.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              on ? delegated : self,
              style: TextStyle(color: on ? TeamColors.text : TeamColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            on ? 'Personal' : 'Ich selbst',
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 24,
            child: Switch(
              value: on,
              activeThumbColor: c.accent,
              onChanged: s.busy ? null : onChanged,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Panel(
            colors: c,
            padding: 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Label('Aufgabenverteilung'),
                const SizedBox(height: 4),
                const Text(
                  'Was du abgibst, erledigt das Personal ohne Rückfrage. '
                  'Wie gut, hängt von den Leuten ab.',
                  style: TextStyle(color: TeamColors.muted),
                ),
                const SizedBox(height: 8),
                row(
                  'Aufgebote',
                  'Sportlicher Leiter: ${best(StaffRole.director)}',
                  'Vor jedem Rennen wählst du Fahrer, Rollen und Taktik.',
                  'Der Sportliche Leiter stellt auf und plant jede Etappe; '
                      'die Saisonplanung berücksichtigt er weiter.',
                  d.lineups,
                  (v) => s.delegate('lineups', v),
                ),
                Divider(height: 1, color: c.line),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 230,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Funk im Rennen',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Sportlicher Leiter: ${best(StaffRole.director)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: TeamColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          'Bis zu dreimal je Etappe meldet sich der Leiter: '
                          'wenn die Gruppe des Tages steht, zu Beginn des '
                          'Finales und wenn ein Gegner angreift.',
                          style: TextStyle(color: TeamColors.muted),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<RadioMode>(
                        value: d.radio,
                        isDense: true,
                        underline: const SizedBox(),
                        dropdownColor: c.panel2,
                        style: const TextStyle(
                          fontFamily: 'Barlow',
                          fontSize: 13,
                          color: TeamColors.text,
                        ),
                        onChanged: s.busy
                            ? null
                            : (v) => s.delegate('radio', v!.name),
                        items: [
                          for (final m in RadioMode.values)
                            DropdownMenuItem(value: m, child: Text(m.label)),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.line),
                row(
                  'Training',
                  'Trainer: ${best(StaffRole.coach)}',
                  'Belastung und Schwerpunkt stellst du je Fahrer im Kader ein.',
                  'Der Trainer dosiert jeden Montag nach Frische und Alter, '
                      'nimmt vor geplanten Rennen heraus und wählt den '
                      'Schwerpunkt nach der Stärke des Fahrers.',
                  d.training,
                  (v) => s.delegate('training', v),
                ),
                Divider(height: 1, color: c.line),
                row(
                  'Scouting',
                  'Scout: ${best(StaffRole.scout)}',
                  'Du schickst die Scouts im Transfermarkt einzeln los.',
                  'Ab Juni beobachten freie Scouts von sich aus Fahrer mit '
                      'auslaufendem Vertrag, die zum Team passen.',
                  d.scouting,
                  (v) => s.delegate('scouting', v),
                ),
                Divider(height: 1, color: c.line),
                row(
                  'Vertragsverlängerungen',
                  'Teamleitung',
                  'Auslaufende Verträge verhandelst du selbst.',
                  'Am 1. August verlängert die Teamleitung mit allen, die '
                      'zum Kern gehören oder jung und begabt sind.',
                  career.economy.autoRenew,
                  s.setAutoRenew,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
