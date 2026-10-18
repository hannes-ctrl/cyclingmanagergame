import 'dart:math';

import 'i18n.dart';

import 'model.dart';
import 'rng.dart';
import 'scheme.dart';
import 'stage_sim.dart';
import 'tactics.dart';
import 'trace.dart';
import 'tuning.dart';
import 'material.dart';
import 'weather.dart';

/// A rider with his overall time.
class TimeEntry {
  TimeEntry(this.rider, this.timeS);
  final SimRider rider;
  final double timeS;
}

/// A rider with his points in a classification.
class PointsEntry {
  PointsEntry(this.rider, this.points);
  final SimRider rider;
  final int points;
}

/// A team with its overall time.
class TeamEntry {
  TeamEntry(this.teamId, this.team, this.timeS);
  final int teamId;
  final String team;
  final double timeS;
}

/// All classifications after a stage, best first in each.
class Standings {
  Standings(this.general, this.points, this.mountains, this.youth, this.teams);

  /// General classification by time, bonus seconds deducted.
  final List<TimeEntry> general;
  final List<PointsEntry> points;
  final List<PointsEntry> mountains;

  /// General classification of the riders aged 25 or younger.
  final List<TimeEntry> youth;

  /// Sum of the three best riders per stage.
  final List<TeamEntry> teams;
}

/// Result of a whole stage race.
class StageRaceResult {
  StageRaceResult(this.stages, this.standings);
  final List<StageResult> stages;

  /// State of the classifications after each stage.
  final List<Standings> standings;

  /// Final general classification.
  List<TimeEntry> get gc => standings.last.general;
}

/// A stage race in progress: every stage is simulated on its own, while the
/// classifications and the riders' fatigue carry over.
///
/// Part of the fatigue stays between stages: a hard day costs more than an
/// easy one, and a rider with good recovery wins more of it back overnight
/// and on rest days. Form drifts slightly from day to day around the
/// previous day's value; a crash costs form for some days. Riders who crash
/// out, fall ill or finish outside the time limit leave the race.
class StageRaceRun {
  /// Starts a race.
  ///
  /// @param riders Start list.
  /// @param seed Seed for all randomness of the race.
  /// @param year Race year, decides who counts as a young rider.
  /// @param tuning Tuning values; defaults to the standard set.
  /// @param baseForm Form each rider brings into the race, by rider id.
  /// @param scheme Points, mountain points and bonus seconds of the race.
  /// @param oneDay Whether this is a one-day race.
  /// @param month Month of the race, for the weather.
  /// @param country Country of the race, for the weather.
  StageRaceRun(List<SimRider> riders,
      {required int seed,
      this.year = 2026,
      this.tuning,
      this.baseForm = const {},
      this.scheme = PointsScheme.standard,
      this.oneDay = false,
      this.month = 7,
      this.country = ''})
      : riders = [...riders],
        _rng = Rng(seed) {
    _nextSeed = _rng.nextInt(1 << 31);
    for (final r in riders) {
      total[r.id] = 0;
      points[r.id] = 0;
      mountain[r.id] = 0;
      debt[r.id] = 0;
      form[r.id] = 1;
      // Young riders: 25 or younger in the year of the race.
      if (r.born >= (year - 25) * 10000 + 101) young.add(r.id);
    }
  }

  /// Riders still in the race.
  final List<SimRider> riders;

  /// Takes a rider out of the race (crash, illness). He is missing from the
  /// next stage on and from all classifications.
  ///
  /// @param riderId Id of the rider.
  void withdraw(int riderId) {
    riders.removeWhere((r) => r.id == riderId);
    total.remove(riderId);
    points.remove(riderId);
    mountain.remove(riderId);
    debt.remove(riderId);
    form.remove(riderId);
    young.remove(riderId);
  }

  /// Form a rider brings into the race (factor around 1.0), by rider id.
  /// The daily variation during the race comes on top.
  final Map<int, double> baseForm;
  final int year;
  final SimTuning? tuning;
  final Rng _rng;

  /// Points, mountain points and bonus seconds of the race.
  final PointsScheme scheme;

  /// Whether this is a one-day race (decides the finish type).
  final bool oneDay;

  /// Month and country of the race, for the weather.
  final int month;
  final String country;

  /// Chance per rider and stage that he falls ill and gives up.
  static const illnessPerStage = 0.001;

  final total = <int, double>{};
  final points = <int, int>{};
  final mountain = <int, int>{};
  final teamTime = <int, double>{};

  /// Teams that have had fewer than three riders at the line of a stage:
  /// they are out of the team classification for good.
  final _teamsOut = <int>{};
  final debt = <int, double>{};
  final form = <int, double>{};
  final young = <int>{};
  final results = <StageResult>[];
  final standings = <Standings>[];

