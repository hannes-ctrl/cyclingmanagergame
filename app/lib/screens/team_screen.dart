import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'rider_dialog.dart';

/// Page of a team: who it is, where it stands this season and its squad.
/// Riders the player's scouts do not know well show their strength as a
/// range, as everywhere else.
class TeamPage extends StatelessWidget {
  /// Creates the page.
  ///
  /// @param state Application state.
  /// @param teamId Id of the team.
  const TeamPage({super.key, required this.state, required this.teamId});
  final AppState state;
  final int teamId;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = s.colors;
    final career = s.career;
    final team = career.teams[teamId];
    if (team == null) {
      return Center(child: Text(tr('The team no longer exists.')));
    }
    final book = career.staff;
    final squad = [...?career.squads[teamId]]
      ..sort((a, b) => Economy.rating(b).compareTo(Economy.rating(a)));
    final ids = [for (final r in squad) r.id];
    // Place in the ranking of the season.
    final ranking = career.teamPoints.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final place = ranking.indexWhere((e) => e.key == teamId) + 1;
    final points = (career.teamPoints[teamId] ?? 0).round();
    final wins = squad.fold(0, (n, r) => n + career.winsOf(r.id, career.year));
    final age = squad.isEmpty
        ? 0.0
        : squad.fold(0, (n, r) => n + career.year - r.born ~/ 10000) /
              squad.length;
    final development = team.division == 'Under23';
    final free = team.division == 'Free';

    Widget tile(String label, String value) => Container(
      width: 150,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: TeamColors.ground,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Label(label),
          const SizedBox(height: 2),
          Text(value, style: headStyle(20)),
        ],
      ),
    );

    /// Strength of a rider as the scouts see it.
    String strength(SimRider r) {
      final (low, high) = book.range(r.id, 'Strength', Economy.rating(r));
      return low == high ? '$low' : '$low–$high';
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Jersey(dataDir: s.dataDir, abbr: s.jerseyOf(teamId), size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name, style: headStyle(27)),
                    Row(
                      children: [
                        InkWell(
                          onTap: () => s.searchRidersOf(team.country),
                          child: Flag(team.country, width: 20),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          [
                            team.country,
                            free
                                ? tr('free agent')
                                : development
                                ? tr('Development team')
                                : career.licences.of(teamId).label,
                            if (team.manager.isNotEmpty) team.manager,
                            if (!free)
                              tr('Style: {0}', [career.styleOf(teamId).label]),
                            if (!free)
                              '${career.equipment.supplyOf(teamId).bike.name} · ${career.equipment.supplyOf(teamId).tyres.name}',
                          ].join(' · '),
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: s.closeTeam, child: Text(tr('Back'))),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              tile(tr('Rider'), '${squad.length}'),
              tile(tr('Avg. age'), dec(age)),
              if (!free) ...[
                tile(tr('Points {0}', [career.year]), '$points'),
                tile(
                  tr('Rank {0}', [career.year]),
                  place > 0 ? '$place.' : '–',
                ),
                tile(tr('Wins {0}', [career.year]), '$wins'),
                // Every team keeps books; the player sees what others can spend.
                tile(
                  tr('Budget'),
                  '${euro(career.finances.budgetOf(teamId))} €',
                ),
                tile(
                  tr('Balance'),
                  '${euro(career.finances.balanceOf(teamId))} €',
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Panel(
              colors: c,
              child: DenseTable<SimRider>(
                colors: c,
                rows: squad,
                onTap: (r) => showRiderDialog(context, s, r.id, among: ids),
                columns: [
                  Col('', 30, (r, _) => watchStar(s, r)),
                  Col(
                    tr('Rider'),
                    230,
                    (r, _) => cellText(career.fullName(r.id)),
                    sortKey: (r) => r.lastName,
                  ),
                  Col(tr('Nat'), 70, (r, _) => flagCell(r.country)),
                  Col(
                    tr('Age'),
                    60,
                    (r, _) => cellText('${career.year - r.born ~/ 10000}'),
                    numeric: true,
                    sortKey: (r) => -r.born,
                  ),
                  Col(
                    tr('Type'),
                    130,
                    (r, _) => cellText(
                      book.knowledge(r.id) >= 1 ? tr(riderType(r)) : '?',
                      color: TeamColors.muted,
                    ),
                  ),
                  Col(
                    tr('Strength'),
                    80,
                    (r, _) => cellText(strength(r)),
                    numeric: true,
                    sortKey: (r) => Economy.rating(r),
                  ),
                  Col(
                    tr('Points'),
                    80,
                    (r, _) =>
                        cellText('${(career.riderPoints[r.id] ?? 0).round()}'),
                    numeric: true,
                    sortKey: (r) => career.riderPoints[r.id] ?? 0,
                  ),
                  Col(
                    tr('Wins'),
                    70,
                    (r, _) => cellText('${career.winsOf(r.id, career.year)}'),
                    numeric: true,
                    sortKey: (r) => career.winsOf(r.id, career.year),
                  ),
                  Col(
                    tr('Contract'),
                    80,
                    (r, _) => cellText(
                      switch (career.economy.contracts[r.id]?.endYear) {
                        final year? when !free => contractEnd(year),
                        _ => '–',
                      },
                      color: TeamColors.muted,
                    ),
                    numeric: true,
                    sortKey: (r) =>
                        career.economy.contracts[r.id]?.endYear ?? 0,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
