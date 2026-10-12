import 'dart:math';

import 'package:sim/sim.dart';

import 'career.dart';
import 'economy.dart';

/// Job of a staff member.
enum StaffRole {
  director('Sportlicher Leiter', 'Sportliche Leiter'),
  coach('Trainer', 'Trainer'),
  doctor('Arzt', 'Ärzte'),
  scout('Scout', 'Scouts');

  const StaffRole(this.label, this.plural);
  final String label;

  /// The label for more than one person.
  final String plural;
}

/// What a sports director is particularly good at.
enum DirectorFocus {
  stageRaces('Rundfahrten'),
  classics('Klassiker'),
  sprints('Sprintrennen');

  const DirectorFocus(this.label);
  final String label;
}

/// A staff member. Values run from 1 to 20.
class Staff {
  Staff(this.id, this.name, this.role, this.skill, this.second, this.third,
      this.focus, this.wage, this.teamId);
  final int id;
  final String name;
  final StaffRole role;

  /// Main value: tactics (sports director), training quality, medicine,
  /// judgement (scout).
  final int skill;

  /// Sports director only: reading the race.
  final int second;

  /// Sports director only: motivation.
  final int third;
  final DirectorFocus focus;

  /// Wage in euros per year.
  final int wage;

  /// Team, 0 = unemployed.
  int teamId;

  /// Tied up at a race until this day.
  DateTime? busyUntil;

  /// Id of the race whose team car he is currently in.
  int? atRace;

  /// Quality in a race: tactics and reading the race, with a bonus if the
  /// race matches his speciality.
  ///
  /// @param race The race.
  /// @param sprintStart Whether the first stage is a sprint stage.
  /// @returns A value from 0 to 1.
  double raceSkill(RaceEntry race, {required bool sprintStart}) {
    final fits = switch (focus) {
      DirectorFocus.stageRaces => race.isStageRace,
      DirectorFocus.classics => !race.isStageRace,
      DirectorFocus.sprints => sprintStart,
    };
    return ((skill + second) / 40 + (fits ? 0.08 : 0)).clamp(0.0, 1.0);
  }
}

/// A rider a scout is currently watching.
class ScoutJob {
  ScoutJob(this.riderId, this.scoutId, this.until);
  final int riderId;
  final int scoutId;
  final DateTime until;
}

/// Staff of all teams, assignment of sports directors, and scouting.
///
/// The WorldDB knows no sports directors; staff is generated at the start of
/// the career to match the strength of each team.
class StaffBook {
  StaffBook(this.c) {
    _generate();
  }

  final Career c;
  final all = <Staff>[];
  final jobs = <ScoutJob>[];

  /// Riders a scout has finished watching: their attributes are known.
  final scouted = <int>{};

  /// @param teamId Team id.
  /// @param role Optional role filter.
  /// @returns The team's staff.
  Iterable<Staff> of(int teamId, [StaffRole? role]) =>
      all.where((s) => s.teamId == teamId && (role == null || s.role == role));

  /// Staff without a team, i.e. the job market.
  Iterable<Staff> get free => all.where((s) => s.teamId == 0);

  /// @param teamId Team id.
  /// @returns The sum of staff wages in euros per year.
  int wages(int teamId) => of(teamId).fold(0, (sum, s) => sum + s.wage);

  /// Generates the staff of every team and the job market.
  void _generate() {
    final rng = Random(c.seed * 17 + 3);
    final names = c.fullNames.values.toList();
    var id = 1;
    String name() {
      final last = names[rng.nextInt(names.length)].split(' ').last;
      final first = names[rng.nextInt(names.length)].split(' ').first;
      return '$first $last';
    }

    int level(double base) =>
        (base + rng.nextDouble() * 5 - 2.5).round().clamp(2, 20);

    void add(int teamId, StaffRole role, double base, {String? fixedName}) {
      final skill = level(base);
      all.add(Staff(
        id++,
        fixedName ?? name(),
        role,
        skill,
        level(base),
        level(base),
        DirectorFocus.values[rng.nextInt(DirectorFocus.values.length)],
        // Good people cost disproportionately more.
        (20000 + 2500 * skill + 450 * skill * skill) ~/ 1000 * 1000,
        teamId,
      ));
    }

    for (final team in c.teams.values) {
      if (team.division == 'Free') continue;
      // Team strength 60 to 80 becomes a base level of roughly 5 to 16.
      final base = ((c.teamStrength(team.id) - 60) * 0.55 + 5).clamp(4.0, 17.0);
      final (directors, coaches, doctors, scouts) =
          team.division.startsWith('[1]')
              ? (4, 3, 2, 2)
              : team.division.startsWith('[2]')
                  ? (3, 2, 1, 1)
                  : (2, 1, 1, 0);
      for (var i = 0; i < directors; i++) {
        // The team manager from the WorldDB is the first sports director.
        add(team.id, StaffRole.director, base + (i == 0 ? 1.5 : 0),
            fixedName: i == 0 && team.manager.isNotEmpty ? team.manager : null);
      }
      for (var i = 0; i < coaches; i++) {
        add(team.id, StaffRole.coach, base);
      }
      for (var i = 0; i < doctors; i++) {
        add(team.id, StaffRole.doctor, base);
      }
      for (var i = 0; i < scouts; i++) {
        add(team.id, StaffRole.scout, base);
      }
    }
    // Job market: a few free people of every kind and level.
    for (var i = 0; i < 48; i++) {
      add(0, StaffRole.values[i % 4], 5 + rng.nextDouble() * 11);
    }
  }