  /// Weather of the next stage. It follows from the seed of the stage, so
  /// it is known before the stage is ridden.
  Weather get nextWeather =>
      Weather.draw(Random(_nextSeed * 31 + 7), month, country);

  /// Seed of the next stage.
  int get nextSeed => _nextSeed;

  /// Seed of the first stage of a race that has not been started yet.
  ///
  /// @param seed Seed the race will be started with.
  /// @returns The seed of its first stage.
  static int firstSeed(int seed) => Rng(seed).nextInt(1 << 31);

  /// Weather of the first stage of a race that has not been started yet.
  ///
  /// @param seed Seed the race will be started with.
  /// @param month Month of the race.
  /// @param country Country of the race.
  /// @returns The weather its first stage will have.
  static Weather firstWeather(int seed, int month, String country) =>
      Weather.draw(Random(Rng(seed).nextInt(1 << 31) * 31 + 7), month, country);

  /// Everything simulated so far.
  StageRaceResult get result => StageRaceResult(results, standings);

  /// @returns Each rider's gap to the leader of the general classification.
  Map<int, double> _gapsBefore() {
    final best = total.values.reduce(min);
    return {for (final e in total.entries) e.key: e.value - best};
  }

  /// Gaps in the general classification as they stand before the next
  /// stage; empty before the first.
  Map<int, double> get gcGaps => results.isEmpty ? const {} : _gapsBefore();

  // Seed of the next stage, drawn in advance so that a preview sees the same
  // run as the stage that counts later.
  late int _nextSeed;
  final _before = <_Snapshot>[];

  /// Captures everything that decides the next stage.
  ///
  /// @param plans Tactics of the teams that do not follow the automatic plan.
  /// @param directors Quality of the sports director per team.
  /// @param radio Radio answers of the player's team.
  /// @param kits Material and staff per team.
  /// @param orders The player's orders to his riders, as given live.
  /// @returns The snapshot.
  _Snapshot _snapshot(Map<int, TeamPlan> plans, Map<int, double> directors,
          Map<RadioKind, int> radio, Map<int, TeamKit> kits,
          [List<TimedOrder> orders = const []]) =>
      _Snapshot(
        [...riders],
        _nextSeed,
        results.isEmpty ? const {} : _gapsBefore(),
        {
          for (final r in riders)
            r.id: RiderCondition(
                form: form[r.id]! * (baseForm[r.id] ?? 1),
                energy: 1 - debt[r.id]!),
        },
        plans,
        directors,
        radio,
        kits,
        _mountainLeaders(),
        orders,
      );

  /// Riders in the running for the mountains jersey: the leader of the
  /// classification and those within half of his points.
  Set<int> _mountainLeaders() {
    if (mountain.isEmpty) return const {};
    final best = mountain.values.reduce(max);
    if (best <= 0) return const {};
    return {
      for (final e in mountain.entries)
        if (e.value > 0 && e.value >= best / 2) e.key,
    };
  }

  /// Simulates a stage from a snapshot.
  ///
  /// @param route The stage.
  /// @param s State before the stage.
  /// @param plans Overrides the plans stored in the snapshot.
  /// @param radioTeam Team that is asked over the radio.
  /// @param radio Overrides the radio answers stored in the snapshot.
  /// @param askRadio Whether to pause at the first unanswered question.
  /// @param track Whether to record where every rider was.
  /// @returns The stage result.
  StageResult _simulate(SimRoute route, _Snapshot s,
          {Map<int, TeamPlan>? plans,
          int? radioTeam,
          Map<RadioKind, int>? radio,
          bool askRadio = false,
          bool track = false}) =>
      simulateStage(
        route,
        s.riders,
        seed: s.seed,
        tuning: tuning,
        plans: plans ?? s.plans,
        directorSkills: s.directors,
        gcGaps: s.gcGaps,
        conditions: s.conditions,
        radioTeam: radioTeam,
        radio: radio ?? s.radio,
        askRadio: askRadio,
        month: month,
        country: country,
        illness: oneDay ? 0 : illnessPerStage,
        kits: s.kits,
        mountainLeaders: s.mountainLeaders,
        track: track,
        orders: s.orders,
      );

  /// Packs a stage into a job.
  StageJob _job(SimRoute route, _Snapshot s,
          {int? radioTeam, bool askRadio = false, bool track = false}) =>
      StageJob._(route, s, tuning, month, country, oneDay ? 0 : illnessPerStage,
          radioTeam, askRadio, I18n.lang, track);

