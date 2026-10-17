import 'dart:math';

import 'package:sim/sim.dart';

import 'career.dart';
import 'devteam.dart';
import 'economy.dart';
import 'facilities.dart';
import 'prizes.dart';

/// The money of one team the player does not run.
class TeamBooks {
  TeamBooks(this.budget, this.balance, this.anchorBudget, this.anchorRank);

  /// Sponsor money per year.
  double budget;

  /// Money in the account.
  double balance;

  /// Budget and place among all teams by strength at the start of the
  /// career: what the sponsors' money is measured against.
  double anchorBudget;
  final int anchorRank;

  /// Prize money won since the last monthly statement.
  double prizeMonth = 0;
}

/// The finances of every team. The player's team keeps its books in
/// [Economy] (sponsors with contracts, a monthly statement); every other team
/// has a budget, an account and the same costs, settled each month by the
/// same rules: sponsor money and prize money in, wages, running costs, staff,
/// facilities and the development team out.
///
/// The money decides on the market: a team only signs and renews what its
/// wage limit allows, and that limit grows with savings and shrinks with
/// debts, for the player's team too. A team with savings to spare builds up
/// its facilities. Sponsor money follows the team ranking from year to
/// year, as it does for the player.
class Finances {
  Finances(this.c) {
    _open();
  }

  final Career c;

  /// The books of every team but the player's and the free agents.
  final books = <int, TeamBooks>{};

  /// Share of the budget a team keeps in the account as a reserve.
  static const reserveShare = 0.1;

  /// Share of the budget a team the player does not run keeps at most at
  /// the turn of the year.
  static const savingsShare = 1 / 3;

  void _open() {
    final order = [
      for (final t in c.teams.values)
        if (t.division != 'Free') t.id,
    ]..sort((a, b) => c.teamStrength(b).compareTo(c.teamStrength(a)));
    for (final (i, id) in order.indexed) {
      if (id == c.teamId) continue;
      final budget = breakEven(id);
      // The anchor is what the sponsors would pay a team with an average
      // marketing department.
      books[id] = TeamBooks(
          budget, budget * 0.1, budget / c.facilities.marketing(id), i + 1);
    }
    _wageLevel = wageLevel();
  }

  /// Swaps the books when the player changes teams: the old team gets books
  /// of its own with the player's money, less what it still owes this
  /// month; the new one gives up its books.
  ///
  /// @param from The team the player leaves.
  /// @param to The team he takes over.
  /// @returns The books of the new team.
  TeamBooks handOver(int from, int to) {
    final e = c.economy;
    books[from] = TeamBooks(e.budget, e.available, e.anchorBudget, e.anchorRank)
      ..prizeMonth = e.prizeMonth;
    final even = breakEven(to);
    return books.remove(to) ?? TeamBooks(even, even * 0.1, even, e.anchorRank);
  }

  /// @param teamId A team.
  /// @returns Its sponsor money per year.
  double budgetOf(int teamId) =>
      teamId == c.teamId ? c.economy.budget : books[teamId]?.budget ?? 0;

  /// @param teamId A team.
  /// @returns Money in its account.
  double balanceOf(int teamId) =>
      teamId == c.teamId ? c.economy.balance : books[teamId]?.balance ?? 0;

  /// The budget at which a team covers its wages and running costs: what
  /// its sponsors pay at the start of a career. Prize money is then its
  /// profit, and the ranking moves the money from there.
  ///
  /// @param teamId A team.
  /// @returns Euros per year.
  double breakEven(int teamId) {
    final share = 0.22 +
        Facilities.upkeepShare *
            Facility.values
                .fold(0, (s, f) => s + c.facilities.level(teamId, f));
    final fixed = c.economy.wageBill(teamId) + _fixedCosts(teamId);
    return max(300000.0, fixed / (1 - share) * 1.03);
  }

  /// The most a team may pay its riders in a season: what its budget leaves
  /// after the running costs, plus half of what it has saved beyond its
  /// reserve, minus half of what it is short of it; between two fifths of
  /// the budget and the whole of it.
  ///
  /// @param teamId A team.
  /// @returns Euros per year.
  double wageLimit(int teamId) {
    final budget = budgetOf(teamId);
    final spare = balanceOf(teamId) - reserveShare * budget;
    return (budget - runningCosts(teamId) + 0.5 * spare)
        .clamp(0.4 * budget, budget)
        .toDouble();
  }

  /// Running costs of a team per year beside the riders' wages: travel,
  /// material and service as a share of the budget, less what the
  /// suppliers pay, plus staff, facilities and a development team.
  ///
  /// @param teamId A team.
  /// @returns Euros per year.
  double runningCosts(int teamId) =>
      budgetOf(teamId) * 0.22 +
      c.facilities.upkeep(teamId) +
      _fixedCosts(teamId);

  /// The costs that do not grow with the budget: staff and a development
  /// team, less what the suppliers pay.
  double _fixedCosts(int teamId) =>
      c.staff.wages(teamId) -
      c.equipment.supplyOf(teamId).fee +
      (teamId == c.teamId
          ? c.devTeam.cost
          : c.devTeam.links[teamId] != null
              ? DevTeam.yearlyCost
              : 0);

