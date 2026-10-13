import 'dart:math';

import 'package:sim/sim.dart';

import 'career.dart';
import 'economy.dart';
import 'points.dart';

/// What a rider is like as a person. The values are fixed for a rider in a
/// career and lie between 0 and 1. The player sees them as words and as one
/// summary, named as in football management games, and only for riders his
/// scouts know well.
class Personality {
  const Personality(
      this.professionalism, this.ambition, this.loyalty, this.consistency);

  /// How seriously he takes training and recovery: he develops faster.
  final double professionalism;

  /// How much he wants results and a role of his own: his morale reacts
  /// more strongly, to good and to bad.
  final double ambition;

  /// How attached he is to his team: he asks less to stay.
  final double loyalty;

  /// How little his form differs from race to race.
  final double consistency;

  /// Draws the personality of a rider. The same rider in the same career
  /// always gets the same one.
  ///
  /// Most riders come out near the middle, a few at either end, so that
  /// good, balanced and difficult characters all exist. Two things shift
  /// the draw a little: riders past thirty have learned to live for the
  /// job, and young riders of great potential tend to want more.
  ///
  /// @param riderId Id of the rider.
  /// @param seed Seed of the career.
  /// @param age His age, 0 if unknown.
  /// @param potential His potential, 4 if unknown.
  /// @returns His personality.
  static Personality of(int riderId, int seed,
      {int age = 0, double potential = 4}) {
    final r = Random(seed * 1000003 + riderId * 7919);
    double draw([double shift = 0]) =>
        (((r.nextDouble() + r.nextDouble() + r.nextDouble()) / 3 - 0.5) * 1.05 +
                0.5 +
                shift)
            .clamp(0.0, 1.0);
    return Personality(
      draw(age >= 31 ? 0.08 : 0),
      draw(age > 0 && age <= 24 && potential >= 5 ? 0.08 : 0),
      draw(),
      draw(),
    );
  }

  /// @param value One of the values of a personality.
  /// @returns It as a word.
  static String word(double value) => value >= 0.75
      ? tr('sehr hoch')
      : value >= 0.58
          ? tr('hoch')
          : value >= 0.42
              ? tr('mittel')
              : value >= 0.25
                  ? tr('niedrig')
                  : tr('sehr niedrig');

  /// The personality in one term, in the manner of football management
  /// games. The most striking trait names it; a rider without one is
  /// balanced.
  String get label => tr(_label.$1);

  /// Whether the summary is a good sign (1), neutral (0) or a warning (−1).
  int get tone => _label.$2;

  (String, int) get _label {
    final p = professionalism, a = ambition, l = loyalty, k = consistency;
    if (p >= 0.8 && a >= 0.55 && l >= 0.45) return ('Musterprofi', 1);
    if (p >= 0.75 && a >= 0.75) return ('Perfektionist', 1);
    if (a >= 0.78 && l <= 0.3) return ('Söldner', -1);
    if (p <= 0.2) return ('Nachlässig', -1);
    if (k <= 0.18) return ('Launisch', -1);
    if (l <= 0.18) return ('Unbeständig', -1);
    if (a <= 0.18) return ('Ohne Ehrgeiz', -1);
    if (l >= 0.82) return ('Dem Team ergeben', 1);
    if (p >= 0.7) return ('Professionell', 1);
    if (a >= 0.8) return ('Sehr ehrgeizig', 0);
    if (a >= 0.68 && p >= 0.5) return ('Zielstrebig', 1);
    if (l >= 0.68) return ('Loyal', 1);
    if (a >= 0.66) return ('Ehrgeizig', 0);
    if (k >= 0.8) return ('Verlässlich', 1);
    if (p >= 0.6) return ('Recht professionell', 1);
    if (p <= 0.33) return ('Lässig', -1);
    if (a <= 0.32) return ('Genügsam', 0);
    return ('Ausgeglichen', 0);
  }
}

/// The standing of a rider in his team, as agreed between him and the
/// management. It says what he may expect: a star and a leader want to ride
/// for themselves in the races that matter, a helper does not.
enum TeamRole {
  star('Star'),
  leader('Kapitän'),
  keyHelper('Edelhelfer'),
  helper('Helfer'),
  prospect('Talent');

  const TeamRole(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);

