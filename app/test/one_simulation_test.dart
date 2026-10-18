// Checks that there is only one race simulation: a stage that is watched
// (with the radio on), skipped (radio off) or run through by "simulate
// until" is the same race, computed by the same code from the same seed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game/game.dart';
import 'package:radmanager/app_state.dart';
import 'package:sim/sim.dart';

/// @param r A stage result.
/// @returns Everything that makes up the race, as one comparable text.
String signature(StageResult r) => [
  for (final p in r.placings) '${p.rider.id}:${p.timeS.toStringAsFixed(3)}',
  for (final e in r.events) '${e.km}|${e.type.name}|${e.text}',
  for (final a in r.abandons) '${a.rider.id} out at ${a.km} (${a.reason.name})',
  for (final e in r.injuries.entries) '${e.key} hurt ${e.value.formLoss}',
  r.weather?.toJson().join(',') ?? '',
].join('\n');

/// @param c A career.
/// @returns The signatures of all stages ridden so far, by race and stage.
Map<String, String> season(Career c) => {
  for (final p in c.progress.values)
    for (var i = 0; i < p.run.results.length; i++)
      '${p.race.info.name} ${i + 1}': signature(p.run.results[i]),
};

void main() {
  final dataDir = AppState.findDataDir();

  test(
    'Preview, counted stage and replay are the same race',
    skip: dataDir == null,
    () {
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final race = world.findRace('Paris-Nice')!;
      final riders = world.startList(race.id);
      final team = riders.first.teamId;
      final stages = world.stages(race.id);
      final run = StageRaceRun(riders, seed: 4711, month: 3, country: 'FRA');
      var checked = 0;
      for (var i = 0; i < 4; i++) {
        final route = world.route(stages[i].id);
        final preview = run.preview(route, radioTeam: team);
        final counted = run.nextStage(route, radioTeam: team);
        final replay = run.replay(i, route, radioTeam: team);
        expect(signature(preview), signature(counted));
        expect(signature(replay), signature(counted));
        // Answering every question with the sports director's own choice is
        // the same as not being asked.
        if (route.kind != StageKind.road) continue;
        final answers = <RadioKind, int>{};
        for (var k = 0; k < RadioKind.values.length + 1; k++) {
          final asked = run.replay(
            i,
            route,
            radioTeam: team,
            radio: answers,
            askRadio: true,
          );
          final call = asked.openCall;
          if (call == null) {
            expect(signature(asked), signature(counted));
            checked++;
            break;
          }
          answers[call.kind] = call.suggested;
        }
      }
      expect(checked, greaterThan(0));
    },
  );

  test(
    'Watching, skipping and simulating to a date give the same season',
    skip: dataDir == null,
    () {
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final tuning = SimTuning.load('$dataDir/calibration/tuning.json');
      final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
      Career start() => Career(world, teamId: team, seed: 99, tuning: tuning);
      const days = 70;

      // Watching: the player confirms the suggested line-up and answers every
      // radio call with what the sports director recommends.
      final watched = start();
      var calls = 0;
      for (var d = 0; d < days; d++) {
        for (
          var p = watched.needsDecision;
          p != null;
          p = watched.needsDecision
        ) {
          watched.confirm(p, p.suggestedLineup);
        }
        for (
          var r = watched.nextRadioCall();
          r != null;
          r = watched.nextRadioCall()
        ) {
          watched.answerRadio(
            r.race.race.info.id,
            r.call.kind,
            r.call.suggested,
          );
          calls++;
        }
        watched.advance();
      }

      // Skipping: the radio is off, the line-ups are confirmed by hand.
      final skipped = start()..delegation.radio = RadioMode.off;
      for (var d = 0; d < days; d++) {
        for (
          var p = skipped.needsDecision;
          p != null;
          p = skipped.needsDecision
        ) {
          skipped.confirm(p, p.suggestedLineup);
        }
        expect(skipped.nextRadioCall(), isNull);
        skipped.advance();
      }

      // "Simulate until" with the staff in charge: nothing but advancing.
      final until = start()
        ..delegation.lineups = true
        ..delegation.radio = RadioMode.off;
      for (var d = 0; d < days; d++) {
        until.advance();
      }

      final a = season(watched), b = season(skipped), c = season(until);
      expect(calls, greaterThan(5));
      expect(a.length, greaterThan(40));
      expect(b.keys, a.keys);
      expect(c.keys, a.keys);
      for (final stage in a.keys) {
        expect(b[stage], a[stage], reason: 'skipped: $stage');
        expect(c[stage], a[stage], reason: 'simulate until: $stage');
      }
    },
  );

  test(
    'Computed in the background gives the same season',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 15)),
    () async {
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final tuning = SimTuning.load('$dataDir/calibration/tuning.json');
      final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
      Career start() => Career(world, teamId: team, seed: 99, tuning: tuning)
        ..delegation.lineups = true
        ..delegation.radio = RadioMode.off;
      const days = 45;
      final here = start(), there = start();
      for (var d = 0; d < days; d++) {
        here.advance();
        await there.advanceAsync();
      }
      final a = season(here), b = season(there);
      expect(a.length, greaterThan(20));
      expect(b.keys, a.keys);
      for (final stage in a.keys) {
        expect(b[stage], a[stage], reason: stage);
      }
      // The radio question as well.
      final x = start()..delegation.radio = RadioMode.all;
      final y = start()..delegation.radio = RadioMode.all;
      for (var d = 0; d < 25; d++) {
        expect(
          (await y.nextRadioCallAsync())?.call.text,
          x.nextRadioCall()?.call.text,
        );
        x.advance();
        await y.advanceAsync();
      }
    },
  );

  test('Only one place in the game simulates stages', () {
    // Everything in the game and the app has to go through StageRaceRun, so
    // that no screen can end up with a second, different race.
    final callers = <String>[];
    for (final dir in ['../packages/game/lib', '../packages/sim/lib', 'lib']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (RegExp(r'\bsimulateStage\(').hasMatch(f.readAsStringSync())) {
          callers.add(f.uri.pathSegments.last);
        }
      }
    }
    // The definition itself and the one caller.
    expect(callers..sort(), ['stage_race.dart', 'stage_sim.dart']);
  });
}
