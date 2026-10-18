import 'dart:math';

import 'package:sim/sim.dart';

import 'career.dart';
import 'economy.dart';

/// Job of a staff member.
enum StaffRole {
  director('Sports director', 'Sports directors'),
  coach('Coach', 'Coach'),
  doctor('Doctor', 'Doctors'),
  scout('Scout', 'Scouts'),

  /// Prepares and repairs the bikes: a quick wheel change, fewer punctures
  /// and mechanical problems.
  mechanic('Mechanic', 'Mechanics'),

  /// Soigneur and physiotherapist: helps the riders recover overnight in
  /// stage races.
  physio('Physiotherapist', 'Physiotherapists');

  const StaffRole(this._label, this._plural);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);

  /// The label for more than one person.
  final String _plural;

  /// The label for more than one in the current language.
  String get plural => tr(_plural);
}

/// What a sports director is particularly good at.
enum DirectorFocus {
  stageRaces('Stage races'),
  classics('Classics'),
  sprints('Sprint races');

  const DirectorFocus(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
}

/// A staff member. Values run from 1 to 20.
class Staff {
  Staff(this.id, this.name, this.role, this.skill, this.second, this.third,
      this.focus, this.wage, this.teamId,
      {this.born = 0});
  final int id;
  final String name;
  final StaffRole role;

  /// Main value: tactics (sports director), training quality, medicine,
  /// judgement (scout). Young people improve, old ones slowly lose touch.
  int skill;

  /// Sports director only: reading the race.
  int second;

  /// Sports director only: motivation.
  final int third;
  final DirectorFocus focus;

  /// Wage in euros per year.
  int wage;

  /// Year of birth.
  int born;

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

/// A rider a scout is currently watching, or a test at the team's base.
class ScoutJob {
  ScoutJob(this.riderId, this.scoutId, this.until, [this.stage = 2]);
  final int riderId;

  /// Id of the scout; 0 for a test at the base.
  final int scoutId;
  final DateTime until;

  /// What the job brings: 1 a first impression, 2 a detailed report, 3 the
  /// test at the base, after which everything is known.
  final int stage;
}

/// A scout's standing assignment: he looks for riders of a country, an
/// age and a kind, and reports on the most promising he finds.
class ScoutAssignment {
  ScoutAssignment(this.scoutId, this.country, this.maxAge, this.kind,
      this.until, this.next);
  final int scoutId;

  /// Country code, or null for anywhere.
  final String? country;

  /// Oldest age that interests the team.
  final int maxAge;

  /// Kind of rider as in [Economy.kindOf], or null for any.
  final String? kind;

  /// Last day of the assignment.
  final DateTime until;

  /// Day of the next report.
  DateTime next;

  /// @returns The assignment as a compact list.
  List<Object?> toJson() => [
        scoutId,
        country,
        maxAge,
        kind,
        until.millisecondsSinceEpoch,
        next.millisecondsSinceEpoch,
      ];

  /// @param j A list written by [toJson].
  /// @returns The assignment.
  static ScoutAssignment fromJson(List<dynamic> j) => ScoutAssignment(
        j[0] as int,
        j[1] as String?,
        j[2] as int,
        j[3] as String?,
        DateTime.fromMillisecondsSinceEpoch(j[4] as int, isUtc: true),
        DateTime.fromMillisecondsSinceEpoch(j[5] as int, isUtc: true),
      );
}

/// An offer another team has made to one of the player's staff.
typedef StaffLure = ({int teamId, int wage});

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

  /// Riders tested at the base (or, in older saves, scouted): everything
  /// about them is known.
  final scouted = <int>{};

  /// Reports on riders by rider id: 1 a first impression, 2 a detailed
  /// report.
  final reports = <int, int>{};

  /// Standing assignments of the player's scouts.
  final assignments = <ScoutAssignment>[];

  /// Offers of other teams to the player's staff, by staff id; decided at
  /// the turn of the year.
  final lures = <int, StaffLure>{};

  /// What a test at the base costs.
  static const testCost = 6000;