  /// Whether he expects to ride for himself in important races.
  bool get leads => this == star || this == leader;
}

/// What the player can promise a rider.
enum PromiseKind {
  /// He starts in the race; for a whole season: in a Grand Tour.
  start('Start'),

  /// He rides the race as leader, co-leader or sprinter; for a whole
  /// season: at least one WorldTour race.
  leader('Kapitänsrolle');

  const PromiseKind(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
}

/// A promise the player made to a rider: for one race of the season, or,
/// made in contract talks, for a whole season ([raceId] 0).
class RiderPromise {
  RiderPromise(this.riderId, this.raceId, this.kind, this.year);
  final int riderId;

  /// Id of the race, or 0 for a promise that covers a season.
  final int raceId;
  final PromiseKind kind;

  /// Season the promise is for.
  final int year;

  /// @returns The promise as a compact list.
  List<Object> toJson() => [riderId, raceId, kind.index, year];

  /// @param j A list written by [toJson].
  /// @param year Season of a promise stored before seasons were recorded.
  /// @returns The promise.
  static RiderPromise fromJson(List<dynamic> j, int year) => RiderPromise(
      j[0] as int,
      j[1] as int,
      PromiseKind.values[j[2] as int],
      j.length > 3 ? j[3] as int : year);
}

/// The riders as people: personality, standing in the team, morale, season
/// goals and promises.
///
/// Every rider of every team has a personality, goals and a morale; they
/// act on the races of all teams alike. Promises and the standing in the
/// team are the player's tools and exist for his riders.
class People {
  /// Creates the store for a career.
  People(this.c);
  final Career c;

  /// Morale per rider id, −2 (miserable) to +2 (delighted); 0 if absent.
  final morale = <int, double>{};

  /// The last things that moved a rider's morale: `[text, change]`, newest
  /// last, at most four per rider. Kept for the player's riders.
  final notes = <int, List<List<dynamic>>>{};

  /// Open promises.
  final promises = <RiderPromise>[];

  /// Goal races per rider id, at most [maxGoals] each.
  final goals = <int, Set<int>>{};

  /// Riders whose goals the player set himself; the sports director leaves
  /// them alone.
  final ownGoals = <int>{};

  /// Standing in the team the player gave a rider; riders without an entry
  /// have the one that follows from their strength.
  final teamRoles = <int, TeamRole>{};

  /// Days of the season a rider was injured or ill. Nobody blames the team
  /// for races he missed that way.
  final outDays = <int, int>{};

  /// What a rider has done this season, for promises that cover a season:
  /// whether he started a Grand Tour and whether he led in a WorldTour race.
  final _startedGrandTour = <int>{};
  final _ledBigRace = <int>{};

  /// Goal races a rider can have.
  static const maxGoals = 3;

  final _personalities = <int, Personality>{};

  /// @param riderId Id of a rider.
  /// @returns His personality.
  Personality of(int riderId) => _personalities.putIfAbsent(riderId, () {
        final r = c.riderById[riderId];
        return Personality.of(
          riderId,
          c.seed,
          // Fixed at the start of the career, so that it does not change
          // as he grows older.
          age: r == null || r.born == 0
              ? 0
              : c.licences.firstYear - r.born ~/ 10000,
          potential: r?.potential ?? 4,
        );
      });

  /// @param riderId Id of a rider.
  /// @returns His morale, −2 to +2.
  double moraleOf(int riderId) => morale[riderId] ?? 0;

  /// @param value A morale value.
  /// @returns It as a word.
  static String moraleWord(double value) => value >= 1.2
      ? tr('begeistert')
      : value >= 0.4
          ? tr('zufrieden')
          : value > -0.4
              ? tr('in Ordnung')
              : value > -1.2
                  ? tr('unzufrieden')
                  : tr('sehr unzufrieden');

  bool _own(int riderId) => c.riderById[riderId]?.teamId == c.teamId;

  /// Moves the morale of a rider and, for a rider of the player's team,
  /// notes why. An ambitious rider takes things to heart more than others.
  ///
  /// @param riderId Id of the rider.
  /// @param delta Change before his ambition is applied.
  /// @param why What happened, as a short text.
  void move(int riderId, double delta, String why) {
    final change = delta * (0.7 + 0.6 * of(riderId).ambition);
    morale[riderId] = (moraleOf(riderId) + change).clamp(-2.0, 2.0);
    if (!_own(riderId)) return;
    final list = notes.putIfAbsent(riderId, () => [])..add([why, change]);
    if (list.length > 4) list.removeAt(0);
  }

