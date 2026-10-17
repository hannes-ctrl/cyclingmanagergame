import 'dart:math';

import 'career.dart';
import 'package:sim/sim.dart';

/// The player as a manager: his reputation in the sport, the board's
/// verdict on his work and the offers of other teams.
///
/// Reputation runs from 0 to 100. It starts at the level of the team he
/// takes over, rises when his team finishes the season above what its
/// strength promised and when it meets its goals, falls otherwise, and
/// drifts a little towards the level of the team he runs.
///
/// On 1 November, when the races are over, the board meets: it judges the
/// season by the confidence the goals will leave it with. A first bad
/// season brings a warning, a second one in a row the dismissal at the end
/// of the year. On the same day other teams may offer him a job, as a talk
/// in the inbox; a dismissed manager always gets offers, from weaker teams.
/// An accepted offer takes effect at the turn of the year: he takes over
/// the new team with its riders, staff, money and sponsors, the old team
/// goes on without him. Warnings, dismissal and offers only come with the
/// job market switched on under "Delegation"; the reputation moves always.
class Manager {
  /// Starts at the level of the team the player takes over.
  ///
  /// @param c The career, with its teams in place.
  Manager(this.c) : expected = c.economy.strengthRank() {
    reputation = levelOf(expected);
  }

  final Career c;

  /// Reputation, 0 to 100.
  late double reputation;

  /// Place among all teams by strength at the start of the season: what
  /// the season is measured against.
  int expected;

  /// Whether the board has warned him and the warning still stands.
  bool warned = false;

  /// Whether the board ends his work at the end of the season.
  bool dismissed = false;

  /// Teams that offered him a job this autumn.
  final offers = <int>[];

  /// The team he will run from the turn of the year, or null.
  int? nextTeam;

  /// The team he ran per season.
  final seasons = <int, int>{};

  /// His reputation at the end of each season.
  final marks = <int, double>{};

  /// Below this projected confidence the board is unhappy.
  static const unhappy = 25.0;

  /// From this projected confidence on, a warning is forgotten.
  static const content = 40.0;

  /// The reputation that fits a team of a place among all teams by
  /// strength: 85 for the strongest, 15 from about place 60 on.
  ///
  /// @param rank Place by strength, 1 for the strongest.
  /// @returns The reputation.
  static double levelOf(int rank) =>
      (85 - 1.2 * (rank - 1)).clamp(15.0, 85.0).toDouble();

  /// The place by strength of the teams a manager of a reputation may hope
  /// to run.
  ///
  /// @param reputation His reputation.
  /// @returns The place.
  static int reachOf(double reputation) => 1 + ((85 - reputation) / 1.2).ceil();

  /// The reputation as a word.
  String get standing => switch (reputation) {
        >= 75 => tr('World class'),
        >= 60 => tr('Respected'),
        >= 45 => tr('Established'),
        >= 30 => tr('Promising'),
        _ => tr('Unknown'),
      };

  /// At the start of a season: what it will be measured against.
  void openSeason() {
    expected = c.economy.strengthRank();
    offers.clear();
    nextTeam = null;
    dismissed = false;
  }

  /// Daily: on 1 November the board meets and other teams make offers.
  void daily() {
    final t = c.today;
    if (t.month == 11 && t.day == 1) _autumn();
  }

  void _autumn() {
    final rank = c.rankingPlaces()[c.teamId] ?? c.teams.length;
    final goals = c.economy.goals;
    final met = goals.where((g) => g.achieved()).length;
    final before = reputation;
    reputation = (reputation +
            ((expected - rank) * 0.6).clamp(-8.0, 10.0) +
            1.5 * met -
            (goals.length - met) +
            0.1 * (levelOf(rank) - reputation))
        .clamp(0.0, 100.0)
        .toDouble();
    final change = (reputation - before).round();

    final projected = c.economy.projectedConfidence();
    final market = c.delegation.jobMarket;
    var verdict = '';
    if (!market) {
      // Without the job market he keeps his job whatever happens.
    } else if (projected < unhappy) {
      if (warned) {
        dismissed = true;
        verdict = tr(
            'The board has lost its confidence and ends your work at the end of the season. Other teams will offer you a job.');
      } else {
        warned = true;
        verdict = tr(
            'The board is unhappy with the season and expects a clear improvement next year; another season like this would cost you the job.');
      }
    } else if (projected >= content) {
      warned = false;
    }
    c.inbox.add(Message(
      c.today,
      tr('Board'),
      tr('Your reputation: {0}', [standing]),
      tr(
          'Reputation {0} of 100 ({1}{2}): place {3} in the team ranking, where the strength of the team promised place {4}; {5} of {6} goals met. {7}',
          [
            reputation.round(),
            change >= 0 ? '+' : '',
            change,
            rank,
            expected,
            met,
            goals.length,
            verdict,
          ]).trim(),
    ));
    if (market) _makeOffers();
  }