  // --- Daily -----------------------------------------------------------------

  /// Daily: prize money of the day's stages, and on the first of a month
  /// the monthly statement of every team.
  ///
  /// @param ridden Today's stages.
  void daily(
      List<({RaceProgress race, int stageIndex, StageResult result})> ridden) {
    for (final day in ridden) {
      final teams = {for (final r in day.race.riders) r.teamId};
      for (final id in teams) {
        final b = books[id];
        if (b != null) b.prizeMonth += Prizes.kept(day.race, day.result, id);
      }
    }
    if (c.today.day != 1) return;
    for (final e in books.entries) {
      final b = e.value;
      b.balance += b.budget / 12 +
          b.prizeMonth -
          c.economy.wageBill(e.key) / 12 -
          runningCosts(e.key) / 12;
      b.prizeMonth = 0;
    }
  }

  // --- Turn of the season ----------------------------------------------------

  /// End of the season, before the transfers: sponsor money for next year
  /// from the team ranking, and facilities for those who can afford them.
  void closeSeason() {
    // Sponsor money follows the wage level of the whole world: when the
    // field grows stronger and dearer, the money grows with it.
    final index = wageLevel();
    final growth = _wageLevel > 0 ? index / _wageLevel : 1.0;
    _wageLevel = index;
    for (final b in books.values) {
      b.anchorBudget *= growth;
    }
    c.economy.indexAnchor(growth);
    final place = c.rankingPlaces();
    double weight(int rank) => 1 / (1 + 0.04 * (rank - 1));
    for (final e in books.entries) {
      final b = e.value;
      final rank = place[e.key] ?? place.length;
      final target = b.anchorBudget *
          weight(rank) /
          weight(b.anchorRank) *
          c.facilities.marketing(e.key);
      // Sponsor contracts run for years: a third of the way to the target
      // each season, and never more than a quarter up or down.
      final next = (b.budget * 2 / 3 + target / 3)
          .clamp(b.budget * 0.75, b.budget * 1.25)
          .toDouble();
      b.budget = next;
      _build(e.key, b);
      _wear(e.key);
      // Owners and sponsors do not leave profits in the account: what is
      // left beyond a third of the budget after building goes to them.
      b.balance = min(b.balance, savingsShare * b.budget);
    }
  }

  /// The market wage of every rider under contract with a team, summed:
  /// the wage level of the world.
  ///
  /// @returns Euros per year.
  double wageLevel() {
    var sum = 0.0;
    for (final r in c.riderById.values) {
      final team = c.teams[r.teamId];
      if (team == null || team.division == 'Free') continue;
      sum += c.economy.marketWage(r);
    }
    return sum;
  }

  /// Wage level at the start of the career or the last turn of the year.
  double _wageLevel = 0;

  /// A team whose savings pay for it and still leave its reserve raises its
  /// weakest facility by one level, up to what fits its strength, so that
  /// the levels of the world do not climb from season to season.
  void _build(int teamId, TeamBooks b) {
    final levels = c.facilities.levels[teamId];
    if (levels == null) return;
    final weakest = Facility.values
        .reduce((x, y) => (levels[y] ?? 3) < (levels[x] ?? 3) ? y : x);
    final level = levels[weakest] ?? 3;
    if (level >= c.facilities.fitting(teamId)) return;
    final cost = c.facilities.costAt(teamId, level);
    if (b.balance - cost < reserveShare * b.budget) return;
    b.balance -= cost;
    levels[weakest] = level + 1;
  }

  /// A facility above what fits a team's strength is not kept up to date:
  /// each season it loses a level with a chance of three in ten. Building
  /// up to what fits and wearing down from above keep the levels of the
  /// world where they started.
  void _wear(int teamId) {
    final levels = c.facilities.levels[teamId];
    if (levels == null) return;
    final fits = c.facilities.fitting(teamId);
    for (final f in Facility.values) {
      final level = levels[f] ?? 3;
      if (level <= fits) continue;
      if (Economy.unit(teamId * 7 + f.index, c.year) < 0.3) {
        levels[f] = level - 1;
      }
    }
  }

  // --- Saving ----------------------------------------------------------------

  /// @returns Everything as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'level': _wageLevel,
        for (final e in books.entries)
          '${e.key}': [
            e.value.budget,
            e.value.balance,
            e.value.anchorBudget,
            e.value.anchorRank,
            e.value.prizeMonth,
          ],
      };

  /// @param j A map written by [toJson], or null for a save from before
  ///   every team kept books.
  void restore(Map<String, dynamic>? j) {
    books.clear();
    if (j == null) {
      _open();
      return;
    }
    _wageLevel = (j['level'] as num?)?.toDouble() ?? wageLevel();
    for (final e in j.entries) {
      if (e.key == 'level') continue;
      final v = e.value as List<dynamic>;
      books[int.parse(e.key)] = TeamBooks(
        (v[0] as num).toDouble(),
        (v[1] as num).toDouble(),
        (v[2] as num).toDouble(),
        v[3] as int,
      )..prizeMonth = (v[4] as num).toDouble();
    }
  }
}