  /// Factor on a rider's form in a race: his morale, whether the race is
  /// one of his goals, and how evenly he performs.
  ///
  /// @param r The rider.
  /// @param raceId Id of the race.
  /// @returns A factor close to 1.
  double formFactor(SimRider r, int raceId) {
    var factor = 1 + 0.004 * moraleOf(r.id);
    final mine = goals[r.id];
    if (mine != null && mine.isNotEmpty) {
      // He peaks for his goals and is a little short of that elsewhere.
      factor *= mine.contains(raceId) ? 1.012 : 0.997;
    }
    // The day he has: fixed per rider and race, wider for an uneven rider.
    final luck = Random(c.seed * 31 + r.id * 131 + raceId * 17 + c.year);
    final spread = 0.008 * (1 - of(r.id).consistency);
    return factor * (1 + spread * (luck.nextDouble() * 2 - 1));
  }

  /// @param riderId Id of a rider.
  /// @returns Factor on his development: 0.9 for a careless rider, 1.1 for
  ///   a very professional one.
  double growthFactor(int riderId) => 0.9 + 0.2 * of(riderId).professionalism;

  /// What a rider's mood and character do to the wage he asks of the
  /// player: his own rider asks less if he is loyal and content; a rider of
  /// another team is easier to get if he is unhappy where he is.
  ///
  /// @param riderId Id of the rider.
  /// @returns A factor on his demand.
  double demandFactor(int riderId) => _own(riderId)
      ? (1.06 - 0.12 * of(riderId).loyalty) * (1 - 0.04 * moraleOf(riderId))
      : 1 + 0.03 * moraleOf(riderId);

  // --- Standing in the team ------------------------------------------------------

  /// The standing a rider has by his strength and age: the two strongest
  /// are stars if they are of world class, the next few leaders, the middle
  /// of the squad key helpers, the rest helpers; a gifted young rider
  /// outside the leaders is a talent.
  ///
  /// @param riderId Id of a rider.
  /// @returns His standing without a decision of the player.
  TeamRole naturalRole(int riderId) {
    final r = c.riderById[riderId];
    if (r == null) return TeamRole.helper;
    final squad = [...?c.squads[r.teamId]]
      ..sort((a, b) => Economy.rating(b).compareTo(Economy.rating(a)));
    final rank = squad.indexWhere((x) => x.id == riderId);
    final age = c.year - r.born ~/ 10000;
    if (rank < 2 && Economy.rating(r) >= 80) return TeamRole.star;
    if (rank < 6) return TeamRole.leader;
    if (age <= 22 && r.potential >= 4.5) return TeamRole.prospect;
    if (rank < 14) return TeamRole.keyHelper;
    return TeamRole.helper;
  }

  /// @param riderId Id of a rider.
  /// @returns His standing in the team.
  TeamRole roleOf(int riderId) => teamRoles[riderId] ?? naturalRole(riderId);

  /// Gives a rider of the player's team another standing. A step up
  /// pleases him, a step down does not.
  ///
  /// @param riderId Id of the rider.
  /// @param role His new standing.
  void setRole(int riderId, TeamRole role) {
    final before = roleOf(riderId);
    if (role == before) return;
    teamRoles[riderId] = role;
    // Enum order: star first. A talent is not a rank of its own.
    int rank(TeamRole x) => x == TeamRole.prospect ? 3 : x.index;
    final step = rank(before) - rank(role);
    if (step > 0) {
      move(riderId, 0.4, tr('Aufgewertet: {0}', [role.label]));
    } else if (step < 0) {
      move(riderId, -0.6, tr('Zurückgestuft: {0}', [role.label]));
    }
  }

  // --- Goals ------------------------------------------------------------------

  /// Sets or removes a goal race of a rider of the player's team.
  ///
  /// @param riderId Id of the rider.
  /// @param raceId Id of the race.
  /// @returns null on success, otherwise the reason.
  String? toggleGoal(int riderId, int raceId) {
    final mine = goals.putIfAbsent(riderId, () => {});
    ownGoals.add(riderId);
    if (mine.remove(raceId)) return null;
    if (mine.length >= maxGoals) {
      return tr('Ein Fahrer kann höchstens {0} Saisonziele haben.', [maxGoals]);
    }
    mine.add(raceId);
    // A goal he is not planned for makes no sense.
    c.program.putIfAbsent(raceId, () => {}).add(riderId);
    return null;
  }

