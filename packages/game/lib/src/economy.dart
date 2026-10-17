import 'dart:math';

import 'package:sim/sim.dart';

import 'career.dart';
import 'founding.dart';
import 'licence.dart';
import 'people.dart';
import 'prizes.dart';
import 'points.dart';

/// A rider's contract. Wages in euros per year.
class Contract {
  Contract(this.wage, this.endYear);
  int wage;

  /// Last year in which the contract is valid.
  int endYear;

  /// Already signed for next season: team, wage, term. The team may be the
  /// current one (a renewal).
  int? nextTeam;
  int nextWage = 0;
  int nextEnd = 0;

  /// After a refusal the rider will not listen to a new offer from the same
  /// team until this day.
  DateTime? refusedUntil;
}

/// What a season goal measures.
enum GoalKind { ranking, grandTourPodium, grandTourStage, wins }

/// A season goal set by sponsor and board.
class Goal {
  Goal(this.kind, this.text, this.weight, this.target, this.achieved);

  /// What is measured.
  final GoalKind kind;

  /// Place or number of wins to reach; unused for the Grand Tour goals.
  final int target;
  final String text;

  /// Weight for the board's confidence, 1 to 3.
  final int weight;

  /// Whether the goal is met as things stand.
  final bool Function() achieved;
}

/// One line of the monthly statement.
class MonthLine {
  MonthLine(this.month, this.sponsor, this.prize, this.wages, this.costs);
  final DateTime month;
  final double sponsor;
  final double prize;
  final double wages;
  final double costs;

  /// Income minus expenses of the month.
  double get result => sponsor + prize - wages - costs;
}

/// A sponsor of the team with a running contract.
class Sponsor {
  Sponsor(this.name, this.amount, this.endYear, {this.demandPlace});
  final String name;

  /// Payment per year.
  double amount;

  /// Last year in which the contract is valid.
  final int endYear;

  /// Place in the team ranking the sponsor demands; if it is missed, he cuts
  /// his payment by a fifth the following year.
  final int? demandPlace;
}

/// What a sponsor wishes for in a season, met by the races themselves.
enum WishKind {
  breakAtHome('A rider in the break at a race in {0}'),
  winAtHome('A win in {0}'),
  breakDays('{0} days in the break'),
  combativity('{0} combativity awards'),
  grandTourStage('A stage win at a Grand Tour'),
  monumentTop10('A top ten in a monument');

  const WishKind(this._text);
  final String _text;
}

/// A sponsor's wish for the season. Met, it brings a bonus of a tenth of
/// his payment at the end of the year.
class SponsorWish {
  SponsorWish(this.kind, this.target, this.country);
  final WishKind kind;

  /// How many: days, awards, or 1.
  final int target;

  /// Country code for the wishes at home.
  final String country;

  /// The wish in the current language.
  String get text => tr(kind._text, [
        kind == WishKind.breakAtHome || kind == WishKind.winAtHome
            ? country
            : target,
      ]);

  /// @returns The wish as a compact list.
  List<Object> toJson() => [kind.index, target, country];

  /// @param j A list written by [toJson].
  /// @returns The wish.
  static SponsorWish fromJson(List<dynamic> j) =>
      SponsorWish(WishKind.values[j[0] as int], j[1] as int, j[2] as String);
}

/// The player's offer to a rider of another team, waiting for his answer.
class PendingOffer {
  PendingOffer(this.wage, this.years, this.promise, this.until);
  final int wage;
  final int years;
  final PromiseKind? promise;

  /// Day of his answer.
  final DateTime until;
}

/// A sponsor's offer for the time after an expiring contract.
class SponsorOffer {
  SponsorOffer(this.name, this.amount, this.years, {this.demandPlace});
  final String name;
  final double amount;
  final int years;
  final int? demandPlace;
}

/// Contracts, finances and transfer market.
///
/// The WorldDB contains neither wages nor budgets; both are derived here
/// from rider strength. As in real cycling there are no transfer fees: riders
/// move at the turn of the year, when a contract runs out.
class Economy {
  Economy(this.c) {
    for (final r in c.riderById.values) {
      // If the WorldDB has no contract end, the contract runs one to three years,
      // fixed per rider; otherwise nearly all contracts would end at once.
      final end = r.contractEnd >= c.year ? r.contractEnd : c.year + r.id % 3;
      contracts[r.id] = Contract(marketWage(r), end);
    }
    budget = wageBill(c.teamId) * 1.45;
    balance = budget * 0.1;
    _anchorBudget = budget;
    _anchorRank = _strengthRank();
    _initSponsors();
    _startSize.length; // record squad sizes now, not on first access
  }

  final Career c;
  final contracts = <int, Contract>{};

  // --- Sponsors ---------------------------------------------------------------
  // Sponsor money comes from three contracts: a main sponsor and two
  // co-sponsors. When one runs out, offers arrive in June; the player picks
  // one or lets the board sign at the end of the year.

  /// Main sponsor first.
  final sponsors = <Sponsor>[];

  /// Offers per slot in [sponsors] while that contract is running out.
  final offers = <int, List<SponsorOffer>>{};

  /// Offer the player accepted per slot; takes effect next season.
  final signed = <int, SponsorOffer>{};

  /// Running search for a further offer: slot and day of the answer.
  final searches = <int, DateTime>{};
  final _searched = <int>{};

  static const _invented = [
    'Nordlicht Energie',
    'Alpenquell',
    'Vela Logistik',
    'Kronberg Bau',
    'Solaris Versicherung',
    'Tessa Mobil',
    'Meridian Bank',
    'Fjordline',
    'Arcada Software',
    'Pico Kaffee',
    'Ostwind Reisen',
    'Granit Werkzeuge',
  ];