  /// The next stage as a job that does not count: for a preview that is
  /// simulated on another isolate.
  ///
  /// @param route The stage.
  /// @param plans Tactics of the teams that do not follow the automatic plan.
  /// @param directorSkills Quality of the sports director per team.
  /// @param radioTeam Team that is asked over the radio.
  /// @param radio Answers given so far.
  /// @param askRadio Whether to pause at the first unanswered question.
  /// @param kits Material and staff per team.
  /// @param track Whether to record where every rider was, for the 3D view.
  /// @param orders Orders to riders of the radio team, as given live.
  /// @returns The job; its result is not to be passed to [finish].
  StageJob previewJob(SimRoute route,
          {Map<int, TeamPlan> plans = const {},
          Map<int, double> directorSkills = const {},
          int? radioTeam,
          Map<RadioKind, int> radio = const {},
          bool askRadio = false,
          Map<int, TeamKit> kits = const {},
          bool track = false,
          List<TimedOrder> orders = const []}) =>
      _job(route, _snapshot(plans, directorSkills, radio, kits, orders),
          radioTeam: radioTeam, askRadio: askRadio, track: track);

  /// Starts the next stage: fixes everything that decides it and returns it
  /// as a job. The job can be run here or on another isolate; its result
  /// goes to [finish].
  ///
  /// @param route The stage.
  /// @param plans Tactics of the teams that do not follow the automatic plan.
  /// @param directorSkills Quality of the sports director per team.
  /// @param radioTeam Team whose radio answers apply.
  /// @param radio Radio answers of that team.
  /// @param kits Material and staff per team.
  /// @param track Whether to record where every rider was, for the 3D view.
  /// @param orders Orders to riders of the radio team, as given live.
  /// @returns The job.
  StageJob begin(SimRoute route,
      {Map<int, TeamPlan> plans = const {},
      Map<int, double> directorSkills = const {},
      int? radioTeam,
      Map<RadioKind, int> radio = const {},
      Map<int, TeamKit> kits = const {},
      bool track = false,
      List<TimedOrder> orders = const []}) {
    final snapshot = _snapshot(plans, directorSkills, radio, kits, orders);
    _before.add(snapshot);
    return _job(route, snapshot, radioTeam: radioTeam, track: track);
  }

  /// Takes the result of a job started with [begin] into the race: time
  /// limit, classifications, fatigue.
  ///
  /// @param job The job.
  /// @param result What [StageJob.run] returned, here or on another isolate.
  /// @returns The result with the riders of this race in it.
  StageResult finish(StageJob job, StageResult result) {
    final linked = _relink(result, job._s.riders);
    _timeCut(job.route, linked);
    results.add(linked);
    _classify(job.route, linked);
    _recover(job.route, linked, job._s.kits);
    _nextSeed = _rng.nextInt(1 << 31);
    return linked;
  }

  /// A result that crossed an isolate boundary holds copies of the riders.
  /// The race works with its own rider objects, so they are put back.
  static StageResult _relink(StageResult r, List<SimRider> riders) {
    if (r.placings.isEmpty ||
        riders.any((x) => identical(x, r.placings.first.rider))) {
      return r;
    }
    final own = {for (final x in riders) x.id: x};
    return StageResult(
      [for (final p in r.placings) Placing(own[p.rider.id]!, p.timeS, p.group)],
      r.events,
      r.breakSurvived,
      [
        for (final a in r.awards)
          PointAward(a.point, [for (final x in a.order) own[x.id]!]),
      ],
    )
      ..openCall = r.openCall
      ..timeline = r.timeline
      ..traces = r.traces
      ..power = r.power
      ..injuries = r.injuries
      ..weather = r.weather
      ..track = r.track
      ..abandons = [
        for (final a in r.abandons)
          Abandon(own[a.rider.id]!, a.km, a.reason, a.days),
      ];
  }

  /// Simulates the next stage as a trial that does not count.
  ///
  /// @param route The stage.
  /// @param plans Tactics of the teams that do not follow the automatic plan.
  /// @param directorSkills Quality of the sports director per team.
  /// @param radioTeam Team that is asked over the radio.
  /// @param radio Answers given so far.
  /// @param askRadio Whether to pause at the first question [radio] has no
  ///   answer for.
  /// @param kits Material and staff per team.
  /// @returns The result, or a paused result with an open question.
  StageResult preview(SimRoute route,
          {Map<int, TeamPlan> plans = const {},
          Map<int, double> directorSkills = const {},
          int? radioTeam,
          Map<RadioKind, int> radio = const {},
          bool askRadio = false,
          Map<int, TeamKit> kits = const {}}) =>
      _simulate(route, _snapshot(plans, directorSkills, radio, kits),
          radioTeam: radioTeam, askRadio: askRadio);

