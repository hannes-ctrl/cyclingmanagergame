import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:sim/sim.dart';
import 'package:test/test.dart';

import 'synthetic.dart';

/// Behaviour of the simulation that must hold regardless of fine tuning.
/// Runs on a synthetic field, so no world database is needed.
void main() {
  final field = syntheticField();
  materialTests();

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
    test('the line of a big bunch breaks in the sprint', () {
      // Without breaks the whole bunch shares one time; with them, gaps of
      // a second or more open behind the first places.
      double spread(SimTuning t) {
        final r = simulateStage(flatStage(), field, seed: 3, tuning: t);
        // The biggest group on the line is the bunch.
        final sizes = <int, int>{};
        for (final p in r.placings) {
          sizes[p.group] = (sizes[p.group] ?? 0) + 1;
        }
        final main =
            sizes.entries.reduce((a, b) => b.value > a.value ? b : a).key;
        final bunch = r.placings.where((p) => p.group == main).toList();
        return bunch.last.timeS - bunch.first.timeS;
      }

      final calm = SimTuning({'bunchSplitRate': 0.0, 'crashRate': 0});
      final split = SimTuning(
          {'bunchSplitRate': 0.2, 'bunchSplitFrom': 10, 'crashRate': 0});
      expect(spread(calm), lessThan(0.1));
      expect(spread(split), greaterThan(1));
    });

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
      // Share of the riders outside the biggest group, over the race.
      double split(StageResult r) {
        var sum = 0.0;
        for (final s in r.timeline) {
          final total = s.groups.fold(0, (n, g) => n + g.size);
          final biggest = s.groups.fold(0, (n, g) => max(n, g.size));
          if (total > 0) sum += 1 - biggest / total;
        }
        return r.timeline.isEmpty ? 0 : sum / r.timeline.length;
      }

      var calm = 0.0, gale = 0.0, echelons = 0;
      for (var seed = 0; seed < 4; seed++) {
        calm += split(simulateStage(flatStage(), field,
            seed: seed, weather: const Weather()));
        final g = simulateStage(flatStage(), field,
            seed: seed, weather: const Weather(windMs: 14, windFrom: 1.3));
        gale += split(g);
        echelons += g.events.where((e) => e.type == EventType.echelon).length;
      }
      expect(echelons, greaterThan(0));
      expect(gale, greaterThan(calm * 2));
    });

    test('the track for the 3D view changes nothing and reaches the finish',
        () {
      final route = hillyClassic();
      final plain = simulateStage(route, field, seed: 3);
      final traced = simulateStage(route, field, seed: 3, track: true);
      expect([for (final p in traced.placings) (p.rider.id, p.timeS)],
          [for (final p in plain.placings) (p.rider.id, p.timeS)]);
      expect(plain.track, isNull);
      final track = traced.track!;
      expect(track.length, route.segments.length);
      expect(track.km.last, closeTo(route.raceKm, 0.01));
      for (final p in traced.placings) {
        final times = track.times[p.rider.id]!;
        // Every finisher passes every point, one after the other, and
        // crosses the line with his finishing time give or take the sprint.
        expect(times.every((t) => !t.isNaN), isTrue);
        for (var i = 1; i < times.length; i++) {
          expect(times[i], greaterThan(times[i - 1]));
        }
        expect(times.last, closeTo(p.timeS, 30));
      }
      final tt = simulateStage(timeTrial(), field, seed: 3, track: true);
      final starts = tt.track!.starts.values.toList()..sort();
      expect(starts.first, 0);
      expect(starts[1], 60);

      // The message for the viewer carries the track losslessly.
      final message = jsonDecode(jsonEncode(viewerRace(
          title: 'Test',
          stage: '',
          route: route,
          result: traced,
          riders: field,
          teams: const {},
          ownTeam: field.first.teamId))) as Map<String, dynamic>;
      expect(message['protocol'], viewerProtocol);
      final id = traced.placings.first.rider.id;
      final bytes = base64Decode((message['track']['times'] as Map)['$id']);
      final back = Float32List.view(Uint8List.fromList(bytes).buffer);
      expect(back, track.times[id]);
      expect((message['riders'] as List).where((r) => r['own'] == true),
          hasLength(field.where((r) => r.teamId == field.first.teamId).length));
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

    test('a team with fewer than three riders leaves the team classification',
        () {
      final run = StageRaceRun(field,
          seed: 3, tuning: SimTuning({'crashRate': 0, 'punctureRate': 0}));
      final teams = {for (final r in field) r.teamId}.toList();
      final small = teams[0], gone = teams[1];
      run.nextStage(flatStage());
      List<int> ranked() =>
          [for (final e in run.standings.last.teams) e.teamId];
      expect(ranked(), containsAll([small, gone]));
      for (final r in field.where((r) => r.teamId == small).skip(2)) {
        run.withdraw(r.id);
      }
      for (final r in field.where((r) => r.teamId == gone)) {
        run.withdraw(r.id);
      }
      run.nextStage(flatStage());
      expect(ranked(), isNot(contains(small)));
      expect(ranked(), isNot(contains(gone)));
      expect(ranked(), hasLength(teams.length - 2));
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

/// Material, staff, styles, the power meter and the new roles.
void materialTests() {
  final field = syntheticField();

  group('power meter', () {
    test('records plausible figures for every rider', () {
      final r = simulateStage(mountainStageWithTops(), field, seed: 3);
      final best = r.power[r.placings.first.rider.id]!;
      expect(best.averageW, inInclusiveRange(150, 380));
      expect(best.normalizedW, greaterThanOrEqualTo(best.averageW));
      expect(best.kilojoules,
          closeTo(best.averageW * best.seconds / 1000, best.kilojoules * 0.01));
      expect(best.zones.reduce((a, b) => a + b), closeTo(best.seconds, 5));
      expect(best.climbs, isNotEmpty);
      final last = best.climbs.last;
      expect(last.averageWkg, inInclusiveRange(3.5, 7.5));
      expect(last.vam, inInclusiveRange(800, 2200));
      final json = PowerStats.fromJson(best.toJson());
      expect(json.climbs.length, best.climbs.length);
      expect(r.power.length, field.length);
    });

    test('also in a time trial', () {
      final r = simulateStage(timeTrial(), field.take(20).toList(), seed: 1);
      final p = r.power[r.placings.first.rider.id]!;
      expect(p.intensity, inInclusiveRange(0.85, 1.2));
    });
  });

  group('material', () {
    test('the road bike wins a mountain time trial, not a flat one', () {
      expect(suggestTimeTrialBike(timeTrial()), isTrue);
      expect(suggestTimeTrialBike(mountainTimeTrial()), isFalse);
    });

    test('wide tyres for cobbles, standard for a dry road stage', () {
      expect(suggestTyres(cobbledClassic(), const Weather()), Tyres.wide);
      expect(suggestTyres(flatStage(), const Weather()), Tyres.standard);
    });

    test('wide tyres puncture less on cobbles', () {
      // Mostly punctures on the cobbles, where the tyres matter most.
      final t = SimTuning(
          {'punctureRate': 0.0002, 'cobbleMishap': 0.02, 'crashRate': 0});
      int punctures(Tyres tyres) {
        final kits = {
          for (final r in field) r.teamId: TeamKit(tyres: tyres),
        };
        var n = 0;
        for (var seed = 0; seed < 4; seed++) {
          final r = simulateStage(cobbledClassic(), field,
              seed: seed, tuning: t, kits: kits);
          n += r.traces.values
              .where((x) => x.incident == RiderIncident.puncture)
              .length;
        }
        return n;
      }

      expect(punctures(Tyres.wide), lessThan(punctures(Tyres.narrow) * 0.75));
    });

    test('good physios win back more overnight', () {
      double debtOf(double physios) {
        final run = StageRaceRun(field, seed: 5);
        final kits = {
          for (final r in field)
            r.teamId: TeamKit(physios: r.teamId == 1 ? physios : 0.5),
        };
        // Overnight recovery shows from the second stage on.
        run.nextStage(mountainStage(), kits: kits);
        run.nextStage(mountainStage(), kits: kits);
        final team = field.where((r) => r.teamId == 1);
        return team.fold(0.0, (s, r) => s + (run.debt[r.id] ?? 0));
      }

      expect(debtOf(1), lessThan(debtOf(0)));
    });

    test('kits survive a save', () {
      final kits = {
        for (final r in field)
          r.teamId: TeamKit(
              aero: 0.99,
              tyres: Tyres.wide,
              mechanics: 0.8,
              style: TeamStyle.gc),
      };
      final run = StageRaceRun(field, seed: 9);
      run.nextStage(flatStage(), kits: kits);
      final pool = {for (var i = 0; i < field.length; i++) field[i]: i};
      final copy = StageRaceRun.fromJson(run.toJson((r) => pool[r]!),
          rider: (i) => field[i], routeOf: (i) => flatStage());
      final a = run.replay(0, flatStage(), radioTeam: 1);
      final b = copy.replay(0, flatStage(), radioTeam: 1);
      expect([for (final p in b.placings) p.rider.id],
          [for (final p in a.placings) p.rider.id]);
      expect(copy.results.first.power.length, run.results.first.power.length);
    });
  });

  group('tactics', () {
    test('the team car asks when a leader crashes or punctures', () {
      final t = SimTuning({'punctureRate': 0.001, 'crashRate': 0.003});
      RadioCall? call;
      var seed = 0, team = 0;
      for (; seed < 30 && call == null; seed++) {
        for (team = 1; team <= 4 && call == null; team++) {
          final r = simulateStage(cobbledClassic(), field,
              seed: seed,
              tuning: t,
              radioTeam: team,
              askRadio: true,
              radio: const {
                RadioKind.breakGone: 0,
                RadioKind.finale: 0,
                RadioKind.rivalAttack: 0,
              });
          if (r.openCall?.kind == RadioKind.mishap) call = r.openCall;
        }
      }
      expect(call, isNotNull);
      expect(call!.options, hasLength(3));
      // Every answer lets the stage run to the end.
      for (var answer = 0; answer < 3; answer++) {
        final r = simulateStage(cobbledClassic(), field,
            seed: seed - 1,
            tuning: t,
            radioTeam: team - 1,
            askRadio: true,
            radio: {
              RadioKind.breakGone: 0,
              RadioKind.finale: 0,
              RadioKind.rivalAttack: 0,
              RadioKind.mishap: answer,
            });
        expect(r.openCall, isNull);
        expect(r.placings, isNotEmpty);
      }
    });

    test('a crosswind brings out teams that split the field', () {
      bool echelon(double km) => autoPlans(flatStage(), field, crosswindKm: km)
          .values
          .any((p) => p.approach == Approach.echelon);
      expect(echelon(0), isFalse);
      expect(echelon(20), isTrue);
    });

    test('teams without a leader hunt the mountains jersey', () {
      final gaps = {
        for (var i = 0; i < field.length; i++) field[i].id: i * 30.0
      };
      final plans = autoPlans(mountainStage(), field, gcGaps: gaps);
      expect(
          plans.values
              .expand((p) => p.roles.values)
              .where((r) => r == Role.mountainHunter),
          isNotEmpty);
    });

    test('a mountains hunter takes more points on the climbs', () {
      final route = mountainStageWithTops();
      final auto = autoPlans(route, field);
      // A good breakaway rider of a team that does not ride for the stage.
      final climber = field
          .where((r) => auto[r.teamId]!.approach == Approach.wait)
          .reduce((a, b) => a.attributes.breakaway + a.attributes.mountain >=
                  b.attributes.breakaway + b.attributes.mountain
              ? a
              : b);
      final plan = auto[climber.teamId]!;
      int points(Role role) {
        var sum = 0;
        for (var seed = 0; seed < 6; seed++) {
          final r = simulateStage(route, field, seed: seed, plans: {
            climber.teamId: TeamPlan(
                roles: {...plan.roles, climber.id: role},
                breakPolicy: BreakPolicy.join),
          });
          for (final a in r.awards) {
            final at = a.order.indexWhere((x) => x.id == climber.id);
            if (a.point.category > 0 && at >= 0) sum += 15 - at;
          }
        }
        return sum;
      }

      expect(points(Role.mountainHunter), greaterThan(points(Role.domestique)));
    });
  });

  group('live', () {
    // The team whose riders take orders, and its strongest rider.
    final team = field.first.teamId;
    final mine = field.where((r) => r.teamId == team).toList();
    final leader = mine.reduce((a, b) =>
        a.attributes.hill + a.attributes.mountain >=
                b.attributes.hill + b.attributes.mountain
            ? a
            : b);
    final helpers = mine.where((r) => r != leader).toList();

    /// Rides a stage live in uneven steps and gives orders on the way.
    LiveStage watch(
        SimRoute route, int seed, Map<double, List<(int, RiderOrder)>> orders,
        {bool askRadio = false, int answer = 1}) {
      final live = liveStage(route, field,
          seed: seed, radioTeam: team, askRadio: askRadio);
      final due = orders.keys.toList()..sort();
      var t = 0.0;
      while (!live.finished) {
        if (live.openCall != null) {
          live.answer(answer);
          continue;
        }
        t += 23.7;
        live.advanceTo(t);
        while (due.isNotEmpty && due.first <= live.clock) {
          for (final (id, o) in orders[due.removeAt(0)]!) {
            live.order(id, o);
          }
        }
      }
      return live;
    }

    List<(int, double)> placings(StageResult r) =>
        [for (final p in r.placings) (p.rider.id, p.timeS)];

    test('a stage watched live is the stage simulated with its orders', () {
      final route = hillyClassic();
      final live = watch(route, 4, {
        1800: [
          (helpers[0].id, RiderOrder.tempo),
          (helpers[1].id, RiderOrder.tempo)
        ],
        5400: [
          (leader.id, RiderOrder.follow),
          (helpers[2].id, RiderOrder.save)
        ],
        7200: [(leader.id, RiderOrder.attack)],
        7800: [(helpers[0].id, RiderOrder.none)],
      });
      expect(live.orders, hasLength(6));
      final again = simulateStage(route, field,
          seed: 4, radioTeam: team, orders: live.orders);
      expect(placings(live.result!), placings(again));
      // Without the orders it is another race.
      final plain = simulateStage(route, field, seed: 4, radioTeam: team);
      expect(placings(plain), isNot(placings(again)));
    });

    test('the radio answered live is the radio answered before', () {
      final route = mountainStage();
      final live = watch(route, 2, const {}, askRadio: true);
      expect(live.answers, isNotEmpty);
      final again = simulateStage(route, field,
          seed: 2, radioTeam: team, radio: live.answers);
      expect(placings(live.result!), placings(again));
    });

    test('an attack order sends the rider off at once', () {
      final route = hillyClassic();
      final live = liveStage(route, field, seed: 6, radioTeam: team);
      live.advanceTo(3 * 3600);
      final before = live.groups();
      expect(before, isNotEmpty);
      live.order(leader.id, RiderOrder.attack);
      live.advanceTo(3 * 3600 + 60);
      final attack = live.events.where((e) =>
          (e.type == EventType.attack || e.type == EventType.breakaway) &&
          e.riders.contains(leader.id));
      final ahead =
          live.groups().indexWhere((g) => g.riders.contains(leader.id));
      final main = live.groups().indexWhere(
          (g) => g.riders.length > 20 && !g.riders.contains(leader.id));
      expect(attack.isNotEmpty || ahead < main, isTrue);
    });

    test('a time trial is shown as it goes and takes no orders', () {
      final live = liveStage(timeTrial(), field, seed: 3, radioTeam: team);
      expect(live.timeTrial, isTrue);
      live.order(leader.id, RiderOrder.attack);
      expect(live.orders, isEmpty);
      live.advanceTo(120);
      expect(live.groups(), isNotEmpty);
      live.advanceTo(1e6);
      expect(live.finished, isTrue);
      expect(
          placings(live.result!),
          placings(
              simulateStage(timeTrial(), field, seed: 3, radioTeam: team)));
    });
  });
}