  /// Creates the three starting sponsors, named after the parts of the team name.
  void _initSponsors() {
    final parts = (c.teams[c.teamId]?.name ?? '')
        .split(RegExp(r'\s+[-|]\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    String name(int i) =>
        i < parts.length ? parts[i].trim() : _invented[(c.seed + i) % 12];
    // Staggered terms so that there is something to negotiate every year.
    sponsors
      ..clear()
      ..add(Sponsor(name(0), budget * 0.6, c.year + 2))
      ..add(Sponsor(name(1), budget * 0.25, c.year + 1))
      ..add(Sponsor(name(2), budget * 0.15, c.year));
  }

  /// Sets up the finances of a newly founded team.
  ///
  /// @param yearly Sponsor money per year.
  void found(double yearly) {
    budget = yearly;
    balance = yearly * 0.15;
    _anchorBudget = yearly;
    _anchorRank = _strengthRank();
    _initSponsors();
  }

  /// Sets the money of the player's team at the start of a career, once
  /// staff and facilities are known: the same break-even budget as every
  /// other team gets.
  ///
  /// @param yearly Sponsor money per year.
  void startBudget(double yearly) {
    budget = yearly;
    balance = yearly * 0.1;
    _anchorBudget = yearly;
    _initSponsors();
  }

  /// Moves the money the sponsors measure their offers against with the
  /// wage level of the world.
  ///
  /// @param factor Growth of the wage level over the season.
  void indexAnchor(double factor) => _anchorBudget *= factor;

  /// Scales every sponsor's payment (promotion or relegation).
  ///
  /// @param factor Multiplier on the yearly amounts.
  void scaleSponsors(double factor) {
    for (final s in sponsors) {
      s.amount *= factor;
    }
    budget = sponsors.fold(0.0, (sum, s) => sum + s.amount);
  }

  /// Place of the player's team in the team ranking of the current season;
  /// without points, behind every team with points, by strength.
  int get ownRank => c.rankingPlaces()[c.teamId] ?? c.teams.length;

  double _offerBase(Sponsor s) {
    // What the slot is worth: its share of the budget the team had at the
    // start, moved by how far the team has climbed or fallen in the
    // ranking since, and a little by the board's standing with sponsors.
    final i = sponsors.indexOf(s);
    final share = const [0.6, 0.25, 0.15][(i < 0 ? 2 : i).clamp(0, 2)];
    double weight(int rank) => 1 / (1 + 0.04 * (rank - 1));
    return share *
        _anchorBudget *
        weight(ownRank) /
        weight(_anchorRank) *
        (0.9 + 0.2 * confidence / 100);
  }

  /// Budget and place in the team ranking at the start of the career (or
  /// when the team was founded): what sponsor offers are measured against.
  double _anchorBudget = 0;
  int _anchorRank = 1;

  /// Place of the player's team among all teams by strength, as at the
  /// start of a career before any race.
  int _strengthRank() {
    final order = [
      for (final t in c.teams.values)
        if (t.division != 'Free') t.id,
    ]..sort((a, b) => c.teamStrength(b).compareTo(c.teamStrength(a)));
    return order.indexOf(c.teamId) + 1;
  }

  /// 1 June: offers arrive for expiring contracts.
  void _openSponsorSearch() {
    final names = <String>[];
    for (var i = 0; i < sponsors.length; i++) {
      final s = sponsors[i];
      if (s.endYear != c.year) continue;
      final rng = Random(c.seed * 131 + c.year * 7 + i);
      final base = _offerBase(s);
      String invented() => _invented[rng.nextInt(_invented.length)];
      offers[i] = [
        // The current sponsor only stays if the board is satisfied.
        if (confidence >= 35) SponsorOffer(s.name, base, 2),
        SponsorOffer(invented(), base * 0.94, 3),
        SponsorOffer(invented(), base * 1.15, 2, demandPlace: max(3, ownRank)),
      ];
      names.add(s.name);
    }
    if (names.isEmpty) return;
    c.inbox.add(Message(
      c.today,
      tr('Board'),
      tr('Sponsor search {0}', [c.year + 1]),
      tr('Expiring at the end of the year: {0}. Offers for a successor are under Finances. If you choose nothing by December, the board signs.',
          [names.join(', ')]),
    ));
  }

  /// Has the board look for a further offer for a month. Once per expiring
  /// contract.
  ///
  /// @param slot Index in [sponsors].
  /// @returns null on success, otherwise the reason.
  String? searchSponsor(int slot) {
    if (!offers.containsKey(slot))
      return tr('No search is running for this slot.');
    if (signed.containsKey(slot)) return tr('This has already been signed.');
    if (_searched.contains(slot))
      return tr('The market has nothing more to offer.');
    _searched.add(slot);
    searches[slot] = c.today.add(const Duration(days: 30));
    return null;
  }

  /// Accepts an offer; it takes effect next season.
  ///
  /// @param slot Index in [sponsors].
  /// @param index Index of the offer in [offers] for that slot.
  /// @returns null on success, otherwise the reason.
  String? acceptSponsor(int slot, int index) {
    final list = offers[slot];
    if (list == null || index < 0 || index >= list.length) {
      return tr('The offer no longer exists.');
    }
    if (signed.containsKey(slot)) return tr('This has already been signed.');
    signed[slot] = list[index];
    searches.remove(slot);
    c.inbox.add(Message(
      c.today,
      tr('Board'),
      tr('{0} becomes a sponsor', [list[index].name]),
      tr('{0} pays {3} a year for {2} years from {1}.', [
        list[index].name,
        c.year + 1,
        list[index].years,
        _euro(list[index].amount)
      ]),
    ));
    return null;
  }

  /// Delivers the extra offers of searches that are due today.
  void _finishSearches() {
    for (final slot in searches.keys.toList()) {
      if (searches[slot]!.isAfter(c.today)) continue;
      searches.remove(slot);
      final rng = Random(c.seed * 977 + c.year * 13 + slot);
      // The better the reputation, the more likely someone pays more.
      final factor = 0.95 + 0.3 * rng.nextDouble() * (0.5 + confidence / 100);
      final offer = SponsorOffer(_invented[rng.nextInt(_invented.length)],
          _offerBase(sponsors[slot]) * factor, 1 + rng.nextInt(3));
      offers[slot]?.add(offer);
      c.inbox.add(Message(
        c.today,
        tr('Board'),
        tr('Another sponsor offer'),
        tr('{0} offers {1} a year for {2} years.',
            [offer.name, _euro(offer.amount), offer.years]),
      ));
    }
  }

  /// The wish of each sponsor for the season, by slot in [sponsors].
  final wishes = <SponsorWish>[];

  /// What the team did this season that sponsors care about: `win:<country>`,
  /// `break:<country>` and `monument10`.
  final feats = <String, int>{};

  /// Slots whose wish has been met this season.
  final wishesMet = <int>{};

  /// Share of his payment a sponsor adds when his wish is met.
  static const wishBonus = 0.1;

  /// Draws the sponsors' wishes for a season. A big team's sponsors want
  /// big results; a small team's want to be seen, in the break and at home.
  void _drawWishes() {
    wishes.clear();
    wishesMet.clear();
    feats.clear();
    final rank = _strengthRank();
    final home = c.teams[c.teamId]?.country ?? '';
    final options = rank <= 10
        ? [
            SponsorWish(WishKind.monumentTop10, 1, home),
            SponsorWish(WishKind.grandTourStage, 1, home),
            SponsorWish(WishKind.winAtHome, 1, home),
          ]
        : rank <= 25
            ? [
                SponsorWish(WishKind.winAtHome, 1, home),
                SponsorWish(WishKind.grandTourStage, 1, home),
                SponsorWish(WishKind.breakDays, 25, home),
                SponsorWish(WishKind.combativity, 5, home),
              ]
            : [
                SponsorWish(WishKind.breakAtHome, 1, home),
                SponsorWish(WishKind.breakDays, 15, home),
                SponsorWish(WishKind.combativity, 3, home),
                SponsorWish(WishKind.winAtHome, 1, home),
              ];
    options.shuffle(Random(c.seed * 53 + c.year * 7));
    for (var i = 0; i < sponsors.length; i++) {
      wishes.add(options[i % options.length]);
    }
  }

  /// @param w A wish.
  /// @returns How far the team has come towards it this season.
  int progressOf(SponsorWish w) => switch (w.kind) {
        WishKind.breakAtHome => feats['break:${w.country}'] ?? 0,
        WishKind.winAtHome => feats['win:${w.country}'] ?? 0,
        WishKind.breakDays => c.teamBreakDays(c.teamId),
        WishKind.combativity => c.teamCombative(c.teamId),
        WishKind.grandTourStage => grandTourStage ? 1 : 0,
        WishKind.monumentTop10 => feats['monument10'] ?? 0,
      };

  /// Counts what the day's stages did for the sponsors' wishes, and tells
  /// the player when one is met.
  ///
  /// @param ridden Today's stages.
  void _countFeats(
      List<({RaceProgress race, int stageIndex, StageResult result})> ridden) {
    for (final day in ridden) {
      final country = day.race.race.info.country;
      final result = day.result;
      if (result.traces.entries.any(
          (e) => e.value.inBreak && c.riderById[e.key]?.teamId == c.teamId)) {
        feats['break:$country'] = (feats['break:$country'] ?? 0) + 1;
      }
      if (result.placings.first.rider.teamId == c.teamId) {
        feats['win:$country'] = (feats['win:$country'] ?? 0) + 1;
      }
      if (day.race.race.tier == RaceTier.monument &&
          result.placings.take(10).any((x) => x.rider.teamId == c.teamId)) {
        feats['monument10'] = (feats['monument10'] ?? 0) + 1;
      }
    }
    for (var i = 0; i < wishes.length && i < sponsors.length; i++) {
      final w = wishes[i];
      if (wishesMet.contains(i) || progressOf(w) < w.target) continue;
      wishesMet.add(i);
      c.inbox.add(Message(
        c.today,
        tr('Board'),
        tr('{0} is pleased', [sponsors[i].name]),
        tr('The wish of {0} for this season is met: {1}. A bonus of {2} follows at the end of the year.',
            [sponsors[i].name, w.text, _euro(sponsors[i].amount * wishBonus)]),
      ));
    }
  }

  /// End of the year: check demands, start new contracts.
  ///
  /// @param lines Receives sentences for the season summary.
  void _settleSponsors(List<String> lines) {
    final rank = ownRank;
    for (final i in wishesMet) {
      if (i >= sponsors.length) continue;
      final bonus = sponsors[i].amount * wishBonus;
      balance += bonus;
      lines.add(tr('{0} pays a bonus of {1} for the wish that was met',
          [sponsors[i].name, _euro(bonus)]));
    }
    for (var i = 0; i < sponsors.length; i++) {
      final s = sponsors[i];
      if (s.endYear > c.year) {
        final place = s.demandPlace;
        if (place != null && rank > place) {
          s.amount *= 0.8;
          lines.add(tr(
              '{0} cuts a fifth because place {1} in the team ranking was missed',
              [s.name, place]));
        }
        continue;
      }
      final list = offers[i] ?? const <SponsorOffer>[];
      final next = signed[i] ??
          (list.isNotEmpty
              ? list.first
              : SponsorOffer(s.name, _offerBase(s) * 0.9, 1));
      if (!signed.containsKey(i)) {
        lines.add(tr('The board has signed with {0}', [next.name]));
      }
      sponsors[i] = Sponsor(next.name, next.amount, c.year + next.years,
          demandPlace: next.demandPlace);
    }
    offers.clear();
    signed.clear();
    searches.clear();
    _searched.clear();
    budget = sponsors.fold(0.0, (sum, s) => sum + s.amount);
  }

  double _charged = 0;

  /// Books a one-off expense (a training camp, say); it appears in the next
  /// monthly statement under running costs.
  ///
  /// @param amount Amount in euros.
  void charge(double amount) => _charged += amount;

  /// Money that can still be spent: the balance less what is already booked
  /// for the next monthly statement, such as camps booked this month.
  double get available => balance - _charged;

  /// Sponsor money per year.
  late double budget;
  late double balance;

  /// Confidence of the board, 0 to 100. Decides what sponsors offer.
  double confidence = 60;
  final ledger = <MonthLine>[];
  var goals = <Goal>[];

  /// Wins of the player's team in the current season (stages and races).
  int wins = 0;
  bool grandTourPodium = false;
  bool grandTourStage = false;
  double _prize = 0;

  /// @param r A rider.
  /// @returns Whether he is without a team: he can be signed at any time
  ///   and joins at once.
  bool isFreeAgent(SimRider r) => r.teamId == _freeTeam;

  /// Id of the pseudo team that holds the free agents.
  int get _freeTeam =>
      c.teams.values.where((t) => t.division == 'Free').firstOrNull?.id ?? 0;

  /// A rider's strength as one number: his best attribute counts most.
  ///
  /// @param r The rider.
  /// @returns The rating on the attribute scale.
  static double rating(SimRider r) {
    final a = r.attributes;
    final main = [a.flat, a.mountain, a.hill, a.timeTrial, a.sprint, a.cobble]
      ..sort((x, y) => y.compareTo(x));
    return 0.7 * main[0] + 0.3 * (main[0] + main[1] + main[2]) / 3;
  }

  /// @param r A rider.
  /// @returns The yearly wage the market pays for him, in euros.
  int marketWage(SimRider r) {
    final age = c.year - r.born ~/ 10000;
    var wage = 45000 * exp((rating(r) - 66) * 0.24);
    if (age < 23) wage *= 0.7;
    if (age > 33) wage *= 0.8;
    if (age < 25 && r.potential >= 5.5) wage *= 1.3;
    return (max(15000.0, wage) / 1000).round() * 1000;
  }

  /// @param teamId Team id.
  /// @param nextSeason Whether to count next season's contracts instead.
  /// @returns The sum of all wages in euros per year.
  int wageBill(int teamId, {bool nextSeason = false}) {
    var sum = 0;
    for (final r in c.riderById.values) {
      final k = contracts[r.id];
      if (k == null) continue;
      if (!nextSeason) {
        if (r.teamId == teamId) sum += k.wage;
      } else if (k.nextTeam == teamId) {
        sum += k.nextWage;
      } else if (k.nextTeam == null &&
          r.teamId == teamId &&
          k.endYear > c.year) {
        sum += k.wage;
      }
    }
    return sum;
  }

  /// The wage bill of every team for next season as things stand, in one
  /// pass over all riders.
  ///
  /// @returns Euros per year by team id.
  Map<int, double> nextWageBills() {
    final bills = <int, double>{};
    for (final r in c.riderById.values) {
      final k = contracts[r.id];
      if (k == null) continue;
      final team = k.nextTeam ?? (k.endYear > c.year ? r.teamId : null);
      if (team == null) continue;
      bills[team] = (bills[team] ?? 0) +
          (k.nextTeam != null ? k.nextWage : k.wage).toDouble();
    }
    return bills;
  }

  /// @param teamId Team id.
  /// @returns The squad size next season as things stand today.
  int squadNextSeason(int teamId) => c.riderById.values.where((r) {
        final k = contracts[r.id];
        if (k == null) return false;
        return k.nextTeam == teamId ||
            (k.nextTeam == null && r.teamId == teamId && k.endYear > c.year);
      }).length;

  /// From August on, contracts for next season may be signed.
  bool get windowOpen => c.today.month >= 8 && !c.seasonOver;

  /// @param r A rider.
  /// @returns Whether his contract ends this year with nothing signed yet.
  bool expiring(SimRider r) {
    final k = contracts[r.id];
    return k != null && k.endYear <= c.year && k.nextTeam == null;
  }

  /// Whether a rider whose contract runs out ends his career after the
  /// season instead of signing again: from 31 on, the more likely the older
  /// he is, half as likely for a rider who is still among the best. Fixed
  /// per rider and season.
  ///
  /// @param r The rider.
  /// @returns Whether he retires.
  bool retiring(SimRider r) {
    final k = contracts[r.id];
    if (k == null || k.endYear > c.year) return false;
    final age = c.year - r.born ~/ 10000;
    if (age < 31) return false;
    var p = switch (age) {
      31 => 0.15,
      32 => 0.3,
      33 => 0.45,
      34 => 0.6,
      35 => 0.75,
      _ => 0.9,
    };
    if (rating(r) >= 80) p /= 2;
    return unit(r.id, c.year) < p;
  }

  /// A number from 0 to 1 fixed by two integers, such as a rider and a
  /// year. Unlike a plain product modulo 1000, it is unrelated for
  /// neighbouring years and to the rider's mood in [demand]: with the
  /// product, a rider's roll only alternated between two values, so some
  /// riders whose contracts ran out in every other year never retired.
  ///
  /// @param a First number.
  /// @param b Second number.
  /// @returns A number in [0, 1).
  static double unit(int a, int b) {
    var h = (a * 0x9E3779B1 + b * 0x85EBCA77 + 0x165667B1) & 0xFFFFFFFF;
    h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF;
    h = ((h ^ (h >> 12)) * 0x297A2D39) & 0xFFFFFFFF;
    h ^= h >> 15;
    return h / 0x100000000;
  }

  /// @returns Riders of other teams who are available for next season.
  List<SimRider> market() => [
        for (final r in c.riderById.values)
          if (r.teamId != c.teamId && expiring(r) && !retiring(r)) r,
      ];

  /// What a rider asks of the player's team. He wants more for a move than
  /// for a renewal, and every rider is a little different.
  ///
  /// @param r The rider.
  /// @returns The wage he demands, in euros per year.
  int demand(SimRider r) {
    final mood = ((r.id * 2654435761) % 1000) / 1000; // fixed per rider, 0 to 1
    var factor = 0.92 + 0.2 * mood;
    if (r.teamId == _freeTeam) {
      // Without a team he takes less rather than wait.
      factor -= 0.3;
    } else if (r.teamId != c.teamId) {
      factor += 0.1;
    } else {
      // His own rider: loyalty and mood count.
      factor *= c.people.demandFactor(r.id);
    }
    return (marketWage(r) * factor / 1000).round() * 1000;
  }

  /// Makes an offer on behalf of the player.
  ///
  /// @param riderId Id of the rider.
  /// @param wage Offered wage in euros per year.
  /// @param years Contract term.
  /// @param promise What the player promises him for the first season of
  ///   the contract, or null. With a promise he asks a little less.
  /// @returns null if he signs, otherwise the reason for the refusal.
  String? offer(int riderId, int wage, int years, {PromiseKind? promise}) {
    final r = c.riderById[riderId];
    final k = contracts[riderId];
    if (r == null || k == null) return tr('Rider not found.');
    // His own riders can be renewed at any time, also before their contract
    // runs out; the new terms apply from next season.
    final own = r.teamId == c.teamId;
    if (!expiring(r) && !(own && k.nextTeam == null))
      return tr('The contract is still running or already settled.');
    if (pending.containsKey(riderId)) {
      return tr('He is still considering your offer.');
    }
    // A rider without a team can be signed at any time and joins at once.
    final free = r.teamId == _freeTeam;
    if (!free && !own && !windowOpen)
      return tr('Contract talks are only possible from 1 August.');
    if (retiring(r)) {
      return tr('He has decided to end his career after this season.');
    }
    if (k.refusedUntil?.isAfter(c.today) ?? false) {
      return tr(
          'After the last refusal he does not want to negotiate again yet.');
    }
    // An own rider whose contract still runs is already counted for next
    // season, with his present wage.
    final counted = own && k.endYear > c.year;
    if (!counted && squadNextSeason(c.teamId) >= 30) {
      return tr('The squad for next season is full with 30 riders.');
    }
    if (free && (c.squads[c.teamId]?.length ?? 0) >= 30) {
      return tr('The squad is full with 30 riders.');
    }
    final limit = c.finances.wageLimit(c.teamId);
    if (wageBill(c.teamId, nextSeason: true) - (counted ? k.wage : 0) + wage >
            limit ||
        free && wageBill(c.teamId) + wage > limit) {
      return tr(
          'The board does not approve the wage: the wage budget would be exceeded.');
    }
    final wanted = promise == null
        ? demand(r)
        : (demand(r) * (1 - People.promiseDiscount) / 1000).round() * 1000;
    if (wage < wanted) {
      k.refusedUntil = c.today.add(const Duration(days: 14));
      // The agent only names the ballpark.
      final hint = (wanted / 50000).ceil() * 50000;
      return tr(
          'Declined. His agent speaks of at least {0} a year.', [_euro(hint)]);
    }
    if (!free && !own) {
      // A rider of another team takes a week and hears what else is on
      // offer before he decides.
      final until = c.today.add(const Duration(days: answerDays));
      pending[riderId] = PendingOffer(wage, years.clamp(1, 4), promise, until);
      final rivals = _rivals(r).take(3).map((x) => x.team.name).toList();
      c.inbox.add(Message(
        c.today,
        tr('Agent'),
        tr('{0} considers your offer', [r.name]),
        tr('{0} will answer by {1}.{2}.', [
              c.fullName(r.id),
              until.day.toString().padLeft(2, '0'),
              until.month.toString().padLeft(2, '0'),
            ]) +
            (rivals.isEmpty
                ? ''
                : ' ${tr('Also interested: {0}.', [rivals.join(', ')])}'),
      ));
      return null;
    }
    if (free) {
      // He joins today; before August the running season is the first of
      // his contract, from August the next one.
      _move(r, c.teamId);
      c.teamJoined(c.teamId);
      k
        ..wage = wage
        ..endYear = c.year + years.clamp(1, 4) - (windowOpen ? 0 : 1);
    } else {
      k
        ..nextTeam = c.teamId
        ..nextWage = wage
        ..nextEnd = c.year + years.clamp(1, 4);
    }
    if (promise != null) c.people.promiseSeason(riderId, promise);
    c.inbox.add(Message(
      c.today,
      tr('Agent'),
      free
          ? tr('{0} joins the team', [r.name])
          : r.teamId == c.teamId
              ? tr('{0} extends', [r.name])
              : tr('{0} signs for {1}', [r.name, c.year + 1]),
      tr('{0} has signed for {1} a year until {2}.',
              [c.fullName(r.id), _euro(wage), free ? k.endYear : k.nextEnd]) +
          (promise == null
              ? ''
              : ' ${tr('Promised for {0}: {1}.', [
                      c.year + 1,
                      People.seasonText(promise)
                    ])}'),
    ));
    return null;
  }