  /// Simulates a stage that has already been ridden once more, with the same
  /// randomness but different instructions for one team. Leaves the race
  /// untouched.
  ///
  /// @param index Zero-based index of the stage.
  /// @param route The stage.
  /// @param radioTeam Team whose instructions change.
  /// @param plan New tactics; null keeps the original.
  /// @param radio New radio answers; null keeps the original.
  /// @param askRadio Whether to pause at the first unanswered question.
  /// @returns The alternative result.
  StageResult replay(int index, SimRoute route,
      {required int radioTeam,
      TeamPlan? plan,
      Map<RadioKind, int>? radio,
      bool askRadio = false}) {
    final s = _before[index];
    return _simulate(route, s,
        plans: plan == null ? null : {...s.plans, radioTeam: plan},
        radioTeam: radioTeam,
        radio: radio,
        askRadio: askRadio);
  }

  /// @param index Zero-based index of a ridden stage.
  /// @param teamId Team id.
  /// @returns The plan the team was given for that stage, or null if it
  ///   followed the automatic plan.
  TeamPlan? planUsed(int index, int teamId) => _before[index].plans[teamId];

  /// The plan the sports director drew up for a team on a ridden stage, with
  /// everything he knew then: gaps, styles, the crosswind of the day and the
  /// riders in the running for the mountains jersey.
  ///
  /// @param index Zero-based index of a ridden stage.
  /// @param route The stage.
  /// @param teamId Team id.
  /// @returns The automatic plan, or null if the team did not start.
  TeamPlan? autoPlanUsed(int index, SimRoute route, int teamId) {
    final s = _before[index];
    final weather = Weather.draw(Random(s.seed * 31 + 7), month, country);
    final wind = windAlong(route, weather, Random(s.seed * 17 + 3));
    return autoPlans(route, s.riders,
        gcGaps: s.gcGaps,
        styles: {for (final e in s.kits.entries) e.key: e.value.style},
        crosswindKm: crosswindKm(route, wind),
        mountainLeaders: s.mountainLeaders)[teamId];
  }

  /// @param index Zero-based index of a ridden stage.
  /// @returns The radio answers used on that stage.
  Map<RadioKind, int> radioUsed(int index) => _before[index].radio;

  /// @param index Zero-based index of a ridden stage.
  /// @returns The gaps in the general classification before that stage.
  Map<int, double> gcGapsBefore(int index) => _before[index].gcGaps;

  /// @param index Zero-based index of a ridden stage.
  /// @returns The riders who started that stage.
  List<SimRider> ridersBefore(int index) => _before[index].riders;

  /// Simulates the next stage and updates all classifications.
  ///
  /// @param route The stage.
  /// @param plans Tactics of the teams that do not follow the automatic plan.
  /// @param directorSkills Quality of the sports director per team.
  /// @param radioTeam Team whose radio answers apply.
  /// @param radio Radio answers of that team.
  /// @param kits Material and staff per team.
  /// @returns The stage result.
  StageResult nextStage(SimRoute route,
      {Map<int, TeamPlan> plans = const {},
      Map<int, double> directorSkills = const {},
      int? radioTeam,
      Map<RadioKind, int> radio = const {},
      Map<int, TeamKit> kits = const {}}) {
    final job = begin(route,
        plans: plans,
        directorSkills: directorSkills,
        radioTeam: radioTeam,
        radio: radio,
        kits: kits);
    return finish(job, job.run());
  }

