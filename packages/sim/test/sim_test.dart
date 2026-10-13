import 'dart:math';

import 'package:sim/sim.dart';
import 'package:test/test.dart';

import 'synthetic.dart';

/// Behaviour of the simulation that must hold regardless of fine tuning.
/// Runs on a synthetic field, so no world database is needed.
void main() {
  final field = syntheticField();

  group('route', () {
    test('is cut into 200 m segments with their altitude', () {
      final r = mountainStage();
      expect(r.segments.first.lengthM, 200);
      expect(r.segments.last.altitudeM, greaterThan(2000));
      expect(r.segments.first.altitudeM, closeTo(1100, 5));
    });

    test('gets back the steepest ramp of a climb and keeps its height', () {
      // 3 km at an even 6 %, of which the stage file says it reaches 15 %.
      final profile = [
        for (var i = 0; i <= 100; i++) (i * 0.1, 100.0 + max(0, i - 50) * 6.0),
      ];
      List<double> grades(List<ClimbSpan> climbs) => [
            for (final s in buildRoute(
                    name: 'x',
                    kind: StageKind.road,
                    raceKm: 10,
                    profile: profile,
                    climbs: climbs)
                .segments)
              s.grade,
          ];
      final plain = grades(const []);
      final ramped = grades(const [ClimbSpan(5, 8, 0.15)]);
      expect(plain.reduce(max), closeTo(0.06, 0.001));
      expect(ramped.reduce(max), closeTo(0.15, 0.001));
      double gain(List<double> g) => g.fold(0.0, (s, x) => s + x * 200);
      expect(gain(ramped), closeTo(gain(plain), 0.5));
    });
  });

  group('physics', () {
    test('thin air: less drag and less power', () {
      expect(airDensity(2000), lessThan(airDensity(0) * 0.8));
      expect(altitudePower(500), 1.0);
      expect(altitudePower(2000), closeTo(0.95, 0.01));
      expect(altitudePower(2500), lessThan(0.93));
    });

    test('a light and a heavy rider with the same attribute climb alike', () {
      const light = SimRider(
          id: 1,
          name: 'L',
          teamId: 1,
          team: 'T',
          attributes: _flat70,
          weightKg: 58,
          heightCm: 170);
      const heavy = SimRider(
          id: 2,
          name: 'H',
          teamId: 1,
          team: 'T',
          attributes: _flat70,
          weightKg: 82,
          heightCm: 190);
      final t = SimTuning.standard;
      double speed(SimRider r, double grade) => speedFor(
          thresholdPower(70, t) * bodyScale(r, grade),
          grade,
          soloCda * cdaScale(r),
          0.004,
          mass: r.massKg + bikeMassKg);
      expect(speed(light, 0.08) / speed(heavy, 0.08), closeTo(1, 0.01));
      expect(speed(light, 0) / speed(heavy, 0), closeTo(1, 0.01));
      // Freewheeling downhill the heavy rider is faster.
      expect(descentCap(-0.06, 70, massKg: 82),
          greaterThan(descentCap(-0.06, 70)));
    });

    test('headwind slows, tailwind speeds up', () {
      final calm = speedFor(300, 0, soloCda, 0.004);
      expect(speedFor(300, 0, soloCda, 0.004, headwind: 5), lessThan(calm));
      expect(speedFor(300, 0, soloCda, 0.004, headwind: -5), greaterThan(calm));
    });

    test('ranges of the tuning are physical', () {
      final t = SimTuning({'thresholdWkg': 6.6, 'draftPeloton': 0.7}).clamped();
      expect(t.thresholdWkg, 6.0);
      expect(t.draftPeloton, 0.5);
    });
  });

  group('weather', () {
    test('depends on season and country and survives a save', () {
      double mean(int month, String country) {
        final r = Random(3);
        var sum = 0.0;
        for (var i = 0; i < 200; i++) {
          sum += Weather.draw(r, month, country).temperatureC;
        }
        return sum / 200;
      }

      expect(mean(7, 'FRA'), greaterThan(mean(2, 'FRA') + 10));
      expect(mean(1, 'AUS'), greaterThan(mean(1, 'BEL') + 10));
      final w = Weather.draw(Random(1), 4, 'BEL');
      final back = Weather.fromJson(w.toJson());
      expect(back.temperatureC, w.temperatureC);
      expect(back.windMs, w.windMs);
      expect(back.rain, w.rain);
    });
  });

  group('road stage', () {
    test('same seed, same result', () {
      final a = simulateStage(hillyClassic(), field, seed: 7);
      final b = simulateStage(hillyClassic(), field, seed: 7);
      expect([for (final p in a.placings) p.rider.id],
          [for (final p in b.placings) p.rider.id]);
      expect([for (final p in a.placings) p.timeS],
          [for (final p in b.placings) p.timeS]);
    });

    test('every rider finishes or abandons, exactly once', () {
      final t = SimTuning({'crashRate': 0.003});
      for (var seed = 0; seed < 4; seed++) {
        final r = simulateStage(cobbledClassic(), field, seed: seed, tuning: t);
        final ids = [
          ...r.placings.map((p) => p.rider.id),
          ...r.abandons.map((a) => a.rider.id),
        ];
        expect(ids.length, field.length);
        expect(ids.toSet().length, field.length);
      }
    });

    test('crashes and punctures happen and are recorded', () {
      final t = SimTuning({'crashRate': 0.003, 'punctureRate': 0.001});
      var crashes = 0, punctures = 0;
      for (var seed = 0; seed < 4; seed++) {
        final r = simulateStage(flatStage(), field, seed: seed, tuning: t);
        crashes += r.traces.values
            .where((x) => x.incident == RiderIncident.crash)
            .length;
        punctures += r.traces.values
            .where((x) => x.incident == RiderIncident.puncture)
            .length;
      }
      expect(crashes, greaterThan(0));
      expect(punctures, greaterThan(0));
    });

    test('a flat stage ends in a bunch, a mountain stage in small groups', () {
      var bunch = 0, small = 0;
      for (var seed = 0; seed < 6; seed++) {
        final f = simulateStage(flatStage(), field, seed: seed);
        final first =
            f.placings.where((p) => p.group == f.placings.first.group);
        if (first.length > 50 || f.breakSurvived) bunch++;
        final m = simulateStage(mountainStage(), field, seed: seed);
        if (m.placings.where((p) => p.timeS - m.winnerTimeS <= 1).length <=
            12) {
          small++;
        }
      }
      expect(bunch, greaterThanOrEqualTo(5));
      expect(small, greaterThanOrEqualTo(5));
    });

    test('a gale splits the field in echelons', () {
      var calm = 0, gale = 0, echelons = 0;
      for (var seed = 0; seed < 4; seed++) {
        int first(StageResult r) =>
            r.placings.where((p) => p.timeS - r.winnerTimeS <= 1).length;
        calm += first(simulateStage(flatStage(), field,
            seed: seed, weather: const Weather()));
        final g = simulateStage(flatStage(), field,
            seed: seed, weather: const Weather(windMs: 14, windFrom: 1.3));
        gale += first(g);
        echelons += g.events.where((e) => e.type == EventType.echelon).length;
      }
      expect(echelons, greaterThan(0));
      expect(gale, lessThan(calm * 0.8));
    });

    test('weather is part of the result', () {
      final r = simulateStage(flatStage(), field, seed: 2, month: 1);
      expect(r.weather, isNotNull);
      expect(r.events.first.type, EventType.weather);
    });
  });

  group('partial plans', () {
    test('a pinned leader stays leader on every stage, the rest is replanned',
        () {
      final field = syntheticField();
      final team = field.first.teamId;
      final mine = [
        for (final r in field)
          if (r.teamId == team) r,
      ];
      final present = {for (final r in mine) r.id};
      // Pin a rider the sports director would not pick himself.
      final flat = autoPlans(flatStage(), field)[team]!;
      final mountain = autoPlans(mountainStage(), field)[team]!;
      final pick = mine.firstWhere((r) =>
          flat.roleOf(r.id) != Role.sprinter &&
          mountain.roleOf(r.id) != Role.leader);
      final wish = PlanWish(roles: {pick.id: Role.leader});
      final onFlat = wish.applyTo(flat, flatStage(), present);
      final onMountain = wish.applyTo(mountain, mountainStage(), present);
      expect(onFlat.roleOf(pick.id), Role.leader);
      expect(onMountain.roleOf(pick.id), Role.leader);
      // The director's own leader makes room, his sprinter stays.
      expect(
          mine.where((r) => onMountain.roleOf(r.id) == Role.leader).length, 1);
      expect(mine.where((r) => onFlat.roleOf(r.id) == Role.sprinter).length, 1);
      // What was not pinned follows the stage.
      expect(onFlat.approach, flat.approach);
      expect(onMountain.breakPolicy, mountain.breakPolicy);
    });

    test('a pinned sprinter is protected in the mountains', () {
      final field = syntheticField();
      final team = field.first.teamId;
      final mine = [
        for (final r in field)
          if (r.teamId == team) r,
      ];
      final wish = PlanWish(
          roles: {mine.last.id: Role.sprinter}, approach: Approach.control);
      final plan = wish.applyTo(autoPlans(mountainStage(), field)[team]!,
          mountainStage(), {for (final r in mine) r.id});
      expect(plan.roleOf(mine.last.id), Role.protected);
      expect(plan.approach, Approach.control);
      expect(PlanWish.fromJson(wish.toJson()).roles, wish.roles);
    });
  });

  group('time trials', () {
    test('fatigue costs time in a time trial', () {
      final rider = field.first;
      double time(double energy) => simulateStage(timeTrial(), [rider],
          seed: 1,
          conditions: {rider.id: RiderCondition(energy: energy)},
          tuning: SimTuning({'crashRate': 0, 'punctureRate': 0})).winnerTimeS;
      expect(time(0.6), greaterThan(time(1.0) + 5));
    });

    test('a team in line is faster than its riders alone', () {
      final t = SimTuning({'crashRate': 0, 'punctureRate': 0});
      final itt = simulateStage(timeTrial(), field, seed: 1, tuning: t);
      final ttt = simulateStage(teamTimeTrial(), field, seed: 1, tuning: t);
      final ittKmh = 35 / (itt.winnerTimeS / 3600);
      final tttKmh = 30 / (ttt.winnerTimeS / 3600);
      expect(tttKmh, greaterThan(ittKmh * 1.03));
      // The riders who finish with the team share its time.
      final team = ttt.placings.where((p) => p.rider.teamId == 1).toList();
      expect(team.where((p) => p.timeS == team.first.timeS).length,
          greaterThanOrEqualTo(5));
    });
  });

  group('stage race', () {
    test('fatigue levels off by recovery, rest days help', () {
      SimRider withRecovery(SimRider r, double value) => r.withAttributes(
          r.attributes.adjusted((n, v) => n == 'recovery' ? value : v));
      final riders = [
        for (var i = 0; i < field.length; i++)
          withRecovery(field[i], i.isEven ? 80 : 60),
      ];
      final run = StageRaceRun(riders,
          seed: 4, tuning: SimTuning({'crashRate': 0, 'punctureRate': 0}));
      for (var i = 0; i < 6; i++) {
        run.nextStage(i.isEven ? mountainStage() : hillyClassic());
      }
      double mean(bool good) {
        final x = [
          for (var i = 0; i < riders.length; i++)
            if (i.isEven == good && run.debt.containsKey(riders[i].id))
              run.debt[riders[i].id]!,
        ];
        return x.reduce((a, b) => a + b) / x.length;
      }

      expect(mean(true), lessThan(mean(false) * 0.8));
      final before = mean(false);
      run.restDay();
      expect(mean(false), lessThan(before * 0.8));
    });

    test('riders far outside the time limit leave the race', () {
      SimRider weak(SimRider r) =>
          r.withAttributes(r.attributes.adjusted((_, v) => v - 25));
      final riders = [
        for (var i = 0; i < field.length; i++)
          i % 30 == 5 ? weak(field[i]) : field[i],
      ];
      final run = StageRaceRun(riders,
          seed: 2, tuning: SimTuning({'crashRate': 0, 'punctureRate': 0}));
      run.nextStage(flatStage());
      final r = run.nextStage(mountainStage());
      final cut = r.abandons.where((a) => a.reason == AbandonReason.timeCut);
      expect(cut, isNotEmpty);
      for (final a in cut) {
        expect(run.riders.any((x) => x.id == a.rider.id), isFalse);
        expect(run.result.gc.any((e) => e.rider.id == a.rider.id), isFalse);
      }
    });

    test('a saved race continues exactly as the original', () {
      final t = SimTuning({'crashRate': 0.003});
      final run = StageRaceRun(field, seed: 9, tuning: t, month: 4);
      final routes = [
        flatStage(),
        mountainStage(),
        hillyClassic(),
        flatStage()
      ];
      for (var i = 0; i < 3; i++) {
        run.nextStage(routes[i]);
        if (i == 1) run.restDay();
      }
      final pool = {for (var i = 0; i < field.length; i++) field[i]: i};
      final json = run.toJson((r) => pool[r]!);
      final copy = StageRaceRun.fromJson(json,
          rider: (i) => field[i], routeOf: (i) => routes[i], tuning: t);
      expect([for (final e in copy.result.gc) e.rider.id],
          [for (final e in run.result.gc) e.rider.id]);
      expect(
          copy.results.last.abandons.length, run.results.last.abandons.length);
      final a = run.nextStage(routes[3]);
      final b = copy.nextStage(routes[3]);
      expect([for (final p in b.placings) p.rider.id],
          [for (final p in a.placings) p.rider.id]);
      expect(b.weather?.temperatureC, a.weather?.temperatureC);
    });
  });
}

const _flat70 = Attributes(
  flat: 70,
  mountain: 70,
  mediumMountain: 70,
  hill: 70,
  timeTrial: 70,
  prologue: 70,
  cobble: 70,
  sprint: 70,
  acceleration: 70,
  downhill: 70,
  endurance: 70,
  resistance: 70,
  recovery: 70,
  breakaway: 70,
);