  /// Days a rider of another team takes to answer an offer.
  static const answerDays = 7;

  /// The player's offers waiting for an answer, by rider id.
  final pending = <int, PendingOffer>{};

  /// How much a team's offer appeals to a rider: the wage against his
  /// worth, the level of the team, whether he would lead there, and home.
  ///
  /// @param r The rider.
  /// @param team Id of the team.
  /// @param wage The wage offered.
  /// @returns A score; the highest wins.
  double appeal(SimRider r, int team, int wage) {
    final level = c.teamStrength(team);
    final rating = Economy.rating(r);
    return wage / marketWage(r) +
        0.03 * (level - rating).clamp(-4.0, 6.0) +
        (rating >= level ? 0.05 : 0) +
        (c.teams[team]?.country == r.country ? 0.08 : 0);
  }

  /// The other teams that would bid for a rider now: those he suits, with
  /// room in the squad and a wage they can pay, the most appealing first.
  ///
  /// @param r The rider.
  /// @returns Team and wage of each bid.
  List<({TeamInfo team, int wage, double appeal})> _rivals(SimRider r) {
    final bills = nextWageBills();
    final out = <({TeamInfo team, int wage, double appeal})>[];
    final market = marketWage(r);
    for (final team in c.teams.values) {
      if (team.id == c.teamId || team.division == 'Free') continue;
      final target = _target(team);
      if (target == 0 || squadNextSeason(team.id) >= target) continue;
      if (team.division == 'Under23' && c.year + 1 - r.born ~/ 10000 > 22) {
        continue;
      }
      final level = c.teamStrength(team.id);
      final own = team.id == r.teamId;
      if (rating(r) > level + 6 || (!own && outlook(r) < level - 9)) continue;
      if (own && !_worthKeeping(r, level - 3)) continue;
      final room = c.finances.wageLimit(team.id) - (bills[team.id] ?? 0);
      if (room < market * 0.8) continue;
      final wage = min(market, (room / 1000).floor() * 1000);
      // His own team counts a little more: he knows it, and it knows him.
      final a = appeal(r, team.id, wage) +
          (own ? 0.1 * c.people.of(r.id).loyalty : 0);
      out.add((team: team, wage: wage, appeal: a));
    }
    return out..sort((a, b) => b.appeal.compareTo(a.appeal));
  }

