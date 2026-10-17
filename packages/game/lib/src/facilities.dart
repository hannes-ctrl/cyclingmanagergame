import 'package:sim/sim.dart';

import 'career.dart';
import 'economy.dart';

/// The facilities a team can run.
enum Facility {
  /// Gyms, altitude rooms, training planning: riders develop faster.
  training('Training centre',
      'Riders develop faster: a twenty-fifth more per level above three.'),

  /// Doctors' rooms, rehabilitation: shorter lay-offs, fewer infections.
  medical('Medical centre',
      'Lay-offs are a twentieth shorter per level above three, infections rarer.'),

  /// Scouts' contacts and databases: riders of other teams are known better.
  scouting('Scouting network',
      'Riders of other teams are better known without a scout, and reports come faster.'),

  /// Performance diagnostics and nutrition: recovery in stage races.
  science('Sports science',
      'Riders recover better overnight in stage races, as with better physiotherapists.'),

  /// The team's own academy: talent for the development team.
  academy('Youth academy',
      'More and better talents come to the development team, and they develop faster.'),

  /// Media, fans, hospitality: what the sponsors get for their money.
  marketing('Marketing department',
      'Sponsors pay more: three per cent per level above three, on new contracts and offers.');

  const Facility(this._label, this._effect);
  final String _label;
  final String _effect;

  /// The label in the current language.
  String get label => tr(_label);

  /// What one level more does, in the current language.
  String get effect => tr(_effect);
}

/// A facility being built up to the next level.
class Build {
  Build(this.facility, this.ready);
  final Facility facility;

  /// Day the new level is ready.
  final DateTime ready;
}

/// The facilities of every team, one to five levels each. A team starts
/// with levels that fit its strength: about 3 at a strength of 75, 4 at 80,
/// 5 at 85. Level 3 is the average and changes nothing; every level above
/// or below shifts development, lay-offs, scouting, recovery and the youth
/// a little. The same rules act for every team; only the player builds.
class Facilities {
  Facilities(this.c) {
    _assign();
  }

  final Career c;

  /// Levels per team id and facility.
  final levels = <int, Map<Facility, int>>{};

  /// The player's facility under construction, or null.
  Build? building;

  /// Highest level.
  static const maxLevel = 5;

  void _assign() {
    for (final t in c.teams.values) {
      if (t.division == 'Free') continue;
      final base = fitting(t.id);
      levels[t.id] = {
        for (final f in Facility.values)
          // A little variety between the facilities of a team, fixed per
          // team: one in five a level lower, one in five a level higher.
          f: (base + _variety(t.id, f)).clamp(1, maxLevel),
      };
    }
  }

  /// The level that fits a team of its strength: about 3 at 75, 4 at 80,
  /// 5 at 85.
  ///
  /// @param teamId Id of a team.
  /// @returns 1 to 5.
  int fitting(int teamId) =>
      ((c.teamStrength(teamId) - 60) / 5).round().clamp(1, maxLevel);

  /// @param teamId Id of a team.
  /// @param f A facility.
  /// @returns -1, 0 or 1 steps off the level the team's strength gives.
  static int _variety(int teamId, Facility f) =>
      switch ((teamId * 7 + f.index * 3) % 5) { 0 => -1, 4 => 1, _ => 0 };

  /// @param teamId Id of a team.
  /// @param f A facility.
  /// @returns Its level, 1 to 5; 3 for a team without facilities.
  int level(int teamId, Facility f) => levels[teamId]?[f] ?? 3;

  /// Steps above (positive) or below the average level 3.
  int _step(int teamId, Facility f) => level(teamId, f) - 3;

  /// Factor on the development of a team's riders.
  double development(int teamId) => 1 + 0.04 * _step(teamId, Facility.training);

  /// Factor on the days a rider of the team is out.
  double layOff(int teamId) => 1 - 0.05 * _step(teamId, Facility.medical);

  /// Factor on the chance of an infection.
  double infections(int teamId) => 1 - 0.08 * _step(teamId, Facility.medical);

  /// What the scouting network adds to the knowledge of other riders.
  double scoutingBonus(int teamId) => 0.03 * _step(teamId, Facility.scouting);

  /// Factor on the days a scout needs for a report.
  double scoutDays(int teamId) => 1 - 0.07 * _step(teamId, Facility.scouting);

  /// What sports science adds to the quality of recovery, 0 to 1 scale.
  double recoveryBonus(int teamId) => 0.08 * _step(teamId, Facility.science);

  /// Talents the development team takes from each intake.
  int academyIntake(int teamId) =>
      (2 + _step(teamId, Facility.academy)).clamp(1, 4);

  /// Factor on what sponsors pay a team. Sponsor money is measured against
  /// a team with level 3, so the level a team starts with is already in
  /// its budget; building up raises the next contracts.
  ///
  /// @param teamId Id of a team.
  /// @returns The factor, 0.94 to 1.06.
  double marketing(int teamId) => 1 + 0.03 * _step(teamId, Facility.marketing);

  /// Factor on the development of the riders of the development team.
  double academyDevelopment(int teamId) =>
      1 + 0.03 * _step(teamId, Facility.academy);