  /// Year of birth of a staff member, fixed by his id.
  int _bornFor(int id) => c.year - 28 - (id * 7919 + c.seed) % 32;

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
        id,
        fixedName ?? name(),
        role,
        skill,
        level(base),
        level(base),
        DirectorFocus.values[rng.nextInt(DirectorFocus.values.length)],
        // Good people cost disproportionately more.
        wageFor(skill),
        teamId,
        born: _bornFor(id),
      ));
      id++;
    }

    for (final team in c.teams.values) {
      if (team.division == 'Free') continue;
      final base = _baseFor(team.id);
      final (directors, coaches, doctors, scouts) =
          team.division.startsWith('[1]')
              ? (4, 3, 2, 2)
              : team.division.startsWith('[2]')
                  ? (3, 2, 1, 1)
                  : (2, 1, 1, 0);
      final (mechanics, physios) = _careCrew(team.division);
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
      for (var i = 0; i < mechanics; i++) {
        add(team.id, StaffRole.mechanic, base);
      }
      for (var i = 0; i < physios; i++) {
        add(team.id, StaffRole.physio, base);
      }
    }
    // Job market: a few free people of every kind and level.
    for (var i = 0; i < 12 * StaffRole.values.length; i++) {
      add(0, StaffRole.values[i % StaffRole.values.length],
          5 + rng.nextDouble() * 11);
    }
  }

  /// The level of a team's staff at the start: team strength 60 to 80
  /// becomes a base level of roughly 5 to 16.
  ///
  /// @param teamId Id of the team.
  /// @returns The base level.
  double _baseFor(int teamId) =>
      ((c.teamStrength(teamId) - 60) * 0.55 + 5).clamp(4.0, 17.0).toDouble();

  /// Fits the staff of a newly founded team to its strength once its squad
  /// is in place: before that it has no riders, and its people were those
  /// of the weakest team.
  ///
  /// @param teamId Id of the team.
  ///
  /// @param keepBetter Whether people better than that keep their values,
  ///   for a running career.
  void fitTo(int teamId, {bool keepBetter = false}) {
    final rng = Random(c.seed * 31 + teamId);
    final base = _baseFor(teamId);
    int level(double b) =>
        (b + rng.nextDouble() * 5 - 2.5).round().clamp(2, 20);
    var first = true;
    for (final s in of(teamId)) {
      final lead = first && s.role == StaffRole.director;
      if (lead) first = false;
      final skill = level(base + (lead ? 1.5 : 0)), second = level(base);
      if (keepBetter && s.skill >= skill) continue;
      s
        ..skill = skill
        ..second = keepBetter ? max(s.second, second) : second
        ..wage = wageFor(skill);
    }
  }

  /// What a staff member of a skill earns: good people cost
  /// disproportionately more.
  ///
  /// @param skill His main value.
  /// @returns Euros per year.
  static int wageFor(int skill) =>
      (20000 + 2500 * skill + 450 * skill * skill) ~/ 1000 * 1000;

  /// Mechanics and physiotherapists by tier.
  static (int, int) _careCrew(String division) => division.startsWith('[1]')
      ? (4, 3)
      : division.startsWith('[2]')
          ? (3, 2)
          : (2, 1);

  /// Gives every team mechanics and physiotherapists, for a save from
  /// before they existed.
  void _addCareCrew() {
    final rng = Random(c.seed * 29 + 11);
    final names = c.fullNames.values.toList();
    var id = all.fold(0, (top, s) => max(top, s.id)) + 1;
    int level(double base) =>
        (base + rng.nextDouble() * 5 - 2.5).round().clamp(2, 20);
    void add(int teamId, StaffRole role, double base) {
      final skill = level(base);
      final first = names[rng.nextInt(names.length)].split(' ').first;
      final last = names[rng.nextInt(names.length)].split(' ').last;
      all.add(Staff(id, '$first $last', role, skill, level(base), level(base),
          DirectorFocus.stageRaces, wageFor(skill), teamId,
          born: _bornFor(id)));
      id++;
    }

    for (final team in c.teams.values) {
      if (team.division == 'Free') continue;
      final base = ((c.teamStrength(team.id) - 60) * 0.55 + 5).clamp(4.0, 17.0);
      final (mechanics, physios) = _careCrew(team.division);
      for (var i = 0; i < mechanics; i++) {
        add(team.id, StaffRole.mechanic, base);
      }
      for (var i = 0; i < physios; i++) {
        add(team.id, StaffRole.physio, base);
      }
    }
    for (var i = 0; i < 12; i++) {
      add(0, i.isEven ? StaffRole.mechanic : StaffRole.physio,
          5 + rng.nextDouble() * 11);
    }
  }

  /// Quality of a team's mechanics, 0 to 1: the best one's skill, as far as
  /// there are enough of them for the races of the season (about one for
  /// eight riders).
  ///
  /// @param teamId Id of the team.
  /// @returns 0 to 1; about 0.5 for an average professional team.
  double mechanicQuality(int teamId) => _care(teamId, StaffRole.mechanic, 8);

  /// Quality of a team's physiotherapists, 0 to 1, as for [mechanicQuality]
  /// with one for ten riders.
  ///
  /// @param teamId Id of the team.
  /// @returns 0 to 1.
  double physioQuality(int teamId) => _care(teamId, StaffRole.physio, 10);

  double _care(int teamId, StaffRole role, int perHead) {
    final n = of(teamId, role).length;
    if (n == 0) return 0;
    final riders = c.squads[teamId]?.length ?? 0;
    final cover = riders == 0 ? 1.0 : (n * perHead / riders).clamp(0.0, 1.0);
    // Skill 14 is an average professional, 20 the best there is.
    return ((_best(teamId, role) - 8) / 12 * (0.7 + 0.3 * cover))
        .clamp(0.0, 1.0);
  }

  // --- Effects ----------------------------------------------------------------

  int _best(int teamId, StaffRole role) =>
      of(teamId, role).fold(0, (best, s) => max(best, s.skill));

  /// Debug switch of the app: every rider counts as fully known. Not saved.
  bool revealAll = false;

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
    StaffRole.mechanic: 5,
    StaffRole.physio: 4,
  };

  /// Hires someone from the job market.
  ///
  /// @param staffId Id of the staff member.
  /// @returns null on success, otherwise the reason.
  String? hire(int staffId) {
    final s = all.where((x) => x.id == staffId).firstOrNull;
    if (s == null || s.teamId != 0) return tr('No longer available.');
    if (of(c.teamId, s.role).length >= limits[s.role]!) {
      return tr('More than {0} {1} are not allowed.',
          [limits[s.role], s.role.plural]);
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
    if (s == null || s.teamId != c.teamId)
      return tr('Does not belong to the team.');
    if (s.busyUntil?.isAfter(c.today) ?? false) {
      return tr('He is at a race right now.');
    }
    if (jobs.any((j) => j.scoutId == staffId) ||
        assignments.any((a) => a.scoutId == staffId)) {
      return tr('He is on a scouting assignment.');
    }
    lures.remove(staffId);
    s
      ..teamId = 0
      ..atRace = null;
    return null;
  }

  // --- Scouting ---------------------------------------------------------------

  /// How well the team knows a rider of another team. Everyone has a fair
  /// idea of well-known professionals, little of riders from small teams
  /// and hardly any of free agents. Reports narrow it in stages: a first
  /// impression, a detailed report, and a test at the base after which
  /// everything is known.
  ///
  /// @param riderId Id of the rider.
  /// @returns A value from 0 to 1; 1 means exact values are known.
  double knowledge(int riderId) {
    if (revealAll) return 1;
    final r = c.riderById[riderId];
    if (r == null) return 1;
    if (r.teamId == c.teamId || scouted.contains(riderId)) return 1;
    if (c.devTeam.has(riderId)) return 1;
    final division = c.teams[r.teamId]?.division ?? 'Free';
    final scout = _best(c.teamId, StaffRole.scout) / 20;
    final base = (division.startsWith('[1]')
            ? 0.65
            : division.startsWith('[2]')
                ? 0.45
                : division == 'Free'
                    ? 0.1
                    : 0.2) +
        0.15 * scout +
        c.facilities.scoutingBonus(c.teamId);
    final report = switch (reports[riderId] ?? 0) {
      0 => 0.0,
      1 => 0.72 + 0.05 * scout,
      _ => 0.88 + 0.05 * scout,
    };
    return max(base, report).clamp(0.0, 0.95);
  }

  /// @param riderId Id of a rider.
  /// @returns How far the team's scouting of him has come: 0 nothing, 1 a
  ///   first impression, 2 a detailed report, 3 tested at the base.
  int stageOf(int riderId) =>
      scouted.contains(riderId) ? 3 : reports[riderId] ?? 0;

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

  /// Scouts of the player's team without a job or an assignment, the best
  /// first.
  List<Staff> get idleScouts => of(c.teamId, StaffRole.scout)
      .where((s) =>
          !jobs.any((j) => j.scoutId == s.id) &&
          !assignments.any((a) => a.scoutId == s.id))
      .toList()
    ..sort((a, b) => b.skill.compareTo(a.skill));

  /// Sends a free scout to watch a rider: the next stage of his scouting,
  /// a first impression or a detailed report.
  ///
  /// @param riderId Id of the rider.
  /// @returns null if a scout is on his way, otherwise the reason.
  String? scout(int riderId) {
    if (knowledge(riderId) >= 1) return tr('Everything is known about him.');
    if (jobs.any((j) => j.riderId == riderId))
      return tr('He is already being scouted.');
    final stage = (reports[riderId] ?? 0) + 1;
    if (stage > 2) {
      return tr(
          'The scouts have seen enough; only a test at the base tells more.');
    }
    final idle = idleScouts;
    if (idle.isEmpty) {
      return of(c.teamId, StaffRole.scout).isEmpty
          ? tr('The team has no scout.')
          : tr('All scouts are on assignment.');
    }
    final s = idle.first;
    // A first impression takes one to two weeks, a detailed report two
    // weeks for a good scout and five for a weak one.
    final days = ((stage == 1 ? 20 - 0.6 * s.skill : 38 - 1.3 * s.skill) *
            c.facilities.scoutDays(c.teamId))
        .round()
        .clamp(5, 40);
    jobs.add(ScoutJob(riderId, s.id, c.today.add(Duration(days: days)), stage));
    return null;
  }

  /// Invites a rider for a test at the team's base after a detailed report:
  /// a few days and some money, and then everything about him is known,
  /// his potential included.
  ///
  /// @param riderId Id of the rider.
  /// @returns null if the test is arranged, otherwise the reason.
  String? test(int riderId) {
    if (knowledge(riderId) >= 1) return tr('Everything is known about him.');
    if (jobs.any((j) => j.riderId == riderId))
      return tr('He is already being scouted.');
    if ((reports[riderId] ?? 0) < 2) {
      return tr('A test at the base comes after a detailed report.');
    }
    if (c.economy.available < testCost) {
      return tr('There is not enough money in the account.');
    }
    c.economy.charge(testCost.toDouble());
    jobs.add(ScoutJob(riderId, 0, c.today.add(const Duration(days: 5)), 3));
    return null;
  }

  /// Gives a free scout a standing assignment for two months.
  ///
  /// @param scoutId Id of the scout.
  /// @param country Country code, or null for anywhere.
  /// @param maxAge Oldest age that interests the team.
  /// @param kind Kind of rider as in [Economy.kindOf], or null for any.
  /// @returns null on success, otherwise the reason.
  String? assign(int scoutId, String? country, int maxAge, String? kind) {
    final s =
        of(c.teamId, StaffRole.scout).where((x) => x.id == scoutId).firstOrNull;
    if (s == null) return tr('Does not belong to the team.');
    if (!idleScouts.contains(s)) return tr('He is on a scouting assignment.');
    assignments.add(ScoutAssignment(
      scoutId,
      country,
      maxAge.clamp(18, 40),
      kind,
      c.today.add(const Duration(days: 60)),
      c.today.add(Duration(days: _interval(s))),
    ));
    return null;
  }

  /// Ends a scout's assignment early.
  ///
  /// @param scoutId Id of the scout.
  /// @returns null on success, otherwise the reason.
  String? recall(int scoutId) {
    final before = assignments.length;
    assignments.removeWhere((a) => a.scoutId == scoutId);
    return assignments.length < before ? null : tr('He has no assignment.');
  }

  /// Days between two reports of an assignment: a good scout finds
  /// riders faster.
  int _interval(Staff s) =>
      ((22 - 0.6 * s.skill) * c.facilities.scoutDays(c.teamId))
          .round()
          .clamp(6, 22);

  /// A report of an assignment: the two riders the scout rates highest
  /// among those he has not reported on yet. His judgement errs by up to
  /// a few points, the more the weaker he is.
  void _assignmentReport(ScoutAssignment a) {
    final scout = all.where((x) => x.id == a.scoutId).firstOrNull;
    if (scout == null) return;
    final error = (20 - scout.skill) / 20 * 6;
    double judged(SimRider r) =>
        c.economy.outlook(r) +
        (Economy.unit(r.id * 13 + scout.id, c.year) * 2 - 1) * error;
    final found = [
      for (final r in c.riderById.values)
        if (r.teamId != c.teamId &&
            !c.devTeam.has(r.id) &&
            (reports[r.id] ?? 0) == 0 &&
            !scouted.contains(r.id) &&
            (a.country == null || r.country == a.country) &&
            c.year - r.born ~/ 10000 <= a.maxAge &&
            (a.kind == null || Economy.kindOf(r) == a.kind))
          r,
    ]..sort((x, y) => judged(y).compareTo(judged(x)));
    final picked = found.take(2).toList();
    if (picked.isEmpty) return;
    for (final r in picked) {
      reports[r.id] = 1;
    }
    c.inbox.add(Message(
      c.today,
      scout.name,
      tr('Scouting assignment: {0}', [
        picked.map((r) => r.name).join(', '),
      ]),
      tr(
          'First impressions from my assignment: {0}. Their estimates are now narrower in the market; a detailed report tells more.',
          [
            [
              for (final r in picked)
                '${c.fullName(r.id)} (${c.year - r.born ~/ 10000}, ${c.teams[r.teamId]?.name ?? r.team}${c.economy.expiring(r) ? ', ' + tr('contract ending') : ''})',
            ].join('; ')
          ]),
    ));
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
          id,
          '$first $last',
          role,
          skill,
          level(base),
          level(base),
          DirectorFocus.values[rng.nextInt(DirectorFocus.values.length)],
          wageFor(skill),
          0,
          born: _bornFor(id),
        ));
        id++;
      }
    }
  }

  void daily() {
    if (c.today.day == 1) _renewMarket();
    if (c.today.day == 1 && c.today.month == 11) _ambitions();
    if (c.today.weekday == DateTime.monday) _weeklyNote();
    for (final a in [...assignments]) {
      if (c.today.isAfter(a.until)) {
        assignments.remove(a);
        continue;
      }
      if (c.today.isBefore(a.next)) continue;
      _assignmentReport(a);
      final scout = all.where((x) => x.id == a.scoutId).firstOrNull;
      a.next =
          c.today.add(Duration(days: scout == null ? 14 : _interval(scout)));
    }
    final done = jobs.where((j) => !j.until.isAfter(c.today)).toList();
    for (final j in done) {
      jobs.remove(j);
      final r = c.riderById[j.riderId];
      if (j.stage >= 3) {
        scouted.add(j.riderId);
      } else {
        reports[j.riderId] = max(reports[j.riderId] ?? 0, j.stage);
      }
      if (r == null) continue;
      final scoutName = j.scoutId == 0
          ? tr('Coach')
          : all.where((s) => s.id == j.scoutId).firstOrNull?.name ?? 'Scout';
      if (j.stage == 1) {
        final (low, high) = range(r.id, 'Strength', Economy.rating(r));
        c.inbox.add(Message(
          c.today,
          scoutName,
          tr('First impression of {0}', [r.name]),
          tr(
              '{0} ({1}, {2}, {3}): I would put him between {4} and {5}, above all a {6}. A detailed report would tell more.',
              [
                c.fullName(r.id),
                c.year - r.born ~/ 10000,
                r.country,
                c.teams[r.teamId]?.name ?? r.team,
                low,
                high,
                tr(Economy.kindLabel(Economy.kindOf(r))),
              ]),
        ));
        continue;
      }
      if (j.stage == 2) {
        final (low, high) = range(r.id, 'Strength', Economy.rating(r));
        final (pLow, pHigh) = range(r.id, 'Potential', r.potential * 10);
        c.inbox.add(Message(
          c.today,
          scoutName,
          tr('Detailed report on {0}', [r.name]),
          tr(
              '{0} ({1}, {2}): strength {3} to {4}, potential {5} to {6}, {7}. A test at the base would make everything exact.',
              [
                c.fullName(r.id),
                c.year - r.born ~/ 10000,
                c.teams[r.teamId]?.name ?? r.team,
                low,
                high,
                dec(pLow / 10),
                dec(pHigh / 10),
                c.people.of(r.id).label,
              ]),
        ));
        continue;
      }
      final a = r.attributes;
      c.inbox.add(Message(
        c.today,
        scoutName,
        tr('Report on {0}', [r.name]),
        tr(
            '{0} ({1}, {2}): mountain {3}, hill {4}, time trial {5}, sprint {6}, cobbles {7}, flat {8}. Potential {9}. {10}',
            [
              c.fullName(r.id),
              c.year - r.born ~/ 10000,
              r.country,
              a.mountain.round(),
              a.hill.round(),
              a.timeTrial.round(),
              a.sprint.round(),
              a.cobble.round(),
              a.flat.round(),
              r.potential.toStringAsFixed(1),
              r.potential >= 5.5 && c.year - r.born ~/ 10000 < 24
                  ? tr('A talent worth getting to early.')
                  : tr('His values are now exact in the market list.')
            ]),
      ));
    }
  }

  // --- Over the seasons -------------------------------------------------------

  /// At the turn of the year: young staff get better and old staff a little
  /// worse, staff the player did not keep go to the teams that lured them,
  /// and the other teams replace their weakest people where the market has
  /// clearly better ones.
  /// The player leaves for another team: his scouts stay with the old team,
  /// and so do their jobs; what they found out he keeps.
  void handOver() {
    jobs.clear();
    assignments.clear();
    lures.clear();
  }

  void closeSeason() {
    for (final s in all) {
      final age = c.year - s.born;
      final roll = Economy.unit(s.id * 31 + 7, c.year);
      if (age < 40 && roll < 0.45 * (20 - s.skill) / 18) {
        s.skill = (s.skill + 1).clamp(2, 20);
        if (s.role == StaffRole.director)
          s.second = (s.second + 1).clamp(2, 20);
      } else if (age >= 56 && roll > 0.7) {
        s.skill = (s.skill - 1).clamp(2, 20);
      }
    }
    for (final e in lures.entries) {
      final s = all.where((x) => x.id == e.key).firstOrNull;
      if (s == null || s.teamId != c.teamId) continue;
      final team = e.value.teamId;
      // The one he replaces there goes on the market.
      final there = of(team, s.role).toList()
        ..sort((a, b) => a.skill.compareTo(b.skill));
      if (there.isNotEmpty) there.first.teamId = 0;
      s
        ..teamId = team
        ..wage = e.value.wage
        ..atRace = null;
      c.inbox.add(Message(
        c.today,
        tr('Staff'),
        tr('{0} leaves for {1}', [s.name, c.teams[team]?.name ?? '']),
        tr('{0} has accepted the offer of {1} and leaves the team at the turn of the year.',
            [s.name, c.teams[team]?.name ?? '']),
      ));
    }
    lures.clear();
    _othersHire();
  }

  /// Every other team replaces its weakest person of one role a season, if
  /// the market has one at least three points better at a wage it can pay.
  void _othersHire() {
    for (final team in c.teams.values) {
      if (team.id == c.teamId || team.division == 'Free') continue;
      for (final role in StaffRole.values) {
        final mine = of(team.id, role).toList();
        if (mine.isEmpty) continue;
        final weakest = mine.reduce((a, b) => b.skill < a.skill ? b : a);
        final better = of(0, role)
            .where((x) =>
                x.skill >= weakest.skill + 3 && x.wage <= weakest.wage * 1.6)
            .toList();
        if (better.isEmpty) continue;
        final pick = better.reduce((a, b) => b.skill > a.skill ? b : a);
        weakest.teamId = 0;
        pick.teamId = team.id;
        break;
      }
    }
  }

  /// 1 November: other teams try to lure the player's best people. A
  /// stronger team whose best of the role is weaker offers a third more.
  void _ambitions() {
    final level = c.teamStrength(c.teamId);
    for (final s in of(c.teamId).toList()) {
      if (s.skill < 13 || lures.containsKey(s.id)) continue;
      if (Economy.unit(s.id, c.year * 3 + 1) >= 0.2) continue;
      final keen = [
        for (final t in c.teams.values)
          if (t.id != c.teamId &&
              t.division.startsWith('[1]') &&
              c.teamStrength(t.id) > level &&
              _best(t.id, s.role) < s.skill)
            t,
      ]..sort((a, b) => c.teamStrength(b.id).compareTo(c.teamStrength(a.id)));
      if (keen.isEmpty) continue;
      final team = keen.first;
      final wage = (s.wage * 1.33 / 1000).round() * 1000;
      lures[s.id] = (teamId: team.id, wage: wage);
      c.inbox.add(Message(
        c.today,
        tr('Staff'),
        tr('{0} has an offer from {1}', [s.name, team.name]),
        tr('{1} offers {0} ({2}) {3} a year. Match it on the staff page by 31 December, or he leaves at the turn of the year.',
            [s.name, team.name, s.role.label, Economy.euro(wage)]),
      ));
    }
  }

  /// Matches another team's offer: the staff member stays at its wage.
  ///
  /// @param staffId Id of the staff member.
  /// @returns null on success, otherwise the reason.
  String? keep(int staffId) {
    final lure = lures[staffId];
    final s = all.where((x) => x.id == staffId).firstOrNull;
    if (lure == null || s == null) return tr('He has no other offer.');
    s.wage = lure.wage;
    lures.remove(staffId);
    return null;
  }

  /// Monday: one of the staff writes what he would change, the most
  /// pressing matter first and a different one from week to week.
  void _weeklyNote() {
    final squad = c.squads[c.teamId] ?? const <SimRider>[];
    final notes = <(StaffRole, String, String)>[];
    // The coach: riders who are run down.
    final tired = [
      for (final r in squad)
        if (c.shapeOf(r.id).freshness < -25 &&
            c.shapeOf(r.id).load != TrainingLoad.low &&
            !c.isInjured(r.id, c.today))
          r.name,
    ];
    if (tired.isNotEmpty) {
      notes.add((
        StaffRole.coach,
        tr('Tired riders'),
        tr('{0} are run down. I would set their training to easy for a week.',
            [tired.take(4).join(', ')]),
      ));
    }
    // The sports director: a race soon with places nobody is planned for.
    if (!c.delegation.planning) {
      for (final race in c.ownRaces) {
        final days = race.start.difference(c.today).inDays;
        if (days < 3 || days > 14 || c.progress.containsKey(race.info.id)) {
          continue;
        }
        final planned = c.program[race.info.id]?.length ?? 0;
        final size = c.world.raceField(race.info.id).ridersPerTeam;
        if (planned < size) {
          notes.add((
            StaffRole.director,
            tr('{0} in {1} days', [race.info.name, days]),
            tr('Only {0} of {1} places are planned for {2}. I would fill them now in the race planner.',
                [planned, size, race.info.name]),
          ));
          break;
        }
      }
    }
    // The coach: young riders without a mentor while an older one is free.
    final young = [
      for (final r in squad)
        if (c.year - r.born ~/ 10000 <= 22 && c.people.mentorOf(r.id) == null)
          r,
    ];
    final free = [
      for (final r in squad)
        if (c.people.mentorReason(r.id) == null &&
            c.people.menteesOf(r.id).length < 2)
          r,
    ];
    if (young.isNotEmpty && free.isNotEmpty) {
      notes.add((
        StaffRole.coach,
        tr('A mentor for {0}', [young.first.name]),
        tr('{0} has nobody to learn from. {1} could look after him; he would develop a little faster.',
            [young.first.name, free.first.name]),
      ));
    }
    // The scout: from August, a rider on the market who would suit us.
    if (c.economy.windowOpen) {
      final level = c.teamStrength(c.teamId);
      final fit = [
        for (final r in c.economy.market())
          if (knowledge(r.id) >= 0.7 &&
              Economy.rating(r) >= level - 2 &&
              Economy.rating(r) <= level + 4 &&
              !c.watch.contains(r.id))
            r,
      ]..sort((a, b) => Economy.rating(b).compareTo(Economy.rating(a)));
      if (fit.isNotEmpty) {
        notes.add((
          StaffRole.scout,
          tr('{0} is available', [fit.first.name]),
          tr('{0} ({1}) has no contract for next season yet and would suit us. I would put him on the shortlist.',
              [c.fullName(fit.first.id), c.teams[fit.first.teamId]?.name ?? '']),
        ));
      }
    }
    if (notes.isEmpty) return;
    final week = c.today.difference(DateTime.utc(c.year, 1, 1)).inDays ~/ 7;
    final (role, subject, text) = notes[week % notes.length];
    final who = of(c.teamId, role).fold<Staff?>(
        null, (best, s) => best == null || s.skill > best.skill ? s : best);
    if (who == null) return;
    c.inbox.add(Message(
      c.today,
      tr('Staff'),
      tr('{0}: {1}', [who.name, subject]),
      text,
    ));
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
              s.born,
            ],
        ],
        'jobs': [
          for (final j in jobs)
            [j.riderId, j.scoutId, j.until.millisecondsSinceEpoch, j.stage],
        ],
        'scouted': scouted.toList(),
        'reports': {for (final e in reports.entries) '${e.key}': e.value},
        'assignments': [for (final a in assignments) a.toJson()],
        'lures': {
          for (final e in lures.entries)
            '${e.key}': [e.value.teamId, e.value.wage],
        },
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
            born: s.length > 11 ? s[11] as int : _bornFor(s[0] as int),
          )
            ..busyUntil = date(s[9])
            ..atRace = s[10] as int?,
      ]);
    jobs
      ..clear()
      ..addAll([
        for (final x in (j['jobs'] as List).cast<List<dynamic>>())
          // A job from before the stages makes everything known.
          ScoutJob(x[0] as int, x[1] as int, date(x[2])!,
              x.length > 3 ? x[3] as int : 3),
      ]);
    scouted
      ..clear()
      ..addAll((j['scouted'] as List).cast<int>());
    reports
      ..clear()
      ..addAll({
        for (final e
            in (j['reports'] as Map<String, dynamic>? ?? const {}).entries)
          int.parse(e.key): e.value as int,
      });
    assignments
      ..clear()
      ..addAll([
        for (final a
            in (j['assignments'] as List? ?? const []).cast<List<dynamic>>())
          ScoutAssignment.fromJson(a),
      ]);
    lures
      ..clear()
      ..addAll({
        for (final e
            in (j['lures'] as Map<String, dynamic>? ?? const {}).entries)
          int.parse(e.key): (
            teamId: (e.value as List)[0] as int,
            wage: e.value[1] as int,
          ),
      });
    if (!all.any((s) => s.role == StaffRole.mechanic)) _addCareCrew();
  }
}