  /// Riders whose time to answer is up decide between the player's offer
  /// and the best bid of the other teams.
  void _answerOffers() {
    for (final id in pending.keys.toList()) {
      final o = pending[id]!;
      if (o.until.isAfter(c.today)) continue;
      pending.remove(id);
      final r = c.riderById[id];
      final k = contracts[id];
      if (r == null || k == null || !expiring(r) || retiring(r)) continue;
      final rivals = _rivals(r);
      final mine = appeal(r, c.teamId, o.wage) + (o.promise == null ? 0 : 0.05);
      final best = rivals.firstOrNull;
      if (best != null && best.appeal > mine) {
        _sign(r, best.team.id, 1 + (r.id + c.year) % 3, wage: best.wage);
        c.inbox.add(Message(
          c.today,
          tr('Agent'),
          tr('{0} chooses {1}', [r.name, best.team.name]),
          tr('{0} has turned down your offer and signed with {1} for {2} a year.',
              [c.fullName(r.id), best.team.name, _euro(best.wage)]),
        ));
        continue;
      }
      // The squad or the wage limit may have filled up in the meantime.
      if (squadNextSeason(c.teamId) >= 30 ||
          wageBill(c.teamId, nextSeason: true) + o.wage >
              c.finances.wageLimit(c.teamId)) {
        c.inbox.add(Message(
          c.today,
          tr('Agent'),
          tr('{0} cannot join', [r.name]),
          tr('{0} would have signed, but the squad or the wage budget for next season is full now.',
              [c.fullName(r.id)]),
        ));
        continue;
      }
      k
        ..nextTeam = c.teamId
        ..nextWage = o.wage
        ..nextEnd = c.year + o.years;
      if (o.promise != null) c.people.promiseSeason(id, o.promise!);
      c.inbox.add(Message(
        c.today,
        tr('Agent'),
        tr('{0} signs for {1}', [r.name, c.year + 1]),
        tr('{0} has signed for {1} a year until {2}.',
                [c.fullName(r.id), _euro(o.wage), k.nextEnd]) +
            (rivals.isEmpty
                ? ''
                : ' ${tr('He turned down {0}.', [rivals.first.team.name])}'),
      ));
    }
  }

  /// Oldest a rider may be next season to ride for a development team.
  static const devMaxAge = 22;

  /// Largest squad of a development team.
  static const devSquadMax = 16;

  /// Whether a rider can be signed for the player's development team:
  /// young enough, his contract running out, and not too strong for it.
  ///
  /// @param r The rider.
  /// @returns null if he can, otherwise the reason.
  String? devReason(SimRider r) {
    final dev = c.devTeam.teamId;
    if (dev == null) return tr('The team has no development team.');
    if (c.year + 1 - r.born ~/ 10000 > devMaxAge) {
      return tr('Only riders up to {0} can ride for the development team.',
          [devMaxAge]);
    }
    if (rating(r) >= 76) {
      return tr(
          'He is too strong for a development team and wants to turn professional.');
    }
    return null;
  }

  /// Offers a young rider a place in the player's development team. The
  /// development team pays its riders out of its yearly cost, so the offer
  /// costs nothing beyond it; a rider takes it if nothing better is signed.
  ///
  /// @param riderId Id of the rider.
  /// @param years Contract term, one or two years.
  /// @returns null if he signs, otherwise the reason for the refusal.
  String? offerDev(int riderId, int years) {
    final r = c.riderById[riderId];
    final k = contracts[riderId];
    if (r == null || k == null) return tr('Rider not found.');
    final reason = devReason(r);
    if (reason != null) return reason;
    if (!expiring(r)) {
      return tr('The contract is still running or already settled.');
    }
    if (!windowOpen) {
      return tr('Contract talks are only possible from 1 August.');
    }
    if (k.refusedUntil?.isAfter(c.today) ?? false) {
      return tr(
          'He does not want to negotiate again yet after the last refusal.');
    }
    final dev = c.devTeam.teamId!;
    if (squadNextSeason(dev) >= devSquadMax) {
      return tr('The development team is full with {0} riders.', [devSquadMax]);
    }
    k
      ..nextTeam = dev
      ..nextWage = 20000
      ..nextEnd = c.year + years.clamp(1, 2);
    c.inbox.add(Message(
      c.today,
      tr('Development team'),
      tr('{0} joins the development team', [r.name]),
      tr('{0} rides for {1} from {2} until {3}.', [
        c.fullName(r.id),
        c.devTeam.team?.name ?? '',
        c.year + 1,
        k.nextEnd,
      ]),
    ));
    return null;
  }

  /// @param v An amount in euros.
  /// @returns It as text, in millions from one million on.
  static String euro(num v) => _euro(v);

  static String _euro(num v) => v.abs() >= 1000000
      ? tr('{0} m €', [dec(v / 1000000, 2)])
      : '${(v / 1000).round()}.000 €';

  // --- Daily routine ----------------------------------------------------------