  /// Gives riders their goals from a season plan: for each rider the most
  /// important races in which he is among the three best-suited starters of
  /// his team. Riders whose goals the player set are left alone.
  ///
  /// @param program Planned riders per race id.
  /// @param races The races of the plan.
  /// @param teamId The team.
  void goalsFrom(
      Map<int, Set<int>> program, List<RaceEntry> races, int teamId) {
    final byRider = <int, List<RaceEntry>>{};
    for (final race in races) {
      final riders = [
        for (final id in program[race.info.id] ?? const <int>{})
          if (c.riderById[id] case final r?) r,
      ]..sort(
          (a, b) => c.planner.fit(race, b).compareTo(c.planner.fit(race, a)));
      for (final r in riders.take(3)) {
        byRider.putIfAbsent(r.id, () => []).add(race);
      }
    }
    for (final e in byRider.entries) {
      if (ownGoals.contains(e.key)) continue;
      e.value.sort((a, b) {
        final byWeight = c.planner
            .importance(b, teamId)
            .compareTo(c.planner.importance(a, teamId));
        return byWeight != 0 ? byWeight : a.start.compareTo(b.start);
      });
      goals[e.key] = {for (final r in e.value.take(maxGoals)) r.info.id};
    }
  }

  // --- Promises ---------------------------------------------------------------

  /// @param riderId Id of a rider.
  /// @param year A season.
  /// @returns The promise he holds for that season, or null.
  RiderPromise? promiseOf(int riderId, int year) =>
      promises.where((p) => p.riderId == riderId && p.year == year).firstOrNull;

  /// Promises a rider of the player's team a start or a leading role in a
  /// race of the running season.
  ///
  /// @param riderId Id of the rider.
  /// @param raceId Id of the race.
  /// @param kind What is promised.
  /// @returns null on success, otherwise the reason.
  String? promise(int riderId, int raceId, PromiseKind kind) {
    if (promiseOf(riderId, c.year) != null) {
      return tr('Er hat für diese Saison schon ein Versprechen.');
    }
    if (c.progress.containsKey(raceId)) {
      return tr('Das Rennen läuft schon oder ist vorbei.');
    }
    promises.add(RiderPromise(riderId, raceId, kind, c.year));
    final race = c.calendar.where((r) => r.info.id == raceId).firstOrNull;
    move(riderId, 0.6,
        tr('Versprechen: {0} bei {1}', [kind.label, race?.info.name ?? '']));
    return null;
  }

  /// A promise made in contract talks, for the season the contract begins
  /// in: a start in a Grand Tour, or the leading role in at least one
  /// WorldTour race.
  ///
  /// @param riderId Id of the rider.
  /// @param kind What is promised.
  void promiseSeason(int riderId, PromiseKind kind) {
    promises
      ..removeWhere((p) => p.riderId == riderId && p.year == c.year + 1)
      ..add(RiderPromise(riderId, 0, kind, c.year + 1));
  }

  /// @param kind A kind of promise.
  /// @returns What it means when it covers a season.
  static String seasonText(PromiseKind kind) => kind == PromiseKind.start
      ? tr('Start bei einer Grand Tour')
      : tr('Kapitän in einem WorldTour-Rennen');

  /// How much less a rider asks when the offer comes with a promise.
  static const promiseDiscount = 0.08;

  /// Checks the promises for a race when its first stage has been ridden.
  ///
  /// @param p The race.
  void checkPromises(RaceProgress p) {
    final id = p.race.info.id;
    for (final promise in [...promises.where((x) => x.raceId == id)]) {
      promises.remove(promise);
      final rider = c.riderById[promise.riderId];
      if (rider == null || rider.teamId != c.teamId) continue;
      final started = p.riders.any((r) => r.id == promise.riderId);
      // A rider who is injured or ill sees for himself that he cannot
      // start; nobody has broken his word.
      if (!started && c.isInjured(rider.id, p.race.start)) {
        move(
            rider.id,
            0,
            tr('Versprechen entfällt, er ist nicht fit: {0}',
                [p.race.info.name]));
        continue;
      }
      final kept = started &&
          (promise.kind == PromiseKind.start || _leadsIn(p, promise.riderId));
      _settle(rider, promise, p.race.info.name, kept, raceId: id);
    }
  }