  // --- Money -----------------------------------------------------------------

  // Costs are shares of the team's budget, so that a continental team
  // with a million pays for its small facilities what a WorldTeam pays for
  // its large ones in proportion: a level costs half a per cent of the
  // budget a year to run, and building the next one two and a half per cent
  // of the budget times the level it starts from.

  /// Share of the budget one level of a facility costs per season to run.
  static const upkeepShare = 0.005;

  /// Share of the budget per level that building the next level costs.
  static const buildShare = 0.025;

  /// Running costs of all facilities of a team per season.
  ///
  /// @param teamId Id of the team.
  /// @returns Euros.
  double upkeep(int teamId) =>
      Facility.values.fold(0.0, (s, f) => s + level(teamId, f)) *
      upkeepShare *
      c.finances.budgetOf(teamId);

  /// What it costs a team to build a facility up from a level.
  ///
  /// @param teamId Id of the team.
  /// @param level The level it has now.
  /// @returns Euros.
  double costAt(int teamId, int level) =>
      buildShare * c.finances.budgetOf(teamId) * level;

  /// What it costs to build a facility up to the next level.
  ///
  /// @param f The facility.
  /// @returns Euros, or null if it is at the top.
  double? upgradeCost(Facility f) {
    final now = level(c.teamId, f);
    if (now >= maxLevel) return null;
    return costAt(c.teamId, now);
  }

  /// Days it takes to build the next level.
  static int buildDays(int level) => 60 + 30 * level;

  /// Starts building a facility up one level for the player's team.
  ///
  /// @param f The facility.
  /// @returns null on success, otherwise the reason.
  String? upgrade(Facility f) {
    if (building != null) {
      return tr('Another facility is being built.');
    }
    final cost = upgradeCost(f);
    if (cost == null) return tr('The facility is already at the top level.');
    if (c.economy.available < cost) {
      return tr('There is not enough money in the account.');
    }
    c.economy.balance -= cost;
    building =
        Build(f, c.today.add(Duration(days: buildDays(level(c.teamId, f)))));
    return null;
  }

  /// On the first of a month, when the player has handed it to the board:
  /// with no building going on, the board raises the weakest facility if
  /// the account still holds a tenth of the budget afterwards.
  void boardBuilds() {
    if (building != null) return;
    final open = [
      for (final f in Facility.values)
        if (level(c.teamId, f) < maxLevel) f,
    ];
    if (open.isEmpty) return;
    final f =
        open.reduce((a, b) => level(c.teamId, b) < level(c.teamId, a) ? b : a);
    final cost = upgradeCost(f)!;
    if (c.economy.available - cost < 0.1 * c.economy.budget) return;
    if (upgrade(f) != null) return;
    c.inbox.add(Message(
      c.today,
      tr('Board'),
      tr('{0} is being expanded', [f.label]),
      tr(
          'The board has started building the {0} up to level {1} for {2}. It opens in {3} days.',
          [
            f.label,
            level(c.teamId, f) + 1,
            Economy.euro(cost),
            buildDays(level(c.teamId, f)),
          ]),
    ));
  }

  /// The player leaves for another team: a building under way is paid for
  /// and opens for the old team at once.
  ///
  /// @param from The team he leaves.
  void handOver(int from) {
    final b = building;
    if (b == null) return;
    building = null;
    final old =
        levels.putIfAbsent(from, () => {for (final f in Facility.values) f: 3});
    old[b.facility] = (old[b.facility]! + 1).clamp(1, maxLevel);
  }

  /// Daily: a finished building opens.
  void daily() {
    final b = building;
    if (b == null || c.today.isBefore(b.ready)) return;
    building = null;
    final own = levels.putIfAbsent(
        c.teamId, () => {for (final f in Facility.values) f: 3});
    own[b.facility] = (own[b.facility]! + 1).clamp(1, maxLevel);
    c.inbox.add(Message(
      c.today,
      tr('Board'),
      tr('{0} expanded', [b.facility.label]),
      tr('The {0} is now at level {1} of {2}.',
          [b.facility.label, own[b.facility], maxLevel]),
    ));
  }

  // --- Saving -----------------------------------------------------------------

  /// @returns Everything as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'levels': {
          for (final e in levels.entries)
            '${e.key}': [for (final f in Facility.values) e.value[f] ?? 3],
        },
        if (building != null)
          'building': [
            building!.facility.index,
            building!.ready.millisecondsSinceEpoch,
          ],
      };

  /// @param j A map written by [toJson], or null for a save from before
  ///   teams had facilities.
  void restore(Map<String, dynamic>? j) {
    levels.clear();
    building = null;
    if (j == null) {
      _assign();
      return;
    }
    for (final e in (j['levels'] as Map<String, dynamic>).entries) {
      final list = (e.value as List).cast<int>();
      levels[int.parse(e.key)] = {
        for (final f in Facility.values)
          f: f.index < list.length ? list[f.index] : 3,
      };
    }
    if (j['building'] case [final int f, final int ms]) {
      building = Build(Facility.values[f],
          DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
    }
  }
}