  /// Daily bookkeeping: wins, monthly statement, market rounds, sponsors.
  ///
  /// @param ridden Today's stages.
  void daily(
      List<({RaceProgress race, int stageIndex, StageResult result})> ridden) {
    for (final day in ridden) {
      _prizeMonth += Prizes.kept(day.race, day.result, c.teamId);
      final tier = day.race.race.tier;
      final p = day.result.placings;
      if (p.first.rider.teamId == c.teamId) {
        wins++;
        if (tier == RaceTier.grandTour) grandTourStage = true;
      }
      if (day.race.finished && tier == RaceTier.grandTour) {
        final gc = day.race.run.standings.last.general;
        if (gc.take(3).any((e) => e.rider.teamId == c.teamId)) {
          grandTourPodium = true;
        }
      }
    }
    _countFeats(ridden);
    _answerOffers();
    final t = c.today;
    if (t.day == 1) _closeMonth();
    if (t.day == 1 && t.month == 6) _openSponsorSearch();
    if (searches.isNotEmpty) _finishSearches();
    // The other teams settle their contracts in four waves.
    if (t.day == 15 && t.month >= 8 && t.month <= 11) _marketWave();
    if (t.day == 1 && t.month == 8) _watchNotice();
    if (t.day == 1 && t.month == 8) _retirementNotice();
    if (t.day == 1 && t.month == 11) _newIntake();
    // Right at the start of the signing period, before other teams move in.
    if (t.day == 1 && t.month == 8 && autoRenew) _renewOwn();
  }

  /// Prize money won since the last monthly statement.
  double _prizeMonth = 0;

  /// Writes the monthly statement and updates the balance.
  void _closeMonth() {
    _prize = _prizeMonth;
    _prizeMonth = 0;
    final line = MonthLine(
      c.today,
      budget / 12,
      _prize,
      wageBill(c.teamId) / 12,
      // Travel, equipment and running the team, staff, facilities and the
      // development team, less what the suppliers pay: the same running
      // costs as for every other team.
      c.finances.runningCosts(c.teamId) / 12 + _charged,
    );
    _charged = 0;
    ledger.add(line);
    balance += line.result;
  }

  /// One round on the market: teams renew with their own riders and sign
  /// expiring riders of other teams. The best go first.
  void _marketWave() {
    final rng = c.rng;
    // What every team will pay next season; a team signs only within its
    // wage limit.
    final bills = nextWageBills();
    final limits = <int, double>{};
    // What a team offers: the market wage if it fits its limit, otherwise
    // what is left, as long as that is four fifths of the market wage; a
    // rider takes less from a team that wants him rather than wait. Null
    // if the team cannot pay him.
    // Money a team keeps back for its own riders it still wants to renew
    // in a later round; signings from outside come after them.
    final kept = <int, double>{};
    int? offerOf(int team, SimRider r, {bool own = false}) {
      final room = (limits[team] ??= c.finances.wageLimit(team)) -
          (bills[team] ?? 0) -
          (own ? 0 : kept[team] ?? 0);
      // A free agent asks only what he would settle for anyway.
      final market = r.teamId == _freeTeam ? freeWage(r) : marketWage(r);
      if (market <= room) return market;
      if (room >= market * 0.8) return (room / 1000).floor() * 1000;
      return null;
    }

    void book(int team, int wage) => bills[team] = (bills[team] ?? 0) + wage;
    // The free agents are no team: they neither renew nor sign.
    final teams = c.teams.values
        .where((t) => t.id != c.teamId && t.division != 'Free')
        .toList()
      ..sort((a, b) => c.teamStrength(b.id).compareTo(c.teamStrength(a.id)));
    // Renewals: whoever belongs to the core or is young and gifted.
    for (final team in teams) {
      final squad = c.squads[team.id] ?? const <SimRider>[];
      if (squad.isEmpty) continue;
      final ratings = [for (final r in squad) rating(r)]..sort();
      final median = ratings[ratings.length ~/ 2];
      // A rider who has outgrown his team does not renew; he goes to a
      // stronger one.
      final keep = [
        for (final r in squad)
          if (expiring(r) &&
              !retiring(r) &&
              !pending.containsKey(r.id) &&
              // A miserable rider wants to leave and does not renew.
              c.people.moraleOf(r.id) > -1.2 &&
              _worthKeeping(r, median) &&
              rating(r) <= c.teamStrength(team.id) + 6)
            r,
      ];
      kept[team.id] = 0;
      for (final r in keep) {
        if (rng.nextDouble() > 0.45) {
          kept[team.id] = kept[team.id]! + marketWage(r) * 0.8;
          continue;
        }
        final wage = offerOf(team.id, r, own: true);
        if (wage == null) continue;
        _sign(r, team.id, 1 + rng.nextInt(3), wage: wage);
        book(team.id, wage);
      }
    }
    // Promotions: a team with a development team first looks there. Up to
    // two of its best young riders move up each year, if they are close to
    // the level of the team or gifted enough to grow into it.
    for (final team in teams) {
      final dev = c.devTeam.links[team.id];
      if (dev == null || team.id == c.teamId) continue;
      final target = _target(team);
      final level = c.teamStrength(team.id);
      final young = [
        for (final r in c.squads[dev] ?? const <SimRider>[])
          if (contracts[r.id]?.nextTeam == null &&
              (rating(r) >= level - 7 ||
                  r.potential >= 5 && rating(r) >= level - 11))
            r,
      ]..sort((a, b) =>
          (rating(b) + 2 * b.potential).compareTo(rating(a) + 2 * a.potential));
      final already = _promoted[team.id] ?? 0;
      for (final r in young.take(2 - already)) {
        if (squadNextSeason(team.id) >= target) break;
        if (rng.nextDouble() < 0.5) continue;
        // Its own young riders: they may use the money kept for renewals.
        final wage = offerOf(team.id, r, own: true);
        if (wage == null) continue;
        _sign(r, team.id, 2, wage: wage);
        book(team.id, wage);
        _promoted[team.id] = (_promoted[team.id] ?? 0) + 1;
      }
    }
    // Signings: every team with a gap takes up to two riders who suit it.
    final sizes = <int, int>{};
    // Riders of each kind a team has for next season, counting only those
    // near its level.
    final kinds = <int, Map<String, int>>{};
    for (final r in c.riderById.values) {
      final k = contracts[r.id]!;
      final team = k.nextTeam ?? (k.endYear > c.year ? r.teamId : null);
      if (team == null) continue;
      sizes[team] = (sizes[team] ?? 0) + 1;
      if (rating(r) >= c.teamStrength(team) - 6) {
        final of = kinds.putIfAbsent(team, () => {});
        of[kindOf(r)] = (of[kindOf(r)] ?? 0) + 1;
      }
    }
    final pool = c.riderById.values
        .where((r) => expiring(r) && !retiring(r) && !pending.containsKey(r.id))
        .toList()
      ..sort((a, b) => rating(b).compareTo(rating(a)));
    final worth = {for (final r in pool) r.id: outlook(r)};
    final kind = {for (final r in pool) r.id: kindOf(r)};
    for (final team in teams) {
      final target = _target(team);
      if (target == 0) continue;
      var signed = 0;
      final level = c.teamStrength(team.id);
      // Every team looks at the market through its style and its needs,
      // and a rider from its own country counts a little more.
      final style = c.styleOf(team.id);
      final has = kinds.putIfAbsent(team.id, () => {});
      final value = {
        for (final r in pool)
          r.id: worth[r.id]! +
              styleBonus(r, style) +
              ((has[kind[r.id]] ?? 0) < (needed[kind[r.id]] ?? 0) ? 2 : 0) +
              (r.country == team.country ? 1 : 0),
      };
      final wanted = [...pool]
        ..sort((a, b) => value[b.id]!.compareTo(value[a.id]!));
      for (final r in wanted) {
        if (signed >= 2 || (sizes[team.id] ?? 0) >= target) break;
        if (!expiring(r) || r.teamId == team.id) continue;
        // A rider does not move to a team far below his level, and no team
        // takes riders far below its own.
        if (rating(r) > level + 6 || outlook(r) < level - 9) continue;
        if (rng.nextDouble() < 0.5) continue;
        final wage = offerOf(team.id, r);
        if (wage == null) continue;
        _sign(r, team.id, 1 + rng.nextInt(3), wage: wage);
        book(team.id, wage);
        sizes[team.id] = (sizes[team.id] ?? 0) + 1;
        if (rating(r) >= level - 6)
          has[kind[r.id]!] = (has[kind[r.id]] ?? 0) + 1;
        signed++;
      }
    }
  }

  /// What a rider is above all: his best main attribute.
  ///
  /// @param r The rider.
  /// @returns 'mountain', 'hill', 'timeTrial', 'sprint', 'cobble' or 'flat'.
  static String kindOf(SimRider r) {
    final a = r.attributes;
    var best = 'flat', value = a.flat;
    for (final (name, v) in [
      ('mountain', a.mountain),
      ('hill', a.hill),
      ('timeTrial', a.timeTrial),
      ('sprint', a.sprint),
      ('cobble', a.cobble),
    ]) {
      if (v > value) {
        best = name;
        value = v;
      }
    }
    return best;
  }