  // --- Effects ----------------------------------------------------------------

  int _best(int teamId, StaffRole role) =>
      of(teamId, role).fold(0, (best, s) => max(best, s.skill));

  /// @param teamId Team id.
  /// @returns The factor on the riders' monthly development (around 1.0).
  double coachFactor(int teamId) {
    // One coach looks after about ten riders well; with fewer coaches the
    // best one's skill reaches the squad only in part.
    final coaches = of(teamId, StaffRole.coach).length;
    final riders = c.squads[teamId]?.length ?? 0;
    final cover = riders == 0 ? 1.0 : (coaches * 10 / riders).clamp(0.0, 1.0);
    return 0.85 +
        0.3 * _best(teamId, StaffRole.coach) / 20 * (0.6 + 0.4 * cover);
  }

  /// @param teamId Team id.
  /// @returns How many of the team's riders its coaches can look after
  ///   properly, as a share from 0 to 1.
  double coachCover(int teamId) {
    final riders = c.squads[teamId]?.length ?? 0;
    return riders == 0
        ? 1.0
        : (of(teamId, StaffRole.coach).length * 10 / riders).clamp(0.0, 1.0);
  }

  /// @param teamId Team id.
  /// @returns The factor on time out after a crash or illness (around 1.0).
  double doctorFactor(int teamId) =>
      1.2 - 0.4 * _best(teamId, StaffRole.doctor) / 20;

  /// @param teamId Team id.
  /// @param date A day.
  /// @returns The team's sports directors who are free on that day.
  List<Staff> availableDirectors(int teamId, DateTime date) => [
        for (final s in of(teamId, StaffRole.director))
          if (!(s.busyUntil?.isAfter(date) ?? false)) s,
      ];

  /// Puts a sports director in the team car.
  ///
  /// @param teamId Team id.
  /// @param race The race.
  /// @param sprintStart Whether the first stage is a sprint stage.
  /// @param wanted Id of the director to send; without it the team takes the
  ///   best free one for this race.
  /// @returns His quality (0 to 1), his motivation value and the person;
  ///   without a free director a mechanic drives, with poor values.
  ({double skill, int motivation, Staff? staff}) seat(
      int teamId, RaceEntry race, bool sprintStart,
      {int? wanted}) {
    final free = availableDirectors(teamId, race.start);
    if (free.isEmpty) return (skill: 0.3, motivation: 8, staff: null);
    Staff pick = free.first;
    for (final s in free) {
      if (s.id == wanted) {
        pick = s;
        break;
      }
      if (wanted == null &&
          s.raceSkill(race, sprintStart: sprintStart) >
              pick.raceSkill(race, sprintStart: sprintStart)) {
        pick = s;
      }
    }
    pick
      ..busyUntil = race.end.add(const Duration(days: 1))
      ..atRace = race.info.id;
    return (
      skill: pick.raceSkill(race, sprintStart: sprintStart),
      motivation: pick.third,
      staff: pick,
    );
  }

  // --- Job market -------------------------------------------------------------

  /// Maximum number per role in the player's team.
  static const limits = {
    StaffRole.director: 5,
    StaffRole.coach: 4,
    StaffRole.doctor: 2,
    StaffRole.scout: 3,
  };