  /// Teams that may offer him a job, from the strongest: every team with a
  /// licence but his own, by strength.
  List<int> _byStrength() => [
        for (final t in c.teams.values)
          if (t.division.startsWith('[')) t.id,
      ]..sort((a, b) => c.teamStrength(b).compareTo(c.teamStrength(a)));

  void _makeOffers() {
    offers.clear();
    final order = _byStrength();
    final own = order.indexOf(c.teamId) + 1;
    final reach = reachOf(reputation);
    final rng = Random(c.seed * 97 + c.year * 13);
    final candidates = <int>[];
    for (final (i, id) in order.indexed) {
      if (id == c.teamId) continue;
      final rank = i + 1;
      if (dismissed) {
        // Only weaker teams want a dismissed manager.
        if (rank > own && rank <= max(own + 15, reach + 5)) candidates.add(id);
      } else if (rank < own && rank >= reach - 2) {
        // A step up, within reach of his reputation.
        if (rng.nextDouble() < 0.35) candidates.add(id);
      }
    }
    if (dismissed) candidates.shuffle(rng);
    for (final id in candidates.take(dismissed ? 3 : 2)) {
      offers.add(id);
      final team = c.teams[id]!;
      c.inbox.add(Message(
        c.today,
        tr('Agent'),
        tr('Job offer from {0}', [team.name]),
        tr('{0} (place {1} by strength) would like you to take over the team from next season. If you accept, you leave {2} at the turn of the year and take over the riders, staff, money and sponsors of {0}.',
            [team.name, order.indexOf(id) + 1, c.teams[c.teamId]!.name]),
        talk: Talk('job', id, [tr('Accept the offer'), tr('Decline')]),
      ));
    }
    if (dismissed && offers.isEmpty) {
      // Nobody at all: the weakest team with a licence takes him.
      final last = order.lastWhere((id) => id != c.teamId);
      offers.add(last);
    }
  }

  /// Answers a job offer.
  ///
  /// @param teamId The team that made it.
  /// @param choice 0 to accept, 1 to decline.
  /// @returns null on success, otherwise the reason.
  String? answer(int teamId, int choice) {
    if (!offers.contains(teamId)) return tr('The offer is no longer open.');
    if (choice == 0) {
      if (nextTeam != null) {
        return tr('You have already accepted the offer of {0}.',
            [c.teams[nextTeam]!.name]);
      }
      nextTeam = teamId;
      return null;
    }
    if (choice == 1) {
      if (nextTeam == teamId) nextTeam = null;
      return null;
    }
    return tr('Unknown answer.');
  }

  /// At the turn of the year, before the new season: the team he runs from
  /// now on, or null if he stays. A dismissed manager who accepted nothing
  /// takes the first offer.
  int? closeSeason() {
    seasons[c.year] = c.teamId;
    marks[c.year] = reputation;
    final to = nextTeam ?? (dismissed ? offers.firstOrNull : null);
    if (to == null || to == c.teamId) return null;
    // A new board, a new start.
    warned = false;
    return to;
  }

  /// @returns The state as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'reputation': reputation,
        'expected': expected,
        'warned': warned,
        'dismissed': dismissed,
        'offers': offers,
        'next': nextTeam,
        'seasons': {for (final e in seasons.entries) '${e.key}': e.value},
        'marks': {for (final e in marks.entries) '${e.key}': e.value},
      };

  /// @param j A map written by [toJson], or null for a save from before
  ///   the manager had a reputation.
  void restore(Map<String, dynamic>? j) {
    if (j == null) return;
    reputation = (j['reputation'] as num).toDouble();
    expected = j['expected'] as int;
    warned = j['warned'] as bool;
    dismissed = j['dismissed'] as bool;
    offers
      ..clear()
      ..addAll((j['offers'] as List).cast<int>());
    nextTeam = j['next'] as int?;
    seasons
      ..clear()
      ..addAll({
        for (final e in (j['seasons'] as Map<String, dynamic>).entries)
          int.parse(e.key): e.value as int,
      });
    marks
      ..clear()
      ..addAll({
        for (final e
            in (j['marks'] as Map<String, dynamic>? ?? const {}).entries)
          int.parse(e.key): (e.value as num).toDouble(),
      });
  }
}