  /// @param kind A kind as from [kindOf].
  /// @returns Its name as a translation key.
  static String kindLabel(String kind) => switch (kind) {
        'mountain' => 'climber',
        'hill' => 'puncheur',
        'timeTrial' => 'time triallist',
        'sprint' => 'sprinter',
        'cobble' => 'cobble specialist',
        _ => 'rouleur',
      };

  /// How many riders of each kind near its level a team wants: when it
  /// keeps fewer, riders of that kind are worth two points more to it on
  /// the market, so that a team replaces the sprinter who leaves.
  static const needed = {
    'mountain': 3,
    'sprint': 2,
    'hill': 2,
    'timeTrial': 1,
    'cobble': 1,
  };

  /// How much a rider is worth to a team of a style beyond his rating.
  ///
  /// @param r The rider.
  /// @param style Style of the team.
  /// @returns Points on the rating scale.
  double styleBonus(SimRider r, TeamStyle style) {
    final a = r.attributes;
    final age = c.year - r.born ~/ 10000;
    return switch (style) {
      TeamStyle.sprint => a.sprint >= 76 ? 3 : 0,
      TeamStyle.gc => a.mountain >= 75 ? 3 : 0,
      TeamStyle.classics => a.cobble >= 74 || a.hill >= 76 ? 3 : 0,
      TeamStyle.youth => age <= 24
          ? 3
          : age >= 31
              ? -3
              : 0,
      TeamStyle.experience => age >= 29
          ? 2
          : age <= 22
              ? -2
              : 0,
      TeamStyle.balanced => 0,
    };
  }

  /// Riders each team has promoted from its development team this season.
  final _promoted = <int, int>{};

  /// Target size of a squad: as large as at the start of the career.
  ///
  /// @param team The team.
  /// @returns The number of riders it aims for.
  int _target(TeamInfo team) => team.division == 'Free'
      ? 0
      : (_startSize[team.id] ?? 0).clamp(_minimum(team.id), 30);

  /// Fewest riders a team must have by its licence: 27 for a WorldTeam, 20
  /// for a ProTeam.
  ///
  /// @param teamId Id of the team.
  /// @returns The minimum squad size; 0 for other teams.
  int _minimum(int teamId) => switch (c.licences.of(teamId)) {
        Licence.worldTour => FoundingRules.minWorldTour,
        Licence.pro => FoundingRules.minPro,
        _ => 0,
      };

  late var _startSize = {
    for (final e in c.squads.entries) e.key: e.value.length,
  };

  /// Whom a team wants to keep: the core and the gifted young.
  ///
  /// @param r The rider.
  /// @param median Median rating of his squad.
  /// @returns Whether the team renews with him.
  bool _worthKeeping(SimRider r, double median) {
    final age = c.year - r.born ~/ 10000;
    if (age >= 37 || age >= 35 && rating(r) < median) return false;
    // From 31 the team looks at what he will still be worth.
    final worth = age >= 31 ? outlook(r) : rating(r);
    return worth >= median - 4 || (age < 25 && r.potential >= 5);
  }

  /// What a rider is worth to a team that signs him for a few years: his
  /// rating now, plus what a young rider of potential will still gain,
  /// minus what an old one will lose.
  ///
  /// @param r The rider.
  /// @returns A value on the rating scale.
  double outlook(SimRider r) {
    final age = c.year + 1 - r.born ~/ 10000;
    final growth = max(0, 25 - age) * (r.potential - 3.5) * 0.35;
    final decline = max(0, age - 32) * 1.5;
    return rating(r) + growth - decline;
  }

  /// @param squad A squad.
  /// @returns The median rating of its riders.
  double _median(List<SimRider> squad) {
    final ratings = [for (final r in squad) rating(r)]..sort();
    return ratings[ratings.length ~/ 2];
  }

  /// Whether the board renews expiring contracts of the player's team on
  /// 1 August by itself.
  bool autoRenew = true;

  /// Renews the player's expiring contracts on behalf of the board.
  void _renewOwn() {
    final squad = c.squads[c.teamId] ?? const <SimRider>[];
    if (squad.isEmpty) return;
    final median = _median(squad);
    final kept = <String>[], released = <String>[];
    for (final r in squad) {
      if (!expiring(r) || retiring(r)) continue;
      final wantsOut =
          c.people.letGo.contains(r.id) || c.people.askedToLeave.contains(r.id);
      if (!wantsOut &&
          _worthKeeping(r, median) &&
          squadNextSeason(c.teamId) < 30) {
        _sign(r, c.teamId, 2);
        kept.add(c.fullName(r.id));
      } else {
        released.add(c.fullName(r.id));
      }
    }
    if (kept.isEmpty && released.isEmpty) return;
    c.inbox.add(Message(
      c.today,
      tr('Board'),
      tr('Expiring contracts settled'),
      tr(
          '{0}{1}To decide this yourself, switch off automatic renewals in the transfer section.',
          [
            kept.isEmpty
                ? ''
                : tr('Renewed for two years: {0}. ', [kept.join(', ')]),
            released.isEmpty
                ? ''
                : tr('Without a new offer: {0}. ', [released.join(', ')])
          ]),
    ));
  }

  /// Signs a rider for next season.
  ///
  /// @param r The rider.
  /// @param teamId His team next season.
  /// @param years Contract term.
  /// @param wage Agreed wage; the market wage if null.
  void _sign(SimRider r, int teamId, int years, {int? wage}) {
    contracts[r.id]!
      ..nextTeam = teamId
      ..nextWage = wage ?? marketWage(r)
      ..nextEnd = c.year + years;
    // A rider on the shortlist is off the market.
    if (c.watch.contains(r.id) && teamId != c.teamId) {
      final team = c.teams[teamId]?.name ?? '';
      c.inbox.add(Message(
        c.today,
        'Scouting',
        teamId == r.teamId
            ? tr('{0} renews with {1}', [r.name, team])
            : tr('{0} moves to {1}', [r.name, team]),
        tr('The rider was on your shortlist. His new contract runs until {0}.',
            [c.year + years]),
      ));
    }
  }

  /// At the start of the signing period: which of the player's riders end
  /// their careers after the season.
  void _retirementNotice() {
    final going = [
      for (final r in c.squads[c.teamId] ?? const <SimRider>[])
        if (retiring(r)) c.fullName(r.id),
    ];
    if (going.isEmpty) return;
    c.inbox.add(Message(
      c.today,
      tr('Board'),
      tr('End of career: {0}', [going.join(', ')]),
      tr('These riders will not sign again and end their careers after the season: {0}. Their places are free for next year.',
          [going.join(', ')]),
    ));
  }

  /// At the start of the signing period: which riders of the shortlist can
  /// be signed for next season.
  void _watchNotice() {
    final free = [
      for (final id in c.watch)
        if (c.riderById[id] case final r?)
          if (r.teamId != c.teamId && expiring(r)) r,
    ]..sort((a, b) => rating(b).compareTo(rating(a)));
    if (free.isEmpty) return;
    c.inbox.add(Message(
      c.today,
      'Scouting',
      tr('Shortlist: {0} riders are available', [free.length]),
      tr('The contracts of these riders run out, and none of them has signed elsewhere yet: {0}.',
          [free.map((r) => r.name).join(', ')]),
    ));
  }

  // --- Turn of the season -----------------------------------------------------

  /// Assesses the goals and carries out all transfers. Runs before the career
  /// advances the year.
  void closeSeason() {
    var change = 0.0;
    final lines = <String>[];
    for (final g in goals) {
      final ok = g.achieved();
      change += g.weight * (ok ? 7 : -9);
      lines.add('${ok ? tr('Achieved') : tr('Missed')}: ${g.text}');
    }
    confidence = (confidence + change).clamp(0.0, 100.0);
    final oldBudget = budget;
    _settleSponsors(lines);

    final free = _freeTeam;
    // A game saved before the intake moved to November gets it here, before
    // the contracts turn over.
    if (_intakeYear != c.year) _newIntake();
    final left = <String>[], joined = <String>[];
    for (final r in c.riderById.values.toList()) {
      final k = contracts[r.id]!;
      final age = c.year - r.born ~/ 10000;
      if (k.nextTeam != null) {
        if (k.nextTeam != r.teamId) {
          if (k.nextTeam == c.teamId) joined.add(c.fullName(r.id));
          if (r.teamId == c.teamId) left.add(c.fullName(r.id));
          _move(r, k.nextTeam!);
        }
        k
          ..wage = k.nextWage
          ..endYear = k.nextEnd
          ..nextTeam = null
          ..refusedUntil = null;
      } else if (k.endYear <= c.year) {
        if (r.teamId == c.teamId) left.add(c.fullName(r.id));
        // Without a new contract: retirement for the old, and for those who
        // have already spent a season without a team; otherwise free agent.
        if (retiring(r) ||
            age >= 38 ||
            age >= 36 && rating(r) < 80 ||
            age >= 34 && rating(r) < 73 ||
            age >= 30 && r.teamId == free) {
          _retire(r);
        } else if (r.teamId != free) {
          _move(r, free);
          k.endYear = c.year + 1;
        } else {
          k.endYear = c.year + 1;
        }
      }
    }
    _promoted.clear();
    _fillSquads(free);
    final emergency = _fillOwnSquad(free);

    c.inbox.add(Message(
      c.today,
      tr('Board'),
      tr('Season review {0}', [c.year]),
      tr(
          '{0}. Board confidence: {1} of 100. Budget {2}: {3} ({4}{5} %). {6}{7}{8}',
          [
            lines.join('. '),
            confidence.round(),
            c.year + 1,
            _euro(budget),
            budget >= oldBudget ? '+' : '',
            ((budget / oldBudget - 1) * 100).round(),
            joined.isEmpty ? '' : tr('Arrivals: {0}. ', [joined.join(', ')]),
            left.isEmpty ? '' : tr('Departures: {0}. ', [left.join(', ')]),
            emergency.isEmpty
                ? ''
                : tr(
                    'Because the squad was too small, the board signed on its own: {0}.',
                    [emergency.join(', ')])
          ]),
    ));
  }