  /// Adds a stage result to all classifications. Uses no randomness, so the
  /// classifications of a saved race can be rebuilt from its stage results.
  ///
  /// @param route The stage.
  /// @param result Its result.
  void _classify(SimRoute route, StageResult result) {
    final finish = PointsScheme.finishType(route, oneDay: oneDay);
    final bonus = scheme.secondsFor(finish);
    final perTeam = <int, List<double>>{};
    for (var i = 0; i < result.placings.length; i++) {
      final p = result.placings[i];
      final id = p.rider.id;
      // Times count in whole seconds, minus the bonus at the finish.
      total[id] = total[id]! +
          p.timeS.roundToDouble() -
          (i < bonus.length ? bonus[i] : 0);
      perTeam
          .putIfAbsent(p.rider.teamId, () => [])
          .add(p.timeS.roundToDouble());
    }
    // The team classification counts the three best of each team; a team
    // with fewer than three at the line, or none, drops out of it.
    for (final id in [...teamTime.keys]) {
      if ((perTeam[id]?.length ?? 0) < 3) _teamsOut.add(id);
    }
    for (final e in perTeam.entries) {
      if (e.value.length < 3) _teamsOut.add(e.key);
      if (_teamsOut.contains(e.key)) {
        teamTime.remove(e.key);
        continue;
      }
      final best = e.value.take(3).reduce((a, b) => a + b);
      teamTime[e.key] = (teamTime[e.key] ?? 0) + best;
    }

    void award(Map<int, int> target, List<int> scale, List<int> riderIds) {
      for (var i = 0; i < scale.length && i < riderIds.length; i++) {
        final id = riderIds[i];
        // A rider who abandoned later no longer has a tally.
        if (target.containsKey(id)) target[id] = target[id]! + scale[i];
      }
    }

    final order = [for (final p in result.placings) p.rider.id];
    award(points, scheme.pointsFor(finish), order);
    // A summit finish awards its mountain points in finishing order.
    final summit = finish.startsWith('finish_mountain_') &&
        finish != 'finish_mountainstage';
    if (summit) {
      final category = finish.substring('finish_mountain_'.length);
      var scale = scheme.mountainFor(finish);
      if (scale.isEmpty) scale = scheme.mountainFor('mountain_$category');
      award(mountain, scale, order);
    }
    for (final a in result.awards) {
      final ids = [for (final r in a.order) r.id];
      if (a.point.category > 0) {
        // Already awarded in finishing order above.
        if (summit && a.point.km >= route.raceKm - 0.6) continue;
        award(
            mountain,
            scheme.mountainFor(
                'mountain_${PointsScheme.categoryName(a.point.category)}'),
            ids);
      } else {
        award(points, scheme.pointsFor('sprint_bonif'), ids);
        final seconds = scheme.secondsFor('sprint_bonif');
        for (var i = 0; i < seconds.length && i < ids.length; i++) {
          if (total.containsKey(ids[i])) {
            total[ids[i]] = total[ids[i]]! - seconds[i];
          }
        }
      }
    }

    // Riders who crashed out, fell ill or missed the time limit leave the race.
    for (final a in result.abandons) {
      if (total.containsKey(a.rider.id)) withdraw(a.rider.id);
    }
    final general = [for (final r in riders) TimeEntry(r, total[r.id]!)]
      ..sort((a, b) => a.timeS.compareTo(b.timeS));
    List<PointsEntry> ranking(Map<int, int> table) => [
          for (final r in riders)
            if (table[r.id]! > 0) PointsEntry(r, table[r.id]!),
        ]..sort((a, b) => b.points.compareTo(a.points));
    final teamNames = {for (final r in riders) r.teamId: r.team};
    standings.add(Standings(
      general,
      ranking(points),
      ranking(mountain),
      [
        for (final e in general)
          if (young.contains(e.rider.id)) e,
      ],
      [
        for (final e in teamTime.entries)
          if (teamNames[e.key] != null)
            TeamEntry(e.key, teamNames[e.key]!, e.value),
      ]..sort((a, b) => a.timeS.compareTo(b.timeS)),
    ));
  }

  /// Takes the riders out who finished outside the time limit. When more
  /// than a fifth of the field is outside, the jury lets them all stay.
  /// One-day races have no time limit.
  ///
  /// @param route The stage.
  /// @param result Its result; the riders are added to its abandons.
  void _timeCut(SimRoute route, StageResult result) {
    if (oneDay || result.placings.isEmpty) return;
    final winner = result.placings.first.timeS;
    final share = timeLimitShare(route, route.raceKm / (winner / 3600));
    if (share <= 0) return;
    final limit = (winner * (1 + share)).roundToDouble();
    final outside = [
      for (final p in result.placings)
        if (p.timeS.roundToDouble() > limit) p.rider,
    ];
    if (outside.isEmpty) return;
    if (outside.length > result.placings.length * 0.2) {
      result.events.add(RaceEvent(
          route.raceKm,
          EventType.timeCut,
          tr('{0} riders finish outside the time limit and are reprieved',
              [outside.length])));
      return;
    }
    result.abandons = [
      ...result.abandons,
      for (final r in outside) Abandon(r, route.raceKm, AbandonReason.timeCut),
    ];
    final names = outside.take(6).map((r) => r.name).join(', ');
    result.events.add(RaceEvent(
        route.raceKm,
        EventType.timeCut,
        outside.length > 6
            ? tr('Outside the time limit: {0} and {1} more',
                [names, outside.length - 6])
            : tr('Outside the time limit: {0}', [names])));
  }

  /// Share of the fatigue a rider wins back overnight.
  ///
  /// @param r The rider.
  /// @returns 0.12 to 0.5; about 0.3 at a recovery attribute of 70.
  static double _recoveryRate(SimRider r) =>
      (0.3 * (1 + 0.04 * (r.attributes.recovery - 70))).clamp(0.12, 0.5);