  bool _leadsIn(RaceProgress p, int riderId) {
    final role = c.planUsed(p.race.info.id, 0).roleOf(riderId);
    return role == Role.leader ||
        role == Role.coLeader ||
        role == Role.sprinter;
  }

  void _settle(SimRider rider, RiderPromise promise, String what, bool kept,
      {int? raceId}) {
    if (kept) {
      move(rider.id, 0.4, tr('Versprechen gehalten: {0}', [what]));
      return;
    }
    move(rider.id, -1.2, tr('Versprechen gebrochen: {0}', [what]));
    c.inbox.add(Message(
      c.today,
      tr('Berater'),
      tr('{0} fühlt sich getäuscht', [rider.name]),
      tr('Du hattest ihm etwas zugesagt ({0}: {1}) und es nicht gehalten. Das merkt er sich, auch bei der nächsten Vertragsverhandlung.',
          [promise.kind.label, what]),
      raceId: raceId,
    ));
  }

  // --- The run of the season ---------------------------------------------------

  /// What a stage does to the riders: results lift morale, for every team.
  /// For the player's team the first stage of a race also settles promises
  /// and shows whether a rider rode in the part his standing lets him
  /// expect.
  ///
  /// @param p The race.
  /// @param index Zero-based index of the stage just ridden.
  /// @param result Its result.
  void afterStage(RaceProgress p, int index, StageResult result) {
    final race = p.race;
    if (index == 0) {
      checkPromises(p);
      final big = race.tier.factor >= 5;
      for (final r in p.riders) {
        final id = r.id;
        if (race.tier == RaceTier.grandTour) _startedGrandTour.add(id);
        if (!_own(id) || race.tier == RaceTier.championship) continue;
        final leads = _leadsIn(p, id);
        if (big && leads) _ledBigRace.add(id);
        if (race.tier.factor < 2) continue;
        final standing = roleOf(id);
        final works = c.planUsed(race.info.id, 0).roleOf(id).works;
        if (standing.leads && works) {
          move(id, -0.2, tr('Als Helfer eingesetzt: {0}', [race.info.name]));
        } else if (!standing.leads && leads) {
          move(id, 0.25,
              tr('Durfte auf eigene Rechnung fahren: {0}', [race.info.name]));
        }
      }
    }
    final winner = result.placings.firstOrNull?.rider;
    if (winner != null) {
      move(winner.id, race.tier.factor >= 5 ? 0.6 : 0.35,
          tr('Sieg: {0}', [race.info.name]));
    }
    if (!p.finished) return;
    final order = race.isStageRace
        ? [for (final e in p.run.standings.last.general) e.rider]
        : [for (final x in result.placings) x.rider];
    for (var i = race.isStageRace ? 0 : 1; i < 3 && i < order.length; i++) {
      move(order[i].id, 0.25, tr('{0}. Platz: {1}', [i + 1, race.info.name]));
    }
  }

  /// Once a week: moods even out, and days lost to injury or illness are
  /// counted. Once a month from June on an ambitious rider who gets far
  /// fewer race days than his team mates says so, in every team. A rider
  /// who was out for three weeks or more does not: he knows why he raced
  /// less.
  void weekly() {
    for (final id in morale.keys.toList()) {
      final value = morale[id]! * 0.93;
      value.abs() < 0.02 ? morale.remove(id) : morale[id] = value;
    }
    for (final r in c.riderById.values) {
      if (c.isInjured(r.id, c.today)) {
        outDays[r.id] = (outDays[r.id] ?? 0) + 7;
      }
    }
    if (c.today.day > 7 || c.today.month < 6) return;
    for (final e in c.squads.entries) {
      final squad = e.value;
      if (squad.length < 8) continue;
      final program = e.key == c.teamId ? c.program : c.teamPrograms[e.key];
      if (program == null) continue;
      final ahead = <int, int>{};
      for (final race in c.calendar) {
        if (!race.start.isAfter(c.today)) continue;
        for (final id in program[race.info.id] ?? const <int>{}) {
          ahead[id] = (ahead[id] ?? 0) + race.stages.length;
        }
      }
      int days(SimRider r) => c.shapeOf(r.id).raceDays + (ahead[r.id] ?? 0);
      final mean = squad.fold(0, (n, r) => n + days(r)) / squad.length;
      for (final r in squad) {
        if (c.isInjured(r.id, c.today) || (outDays[r.id] ?? 0) >= 21) continue;
        if (of(r.id).ambition > 0.55 && days(r) < 0.55 * mean) {
          move(r.id, -0.3, tr('Zu wenige Renntage im Programm'));
        }
      }
    }
  }