  /// Moves a rider to another team at once.
  ///
  /// @param r The rider.
  /// @param teamId His new team.
  void move(SimRider r, int teamId) => _move(r, teamId);

  /// Fills the squads of the other teams back up to their starting size from
  /// the free agents (after a newly founded team has taken riders).
  void refill() => _fillSquads(_freeTeam);

  /// @param r The rider to move.
  /// @param teamId His new team.
  void _move(SimRider r, int teamId) {
    if (teamId != _freeTeam) c.people.noteJoined(r.id);
    c.squads[r.teamId]?.removeWhere((x) => x.id == r.id);
    final moved = r.withTeam(teamId, c.teams[teamId]?.abbr ?? '');
    c.squads.putIfAbsent(teamId, () => []).add(moved);
    c.riderById[r.id] = moved;
  }

  /// Removes a rider from the game.
  ///
  /// @param r The rider.
  void _retire(SimRider r) {
    c.noteRetired(r);
    c.squads[r.teamId]?.removeWhere((x) => x.id == r.id);
    c.riderById.remove(r.id);
    contracts.remove(r.id);
  }

  /// Real young riders as models for the new ones: the best 150 of each
  /// age from 19 to 21 in the first year of the career, with their age then.
  /// A year's intake drawn from them is as strong as a real year's best,
  /// so that the field keeps its level over many seasons.
  late final List<(SimRider, int)> intakeModels = () {
    final first = c.licences.firstYear;
    final byAge = <int, List<SimRider>>{};
    for (final r in c.world.riders()) {
      final age = first - r.born ~/ 10000;
      if (age >= 19 && age <= 21) byAge.putIfAbsent(age, () => []).add(r);
    }
    return [
      for (final age in byAge.keys.toList()..sort())
        for (final r in (byAge[age]!
              ..sort((a, b) {
                final x = rating(b).compareTo(rating(a));
                return x != 0 ? x : a.id.compareTo(b.id);
              }))
            .take(150))
          (r, age),
    ];
  }();

  /// A new young rider after one of the [intakeModels]: the model set back
  /// to the rider's age, every attribute a little different, potential,
  /// weight and height close to his.
  ///
  /// @param rng Random numbers.
  /// @param age Age of the new rider in his first season, 18 or 19.
  /// @returns Attributes, potential, weight and height of the new rider.
  ({Attributes attributes, double potential, double weight, double height})
      youngRider(Random rng, int age) {
    final (model, modelAge) = intakeModels[rng.nextInt(intakeModels.length)];
    var shape = model;
    for (var a = modelAge - 1; a >= age; a--) {
      shape = Career.yearEarlier(shape, a);
    }
    double jitter(double spread) => (rng.nextDouble() * 2 - 1) * spread;
    return (
      attributes: shape.attributes
          .adjusted((_, v) => (v + jitter(1.5)).clamp(50.0, 86.0)),
      potential:
          (model.potential + (rng.nextInt(3) - 1) * 0.25).clamp(2.0, 6.0),
      weight: (model.weightKg + jitter(2.5)).clamp(55.0, 85.0).roundToDouble(),
      height:
          (model.heightCm + jitter(2.5)).clamp(160.0, 198.0).roundToDouble(),
    );
  }

  /// Year of the last intake.
  int _intakeYear = 0;

  /// 1 November: the young riders for next season arrive as free agents,
  /// so that they can be signed in the winter, and the academy of the
  /// player's development team brings its talents.
  void _newIntake() {
    _intakeYear = c.year;
    final free = _freeTeam;
    _intake(free);
    c.devTeam.intake(free);
    c.inbox.add(Message(
      c.today,
      'Scouting',
      tr('The young riders of {0}', [c.year + 1]),
      tr('150 young riders of 18 and 19 are on the market without a team. They can be signed for next season, for the development team too; what they are worth only a scout can tell.'),
    ));
  }

  /// Creates the new intake: young riders with names from their country,
  /// free agents at first, each after a real young rider.
  ///
  /// @param free Id of the free-agent team.
  void _intake(int free) {
    final rng = c.rng;
    final byCountry = <String, List<String>>{};
    for (final r in c.riderById.values) {
      final name = c.fullNames[r.id];
      if (name != null && r.country.isNotEmpty) {
        byCountry.putIfAbsent(r.country, () => []).add(name);
      }
    }
    final countries = [
      for (final e in byCountry.entries)
        // Countries with many riders also produce more young talent.
        for (var i = 0; i < e.value.length; i += 25) e.key,
    ];
    var id = c.riderById.keys.reduce(max) + 1;
    for (var n = 0; n < 150; n++) {
      final country = countries[rng.nextInt(countries.length)];
      final names = byCountry[country]!;
      final last = names[rng.nextInt(names.length)].split(' ').last;
      final first = names[rng.nextInt(names.length)].split(' ').first;
      final age = 18 + rng.nextInt(2);
      final young = youngRider(rng, age);
      final rider = SimRider(
        id: id,
        name: '${first.isEmpty ? '' : '${first[0]}. '}$last',
        teamId: free,
        team: c.teams[free]?.abbr ?? '',
        attributes: young.attributes,
        born: (c.year + 1 - age) * 10000 + 601,
        potential: young.potential,
        country: country,
        weightKg: young.weight,
        heightCm: young.height,
      );
      c.squads.putIfAbsent(free, () => []).add(rider);
      c.riderById[id] = rider;
      c.fullNames[id] = '$first $last';
      contracts[id] = Contract(marketWage(rider), c.year);
      id++;
    }
  }

  /// Lets the other teams fill their squads from the free agents.
  ///
  /// @param free Id of the free-agent team.
  void _fillSquads(int free) {
    final rng = c.rng;
    final bills = <int, double>{};
    for (final r in c.riderById.values) {
      bills[r.teamId] =
          (bills[r.teamId] ?? 0) + (contracts[r.id]?.wage ?? 0).toDouble();
    }
    final pool = [...?c.squads[free]]
      ..sort((a, b) => rating(b).compareTo(rating(a)));
    final teams = c.teams.values
        .where((t) => t.id != c.teamId && t.id != free)
        .toList()
      ..sort((a, b) => c.teamStrength(b.id).compareTo(c.teamStrength(a.id)));
    for (final team in teams) {
      final target = _target(team);
      final under23 = team.division == 'Under23';
      final level = c.teamStrength(team.id);
      final limit = c.finances.wageLimit(team.id);
      bool fits(SimRider r) {
        final age = c.year + 1 - r.born ~/ 10000;
        return (!under23 || age <= 22) && rating(r) <= level + 6;
      }

      while ((c.squads[team.id]?.length ?? 0) < target) {
        // A free agent takes up to two fifths less than the market wage
        // rather than stay without a team; the best one the team can pay
        // signs, and if none fits the budget, the cheapest.
        final room = limit - (bills[team.id] ?? 0);
        var at = pool.indexWhere((r) => fits(r) && freeWage(r) <= room);
        if (at < 0) {
          final cheap = [
            for (var i = 0; i < pool.length; i++)
              if (fits(pool[i])) i,
          ];
          if (cheap.isEmpty) break;
          at = cheap
              .reduce((a, b) => freeWage(pool[b]) < freeWage(pool[a]) ? b : a);
        }
        final r = pool.removeAt(at);
        final wage = min(marketWage(r), max(freeWage(r), room.round()));
        _move(r, team.id);
        contracts[r.id]!
          ..wage = wage
          ..endYear = c.year + 1 + rng.nextInt(3);
        bills[team.id] = (bills[team.id] ?? 0) + wage;
      }
    }
  }

  /// What a free agent settles for rather than stay without a team.
  ///
  /// @param r The rider.
  /// @returns Euros per year.
  int freeWage(SimRider r) =>
      (max(15000.0, marketWage(r) * 0.6) / 1000).round() * 1000;