  /// Carries fatigue and form over to the next day.
  ///
  /// The fatigue grows with what a rider spent on the day and shrinks by a
  /// share that depends on his recovery attribute, so it levels off at a
  /// value of its own for every rider instead of a common ceiling.
  ///
  /// @param route The stage.
  /// @param result Its result.
  /// @param kits Material and staff per team: good soigneurs and
  ///   physiotherapists win back more overnight.
  void _recover(SimRoute route, StageResult result,
      [Map<int, TeamKit> kits = const {}]) {
    final road = route.kind == StageKind.road;
    final hours = result.winnerTimeS / 3600;
    for (final p in result.placings) {
      final id = p.rider.id;
      if (!debt.containsKey(id)) continue;
      final trace = result.traces[id];
      final spent = trace != null
          ? max(0.0, 1 - debt[id]! - trace.energy)
          : 0.3 * hours * (road ? 1 : 0.8);
      final hurt = result.injuries[id];
      final care = kits[p.rider.teamId]?.recovery ?? 1;
      debt[id] = (debt[id]! * (1 - _recoveryRate(p.rider) * care) +
              0.1 * spent +
              0.5 * (hurt?.energyLoss ?? 0))
          .clamp(0.0, 0.5);
      form[id] = (1 +
              0.6 * (form[id]! - 1) +
              0.004 * _gauss(_rng) -
              (hurt?.formLoss ?? 0))
          .clamp(0.93, 1.03);
    }
  }

  /// A rest day: the riders recover more than overnight, and some of them
  /// do not find their legs on the day after.
  ///
  /// @param kits Material and staff per team.
  void restDay([Map<int, TeamKit> kits = const {}]) {
    for (final r in riders) {
      final id = r.id;
      final care = kits[r.teamId]?.recovery ?? 1;
      debt[id] =
          (debt[id]! * (1 - 1.6 * _recoveryRate(r) * care)).clamp(0.0, 0.5);
      form[id] =
          (1 + 0.6 * (form[id]! - 1) + 0.008 * _gauss(_rng)).clamp(0.93, 1.03);
    }
  }

  // --- Saving -----------------------------------------------------------------
  // Stored are the inputs and results of every stage plus the state that
  // carries over (fatigue, form, random state). The classifications are
  // rebuilt from the results on loading.

  /// Serialises the race.
  ///
  /// @param ref Maps a rider object to a number the caller can resolve again
  ///   on loading (riders are shared between races and change over time).
  /// @returns A JSON-encodable map.
  Map<String, dynamic> toJson(int Function(SimRider) ref) => {
        'rng': _rng.state,
        'next': _nextSeed,
        'year': year,
        'oneDay': oneDay,
        'month': month,
        'country': country,
        'riders': [for (final r in riders) ref(r)],
        'baseForm': {for (final e in baseForm.entries) '${e.key}': e.value},
        'debt': {for (final e in debt.entries) '${e.key}': e.value},
        'form': {for (final e in form.entries) '${e.key}': e.value},
        'stages': [
          for (var i = 0; i < results.length; i++)
            _stageJson(_before[i], results[i], ref),
        ],
      };

  static Map<String, dynamic> _stageJson(
      _Snapshot s, StageResult r, int Function(SimRider) ref) {
    final at = Map<SimRider, int>.identity();
    for (var i = 0; i < s.riders.length; i++) {
      at[s.riders[i]] = i;
    }
    return {
      'riders': [for (final x in s.riders) ref(x)],
      'seed': s.seed,
      'cond': [
        for (final x in s.riders)
          [s.conditions[x.id]!.form, s.conditions[x.id]!.energy],
      ],
      'plans': {for (final e in s.plans.entries) '${e.key}': e.value.toJson()},
      'dir': {for (final e in s.directors.entries) '${e.key}': e.value},
      'radio': {for (final e in s.radio.entries) e.key.name: e.value},
      if (s.kits.isNotEmpty)
        'kit': {for (final e in s.kits.entries) '${e.key}': e.value.toJson()},
      if (s.mountainLeaders.isNotEmpty) 'kom': s.mountainLeaders.toList(),
      'place': [
        for (final p in r.placings) [at[p.rider], p.timeS, p.group],
      ],
      'events': [
        for (final e in r.events)
          [e.km, e.type.index, e.text, if (e.riders.isNotEmpty) e.riders],
      ],
      'awards': [
        for (final a in r.awards)
          [
            a.point.km,
            a.point.name,
            a.point.category,
            [for (final x in a.order) at[x]],
          ],
      ],
      'break': r.breakSurvived,
      'line': [for (final x in r.timeline) x.toJson()],
      'out': [
        for (final a in r.abandons) [at[a.rider], a.km, a.reason.index, a.days],
      ],
      'hurt': {
        for (final e in r.injuries.entries)
          '${e.key}': [e.value.formLoss, e.value.energyLoss],
      },
      if (r.weather != null) 'wx': r.weather!.toJson(),
      'trace': {
        for (final e in r.traces.entries) '${e.key}': e.value.toJson(),
      },
      if (r.power.isNotEmpty)
        'pow': {for (final e in r.power.entries) '${e.key}': e.value.toJson()},
    };
  }