  /// At the turn of the season: the promises of the season are settled,
  /// goals start over and the moods calm down.
  void closeSeason() {
    for (final promise in [...promises.where((p) => p.year <= c.year)]) {
      promises.remove(promise);
      final rider = c.riderById[promise.riderId];
      if (rider == null || rider.teamId != c.teamId) continue;
      if (promise.raceId != 0) {
        // The race never took place with the team in it.
        final name = c.calendar
                .where((r) => r.info.id == promise.raceId)
                .firstOrNull
                ?.info
                .name ??
            '';
        _settle(rider, promise, name, false);
        continue;
      }
      // Long out of action: the season did not allow it.
      if ((outDays[rider.id] ?? 0) >= 60) continue;
      final kept = promise.kind == PromiseKind.start
          ? _startedGrandTour.contains(rider.id)
          : _ledBigRace.contains(rider.id);
      _settle(rider, promise, seasonText(promise.kind), kept);
    }
    goals.clear();
    ownGoals.clear();
    outDays.clear();
    _startedGrandTour.clear();
    _ledBigRace.clear();
    for (final id in morale.keys.toList()) {
      morale[id] = morale[id]! * 0.5;
    }
    notes.removeWhere((id, _) => !_own(id));
    teamRoles.removeWhere((id, _) => !_own(id));
  }

  // --- Saving -----------------------------------------------------------------

  /// @returns Everything as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'morale': {for (final e in morale.entries) '${e.key}': e.value},
        'notes': {for (final e in notes.entries) '${e.key}': e.value},
        'promises': [for (final p in promises) p.toJson()],
        'goals': {
          for (final e in goals.entries) '${e.key}': e.value.toList(),
        },
        'ownGoals': ownGoals.toList(),
        'roles': {
          for (final e in teamRoles.entries) '${e.key}': e.value.index,
        },
        'out': {for (final e in outDays.entries) '${e.key}': e.value},
        'grandTour': _startedGrandTour.toList(),
        'led': _ledBigRace.toList(),
      };

  /// @param j A map written by [toJson], or null for a save from before
  ///   riders had morale.
  void restore(Map<String, dynamic>? j) {
    morale.clear();
    notes.clear();
    promises.clear();
    goals.clear();
    ownGoals.clear();
    teamRoles.clear();
    outDays.clear();
    _startedGrandTour.clear();
    _ledBigRace.clear();
    if (j == null) return;
    for (final e in (j['morale'] as Map<String, dynamic>).entries) {
      morale[int.parse(e.key)] = (e.value as num).toDouble();
    }
    for (final e in (j['notes'] as Map<String, dynamic>).entries) {
      notes[int.parse(e.key)] = [
        for (final x in e.value as List) (x as List).toList(),
      ];
    }
    promises.addAll([
      for (final p in j['promises'] as List)
        RiderPromise.fromJson(p as List, c.year)
    ]);
    for (final e in (j['goals'] as Map<String, dynamic>).entries) {
      goals[int.parse(e.key)] = (e.value as List).cast<int>().toSet();
    }
    ownGoals.addAll((j['ownGoals'] as List).cast<int>());
    for (final e in (j['roles'] as Map<String, dynamic>? ?? const {}).entries) {
      teamRoles[int.parse(e.key)] = TeamRole.values[e.value as int];
    }
    for (final e in (j['out'] as Map<String, dynamic>? ?? const {}).entries) {
      outDays[int.parse(e.key)] = e.value as int;
    }
    _startedGrandTour.addAll((j['grandTour'] as List? ?? const []).cast<int>());
    _ledBigRace.addAll((j['led'] as List? ?? const []).cast<int>());
  }
}
