import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import 'app_state.dart';
import 'viewer_link.dart';

/// A stage of the player's team watched live: the race clock and its speed,
/// the 3D viewer, the player's orders to his riders and his answers to the
/// radio. The stage is ridden as the clock runs, so an order takes effect
/// where the rider is when it is given.
class LiveRace extends ChangeNotifier {
  /// @param app The game.
  /// @param info The race.
  /// @param stageIndex Index of the stage within the race.
  /// @param stageNumber Number of the stage, 0 for a one-day race.
  /// @param riders The riders at the start.
  /// @param standings Classifications after each stage ridden so far.
  /// @param stage The stage as it is ridden.
  LiveRace(
    this.app, {
    required this.info,
    required this.stageIndex,
    required this.stageNumber,
    required this.riders,
    required this.standings,
    required this.stage,
  });

  /// A stage of today, from [Career.liveJobs].
  ///
  /// @param app The game.
  /// @param job The stage.
  /// @returns The live race, not started.
  factory LiveRace.of(AppState app, LiveJob job) {
    final entry = job.race.race;
    return LiveRace(
      app,
      info: entry.info,
      stageIndex: job.stageIndex,
      stageNumber: entry.isStageRace ? entry.stages[job.stageIndex].number : 0,
      riders: job.race.run.riders,
      standings: job.race.run.result.standings,
      stage: job.job.live(),
    );
  }

  /// Speeds the player can pick, in race seconds per second.
  static const speeds = [1.0, 8.0, 30.0, 120.0, 480.0];

  final AppState app;

  /// The race.
  final RaceInfo info;

  /// Index of the stage within the race.
  final int stageIndex;

  /// Number of the stage, 0 for a one-day race.
  final int stageNumber;

  /// The riders at the start.
  final List<SimRider> riders;

  /// Classifications after each stage ridden so far.
  final List<Standings> standings;

  /// The stage as it is ridden.
  final LiveStage stage;

  /// Race seconds per second.
  double speed = 30;

  /// Whether the clock stands still.
  bool paused = false;

  /// Whether the race has started. Before, the player can still have it
  /// simulated as before, without the 3D viewer.
  bool started = false;

  /// Riders picked for the next order.
  final selected = <int>{};

  Timer? _timer;
  final _watch = Stopwatch();
  LiveFeed? _feed;
  var _sentAt = 0;
  var _shownAt = 0;
  var _closed = false;

  /// The player's riders in the race.
  late final List<SimRider> own = [
    for (final r in riders)
      if (r.teamId == app.team.id) r,
  ];

  /// Whether the 3D viewer gets the race.
  bool get in3d => _feed != null;

  /// Starts the race clock.
  ///
  /// @param in3d Whether to show the race in the 3D viewer too.
  /// @returns null, or why the viewer could not be opened.
  Future<String?> start({bool in3d = true}) async {
    if (started) return null;
    started = true;
    _watch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 40), (_) => _tick());
    notifyListeners();
    return in3d ? open3d() : null;
  }

  /// Shows the race in the 3D viewer, starting it if it is not running.
  ///
  /// @returns null if it is on its way, otherwise why it is not.
  Future<String?> open3d() async {
    final link = ViewerLink.instance;
    final stageRace = stageNumber > 0;
    final dataDir = app.dataDir;
    final answer = await link.show(
      dataDir,
      viewerRace(
        title: info.name,
        stage: stageRace ? tr('Stage {0}', [stageNumber]) : '',
        route: stage.route,
        result: StageResult(const [], const [], false)
          ..weather = stage.weather
          ..track = stage.track,
        riders: riders,
        teams: app.career.teams,
        ownTeam: app.team.id,
        // The same stage is laid out the same way every time.
        seed: info.id * 100 + stageIndex,
        kits: Directory('$dataDir/kits').existsSync() ? '$dataDir/kits' : null,
        kitOf: {for (final r in riders) r.teamId: app.jerseyOf(r.teamId)},
        raceKey: app.world.raceKey(info.id),
        leaders: stageRace && stageIndex > 0 && standings.length >= stageIndex
            ? leaderJerseys(standings[stageIndex - 1])
            : const {},
        logo: File('$dataDir/logos/${info.id}.png').existsSync()
            ? '$dataDir/logos/${info.id}.png'
            : null,
        live: true,
        roles: stage.roles,
      ),
    );
    if (answer == null) {
      _feed = LiveFeed(stage);
      link.onLive = _fromViewer;
      _sentAt = 0;
    }
    notifyListeners();
    return answer;
  }

  /// One step of the clock: the stage is ridden on, the viewer and the
  /// screen are brought up to date.
  void _tick() {
    final dt = _watch.elapsedMicroseconds / 1e6;
    _watch.reset();
    if (!paused && stage.openCall == null && !stage.finished) {
      // A long pause of the window does not make the race jump.
      stage.advanceTo(stage.clock + dt.clamp(0.0, 0.25) * speed);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final done = stage.finished;
    if (_feed != null && (now - _sentAt >= 100 || done)) {
      _sentAt = now;
      _send();
    }
    if (now - _shownAt >= 100 || done || stage.openCall != null) {
      _shownAt = now;
      notifyListeners();
    }
    if (done) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _send() {
    final feed = _feed;
    // Until the viewer has the stage, the feed keeps what is to come.
    if (feed == null || !ViewerLink.instance.ready) return;
    ViewerLink.instance.send(
      feed.update(
        speed: speed,
        paused: paused,
        own: [for (final r in own) r.id],
      ),
    );
  }

  /// A message of the viewer: the player gave an order, changed the speed,
  /// paused or answered the radio there.
  void _fromViewer(Map<String, dynamic> m) {
    switch (m['type']) {
      case 'order':
        final o = RiderOrder.values.asNameMap()[m['order']];
        final ids = [
          for (final x in m['riders'] as List? ?? const []) (x as num).toInt(),
        ];
        if (o != null) order(o, ids);
      case 'speed':
        setSpeed((m['value'] as num).toDouble());
      case 'pause':
        paused = m['on'] as bool? ?? !paused;
        notifyListeners();
      case 'answer':
        answer((m['choice'] as num).toInt());
    }
  }

  /// Gives an order to riders of the player's team.
  ///
  /// @param o What they are to do.
  /// @param riders Their ids; the picked riders if empty.
  void order(RiderOrder o, [Iterable<int> riders = const []]) {
    final ids = riders.isEmpty ? selected : riders;
    for (final id in ids) {
      stage.order(id, o);
    }
    notifyListeners();
  }

  /// Answers the radio question the race waits for.
  ///
  /// @param choice Index of the chosen option.
  void answer(int choice) {
    stage.answer(choice);
    _send();
    notifyListeners();
  }

  /// @param s New speed in race seconds per second.
  void setSpeed(double s) {
    speed = s.clamp(1.0, 480.0);
    notifyListeners();
  }

  /// Stops or starts the clock.
  void togglePause() {
    paused = !paused;
    notifyListeners();
  }

  /// Picks a rider for the next order, or drops him.
  void toggle(int riderId) {
    if (!selected.remove(riderId)) selected.add(riderId);
    notifyListeners();
  }

  /// Rides the rest of the stage at once; the sports director answers what
  /// the radio still asks.
  void finishNow() {
    while (!stage.finished) {
      final call = stage.openCall;
      if (call != null) {
        stage.answer(call.suggested);
      } else {
        stage.advanceTo(1e7);
      }
    }
    _send();
    notifyListeners();
  }

  /// Ends the live race: the clock stops, the viewer stops listening.
  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    final link = ViewerLink.instance;
    if (link.onLive == _fromViewer) link.onLive = null;
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
