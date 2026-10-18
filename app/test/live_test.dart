// A stage of the player's team watched live: the orders given and the radio
// answered on the way go into the game, the day gives the same stage, and a
// loaded save the same state.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:radmanager/app_state.dart';
import 'package:sim/sim.dart';

void main() {
  final dataDir = AppState.findDataDir();
  const saveName = 'savegame_test_live.json';

  test(
    'a stage watched live is the stage of the day',
    skip: dataDir == null,
    () async {
      final file = File('$dataDir/$saveName');
      if (file.existsSync()) file.deleteSync();
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      final a = AppState(dataDir!, saveName: saveName)..watchLive = true;
      // The sports director picks the line-ups.
      a.delegate('lineups', true);
      for (var i = 0; i < 60 && a.liveRace == null; i++) {
        await a.next();
      }
      final live = a.liveRace!;
      expect(live.started, isFalse);
      expect(live.own, isNotEmpty);

      // Ridden here without the viewer and its clock, with an order on the
      // way and the radio answered against the director's advice.
      live.started = true;
      final stage = live.stage;
      var ordered = false;
      while (!stage.finished) {
        if (stage.openCall case final call?) {
          live.answer(call.options.length - 1);
          continue;
        }
        stage.advanceTo(stage.clock + 60);
        if (!ordered && stage.clock > 1800 && !stage.timeTrial) {
          live.order(RiderOrder.tempo, [live.own.first.id]);
          ordered = true;
        }
      }
      final placings = [
        for (final p in stage.result!.placings) (p.rider.id, p.timeS),
      ];
      final info = live.info;
      final index = live.stageIndex;
      await a.endLive();
      expect(a.liveRace, isNull);

      // The day rode the stage again with the orders and answers.
      final day = a.runOf(info)!.result.stages[index];
      expect([for (final p in day.placings) (p.rider.id, p.timeS)], placings);

      // A loaded save is the same game.
      a.flush();
      final b = AppState(dataDir, saveName: saveName)..watchLive = true;
      await b.restore();
      final ja = a.career.toJson(), jb = b.career.toJson();
      for (final k in ja.keys) {
        expect(jsonEncode(jb[k]), jsonEncode(ja[k]), reason: 'state "$k"');
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