  /// Hires someone from the job market.
  ///
  /// @param staffId Id of the staff member.
  /// @returns null on success, otherwise the reason.
  String? hire(int staffId) {
    final s = all.where((x) => x.id == staffId).firstOrNull;
    if (s == null || s.teamId != 0) return 'Nicht mehr zu haben.';
    if (of(c.teamId, s.role).length >= limits[s.role]!) {
      return 'Mehr als ${limits[s.role]} ${s.role.plural} sind nicht vorgesehen.';
    }
    s.teamId = c.teamId;
    return null;
  }

  /// Dismisses a staff member of the player's team.
  ///
  /// @param staffId Id of the staff member.
  /// @returns null on success, otherwise the reason.
  String? fire(int staffId) {
    final s = all.where((x) => x.id == staffId).firstOrNull;
    if (s == null || s.teamId != c.teamId) return 'Gehört nicht zum Team.';
    if (s.busyUntil?.isAfter(c.today) ?? false) {
      return 'Er ist gerade bei einem Rennen.';
    }
    if (jobs.any((j) => j.scoutId == staffId)) {
      return 'Er ist gerade auf Beobachtung.';
    }
    s
      ..teamId = 0
      ..atRace = null;
    return null;
  }

  // --- Scouting ---------------------------------------------------------------

  /// How well the team knows a rider of another team. Everyone has a fair
  /// idea of well-known professionals, hardly any of riders from small teams
  /// and free agents.
  ///
  /// @param riderId Id of the rider.
  /// @returns A value from 0 to 1; 1 means exact values are known.
  double knowledge(int riderId) {
    final r = c.riderById[riderId];
    if (r == null) return 1;
    if (r.teamId == c.teamId || scouted.contains(riderId)) return 1;
    if (c.devTeam.has(riderId)) return 1;
    final division = c.teams[r.teamId]?.division ?? 'Free';
    final base = division.startsWith('[1]')
        ? 0.7
        : division.startsWith('[2]')
            ? 0.5
            : 0.25;
    return (base + 0.2 * _best(c.teamId, StaffRole.scout) / 20)
        .clamp(0.0, 0.95);
  }

  /// Range in which an attribute is believed to lie. The middle is not the
  /// true value, otherwise it could be read off; the offset is fixed per
  /// rider and attribute.
  ///
  /// @param riderId Id of the rider.
  /// @param attribute Name of the attribute.
  /// @param value Its true value.
  /// @returns Lower and upper bound; equal if the value is known.
  (int low, int high) range(int riderId, String attribute, double value) {
    final k = knowledge(riderId);
    if (k >= 1) return (value.round(), value.round());
    final width = ((1 - k) * 9).ceil();
    // Fixed per rider and attribute, independent of the program run.
    final seed = attribute.codeUnits.fold(riderId * 31, (a, b) => a + b * 7);
    final shift = (seed % (width + 1)) - width ~/ 2;
    final mid = value.round() + shift.clamp(-width ~/ 2, width ~/ 2);
    return (mid - width ~/ 2, mid + (width - width ~/ 2));
  }

  /// Sends a free scout to watch a rider.
  ///
  /// @param riderId Id of the rider.
  /// @returns null if a scout is on his way, otherwise the reason.
  String? scout(int riderId) {
    if (knowledge(riderId) >= 1) return 'Über ihn ist alles bekannt.';
    if (jobs.any((j) => j.riderId == riderId))
      return 'Er wird schon beobachtet.';
    final idle = of(c.teamId, StaffRole.scout)
        .where((s) => !jobs.any((j) => j.scoutId == s.id))
        .toList()
      ..sort((a, b) => b.skill.compareTo(a.skill));
    if (idle.isEmpty) {
      return of(c.teamId, StaffRole.scout).isEmpty
          ? 'Das Team hat keinen Scout.'
          : 'Alle Scouts sind unterwegs.';
    }
    final s = idle.first;
    // A good scout needs two weeks, a weak one five.
    final days = (38 - 1.3 * s.skill).round().clamp(10, 40);
    jobs.add(ScoutJob(riderId, s.id, c.today.add(Duration(days: days))));
    return null;
  }

  /// Lets the head scout choose: he sends free scouts to riders on the market
  /// who could suit the team and about whom little is known.
  void scoutOnOwn() {
    final scouts = of(c.teamId, StaffRole.scout).toList();
    if (scouts.isEmpty || jobs.length >= scouts.length) return;
    final level = c.teamStrength(c.teamId);
    double interest(SimRider r) =>
        Economy.rating(r) + (c.year - r.born ~/ 10000 < 24 ? 3 : 0);
    final targets = [
      for (final r in c.economy.market())
        if (knowledge(r.id) < 1 &&
            !jobs.any((j) => j.riderId == r.id) &&
            Economy.rating(r) <= level + 2 &&
            Economy.rating(r) >= level - 9)
          r,
    ]..sort((a, b) => interest(b).compareTo(interest(a)));
    for (final r in targets) {
      if (scout(r.id) != null) break;
    }
  }