  /// Restores a race written by [toJson].
  ///
  /// @param j The stored map.
  /// @param rider Resolves a number written by the `ref` callback.
  /// @param routeOf Returns the route of a stage by its zero-based index.
  /// @param tuning Tuning values for further stages.
  /// @param scheme Points scheme of the race.
  /// @returns The race in the state it was saved in.
  static StageRaceRun fromJson(
    Map<String, dynamic> j, {
    required SimRider Function(int) rider,
    required SimRoute Function(int index) routeOf,
    SimTuning? tuning,
    PointsScheme scheme = PointsScheme.standard,
  }) {
    final stages = (j['stages'] as List).cast<Map<String, dynamic>>();
    List<SimRider> list(dynamic ids) =>
        [for (final i in ids as List) rider(i as int)];
    final current = list(j['riders']);
    final run = StageRaceRun(
      stages.isEmpty ? current : list(stages.first['riders']),
      seed: 0,
      year: j['year'] as int,
      tuning: tuning,
      scheme: scheme,
      oneDay: j['oneDay'] as bool,
      month: j['month'] as int? ?? 7,
      country: j['country'] as String? ?? '',
      baseForm: {
        for (final e in (j['baseForm'] as Map<String, dynamic>).entries)
          int.parse(e.key): (e.value as num).toDouble(),
      },
    );
    // Removes riders who had abandoned by the time of [present].
    void sync(List<SimRider> present) {
      final ids = {for (final r in present) r.id};
      for (final r in [...run.riders]) {
        if (!ids.contains(r.id)) run.withdraw(r.id);
      }
      // Same objects and order as back then.
      run.riders
        ..clear()
        ..addAll(present);
    }

    for (var i = 0; i < stages.length; i++) {
      final s = stages[i];
      final riders = list(s['riders']);
      sync(riders);
      final cond = s['cond'] as List;
      run._before.add(_Snapshot(
        riders,
        s['seed'] as int,
        run.results.isEmpty ? const {} : run._gapsBefore(),
        {
          for (var k = 0; k < riders.length; k++)
            riders[k].id: RiderCondition(
                form: ((cond[k] as List)[0] as num).toDouble(),
                energy: ((cond[k] as List)[1] as num).toDouble()),
        },
        {
          for (final e in (s['plans'] as Map<String, dynamic>).entries)
            int.parse(e.key):
                TeamPlan.fromJson(e.value as Map<String, dynamic>),
        },
        {
          for (final e in (s['dir'] as Map<String, dynamic>).entries)
            int.parse(e.key): (e.value as num).toDouble(),
        },
        {
          for (final e in (s['radio'] as Map<String, dynamic>).entries)
            RadioKind.values.byName(e.key): e.value as int,
        },
        {
          for (final e
              in (s['kit'] as Map<String, dynamic>? ?? const {}).entries)
            int.parse(e.key): TeamKit.fromJson(e.value as List),
        },
        {...(s['kom'] as List? ?? const []).cast<int>()},
      ));
      final result = StageResult(
        [
          for (final p in s['place'] as List)
            Placing(riders[(p as List)[0] as int], (p[1] as num).toDouble(),
                p[2] as int),
        ],
        [
          for (final e in s['events'] as List)
            RaceEvent(
                ((e as List)[0] as num).toDouble(),
                EventType.values[e[1] as int],
                e[2] as String,
                e.length > 3 ? (e[3] as List).cast<int>() : const []),
        ],
        s['break'] as bool,
        [
          for (final a in s['awards'] as List)
            PointAward(
              RoutePoint(((a as List)[0] as num).toDouble(), a[1] as String,
                  a[2] as int),
              [for (final x in a[3] as List) riders[x as int]],
            ),
        ],
      );
      result
        ..timeline = [
          for (final x in s['line'] as List? ?? const [])
            RaceSample.fromJson(x as List),
        ]
        ..traces = {
          for (final e
              in (s['trace'] as Map<String, dynamic>? ?? const {}).entries)
            int.parse(e.key): RiderTrace.fromJson(e.value as List),
        }
        ..power = {
          for (final e
              in (s['pow'] as Map<String, dynamic>? ?? const {}).entries)
            int.parse(e.key): PowerStats.fromJson(e.value as List),
        }
        ..abandons = [
          for (final a in s['out'] as List? ?? const [])
            Abandon(riders[(a as List)[0] as int], (a[1] as num).toDouble(),
                AbandonReason.values[a[2] as int], a[3] as int),
        ]
        ..injuries = {
          for (final e
              in (s['hurt'] as Map<String, dynamic>? ?? const {}).entries)
            int.parse(e.key): Injury(((e.value as List)[0] as num).toDouble(),
                (e.value[1] as num).toDouble()),
        }
        ..weather =
            s['wx'] == null ? null : Weather.fromJson(s['wx'] as List<dynamic>);
      run.results.add(result);
      run._classify(routeOf(i), result);
    }
    sync(current);
    Map<int, double> doubles(String key) => {
          for (final e in (j[key] as Map<String, dynamic>).entries)
            int.parse(e.key): (e.value as num).toDouble(),
        };
    run.debt
      ..clear()
      ..addAll(doubles('debt'));
    run.form
      ..clear()
      ..addAll(doubles('form'));
    run._rng.state = j['rng'] as int;
    run._nextSeed = j['next'] as int;
    return run;
  }
}