  /// If the player has too few riders under contract, the board fills the
  /// squad up to the minimum size with free agents.
  ///
  /// @param free Id of the free-agent team.
  /// @returns Names of the riders signed this way.
  List<String> _fillOwnSquad(int free) {
    // At least 22, and what the licence demands: 27 for a WorldTeam.
    final minimum = max(22, _minimum(c.teamId));
    final own = c.squads.putIfAbsent(c.teamId, () => []);
    final pool = [...?c.squads[free]]
      ..sort((a, b) => rating(b).compareTo(rating(a)));
    final level = c.teamStrength(c.teamId);
    final signed = <String>[];
    while (own.length < minimum && pool.isNotEmpty) {
      var at = pool.indexWhere((r) => rating(r) <= level);
      if (at < 0) at = pool.length - 1;
      final r = pool.removeAt(at);
      _move(r, c.teamId);
      contracts[r.id]!
        ..wage = marketWage(r)
        ..endYear = c.year + 1;
      signed.add(c.fullName(r.id));
    }
    return signed;
  }

  /// Starts a season: the balance stays, counters and goals start over.
  void openSeason() {
    wins = 0;
    grandTourPodium = false;
    grandTourStage = false;
    _drawWishes();
    final rank = _strengthRank();
    final place = max(3, rank + 2);
    final wanted = rank <= 5
        ? 25
        : rank <= 12
            ? 12
            : rank <= 25
                ? 6
                : 3;
    goals = [
      _goal(GoalKind.ranking, place),
      if (rank <= 6)
        _goal(GoalKind.grandTourPodium, 0)
      else if (rank <= 25)
        _goal(GoalKind.grandTourStage, 0),
      _goal(GoalKind.wins, wanted),
    ];
  }

  /// Builds a goal with its text, weight and check.
  ///
  /// @param kind What is measured.
  /// @param target Place or number of wins to reach.
  /// @returns The goal.
  Goal _goal(GoalKind kind, int target) => switch (kind) {
        GoalKind.ranking => Goal(
            kind,
            tr('Team ranking: at least place {0}', [target]),
            3,
            target,
            () => ownRank <= target && c.teamPoints.containsKey(c.teamId)),
        GoalKind.grandTourPodium => Goal(kind, tr('Podium in a Grand Tour'), 2,
            target, () => grandTourPodium),
        GoalKind.grandTourStage => Goal(kind, tr('Stage win in a Grand Tour'),
            2, target, () => grandTourStage),
        GoalKind.wins => Goal(kind, tr('At least {0} wins', [target]), 1,
            target, () => wins >= target),
      };
  static int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;
  static DateTime? _date(Object? ms) => ms == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);
  static List<dynamic> _offerJson(SponsorOffer o) =>
      [o.name, o.amount, o.years, o.demandPlace];
  static SponsorOffer _offer(List<dynamic> o) =>
      SponsorOffer(o[0] as String, (o[1] as num).toDouble(), o[2] as int,
          demandPlace: o[3] as int?);

  /// @returns Contracts, finances, goals and sponsors as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'contracts': {
          for (final e in contracts.entries)
            '${e.key}': [
              e.value.wage,
              e.value.endYear,
              e.value.nextTeam,
              e.value.nextWage,
              e.value.nextEnd,
              _ms(e.value.refusedUntil),
            ],
        },
        'budget': budget,
        'balance': balance,
        'confidence': confidence,
        'anchor': [_anchorBudget, _anchorRank],
        'ledger': [
          for (final l in ledger)
            [_ms(l.month), l.sponsor, l.prize, l.wages, l.costs],
        ],
        'goals': [
          for (final g in goals) [g.kind.index, g.target],
        ],
        'wins': wins,
        'promoted': {for (final e in _promoted.entries) '${e.key}': e.value},
        'gtPodium': grandTourPodium,
        'gtStage': grandTourStage,
        'prize': _prize,
        'prizeMonth': _prizeMonth,
        'sponsors': [
          for (final s in sponsors)
            [s.name, s.amount, s.endYear, s.demandPlace],
        ],
        'offers': {
          for (final e in offers.entries)
            '${e.key}': [for (final o in e.value) _offerJson(o)],
        },
        'signed': {
          for (final e in signed.entries) '${e.key}': _offerJson(e.value),
        },
        'searches': {
          for (final e in searches.entries) '${e.key}': _ms(e.value),
        },
        'searched': _searched.toList(),
        'charged': _charged,
        'intakeYear': _intakeYear,
        'wishes': [for (final w in wishes) w.toJson()],
        'feats': feats,
        'wishesMet': wishesMet.toList(),
        'pending': {
          for (final e in pending.entries)
            '${e.key}': [
              e.value.wage,
              e.value.years,
              e.value.promise?.index,
              e.value.until.millisecondsSinceEpoch,
            ],
        },
        'autoRenew': autoRenew,
        'startSize': {
          for (final e in _startSize.entries) '${e.key}': e.value,
        },
      };

  /// Replaces the state with that of a snapshot.
  ///
  /// @param j A map written by [toJson].
  void restore(Map<String, dynamic> j) {
    double d(String key) => (j[key] as num).toDouble();
    contracts
      ..clear()
      ..addAll({
        for (final e in (j['contracts'] as Map<String, dynamic>).entries)
          int.parse(e.key):
              Contract((e.value as List)[0] as int, e.value[1] as int)
                ..nextTeam = e.value[2] as int?
                ..nextWage = e.value[3] as int
                ..nextEnd = e.value[4] as int
                ..refusedUntil = _date(e.value[5]),
      });
    budget = d('budget');
    balance = d('balance');
    confidence = d('confidence');
    if (j['anchor'] case [final num b, final int r]) {
      _anchorBudget = b.toDouble();
      _anchorRank = r;
    } else {
      _anchorBudget = budget;
      _anchorRank = _strengthRank();
    }
    ledger
      ..clear()
      ..addAll([
        for (final l in (j['ledger'] as List).cast<List<dynamic>>())
          MonthLine(
            _date(l[0])!,
            (l[1] as num).toDouble(),
            (l[2] as num).toDouble(),
            (l[3] as num).toDouble(),
            (l[4] as num).toDouble(),
          ),
      ]);
    goals = [
      for (final g in (j['goals'] as List).cast<List<dynamic>>())
        _goal(GoalKind.values[g[0] as int], g[1] as int),
    ];
    wins = j['wins'] as int;
    _promoted
      ..clear()
      ..addAll({
        for (final e
            in (j['promoted'] as Map<String, dynamic>? ?? const {}).entries)
          int.parse(e.key): e.value as int,
      });
    grandTourPodium = j['gtPodium'] as bool;
    grandTourStage = j['gtStage'] as bool;
    _prize = d('prize');
    _prizeMonth = (j['prizeMonth'] as num?)?.toDouble() ?? 0;
    sponsors
      ..clear()
      ..addAll([
        for (final s in (j['sponsors'] as List).cast<List<dynamic>>())
          Sponsor(s[0] as String, (s[1] as num).toDouble(), s[2] as int,
              demandPlace: s[3] as int?),
      ]);
    offers
      ..clear()
      ..addAll({
        for (final e in (j['offers'] as Map<String, dynamic>).entries)
          int.parse(e.key): [
            for (final o in (e.value as List).cast<List<dynamic>>()) _offer(o),
          ],
      });
    signed
      ..clear()
      ..addAll({
        for (final e in (j['signed'] as Map<String, dynamic>).entries)
          int.parse(e.key): _offer(e.value as List<dynamic>),
      });
    searches
      ..clear()
      ..addAll({
        for (final e in (j['searches'] as Map<String, dynamic>).entries)
          int.parse(e.key): _date(e.value)!,
      });
    _searched
      ..clear()
      ..addAll((j['searched'] as List).cast<int>());
    _charged = d('charged');
    _intakeYear = j['intakeYear'] as int? ?? 0;
    if (j['wishes'] case final List<dynamic> list) {
      wishes
        ..clear()
        ..addAll([for (final w in list) SponsorWish.fromJson(w as List)]);
      feats
        ..clear()
        ..addAll((j['feats'] as Map<String, dynamic>).cast<String, int>());
      wishesMet
        ..clear()
        ..addAll((j['wishesMet'] as List).cast<int>());
    } else {
      _drawWishes();
    }
    pending
      ..clear()
      ..addAll({
        for (final e
            in (j['pending'] as Map<String, dynamic>? ?? const {}).entries)
          int.parse(e.key): PendingOffer(
            (e.value as List)[0] as int,
            e.value[1] as int,
            e.value[2] == null ? null : PromiseKind.values[e.value[2] as int],
            DateTime.fromMillisecondsSinceEpoch(e.value[3] as int, isUtc: true),
          ),
      });
    autoRenew = j['autoRenew'] as bool;
    _startSize = {
      for (final e in (j['startSize'] as Map<String, dynamic>).entries)
        int.parse(e.key): e.value as int,
    };
  }
}