  /// Delivers the reports of scouts who are done today.
  /// Renews the job market: per role the people who have been on offer
  /// longest leave, and six new ones arrive, one for every level from
  /// beginner to top class.
  void _renewMarket() {
    final rng = c.rng;
    final names = c.fullNames.values.toList();
    var id = all.fold(0, (top, s) => max(top, s.id)) + 1;
    int level(double base) =>
        (base + rng.nextDouble() * 4 - 2).round().clamp(2, 20);
    for (final role in StaffRole.values) {
      final offered = of(0, role).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      // Keep the six most recent, so that nobody vanishes after a month.
      for (final s in offered.take(max(0, offered.length - 6))) {
        all.remove(s);
      }
      for (final base in const [4.0, 7.0, 10.0, 13.0, 16.0, 18.5]) {
        final skill = level(base);
        final first = names[rng.nextInt(names.length)].split(' ').first;
        final last = names[rng.nextInt(names.length)].split(' ').last;
        all.add(Staff(
          id++,
          '$first $last',
          role,
          skill,
          level(base),
          level(base),
          DirectorFocus.values[rng.nextInt(DirectorFocus.values.length)],
          (20000 + 2500 * skill + 450 * skill * skill) ~/ 1000 * 1000,
          0,
        ));
      }
    }
  }

  void daily() {
    if (c.today.day == 1) _renewMarket();
    final done = jobs.where((j) => !j.until.isAfter(c.today)).toList();
    for (final j in done) {
      jobs.remove(j);
      scouted.add(j.riderId);
      final r = c.riderById[j.riderId];
      if (r == null) continue;
      final a = r.attributes;
      final scoutName =
          all.where((s) => s.id == j.scoutId).firstOrNull?.name ?? 'Scout';
      c.inbox.add(Message(
        c.today,
        scoutName,
        'Bericht zu ${r.name}',
        '${c.fullName(r.id)} (${c.year - r.born ~/ 10000}, ${r.country}): '
            'Berg ${a.mountain.round()}, Hügel ${a.hill.round()}, '
            'Zeitfahren ${a.timeTrial.round()}, Sprint ${a.sprint.round()}, '
            'Kopfsteinpflaster ${a.cobble.round()}, Flach ${a.flat.round()}. '
            'Potenzial ${r.potential.toStringAsFixed(1)}. '
            '${r.potential >= 5.5 && c.year - r.born ~/ 10000 < 24 ? 'Ein Talent, bei dem es sich lohnt, früh dran zu sein.' : 'Seine Werte sind jetzt in der Marktliste genau.'}',
      ));
    }
  }

  /// @returns All staff, scouting jobs and scouted riders as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'all': [
          for (final s in all)
            [
              s.id,
              s.name,
              s.role.index,
              s.skill,
              s.second,
              s.third,
              s.focus.index,
              s.wage,
              s.teamId,
              s.busyUntil?.millisecondsSinceEpoch,
              s.atRace,
            ],
        ],
        'jobs': [
          for (final j in jobs)
            [j.riderId, j.scoutId, j.until.millisecondsSinceEpoch],
        ],
        'scouted': scouted.toList(),
      };

  /// Replaces the generated staff with that of a snapshot.
  ///
  /// @param j A map written by [toJson].
  void restore(Map<String, dynamic> j) {
    DateTime? date(Object? ms) => ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);
    all
      ..clear()
      ..addAll([
        for (final s in (j['all'] as List).cast<List<dynamic>>())
          Staff(
            s[0] as int,
            s[1] as String,
            StaffRole.values[s[2] as int],
            s[3] as int,
            s[4] as int,
            s[5] as int,
            DirectorFocus.values[s[6] as int],
            s[7] as int,
            s[8] as int,
          )
            ..busyUntil = date(s[9])
            ..atRace = s[10] as int?,
      ]);
    jobs
      ..clear()
      ..addAll([
        for (final x in (j['jobs'] as List).cast<List<dynamic>>())
          ScoutJob(x[0] as int, x[1] as int, date(x[2])!),
      ]);
    scouted
      ..clear()
      ..addAll((j['scouted'] as List).cast<int>());
  }
}
