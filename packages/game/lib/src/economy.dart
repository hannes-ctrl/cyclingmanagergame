import 'dart:math';

import 'package:sim/sim.dart';

import 'career.dart';
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
    _initSponsors();
  }

  /// Scales every sponsor's payment (promotion or relegation).
  ///
  /// @param factor Multiplier on the yearly amounts.
  void scaleSponsors(double factor) {
    for (final s in sponsors) {
      s.amount *= factor;
    }
    budget = sponsors.fold(0.0, (sum, s) => sum + s.amount);
  }

  /// Place of the player's team in the team ranking of the current season.
  int get ownRank {
    final teams = c.teamPoints.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final at = teams.indexWhere((e) => e.key == c.teamId);
    return at < 0 ? teams.length + 1 : at + 1;
  }

  double _offerBase(Sponsor s) => s.amount * (0.8 + 0.4 * confidence / 100);

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
      'Teamleitung',
      'Sponsorensuche ${c.year + 1}',
      'Zum Jahresende laufen aus: ${names.join(', ')}. Unter Finanzen liegen '
          'Angebote für die Nachfolge. Wer bis Dezember nichts wählt, '
          'überlässt den Abschluss der Teamleitung.',
    ));
  }

  /// Has the board look for a further offer for a month. Once per expiring
  /// contract.
  ///
  /// @param slot Index in [sponsors].
  /// @returns null on success, otherwise the reason.
  String? searchSponsor(int slot) {
    if (!offers.containsKey(slot))
      return 'Für diesen Platz wird nicht gesucht.';
    if (signed.containsKey(slot)) return 'Hier ist schon abgeschlossen.';
    if (_searched.contains(slot)) return 'Mehr gibt der Markt nicht her.';
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
      return 'Das Angebot gibt es nicht mehr.';
    }
    if (signed.containsKey(slot)) return 'Hier ist schon abgeschlossen.';
    signed[slot] = list[index];
    searches.remove(slot);
    c.inbox.add(Message(
      c.today,
      'Teamleitung',
      '${list[index].name} wird Sponsor',
      '${list[index].name} zahlt ab ${c.year + 1} für ${list[index].years} Jahre '
          '${_euro(list[index].amount)} im Jahr.',
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
        'Teamleitung',
        'Weiteres Sponsorenangebot',
        '${offer.name} bietet ${_euro(offer.amount)} im Jahr für '
            '${offer.years} Jahre.',
      ));
    }
  }

  /// End of the year: check demands, start new contracts.
  ///
  /// @param lines Receives sentences for the season summary.
  void _settleSponsors(List<String> lines) {
    final rank = ownRank;
    for (var i = 0; i < sponsors.length; i++) {
      final s = sponsors[i];
      if (s.endYear > c.year) {
        final place = s.demandPlace;
        if (place != null && rank > place) {
          s.amount *= 0.8;
          lines.add('${s.name} kürzt um ein Fünftel, weil Platz $place '
              'in der Teamrangliste verfehlt wurde');
        }
        continue;
      }
      final list = offers[i] ?? const <SponsorOffer>[];
      final next = signed[i] ??
          (list.isNotEmpty
              ? list.first
              : SponsorOffer(s.name, _offerBase(s) * 0.9, 1));
      if (!signed.containsKey(i)) {
        lines.add('Die Teamleitung hat mit ${next.name} abgeschlossen');
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

  static const _prizePerPoint = 60.0;

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

  /// @returns Riders of other teams who are available for next season.
  List<SimRider> market() => [
        for (final r in c.riderById.values)
          if (r.teamId != c.teamId && expiring(r)) r,
      ];

  /// What a rider asks of the player's team. He wants more for a move than
  /// for a renewal, and every rider is a little different.
  ///
  /// @param r The rider.
  /// @returns The wage he demands, in euros per year.
  int demand(SimRider r) {
    final mood = ((r.id * 2654435761) % 1000) / 1000; // fixed per rider, 0 to 1
    var factor = 0.92 + 0.2 * mood;
    if (r.teamId != c.teamId) factor += 0.1;
    return (marketWage(r) * factor / 1000).round() * 1000;
  }

  /// Makes an offer on behalf of the player.
  ///
  /// @param riderId Id of the rider.
  /// @param wage Offered wage in euros per year.
  /// @param years Contract term.
  /// @returns null if he signs, otherwise the reason for the refusal.
  String? offer(int riderId, int wage, int years) {
    final r = c.riderById[riderId];
    final k = contracts[riderId];
    if (r == null || k == null) return 'Fahrer nicht gefunden.';
    if (!expiring(r)) return 'Der Vertrag läuft noch oder ist schon geregelt.';
    if (!windowOpen)
      return 'Vertragsgespräche sind erst ab dem 1. August möglich.';
    if (k.refusedUntil?.isAfter(c.today) ?? false) {
      return 'Er möchte nach der letzten Absage noch nicht wieder verhandeln.';
    }
    if (squadNextSeason(c.teamId) >= 30) {
      return 'Der Kader für die nächste Saison ist mit 30 Fahrern voll.';
    }
    if (wageBill(c.teamId, nextSeason: true) + wage > budget * 0.72) {
      return 'Die Teamleitung gibt das Gehalt nicht frei: Das Budget für '
          'Gehälter wäre überschritten.';
    }
    final wanted = demand(r);
    if (wage < wanted) {
      k.refusedUntil = c.today.add(const Duration(days: 14));
      // The agent only names the ballpark.
      final hint = (wanted / 50000).ceil() * 50000;
      return 'Abgelehnt. Sein Berater spricht von mindestens ${_euro(hint)} im Jahr.';
    }
    k
      ..nextTeam = c.teamId
      ..nextWage = wage
      ..nextEnd = c.year + years.clamp(1, 4);
    c.inbox.add(Message(
      c.today,
      'Berater',
      r.teamId == c.teamId
          ? '${r.name} verlängert'
          : '${r.name} unterschreibt für ${c.year + 1}',
      '${c.fullName(r.id)} hat für ${_euro(wage)} im Jahr bis ${k.nextEnd} '
          'unterschrieben.',
    ));
    return null;
  }

  static String _euro(num v) => v >= 1000000
      ? '${(v / 1000000).toStringAsFixed(2).replaceAll('.', ',')} Mio. €'
      : '${(v / 1000).round()}.000 €';

  // --- Daily routine ----------------------------------------------------------

  /// Daily bookkeeping: wins, monthly statement, market rounds, sponsors.
  ///
  /// @param ridden Today's stages.
  void daily(
      List<({RaceProgress race, int stageIndex, StageResult result})> ridden) {
    for (final day in ridden) {
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
    final t = c.today;
    if (t.day == 1) _closeMonth();
    if (t.day == 1 && t.month == 6) _openSponsorSearch();
    if (searches.isNotEmpty) _finishSearches();
    // The other teams settle their contracts in four waves.
    if (t.day == 15 && t.month >= 8 && t.month <= 11) _marketWave();
    // Right at the start of the signing period, before other teams move in.
    if (t.day == 1 && t.month == 8 && autoRenew) _renewOwn();
  }

  double _pointsSeen = 0;

  /// Writes the monthly statement and updates the balance.
  void _closeMonth() {
    final points = c.teamPoints[c.teamId] ?? 0;
    _prize = (points - _pointsSeen) * _prizePerPoint;
    _pointsSeen = points;
    final line = MonthLine(
      c.today,
      budget / 12,
      _prize,
      wageBill(c.teamId) / 12,
      // Travel and equipment as a flat rate, plus staff wages.
      budget * 0.15 / 12 +
          c.staff.wages(c.teamId) / 12 +
          c.devTeam.cost / 12 +
          _charged,
    );
    _charged = 0;
    ledger.add(line);
    balance += line.result;
  }

  /// One round on the market: teams renew with their own riders and sign
  /// expiring riders of other teams. The best go first.
  void _marketWave() {
    final rng = c.rng;
    final teams = c.teams.values.where((t) => t.id != c.teamId).toList()
      ..sort((a, b) => c.teamStrength(b.id).compareTo(c.teamStrength(a.id)));
    // Renewals: whoever belongs to the core or is young and gifted.
    for (final team in teams) {
      final squad = c.squads[team.id] ?? const <SimRider>[];
      if (squad.isEmpty) continue;
      final ratings = [for (final r in squad) rating(r)]..sort();
      final median = ratings[ratings.length ~/ 2];
      for (final r in squad) {
        if (!expiring(r) || rng.nextDouble() > 0.45) continue;
        if (_worthKeeping(r, median)) _sign(r, team.id, 1 + rng.nextInt(3));
      }
    }
    // Signings: every team with a gap takes up to two riders who suit it.
    final sizes = <int, int>{};
    for (final r in c.riderById.values) {
      final k = contracts[r.id]!;
      final team = k.nextTeam ?? (k.endYear > c.year ? r.teamId : null);
      if (team != null) sizes[team] = (sizes[team] ?? 0) + 1;
    }
    final pool = c.riderById.values.where(expiring).toList()
      ..sort((a, b) => rating(b).compareTo(rating(a)));
    for (final team in teams) {
      final target = _target(team);
      if (target == 0) continue;
      var signed = 0;
      final level = c.teamStrength(team.id);
      for (final r in pool) {
        if (signed >= 2 || (sizes[team.id] ?? 0) >= target) break;
        if (!expiring(r) || r.teamId == team.id) continue;
        // Nobody moves to a clearly weaker team, and no team gets a rider far
        // above its level.
        if (rating(r) > level + 2 || rating(r) < level - 9) continue;
        if (rng.nextDouble() < 0.5) continue;
        _sign(r, team.id, 1 + rng.nextInt(3));
        sizes[team.id] = (sizes[team.id] ?? 0) + 1;
        signed++;
      }
    }
  }

  /// Target size of a squad: as large as at the start of the career.
  ///
  /// @param team The team.
  /// @returns The number of riders it aims for.
  int _target(TeamInfo team) =>
      team.division == 'Free' ? 0 : (_startSize[team.id] ?? 0).clamp(0, 30);

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
    if (age >= 37) return false;
    return rating(r) >= median - 4 || (age < 25 && r.potential >= 5);
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
      if (!expiring(r)) continue;
      if (_worthKeeping(r, median) && squadNextSeason(c.teamId) < 30) {
        _sign(r, c.teamId, 2);
        kept.add(c.fullName(r.id));
      } else {
        released.add(c.fullName(r.id));
      }
    }
    if (kept.isEmpty && released.isEmpty) return;
    c.inbox.add(Message(
      c.today,
      'Teamleitung',
      'Auslaufende Verträge geregelt',
      '${kept.isEmpty ? '' : 'Um zwei Jahre verlängert: ${kept.join(', ')}. '}'
          '${released.isEmpty ? '' : 'Ohne neues Angebot: ${released.join(', ')}. '}'
          'Wer das selbst entscheiden will, schaltet die automatische '
          'Verlängerung im Transferbereich ab.',
    ));
  }

  /// Signs a rider for next season at the market wage.
  ///
  /// @param r The rider.
  /// @param teamId His team next season.
  /// @param years Contract term.
  void _sign(SimRider r, int teamId, int years) {
    contracts[r.id]!
      ..nextTeam = teamId
      ..nextWage = marketWage(r)
      ..nextEnd = c.year + years;
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
      lines.add('${ok ? 'Erreicht' : 'Verfehlt'}: ${g.text}');
    }
    confidence = (confidence + change).clamp(0.0, 100.0);
    final oldBudget = budget;
    _settleSponsors(lines);

    final free = _freeTeam;
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
        // Without a new contract: retirement for the old, otherwise free agent.
        if (age >= 37 || (age >= 34 && rating(r) < 71)) {
          _retire(r);
        } else if (r.teamId != free) {
          _move(r, free);
          k.endYear = c.year + 1;
        } else {
          k.endYear = c.year + 1;
        }
      }
    }
    _intake(free);
    c.devTeam.intake(free);
    _fillSquads(free);
    final emergency = _fillOwnSquad(free);

    c.inbox.add(Message(
      c.today,
      'Teamleitung',
      'Saisonbilanz ${c.year}',
      '${lines.join('. ')}. Vertrauen der Teamleitung: ${confidence.round()} von 100. '
          'Budget ${c.year + 1}: ${_euro(budget)} '
          '(${budget >= oldBudget ? '+' : ''}${((budget / oldBudget - 1) * 100).round()} %). '
          '${joined.isEmpty ? '' : 'Zugänge: ${joined.join(', ')}. '}'
          '${left.isEmpty ? '' : 'Abgänge: ${left.join(', ')}. '}'
          '${emergency.isEmpty ? '' : 'Weil der Kader zu klein war, hat die Teamleitung selbst verpflichtet: ${emergency.join(', ')}.'}',
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
    c.squads[r.teamId]?.removeWhere((x) => x.id == r.id);
    final moved = r.withTeam(teamId, c.teams[teamId]?.abbr ?? '');
    c.squads.putIfAbsent(teamId, () => []).add(moved);
    c.riderById[r.id] = moved;
  }

  /// Removes a rider from the game.
  ///
  /// @param r The rider.
  void _retire(SimRider r) {
    c.squads[r.teamId]?.removeWhere((x) => x.id == r.id);
    c.riderById.remove(r.id);
    contracts.remove(r.id);
  }

  /// Creates the new intake: young riders with names from their country,
  /// free agents at first.
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
      // Everyone brings one strength; the rest lies below it.
      final base = 56 + rng.nextDouble() * 9;
      final strong = const [
        ['mountain', 'mediumMountain', 'hill'],
        ['sprint', 'acceleration', 'flat'],
        ['timeTrial', 'prologue', 'flat'],
        ['cobble', 'flat', 'hill'],
        ['hill', 'acceleration', 'mediumMountain'],
      ][rng.nextInt(5)];
      double value(String name) => (base +
              (strong.contains(name) ? 5 + rng.nextDouble() * 5 : 0) +
              rng.nextDouble() * 4)
          .clamp(50.0, 80.0);
      final attributes = Attributes(
        flat: value('flat'),
        mountain: value('mountain'),
        mediumMountain: value('mediumMountain'),
        hill: value('hill'),
        timeTrial: value('timeTrial'),
        prologue: value('prologue'),
        cobble: value('cobble'),
        sprint: value('sprint'),
        acceleration: value('acceleration'),
        downhill: value('downhill'),
        endurance: value('endurance'),
        resistance: value('resistance'),
        recovery: value('recovery'),
        breakaway: value('breakaway'),
      );
      // Potential: mostly average, few exceptions.
      final talent = rng.nextDouble();
      final potential = talent > 0.96
          ? 6.0
          : talent > 0.85
              ? 5.5
              : talent > 0.6
                  ? 5.0
                  : talent > 0.3
                      ? 4.5
                      : 4.0;
      final rider = SimRider(
        id: id,
        name: '${first.isEmpty ? '' : '${first[0]}. '}$last',
        teamId: free,
        team: c.teams[free]?.abbr ?? '',
        attributes: attributes,
        born: (c.year + 1 - 18 - rng.nextInt(2)) * 10000 + 601,
        potential: potential,
        country: country,
      );
      c.squads.putIfAbsent(free, () => []).add(rider);
      c.riderById[id] = rider;
      c.fullNames[id] = '$first $last';
      contracts[id] = Contract(marketWage(rider), c.year + 1);
      id++;
    }
  }

  /// Lets the other teams fill their squads from the free agents.
  ///
  /// @param free Id of the free-agent team.
  void _fillSquads(int free) {
    final rng = c.rng;
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
      while ((c.squads[team.id]?.length ?? 0) < target) {
        final at = pool.indexWhere((r) {
          final age = c.year + 1 - r.born ~/ 10000;
          return (!under23 || age <= 22) && rating(r) <= level + 2;
        });
        if (at < 0) break;
        final r = pool.removeAt(at);
        _move(r, team.id);
        contracts[r.id]!
          ..wage = marketWage(r)
          ..endYear = c.year + 1 + rng.nextInt(3);
      }
    }
  }

  /// If the player has too few riders under contract, the board fills the
  /// squad up to the minimum size with free agents.
  ///
  /// @param free Id of the free-agent team.
  /// @returns Names of the riders signed this way.
  List<String> _fillOwnSquad(int free) {
    const minimum = 22;
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
    _pointsSeen = 0;
    final order = c.teams.values.map((t) => t.id).toList()
      ..sort((a, b) => c.teamStrength(b).compareTo(c.teamStrength(a)));
    final rank = order.indexOf(c.teamId) + 1;
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
            'Teamrangliste: mindestens Platz $target',
            3,
            target,
            () => ownRank <= target && c.teamPoints.containsKey(c.teamId)),
        GoalKind.grandTourPodium => Goal(
            kind,
            'Podium bei einer großen Rundfahrt',
            2,
            target,
            () => grandTourPodium),
        GoalKind.grandTourStage => Goal(
            kind,
            'Etappensieg bei einer großen Rundfahrt',
            2,
            target,
            () => grandTourStage),
        GoalKind.wins => Goal(
            kind, 'Mindestens $target Siege', 1, target, () => wins >= target),
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
        'ledger': [
          for (final l in ledger)
            [_ms(l.month), l.sponsor, l.prize, l.wages, l.costs],
        ],
        'goals': [
          for (final g in goals) [g.kind.index, g.target],
        ],
        'wins': wins,
        'gtPodium': grandTourPodium,
        'gtStage': grandTourStage,
        'prize': _prize,
        'pointsSeen': _pointsSeen,
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
    grandTourPodium = j['gtPodium'] as bool;
    grandTourStage = j['gtStage'] as bool;
    _prize = d('prize');
    _pointsSeen = d('pointsSeen');
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
    autoRenew = j['autoRenew'] as bool;
    _startSize = {
      for (final e in (j['startSize'] as Map<String, dynamic>).entries)
        int.parse(e.key): e.value as int,
    };
  }
}
