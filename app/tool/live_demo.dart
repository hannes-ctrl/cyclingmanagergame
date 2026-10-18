import 'dart:io';

import 'package:radmanager/viewer_link.dart';
import 'package:sim/sim.dart';

/// Watches a stage live in the 3D viewer, the way the game does: the stage
/// is ridden in race time and the riders of one team get orders on the way.
///
///   dart run tool/live_demo.dart "RACE" [stage] [--team ABBR]
///       [--speed 120] [--seconds 60] [--from km] [--shots folder]
///       [--screen n]
///
/// --from rides the stage up to that kilometre of the head of the race
/// before the viewer opens. With --shots the viewer saves a picture every
/// ten seconds into the folder. Set RADMANAGER_GODOT to the Godot editor to
/// watch the project rather than an export.
Future<void> main(List<String> argv) async {
  String text(String name, String fallback) {
    final i = argv.indexOf(name);
    return i >= 0 && i + 1 < argv.length ? argv[i + 1] : fallback;
  }

  final plain = [
    for (var i = 0; i < argv.length; i++)
      if (!argv[i].startsWith('--') &&
          (i == 0 || !argv[i - 1].startsWith('--')))
        argv[i],
  ];
  final name = plain.isNotEmpty ? plain[0] : 'Tour de France';
  final number = plain.length > 1 ? int.parse(plain[1]) : 1;
  final speed = double.parse(text('--speed', '120'));
  final seconds = double.parse(text('--seconds', '60'));
  final fromKm = double.parse(text('--from', '0'));
  final shots = text('--shots', '');
  final dataDir = '${Directory.current.parent.path}/data';

  final world = World('$dataDir/world.sqlite');
  final race = world.findRace(name);
  if (race == null) {
    stderr.writeln('No race "$name".');
    exit(1);
  }
  final stages = world.stages(race.id);
  final stage = stages.firstWhere((s) => s.number == number);
  final route = world.route(stage.id);
  final riders = world.startList(race.id);
  final teams = {for (final t in world.teams()) t.id: t};
  final own = teams.values.firstWhere((t) => t.abbr == text('--team', 'UEX'));
  final tuning = SimTuning.load('$dataDir/calibration/tuning.json');
  final live = liveStage(
    route,
    riders,
    seed: race.id * 100 + number,
    tuning: tuning,
    radioTeam: own.id,
    askRadio: true,
  );
  final mine = [
    for (final r in riders)
      if (r.teamId == own.id) r,
  ];
  final leader = mine.reduce(
    (a, b) =>
        a.attributes.hill + a.attributes.mountain >=
            b.attributes.hill + b.attributes.mountain
        ? a
        : b,
  );
  final helpers = mine.where((r) => r != leader).toList();

  void answerRadio() {
    final call = live.openCall;
    if (call == null) return;
    stdout.writeln(
      'radio at ${(live.clock / 60).round()} min: ${call.text}\n'
      '  -> ${call.options[call.suggested]}',
    );
    live.answer(call.suggested);
  }

  double headKm() {
    final groups = live.groups();
    return groups.isEmpty ? 0 : groups.first.km;
  }

  // Up to the kilometre to start at.
  while (!live.finished && headKm() < fromKm) {
    if (live.openCall != null) {
      answerRadio();
    } else {
      live.advanceTo(live.clock + 30);
    }
  }

  final link = ViewerLink.instance
    ..engineArgs = ['--screen', text('--screen', '1')]
    ..onLive = (m) => stdout.writeln('from the viewer: $m');
  // The test window must not take the focus.
  final cfg = File('${Directory.current.parent.path}/viewer/override.cfg');
  final ownCfg = !cfg.existsSync();
  if (ownCfg) cfg.writeAsStringSync('[display]\n\nwindow/size/no_focus=true\n');
  try {
    final kits = Directory('$dataDir/kits');
    final logo = File('$dataDir/logos/${race.id}.png');
    final error = await link.show(
      dataDir,
      viewerRace(
        title: race.name,
        stage: stages.length > 1 ? 'Stage $number' : '',
        route: route,
        result: StageResult(const [], const [], false)
          ..weather = live.weather
          ..track = live.track,
        riders: riders,
        teams: teams,
        ownTeam: own.id,
        seed: race.id * 100 + number - 1,
        kits: kits.existsSync() ? kits.absolute.path : null,
        kitOf: world.jerseyKeys(),
        raceKey: world.raceKey(race.id),
        logo: logo.existsSync() ? logo.absolute.path : null,
        live: true,
        roles: live.roles,
      ),
    );
    if (error != null) {
      stderr.writeln(error);
      exit(1);
    }
    for (var i = 0; i < 120 && !link.ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    stdout.writeln(link.ready ? 'viewer ready' : 'viewer did not connect');
    // Give the viewer time to lay out the course.
    await Future<void>.delayed(const Duration(seconds: 3));

    final feed = LiveFeed(live);
    final ids = [for (final r in mine) r.id];
    final watch = Stopwatch()..start();
    var last = 0.0, nextShot = 4.0, shot = 0, orders = 0;
    double? asked;
    while (watch.elapsedMilliseconds < seconds * 1000) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final now = watch.elapsedMilliseconds / 1000;
      final dt = now - last;
      last = now;
      if (live.openCall != null) {
        // The radio waits a moment in the viewer, then the director decides.
        asked ??= now;
        if (now - asked > 2) {
          answerRadio();
          asked = null;
        }
      } else if (!live.finished) {
        live.advanceTo(live.clock + dt * speed);
      }
      final share = headKm() / route.raceKm;
      if (orders == 0 && helpers.length >= 2) {
        live
          ..order(helpers[0].id, RiderOrder.tempo)
          ..order(helpers[1].id, RiderOrder.tempo);
        stdout.writeln(
          'tempo for ${helpers[0].name} and ${helpers[1].name} '
          'at km ${headKm().toStringAsFixed(1)}',
        );
        orders++;
      } else if (orders == 1 && share > 0.9) {
        live.order(leader.id, RiderOrder.attack);
        stdout.writeln(
          'attack for ${leader.name} at km ${headKm().toStringAsFixed(1)}',
        );
        orders++;
      }
      link.send(feed.update(speed: speed, paused: false, own: ids));
      if (shots.isNotEmpty && now >= nextShot) {
        link.send({
          'type': 'screenshot',
          'path': '$shots/live_${(shot++).toString().padLeft(2, '0')}.png',
        });
        nextShot += 10;
      }
    }
    stdout.writeln(
      'stopped at km ${headKm().toStringAsFixed(1)}, '
      '${live.finished ? 'finished' : 'running'}, '
      '${live.events.length} events, ${live.orders.length} orders',
    );
    await link.close();
  } finally {
    if (ownCfg && cfg.existsSync()) cfg.deleteSync();
    world.close();
  }
  exit(0);
}