/// One stage with everything that decides it, as plain data. It can be
/// handed to another isolate and simulated there.
class StageJob {
  StageJob._(this.route, this._s, this._tuning, this._month, this._country,
      this._illness, this._radioTeam, this._askRadio, this._lang,
      [this._track = false]);

  /// The stage.
  final SimRoute route;
  final _Snapshot _s;
  final SimTuning? _tuning;
  final int _month;
  final String _country;
  final double _illness;
  final int? _radioTeam;
  final bool _askRadio;

  /// Language of the event texts; an isolate does not know the setting of
  /// the one that started it.
  final Lang _lang;

  /// Whether to record where every rider was, for the 3D view.
  final bool _track;

  /// Simulates the stage. The same job always gives the same result.
  ///
  /// @returns The result, or a paused result with an open radio question.
  StageResult run() {
    I18n.lang = _lang;
    return simulateStage(
      route,
      _s.riders,
      seed: _s.seed,
      tuning: _tuning,
      plans: _s.plans,
      directorSkills: _s.directors,
      gcGaps: _s.gcGaps,
      conditions: _s.conditions,
      radioTeam: _radioTeam,
      radio: _s.radio,
      askRadio: _askRadio,
      month: _month,
      country: _country,
      illness: _illness,
      kits: _s.kits,
      mountainLeaders: _s.mountainLeaders,
      track: _track,
      orders: _s.orders,
    );
  }

  /// The stage to be ridden while it is watched, with the radio answers
  /// and orders the player gives on the way; see [LiveStage]. Ridden with
  /// them, [run] gives the same stage.
  ///
  /// @returns The stage at its start.
  LiveStage live() {
    I18n.lang = _lang;
    return liveStage(
      route,
      _s.riders,
      seed: _s.seed,
      tuning: _tuning,
      plans: _s.plans,
      directorSkills: _s.directors,
      gcGaps: _s.gcGaps,
      conditions: _s.conditions,
      radioTeam: _radioTeam,
      radio: _s.radio,
      askRadio: _askRadio,
      month: _month,
      country: _country,
      illness: _illness,
      kits: _s.kits,
      mountainLeaders: _s.mountainLeaders,
    );
  }
}

/// State before a stage: everything that decides its result.
class _Snapshot {
  _Snapshot(this.riders, this.seed, this.gcGaps, this.conditions, this.plans,
      this.directors, this.radio,
      [this.kits = const {},
      this.mountainLeaders = const {},
      this.orders = const []]);
  final List<SimRider> riders;
  final int seed;
  final Map<int, double> gcGaps;
  final Map<int, RiderCondition> conditions;
  final Map<int, TeamPlan> plans;
  final Map<int, double> directors;
  final Map<RadioKind, int> radio;
  final Map<int, TeamKit> kits;
  final Set<int> mountainLeaders;

  /// The player's orders to his riders, as given live.
  final List<TimedOrder> orders;
}

/// Simulates a whole stage race in one go.
///
/// @param routes The stages in order.
/// @param riders Start list.
/// @param seed Seed for all randomness.
/// @param year Race year, decides the youth classification.
/// @param plansFor Returns, per stage, the tactics of the teams that should
///   not follow the automatic plan.
/// @param tuning Tuning values.
/// @param month Month of the race, for the weather.
/// @param country Country of the race, for the weather.
/// @returns Stage results and classifications.
StageRaceResult simulateStageRace(
  List<SimRoute> routes,
  List<SimRider> riders, {
  required int seed,
  int year = 2026,
  Map<int, TeamPlan> Function(int stageIndex)? plansFor,
  SimTuning? tuning,
  int month = 7,
  String country = '',
}) {
  final run = StageRaceRun(riders,
      seed: seed,
      year: year,
      tuning: tuning,
      oneDay: routes.length == 1,
      month: month,
      country: country);
  for (var si = 0; si < routes.length; si++) {
    run.nextStage(routes[si], plans: plansFor?.call(si) ?? const {});
  }
  return run.result;
}

/// @param r Random source.
/// @returns A standard normal sample.
double _gauss(Random r) {
  final u = max(r.nextDouble(), 1e-12);
  return sqrt(-2 * log(u)) * cos(2 * pi * r.nextDouble());
}
