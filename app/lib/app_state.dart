import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import 'settings.dart';
import 'zip.dart';

/// Colours of the user interface, derived from the team colours.
class TeamColors {
  /// Derives the palette.
  ///
  /// The interface is always dark: a light team colour never fills the
  /// sidebar. Then the secondary colour does, or a dark tint of the team
  /// colour if both are light, and the light colour becomes the accent.
  ///
  /// @param team Main team colour.
  /// @param second Secondary team colour.
  TeamColors(Color team, Color second) : side = _sideOf(team, second) {
    onSide = _on(side);
    // The accent is the other team colour; if it hardly stands out from the
    // sidebar, the sidebar's text colour marks the selection instead.
    // If the sidebar took the secondary colour, the main colour is the accent.
    final swapped =
        team.computeLuminance() > 0.4 && second.computeLuminance() <= 0.4;
    accent = (swapped ? [team, second] : [second, team])
        .where(
          (c) => (c.computeLuminance() - side.computeLuminance()).abs() >= 0.12,
        )
        .firstWhere((_) => true, orElse: () => onSide);
    onAccent = _on(accent);
    panel = Color.lerp(ground, side, 0.12)!;
    panel2 = Color.lerp(ground, side, 0.26)!;
    line = Color.lerp(panel2, muted, 0.3)!;
  }

  /// @param team Main team colour.
  /// @param second Secondary team colour.
  /// @returns The colour of the sidebar: the first of the two that is dark.
  static Color _sideOf(Color team, Color second) => _calm(
    team.computeLuminance() <= 0.4
        ? team
        : second.computeLuminance() <= 0.4
        ? second
        : Color.lerp(ground, team, 0.18)!,
  );

  /// Takes the glare out of a colour that fills a large surface: a pure red
  /// or green keeps its hue but becomes darker and less saturated.
  ///
  /// @param color A team colour.
  /// @returns The colour for the sidebar.
  static Color _calm(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.0, 0.72))
        .withLightness(hsl.lightness.clamp(0.0, 0.3))
        .toColor();
  }

  static const ground = Color(0xFF15122A);
  static const text = Color(0xFFEEECF7);
  static const muted = Color(0xFFA59FC8);
  static const gold = Color(0xFFF7D417);
  static const green = Color(0xFF44C285);
  static const red = Color(0xFFEF6258);

  final Color side;
  late final Color onSide;
  late final Color accent;
  late final Color onAccent;
  late final Color panel;
  late final Color panel2;
  late final Color line;

  /// Picks a text colour by the brightness of the surface underneath; white
  /// text would be unreadable on white or yellow team colours.
  ///
  /// @param background Colour of the surface.
  /// @returns Dark or white text colour.
  static Color _on(Color background) =>
      background.computeLuminance() > 0.4 ? ground : Colors.white;

  /// @param rrggbb Colour as six hex digits.
  /// @returns The opaque colour, or a default purple if it cannot be parsed.
  static Color parse(String rrggbb) =>
      Color(0xFF000000 | (int.tryParse(rrggbb, radix: 16) ?? 0x33206E));
}

/// Result of a race of the career with its routes.
class RaceRun {
  RaceRun(this.race, this.stages, this.routes, this.riders, this.result);
  final RaceInfo race;
  final List<StageInfo> stages;
  final List<SimRoute> routes;
  final List<SimRider> riders;

  /// For stage races in progress this only holds the stages ridden so far.
  final StageRaceResult result;
}

/// A named save game in the `saves` folder.
class SaveInfo {
  SaveInfo(this.path, this.name, this.team, this.gameDate, this.savedAt);
  final String path;
  final String name;
  final String team;
  final DateTime gameDate;
  final DateTime savedAt;
}

/// Application state: the career, the save games and everything the screens
/// act on. Screens listen to it and call its methods; it records every
/// decision so that a save can be replayed.
class AppState extends ChangeNotifier {
  AppState(this.dataDir, {this.persist = true, this.saveName = 'savegame.json'})
    : world = World('$dataDir/world.sqlite') {
    teams = world.teams();
    _worldRaces = world.races();
    final saved = _readSave();
    _open(saved);
  }

  /// Starts the career of a save that was read (or a new one); the state
  /// itself is rebuilt afterwards by [restore].
  ///
  /// @param saved Parsed save, or null for a new career.
  void _open(_Saved? saved) {
    teams.removeWhere((t) => t.id == _custom?.id);
    _custom = null;
    _customRiders = null;
    if (saved?.custom case final j?) {
      _custom = _teamFromJson(j);
      _customRiders = (j['riders'] as List?)?.cast<int>();
      teams.add(_custom!);
    }
    // A snapshot continues with the current tuning; only an old replay save
    // needs the values it was played with.
    tuning = saved?.state == null && saved?.tuning != null
        ? saved!.tuning!
        : SimTuning.load('$dataDir/calibration/tuning.json');
    _newCareer(
      teams.firstWhere(
        (t) => saved == null ? t.abbr == 'RBH' : t.id == saved.teamId,
        orElse: () => teams.first,
      ),
      seed: saved?.seed,
      plan: saved?.state == null,
    );
    if (saved?.state case final state?) {
      career.restore(state, saved!.races);
      _refreshRadio();
    } else {
      _replayDays = saved?.days ?? 0;
      _decisions.addAll(saved?.decisions ?? const {});
    }
  }

  /// Progress of the replay while loading, 0 to 1; null if nothing is loading.
  double? get loading =>
      _replayDays > 0 ? (_days / _replayDays).clamp(0.0, 1.0) : null;

  final String dataDir;

  late final _jerseys = world.jerseyKeys();

  /// @param teamId Team id.
  /// @returns The file name key of the team's jersey picture, or an empty
  ///   string if it has none.
  String jerseyOf(int teamId) => _jerseys[teamId] ?? '';

  /// Whether to write the save and load it at start (switched off in tests).
  final bool persist;

  /// File name of the automatic save in the data folder.
  final String saveName;
  final World world;
  late SimTuning tuning;
  late final List<TeamInfo> teams;
  late final List<RaceInfo> _worldRaces;

  /// All races as the running season has them: world and European
  /// championships carry this year's host country.
  List<RaceInfo> get races {
    final now = {for (final r in career.calendar) r.info.id: r.info};
    return [for (final r in _worldRaces) now[r.id] ?? r];
  }

  late TeamInfo team;
  late TeamColors colors;

  /// Squad of the player's team sorted by name, with current attributes.
  List<SimRider> get squad =>
      [...?career.squads[team.id]]
        ..sort((a, b) => a.lastName.compareTo(b.lastName));
  late Career career;

  /// Days are being simulated right now.
  bool busy = false;

  /// Open question of the sports director from one of today's races. While it
  /// is open, the days do not advance.
  ({RaceProgress race, int stageIndex, RadioCall call})? radio;

  /// Race id the race screen should show next (jump from the inbox).
  int? focusRace;

  /// Set when the shell should open the race page, e.g. after the last
  /// radio call of a stage; the shell clears it.
  bool jumpToRace = false;

  /// Debug mode of the app, set by the shell from the settings.
  bool debug = false;

  /// Debug action: adds money to the account without a booking.
  ///
  /// @param amount Euros to add.
  void debugMoney(double amount) {
    career.economy.balance += amount;
    _save();
    notifyListeners();
  }

  /// Debug action: ends every injury and illness in the player's team.
  void debugHeal() {
    for (final r in squad) {
      career.shapeOf(r.id).injuredUntil = null;
    }
    _save();
    notifyListeners();
  }

  /// Rider whose page is open on top of the selected screen, or null.
  int? riderPage;

  /// Page the shell should open next, as "page" or "page:view"; the shell
  /// clears it.
  String? jumpToPage;

  /// Opens a page of the sidebar from anywhere.
  ///
  /// @param target "page" or "page:view", by the names of the sidebar.
  void goTo(String target) {
    jumpToPage = target;
    notifyListeners();
  }

  /// Country the rider search should show next; the search clears it.
  String? searchCountry;

  /// Opens the rider search for the riders of a country.
  ///
  /// @param country Country code, e.g. `BEL`.
  void searchRidersOf(String country) {
    searchCountry = country;
    goTo('search');
  }

  // What the player set on the screens (filters of the rider search) is
  // kept in a small file of its own, apart from the save games: it belongs
  // to the player, not to a career.
  File get _viewFile => File('$dataDir/ui_state.json');
  Map<String, dynamic>? _views;

  /// @param key Name of a screen.
  /// @returns What was remembered for it, or null.
  Map<String, dynamic>? viewOf(String key) {
    if (_views == null) {
      _views = {};
      if (persist) {
        try {
          _views =
              jsonDecode(_viewFile.readAsStringSync()) as Map<String, dynamic>;
        } on Object {
          // No file yet, or an unreadable one: start empty.
        }
      }
    }
    return _views![key] as Map<String, dynamic>?;
  }

  /// Remembers the settings of a screen beyond this session.
  ///
  /// @param key Name of the screen.
  /// @param value Its settings, JSON-encodable.
  void rememberView(String key, Map<String, dynamic> value) {
    viewOf(key);
    if (jsonEncode(_views![key]) == jsonEncode(value)) return;
    _views![key] = value;
    if (!persist) return;
    try {
      _viewFile.writeAsStringSync(jsonEncode(_views));
    } on FileSystemException {
      // Not being able to remember a filter must not stop anything.
    }
  }

  /// Writes a list as a CSV file into the folder `export` next to the save
  /// games. Semicolons separate the columns, as spreadsheet programs with
  /// a German locale expect; the file starts with a byte order mark so that
  /// umlauts survive.
  ///
  /// @param name Start of the file name.
  /// @param headers Column headings.
  /// @param rows The lines.
  /// @returns The path of the file, or null if it could not be written.
  String? exportCsv(
    String name,
    List<String> headers,
    List<List<String>> rows,
  ) {
    String cell(String v) =>
        v.contains(RegExp('[;"\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
    try {
      final dir = Directory('$dataDir/export')..createSync(recursive: true);
      final file = File('${dir.path}/${name}_$stamp.csv');
      file.writeAsStringSync(
        '\uFEFF${[headers, ...rows].map((r) => r.map(cell).join(';')).join('\r\n')}\r\n',
      );
      return file.path;
    } on FileSystemException {
      return null;
    }
  }

  /// Shows the report of a race, closing whatever lies on top.
  ///
  /// @param raceId Id of the race.
  void showRace(int raceId) {
    focusRace = raceId;
    jumpToRace = true;
    notifyListeners();
  }

  /// Where a rider's form is heading: compares his current form with the
  /// last weekly record.
  ///
  /// @param riderId Id of a rider of the player's team.
  /// @returns ' ↗', ' ↘' or ' →'; empty without a record.
  String formTrend(int riderId) {
    final log = career.formLog[riderId];
    if (log == null || log.isEmpty) return '';
    final change = career.shapeOf(riderId).form - log.last[1];
    return change > 0.003
        ? ' ↗'
        : change < -0.003
        ? ' ↘'
        : ' →';
  }

  /// Team whose page is open on top of the selected screen, or null.
  int? teamPage;

  /// Opens the page of a team.
  ///
  /// @param id Id of the team.
  void openTeam(int id) {
    teamPage = id;
    riderPage = null;
    notifyListeners();
  }

  /// Closes the team page.
  void closeTeam() {
    teamPage = null;
    notifyListeners();
  }

  /// Rider the open rider page is compared with, or null.
  int? compareWith;

  /// Remembers a rider for comparison, or forgets him.
  ///
  /// @param id Id of the rider, or null to end the comparison.
  void compare(int? id) {
    compareWith = id;
    notifyListeners();
  }

  /// Lets the sports director plan all coming races anew.
  ///
  /// @returns The number of races planned.
  int replanSeason() {
    final n = career.planSeason(replace: true);
    _save();
    notifyListeners();
    return n;
  }

  /// Makes a race a season goal of a rider, or takes the goal back.
  ///
  /// @param riderId Id of the rider.
  /// @param raceId Id of the race.
  /// @returns null on success, otherwise the reason.
  String? toggleGoal(int riderId, int raceId) {
    final answer = career.people.toggleGoal(riderId, raceId);
    _save();
    notifyListeners();
    return answer;
  }

  /// Promises a rider a start or a leading role in a race.
  ///
  /// @param riderId Id of the rider.
  /// @param raceId Id of the race.
  /// @param kind What is promised.
  /// @returns null on success, otherwise the reason.
  String? promise(int riderId, int raceId, PromiseKind kind) {
    final answer = career.people.promise(riderId, raceId, kind);
    _save();
    notifyListeners();
    return answer;
  }

  /// Gives a rider of the team another standing.
  ///
  /// @param riderId Id of the rider.
  /// @param role His new standing.
  void setTeamRole(int riderId, TeamRole role) {
    career.people.setRole(riderId, role);
    _save();
    notifyListeners();
  }

  /// Puts a rider on the shortlist or takes him off it.
  ///
  /// @param id Id of the rider.
  void toggleWatch(int id) {
    if (!career.watch.remove(id)) career.watch.add(id);
    _save();
    notifyListeners();
  }

  /// Stores the player's note on a rider; an empty note removes it.
  ///
  /// @param id Id of the rider.
  /// @param text The note.
  void setNote(int id, String text) {
    if (text.trim().isEmpty) {
      career.notes.remove(id);
    } else {
      career.notes[id] = text;
    }
    _save();
  }

  /// Riders the open rider page steps through with the arrow keys: the
  /// list he was opened from.
  List<int> riderList = const [];

  /// Set when the rider page moved to a neighbour in [riderList]; the shell
  /// then does not add a step to its history.
  bool riderStepped = false;

  /// Opens the page of a rider.
  ///
  /// @param id Id of the rider.
  /// @param among Ids of the list he is opened from, in its order. Without
  ///   it a rider of the own squad steps through the squad.
  void openRider(int id, {List<int>? among}) {
    riderPage = id;
    final own = [for (final r in squad) r.id];
    riderList = among ?? (own.contains(id) ? own : const []);
    notifyListeners();
  }

  /// Moves the rider page to a neighbour in the list it was opened from.
  ///
  /// @param delta -1 for the rider before, 1 for the one after.
  void stepRider(int delta) {
    final at = riderList.indexOf(riderPage ?? -1);
    final to = at + delta;
    if (at < 0 || to < 0 || to >= riderList.length) return;
    riderPage = riderList[to];
    riderStepped = true;
    notifyListeners();
  }

  /// Closes the rider page.
  void closeRider() {
    riderPage = null;
    notifyListeners();
  }

  /// Day up to which [simulateUntil] is running, or null.
  DateTime? simulatingTo;

  /// Lets the days run until a date. Without [auto] the run stops like the
  /// continue button whenever a line-up or a radio answer is needed; with it
  /// the sports director takes both over until the date is reached.
  ///
  /// @param target Day to stop at.
  /// @param auto Whether line-ups and radio are left to the staff meanwhile.
  /// @param stopTopics Topics of the inbox (keys of [Message.topics]); the
  ///   run stops on the day a message of one of them arrives.
  /// @returns A future that completes when the run has stopped.
  Future<void> simulateUntil(
    DateTime target, {
    bool auto = false,
    Set<String> stopTopics = const {},
  }) async {
    if (busy || career.seasonOver || !target.isAfter(career.today)) return;
    final d = career.delegation;
    final lineups = d.lineups, radioMode = d.radio;
    if (auto) {
      d
        ..lineups = true
        ..radio = RadioMode.off;
    }
    busy = true;
    stopRequested = false;
    simulatingTo = target;
    final from = career.today;
    _runFrom = from;
    final wins = career.economy.wins;
    final points = career.teamPoints[career.teamId] ?? 0;
    final rank = career.economy.ownRank;
    final inboxFrom = career.inbox.length;
    final injured = {
      for (final r in squad)
        if (career.isInjured(r.id, career.today)) r.id,
    };
    radio = null;
    notifyListeners();
    while (career.today.isBefore(target) &&
        !career.seasonOver &&
        !stopRequested) {
      if (d.lineups) {
        _applySavedDecisions();
      } else if (career.needsDecision != null) {
        break;
      }
      radio = await career.nextRadioCallAsync();
      if (radio != null) break;
      final inboxBefore = career.inbox.length;
      await _playDay();
      _days++;
      _autoSave();
      notifyListeners();
      // Something the player wanted to be told about has arrived.
      if (career.inbox
          .skip(
            inboxBefore < career.inbox.length
                ? inboxBefore
                : career.inbox.length,
          )
          .any((m) => stopTopics.contains(m.topicKey))) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }
    if (auto) {
      d
        ..lineups = lineups
        ..radio = radioMode;
    }
    _summarize(from, wins, points, rank, inboxFrom, injured);
    simulatingTo = null;
    _runFrom = null;
    stopRequested = false;
    _save();
    flush();
    busy = false;
    notifyListeners();
  }

  /// Whether the player asked the running days to stop.
  bool stopRequested = false;

  /// First day of the running run to a date.
  DateTime? _runFrom;

  /// Asks the running days to stop after the current one.
  void stopRun() {
    if (!busy) return;
    stopRequested = true;
    notifyListeners();
  }

  /// Share of a run to a date that is done, 0 to 1.
  double get runProgress {
    final to = simulatingTo, from = _runFrom;
    if (to == null || from == null) return 0;
    final all = to.difference(from).inDays;
    return all <= 0
        ? 1
        : (career.today.difference(from).inDays / all).clamp(0.0, 1.0);
  }

  /// Sets the tyres for a race; null leaves them to the sports director.
  ///
  /// @param raceId Id of the race.
  /// @param tyres The tyres.
  void setTyres(int raceId, Tyres? tyres) {
    if (tyres == null) {
      career.equipment.ownTyres.remove(raceId);
    } else {
      career.equipment.ownTyres[raceId] = tyres;
    }
    _save();
    notifyListeners();
  }

  /// Sets the bike for the time trials of a race; null leaves it to the
  /// sports director.
  ///
  /// @param raceId Id of the race.
  /// @param timeTrialBike true for the time trial bike, false for the road bike.
  void setTimeTrialBike(int raceId, bool? timeTrialBike) {
    if (timeTrialBike == null) {
      career.equipment.ownTimeTrialBike.remove(raceId);
    } else {
      career.equipment.ownTimeTrialBike[raceId] = timeTrialBike;
    }
    _save();
    notifyListeners();
  }

  /// Starts building a facility up one level.
  ///
  /// @param f The facility.
  /// @returns null on success, otherwise the reason.
  String? upgradeFacility(Facility f) {
    if (busy) return tr('The days are running right now.');
    final answer = career.facilities.upgrade(f);
    _save();
    notifyListeners();
    return answer;
  }

  /// Accepts a supplier's offer for next season.
  ///
  /// @param index Position among the offers.
  /// @returns null on success, otherwise the reason.
  String? acceptSupply(int index) {
    final answer = career.equipment.accept(index);
    _save();
    notifyListeners();
    return answer;
  }

  /// Sets the style of the player's team; null lets it follow the squad.
  ///
  /// @param style The style.
  void setOwnStyle(TeamStyle? style) {
    career.ownStyle = style;
    _save();
    notifyListeners();
  }

  /// Saves the running state under a name with today's game date.
  ///
  /// @returns null on success, otherwise the reason.
  String? quickSave() => saveAs(
    tr('Quick save {0}', [
      '${career.today.day.toString().padLeft(2, '0')}.'
          '${career.today.month.toString().padLeft(2, '0')}.${career.year}',
    ]),
  );

  /// Writes everything that helps to find a bug into one ZIP file in
  /// `data/export`: the running save, the settings, the tuning values and a
  /// note with version, seed and team.
  ///
  /// @returns The path of the file, or null if it could not be written.
  String? bugReport() {
    try {
      final zip = ZipWriter()
        ..addText(
          'info.txt',
          [
            'Radmanager $appVersion',
            'Seed ${career.seed}',
            'Team ${team.name} (${team.id})',
            'Game date ${career.today.toIso8601String().substring(0, 10)}',
            'Created ${DateTime.now().toIso8601String()}',
            'Dart ${Platform.version}',
            'System ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          ].join('\n'),
        )
        ..addText('savegame.rmsave', _saveText(tr('Bug report')));
      for (final name in [
        'settings.json',
        'ui_state.json',
        'calibration/tuning.json',
      ]) {
        final f = File('$dataDir/$name');
        if (f.existsSync()) zip.add(name, f.readAsBytesSync());
      }
      final dir = Directory('$dataDir/export')..createSync(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 19)
          .replaceAll(':', '-');
      final file = File('${dir.path}/bugreport-$stamp.zip')
        ..writeAsBytesSync(zip.bytes());
      return file.path;
    } on FileSystemException {
      return null;
    }
  }

  /// After a run to a date of a week or more: one message with what
  /// happened, instead of many to read.
  ///
  /// @param from First day of the run.
  /// @param wins Wins of the team before the run.
  /// @param points Points of the team before the run.
  /// @param rank Place in the team ranking before the run.
  /// @param inboxFrom Length of the inbox before the run.
  /// @param injured The team's riders injured before the run.
  void _summarize(
    DateTime from,
    int wins,
    double points,
    int rank,
    int inboxFrom,
    Set<int> injured,
  ) {
    final days = career.today.difference(from).inDays;
    if (days < 7) return;
    final team = career.teamId;
    final newWins = career.economy.wins - wins;
    final gained = (career.teamPoints[team] ?? 0) - points;
    final nowRank = career.economy.ownRank;
    final hurt = [
      for (final r in squad)
        if (career.isInjured(r.id, career.today) && !injured.contains(r.id))
          r.name,
    ];
    final races = career.progress.values
        .where(
          (p) =>
              p.finished &&
              !p.race.start.isBefore(from) &&
              p.riders.any((r) => r.teamId == team),
        )
        .length;
    final byTopic = <String, int>{};
    for (final m in career.inbox.skip(min(inboxFrom, career.inbox.length))) {
      byTopic[m.topic] = (byTopic[m.topic] ?? 0) + 1;
    }
    String day(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
    career.inbox.add(
      Message(
        career.today,
        tr('Board'),
        tr('What happened from {0} to {1}', [day(from), day(career.today)]),
        [
          tr('Races finished: {0}. Wins: {1}.', [races, newWins]),
          tr('Points for the team ranking: +{0}, now place {1} (before {2}).', [
            gained.round(),
            nowRank,
            rank,
          ]),
          if (hurt.isNotEmpty) tr('Injured or ill: {0}.', [hurt.join(', ')]),
          if (byTopic.isNotEmpty)
            tr('Messages: {0}.', [
              byTopic.entries.map((e) => '${e.key} ${e.value}').join(', '),
            ]),
        ].join(' '),
      ),
    );
  }

  /// Removes a message from the inbox.
  ///
  /// @param m The message.
  void deleteMessage(Message m) {
    career.inbox.remove(m);
    _save();
    notifyListeners();
  }

  /// Removes all messages of a topic, or of every topic, read or not.
  ///
  /// @param topic The topic, or null for all.
  void deleteAll(String? topic) {
    career.inbox.removeWhere((m) => topic == null || m.topic == topic);
    _save();
    notifyListeners();
  }

  /// Marks all messages of a topic, or of every topic, as read.
  ///
  /// @param topic The topic, or null for all.
  void markAllRead(String? topic) {
    for (final m in career.inbox) {
      if (topic == null || m.topic == topic) m.read = true;
    }
    _save();
    notifyListeners();
  }

  /// Switches the messages of a topic on or off.
  ///
  /// @param key Key of the topic, one of [Message.topics].
  /// @param on Whether its messages are delivered.
  void setTopic(String key, bool on) {
    on ? career.mutedTopics.remove(key) : career.mutedTopics.add(key);
    _save();
    notifyListeners();
  }

  /// Switches the daily summaries of the inbox on or off.
  void setDigest(bool on) {
    career.inboxDigest = on;
    _save();
    notifyListeners();
  }

  /// Removes all read messages of a topic, or of every topic.
  ///
  /// @param topic The topic, or null for all.
  void deleteRead(String? topic) {
    career.inbox.removeWhere(
      (m) => m.read && (topic == null || m.topic == topic),
    );
    _save();
    notifyListeners();
  }

  var _days = 0;

  /// The player's line-up decisions per race, for the save game.
  final _decisions = <String, Map<String, dynamic>>{};

  /// Time-bound decisions (training, season plan, …) with the day they were
  /// made on, so that a replay applies them on the same day.
  final _log = <Map<String, dynamic>>[];
  var _replayDays = 0;
  final _routes = <int, List<SimRoute>>{};

  /// Looks for the data folder next to the executable or in the folders above.
  ///
  /// @returns The path of the `data` folder, or null if none was found.
  static String? findDataDir() {
    for (final start in [
      File(Platform.resolvedExecutable).parent,
      Directory.current,
    ]) {
      var dir = start;
      for (var i = 0; i < 8; i++) {
        if (File('${dir.path}/data/world.sqlite').existsSync()) {
          return '${dir.path}/data';
        }
        if (dir.parent.path == dir.path) break;
        dir = dir.parent;
      }
    }
    return null;
  }

  /// Starts a career on 1 January.
  ///
  /// @param t The player's team.
  /// @param seed Seed of the career; random if omitted.
  void _newCareer(TeamInfo t, {int? seed, bool plan = true}) {
    team = t;
    colors = TeamColors(TeamColors.parse(t.color), TeamColors.parse(t.color2));
    career = Career(
      world,
      teamId: t.id,
      custom: t.id == _custom?.id ? _custom : null,
      customRiders: t.id == _custom?.id ? _customRiders : null,
      // RADMANAGER_SEED fixes the seed, to reproduce a run.
      seed:
          seed ??
          int.tryParse(Platform.environment['RADMANAGER_SEED'] ?? '') ??
          DateTime.now().millisecondsSinceEpoch % 100000,
      tuning: tuning,
    );
    _days = 0;
    radio = null;
    _decisions.clear();
    _raceCache.clear();
    // The sports director plans the season before the first day; a loaded
    // game brings its plan along.
    if (plan) {
      career.ensureProgram();
      career.inbox.add(
        Message(
          career.today,
          tr('Board'),
          tr('Welcome to {0}', [t.name]),
          tr(
            'The sports director has planned the season; the race planner shows who rides where. "Continue" at the top right lets the days run until something concerns your team. Before every race you confirm the line-up, during the race the sports director calls in over the radio. What the figures mean and which keys there are is under "Help" at the bottom left.',
          ),
        ),
      );
    }
  }

  /// Team founded by the player, if the career runs with one.
  TeamInfo? _custom;
  List<int>? _customRiders;

  static Map<String, dynamic> _teamToJson(TeamInfo t) => {
    'id': t.id,
    'name': t.name,
    'abbr': t.abbr,
    'division': t.division,
    'country': t.country,
    'color': t.color,
    'color2': t.color2,
  };

  static TeamInfo _teamFromJson(Map<String, dynamic> j) => TeamInfo(
    j['id'] as int,
    j['name'] as String,
    j['abbr'] as String,
    j['division'] as String,
    j['country'] as String,
    j['color'] as String,
    j['color2'] as String,
    '',
  );

  /// Founds a team and starts a new career with it.
  ///
  /// @param name Team name.
  /// @param abbr Abbreviation of up to three letters.
  /// @param country Country code.
  /// @param color Main colour as RRGGBB.
  /// @param color2 Secondary colour as RRGGBB.
  /// @param pro Without [riders]: start as a ProTeam instead of Continental.
  /// @param riders Chosen squad; its strength then decides the licence.
  void foundTeam({
    required String name,
    required String abbr,
    required String country,
    required String color,
    required String color2,
    bool pro = false,
    List<SimRider>? riders,
  }) {
    if (busy) return;
    teams.removeWhere((t) => t.id == _custom?.id);
    // With a hand-picked squad its strength decides the licence.
    final division = riders == null
        ? (pro ? '[2] Pro Tour' : '[3] Continental Tour')
        : FoundingRules(teams, world.riders()).divisionFor(riders);
    _customRiders = riders == null ? null : [for (final r in riders) r.id];
    final id = teams.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;
    final t = TeamInfo(id, name, abbr, division, country, color, color2, '');
    _custom = t;
    teams.add(t);
    chooseTeam(t);
  }

  /// Switches team and starts a new career with it on 1 January.
  ///
  /// @param t The new team.
  void chooseTeam(TeamInfo t) {
    if (busy) return;
    tuning = SimTuning.load('$dataDir/calibration/tuning.json');
    _log.clear();
    _newCareer(t);
    _save();
    notifyListeners();
  }

  // --- Save game ---------------------------------------------------------------
  // File format 2 (.rmsave and savegame.json): UTF-8 text, one JSON document
  // per line. Line 1 is a small header (name, team, dates, seed, founded
  // team), line 2 the state of the career, and every further line one race
  // of the season with its riders and results. Loading takes a second or two
  // and does not depend on the simulation code staying the same.
  //
  // Format 1 was a single JSON document with the player's decisions; such a
  // save is still read and rebuilt by replaying it (see [restore]).

  /// File of the automatic save.
  File get _saveFile => File('$dataDir/$saveName');

  /// Encoded races by id, so that a race that has not changed since the
  /// last save is not encoded again. The key guards against stale entries.
  final _raceCache = <int, ({String key, String text})>{};
  Timer? _saveTimer;

  /// Reads a save file of either format.
  ///
  /// @param named File to read; defaults to the automatic save.
  /// @returns The parsed save, or null if there is none or it is unreadable.
  _Saved? _readSave([File? named]) {
    final file = named ?? _saveFile;
    if ((named == null && !persist) || !file.existsSync()) return null;
    try {
      final lines = const LineSplitter().convert(file.readAsStringSync());
      final j = jsonDecode(lines.first) as Map<String, dynamic>;
      if (j['format'] == 2) {
        return (
          teamId: j['teamId'] as int,
          seed: j['seed'] as int,
          days: 0,
          tuning: null,
          decisions: const <String, Map<String, dynamic>>{},
          custom: j['custom'] as Map<String, dynamic>?,
          state: jsonDecode(lines[1]) as Map<String, dynamic>,
          races: [
            for (final l in lines.skip(2))
              if (l.isNotEmpty) jsonDecode(l) as Map<String, dynamic>,
          ],
        );
      }
      _log.addAll([
        for (final e in (j['log'] ?? const []) as List)
          e as Map<String, dynamic>,
      ]);
      return (
        teamId: j['teamId'] as int,
        seed: j['seed'] as int,
        days: j['days'] as int,
        tuning: SimTuning({
          for (final e in (j['tuning'] as Map<String, dynamic>).entries)
            e.key: (e.value as num).toDouble(),
        }),
        decisions: {
          for (final e
              in ((j['decisions'] ?? const {}) as Map<String, dynamic>).entries)
            e.key: e.value as Map<String, dynamic>,
        },
        custom: j['custom'] as Map<String, dynamic>?,
        state: null,
        races: const <Map<String, dynamic>>[],
      );
    } on Object {
      return null;
    }
  }

  /// Encodes the current state as the text of a save file.
  ///
  /// @param name Name shown in the list of saves.
  /// @returns The file contents.
  String _saveText(String name) {
    final out = StringBuffer()
      ..writeln(
        jsonEncode({
          'format': 2,
          'name': name,
          'savedAt': DateTime.now().toIso8601String(),
          'teamName': team.name,
          'gameDate': career.today.toIso8601String(),
          'teamId': team.id,
          'seed': career.seed,
          'custom': ?(team.id == _custom?.id
              ? {..._teamToJson(_custom!), 'riders': ?_customRiders}
              : null),
        }),
      )
      ..writeln(jsonEncode(career.toJson()));
    for (final p in career.progress.values) {
      final id = p.race.info.id;
      // A race changes when a stage is ridden or a rider drops out.
      final key = '${career.year}/${p.stagesDone}/${p.run.riders.length}';
      var cached = _raceCache[id];
      if (cached == null || cached.key != key) {
        cached = (key: key, text: jsonEncode(career.raceJson(p)));
        _raceCache[id] = cached;
      }
      out.writeln(cached.text);
    }
    return out.toString();
  }

  /// Marks the state as changed. The automatic save is written shortly
  /// afterwards, so that a quick series of clicks causes one write.
  void _save() {
    if (!persist) return;
    _saveTimer ??= Timer(const Duration(milliseconds: 700), flush);
  }

  /// Writes the automatic save now if anything changed since the last write.
  void flush() {
    if (_saveTimer == null) return;
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!persist || _replayDays > 0) return;
    _saveFile.writeAsStringSync(_saveText(tr('Automatic')));
  }

  // --- Named saves --------------------------------------------------------------
  // The running state is saved automatically (savegame.json). In addition
  // the player stores named saves in the `saves` folder and loads them from
  // there.

  /// Folder of the named saves.
  Directory get _savesDir => Directory('$dataDir/saves');

  /// @returns The named saves, most recent first.
  List<SaveInfo> saves() {
    if (!_savesDir.existsSync()) return const [];
    final list = <SaveInfo>[];
    for (final f in _savesDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.rmsave')) continue;
      try {
        // Only the header: the first line, or the whole file in format 1.
        final raf = f.openSync();
        final head = utf8.decode(
          raf.readSync(raf.lengthSync() < 65536 ? raf.lengthSync() : 65536),
          allowMalformed: true,
        );
        raf.closeSync();
        final end = head.indexOf('\n');
        final j = jsonDecode(
          end < 0 ? f.readAsStringSync() : head.substring(0, end),
        ) as Map<String, dynamic>;
        list.add(
          SaveInfo(
            f.path,
            j['name'] as String,
            j['teamName'] as String,
            DateTime.parse(j['gameDate'] as String),
            DateTime.parse(j['savedAt'] as String),
          ),
        );
      } on Object {
        // Unreadable file: do not offer it.
      }
    }
    return list..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  /// Stores the current state under a name; a save of the same name is
  /// overwritten.
  ///
  /// @param name Name chosen by the player.
  /// @returns null on success, otherwise the reason.
  String? saveAs(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return tr('The save needs a name.');
    if (busy) return tr('The days are running right now.');
    final file = clean.replaceAll(RegExp(r'[^A-Za-z0-9äöüÄÖÜß _-]'), '_');
    _savesDir.createSync(recursive: true);
    File('${_savesDir.path}/$file.rmsave').writeAsStringSync(_saveText(clean));
    notifyListeners();
    return null;
  }

  /// Plays one day. The stages are simulated on other isolates, all races
  /// of the day at once, so the window stays free meanwhile.
  Future<void> _playDay() async {
    await career.advanceAsync(
      onRaces: (races) {
        working = races.isEmpty
            ? null
            : races.length == 1
            ? races.first.info.name
            : tr('{0} races', [races.length]);
        notifyListeners();
      },
    );
    working = null;
  }

  /// What is being simulated at the moment, for the header: the name of the
  /// race or the number of races; null between the days.
  String? working;

  /// Number of automatic saves kept.
  static const autoSaves = 4;

  /// Writes an automatic save every Monday of the game. The oldest of the
  /// [autoSaves] files is overwritten, so the player can go back up to four
  /// weeks. Called after a day has been played.
  void _autoSave() {
    if (!persist || loading != null) return;
    if (career.today.weekday != DateTime.monday) return;
    final slot =
        career.today.difference(DateTime.utc(2000)).inDays ~/ 7 % autoSaves;
    try {
      _savesDir.createSync(recursive: true);
      File('${_savesDir.path}/auto-${slot + 1}.rmsave').writeAsStringSync(
        _saveText(tr('Automatic · {0}', [_dayText(career.today)])),
      );
    } on FileSystemException {
      // A full disk or a locked file must not stop the game.
    }
  }

  static String _dayText(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Loads a named save. It becomes the running state; the previous one is
  /// lost unless it was saved under a name.
  ///
  /// @param info The save to load.
  /// @returns null on success, otherwise the reason.
  Future<String?> loadSave(SaveInfo info) async {
    if (busy) return tr('The days are running right now.');
    _log.clear();
    final saved = _readSave(File(info.path));
    if (saved == null) return tr('The file cannot be read.');
    _open(saved);
    notifyListeners();
    // Only a save in the old format still has to be replayed.
    await restore();
    _save();
    flush();
    return null;
  }

  /// Deletes a named save from disk.
  ///
  /// @param info The save to delete.
  void deleteSave(SaveInfo info) {
    final f = File(info.path);
    if (f.existsSync()) f.deleteSync();
    notifyListeners();
  }

  /// Rebuilds the saved state after start-up by replaying the career.
  ///
  /// @returns A future that completes when the state is restored.
  Future<void> restore() async {
    if (_replayDays == 0 || busy) return;
    busy = true;
    notifyListeners();
    while (_days < _replayDays) {
      // First the decisions of the day, among them the change of season.
      _applyLog(_days);
      if (career.seasonOver) break;
      _applySavedDecisions();
      career.advance();
      _days++;
      _autoSave();
      if (_days % 5 == 0) {
        notifyListeners();
        await Future<void>.delayed(Duration.zero);
      }
    }
    _applyLog(_days);
    // Line-ups that had already been confirmed on the current day.
    _applySavedDecisions(onlySaved: true);
    _refreshRadio();
    for (final m in career.inbox) {
      m.read = true;
    }
    _replayDays = 0;
    // From now on the save is a snapshot.
    _save();
    flush();
    busy = false;
    notifyListeners();
  }

  /// "Continue": simulates days until something concerns the player's team.
  ///
  /// @returns A future that completes when the days have stopped.
  Future<void> next() async {
    if (busy || career.seasonOver) return;
    busy = true;
    stopRequested = false;
    notifyListeners();
    final before = career.inbox.length;
    for (var i = 0; i < 60 && !career.seasonOver && !stopRequested; i++) {
      // One of our races starts: have the line-up confirmed first, unless the
      // sports director picks it himself.
      if (career.delegation.lineups) {
        _applySavedDecisions();
      } else if (career.needsDecision != null) {
        break;
      }
      // The sports director asks from the race.
      radio = await career.nextRadioCallAsync();
      if (radio != null) break;
      await _playDay();
      _days++;
      _autoSave();
      notifyListeners();
      // Give the user interface room so that the date keeps moving.
      await Future<void>.delayed(Duration.zero);
      if (career.inbox.length > before) break;
    }
    _save();
    flush();
    busy = false;
    notifyListeners();
  }

  /// Applies all logged decisions of one day.
  ///
  /// @param day Day index since the start of the career.
  void _applyLog(int day) {
    for (final e in _log) {
      if (e['day'] == day) _apply(e);
    }
  }

  /// Applies one logged decision to the career.
  ///
  /// @param e Log entry; its `type` selects the action.
  void _apply(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'load':
        career.shapeOf(e['rider'] as int).load = TrainingLoad.values.byName(
          e['load'] as String,
        );
      case 'program':
        final set = career.program.putIfAbsent(e['race'] as int, () => {});
        (e['on'] as bool) ? set.add(e['rider'] as int) : set.remove(e['rider']);
      case 'focus':
        career.shapeOf(e['rider'] as int).focus = TrainingFocus.values.byName(
          e['focus'] as String,
        );
      case 'plan':
        final plan = e['plan'] as Map<String, dynamic>?;
        if (plan == null) {
          career.ownPlans.remove(e['race']);
        } else {
          // A complete plan replaces the pins.
          career.ownWishes.remove(e['race']);
          career.ownPlans[e['race'] as int] = planFromJson(plan);
        }
      case 'wish':
        // A wish replaces whatever applied before; null hands everything
        // back to the sports director.
        final wish = e['wish'] as Map<String, dynamic>?;
        career.ownPlans.remove(e['race']);
        if (wish == null) {
          career.ownWishes.remove(e['race']);
        } else {
          career.ownWishes[e['race'] as int] = PlanWish.fromJson(wish);
        }
      case 'offer':
        career.economy.offer(
          e['rider'] as int,
          e['wage'] as int,
          e['years'] as int,
          promise: e['promise'] == null
              ? null
              : PromiseKind.values[e['promise'] as int],
        );
      case 'offerDev':
        career.economy.offerDev(e['rider'] as int, e['years'] as int);
      case 'hire':
        career.staff.hire(e['staff'] as int);
      case 'fire':
        career.staff.fire(e['staff'] as int);
      case 'scout':
        career.staff.scout(e['rider'] as int);
      case 'autoRenew':
        career.economy.autoRenew = e['on'] as bool;
      case 'radio':
        career.answerRadio(
          e['race'] as int,
          RadioKind.values.byName(e['kind'] as String),
          e['choice'] as int,
        );
      case 'delegate':
        final d = career.delegation;
        switch (e['key']) {
          case 'lineups':
            d.lineups = e['value'] as bool;
          case 'training':
            d.training = e['value'] as bool;
          case 'scouting':
            d.scouting = e['value'] as bool;
          case 'planning':
            d.planning = e['value'] as bool;
            // Taking the job on means planning what is still open.
            career.ensureProgram();
          case 'radio':
            d.radio = RadioMode.values.byName(e['value'] as String);
        }
      case 'camp':
        career.camps.book(
          CampType.values.byName(e['camp'] as String),
          DateTime.utc(career.year, e['month'] as int, e['dayOfMonth'] as int),
          e['days'] as int,
          (e['riders'] as List).cast<int>(),
        );
      case 'sponsor':
        career.economy.acceptSponsor(e['slot'] as int, e['index'] as int);
      case 'sponsorSearch':
        career.economy.searchSponsor(e['slot'] as int);
      case 'entry':
        final id = e['race'] as int;
        switch (e['action']) {
          case 'decline':
            career.entries.decline(id);
          case 'restore':
            career.entries.restore(id);
          case 'apply':
            career.entries.apply(id);
        }
      case 'promote':
        career.devTeam.promote(e['rider'] as int);
      case 'devTeam':
        career.devTeam.choose(e['team'] as int?);
      case 'season':
        if (career.seasonOver) career.startNextSeason();
    }
  }

  /// @param plan A team plan.
  /// @returns The plan as a JSON-encodable map.
  static Map<String, dynamic> planToJson(TeamPlan plan) => {
    'roles': {for (final e in plan.roles.entries) '${e.key}': e.value.name},
    'approach': plan.approach.name,
    'breakPolicy': plan.breakPolicy.name,
  };

  /// @param j A map written by [planToJson].
  /// @returns The plan.
  static TeamPlan planFromJson(Map<String, dynamic> j) => TeamPlan(
    roles: {
      for (final e in (j['roles'] as Map<String, dynamic>).entries)
        int.parse(e.key): Role.values.byName(e.value as String),
    },
    approach: Approach.values.byName(j['approach'] as String),
    breakPolicy: BreakPolicy.values.byName(j['breakPolicy'] as String),
  );

  /// Logs a decision with today's day index, applies it and saves.
  ///
  /// @param e Log entry without the `day` field.
  void _record(Map<String, dynamic> e) {
    if (busy) return;
    e['day'] = _days;
    _log.add(e);
    _apply(e);
    _save();
    notifyListeners();
  }

  /// Sets a rider's training load.
  ///
  /// @param riderId Id of the rider.
  /// @param load New load.
  void setLoad(int riderId, TrainingLoad load) =>
      _record({'type': 'load', 'rider': riderId, 'load': load.name});

  /// Sets the training load of every rider of the squad.
  ///
  /// @param load New load.
  void setLoadAll(TrainingLoad load) {
    for (final r in squad) {
      if (career.shapeOf(r.id).load != load) setLoad(r.id, load);
    }
  }

  /// Sets a rider's training focus.
  ///
  /// @param riderId Id of the rider.
  /// @param focus New focus.
  void setFocus(int riderId, TrainingFocus focus) =>
      _record({'type': 'focus', 'rider': riderId, 'focus': focus.name});

  /// Pins roles and instructions for the remaining stages of a running
  /// race; the sports director plans the rest stage by stage.
  ///
  /// @param raceId Id of the race.
  /// @param wish What is pinned; null hands everything back to the sports
  ///   director.
  void setWish(int raceId, PlanWish? wish) {
    _record({
      'type': 'wish',
      'race': raceId,
      'wish': wish == null || wish.isEmpty ? null : wish.toJson(),
    });
    // With different tactics the stage unfolds differently: ask again.
    if (radio != null) {
      _refreshRadio();
      notifyListeners();
    }
  }

  /// Sets the team's tactics for the remaining stages of a running race.
  ///
  /// @param raceId Id of the race.
  /// @param plan New tactics; null hands the decision back to the sports
  ///   director.
  void setPlan(int raceId, TeamPlan? plan) {
    _record({
      'type': 'plan',
      'race': raceId,
      'plan': plan == null ? null : planToJson(plan),
    });
    // With different tactics the stage unfolds differently: ask again.
    if (radio != null) {
      _refreshRadio();
      notifyListeners();
    }
  }

  /// Offers a young rider a place in the development team.
  ///
  /// @param riderId Id of the rider.
  /// @param years Contract term.
  /// @returns null if he signs, otherwise the reason.
  String? offerDev(int riderId, int years) {
    if (busy) return tr('The days are running right now.');
    final answer = career.economy.offerDev(riderId, years);
    _log.add({
      'type': 'offerDev',
      'rider': riderId,
      'years': years,
      'day': _days,
    });
    _save();
    notifyListeners();
    return answer;
  }

  /// Makes a contract offer to a rider.
  ///
  /// @param riderId Id of the rider.
  /// @param wage Offered wage in euros per year.
  /// @param years Contract term.
  /// @param promise What he is promised for the first season, or null.
  /// @returns null if he signs, otherwise the reason for the refusal.
  String? offer(int riderId, int wage, int years, {PromiseKind? promise}) {
    if (busy) return tr('The days are running right now.');
    final answer = career.economy.offer(riderId, wage, years, promise: promise);
    // Log refusals too: they block the rider for two weeks.
    _log.add({
      'type': 'offer',
      'rider': riderId,
      'wage': wage,
      'years': years,
      if (promise != null) 'promise': promise.index,
      'day': _days,
    });
    _save();
    notifyListeners();
    return answer;
  }

  /// Runs a staff action (hire, dismiss, send a scout) and logs it on success.
  ///
  /// @param type Log type.
  /// @param key Name of the id field in the log entry.
  /// @param id Id passed to the action.
  /// @param action The action; returns null on success.
  /// @returns null on success, otherwise the reason.
  String? _act(String type, String key, int id, String? Function(int) action) {
    if (busy) return tr('The days are running right now.');
    final answer = action(id);
    if (answer == null) {
      _log.add({'type': type, key: id, 'day': _days});
      _save();
    }
    notifyListeners();
    return answer;
  }

  /// @param staffId Id of a staff member on the job market.
  /// @returns null on success, otherwise the reason.
  String? hire(int staffId) =>
      _act('hire', 'staff', staffId, career.staff.hire);

  /// @param staffId Id of a staff member of the team.
  /// @returns null on success, otherwise the reason.
  String? fire(int staffId) =>
      _act('fire', 'staff', staffId, career.staff.fire);

  /// @param riderId Id of the rider to watch.
  /// @returns null on success, otherwise the reason.
  String? scout(int riderId) =>
      _act('scout', 'rider', riderId, career.staff.scout);

  /// Switches automatic contract renewals by the board on or off.
  ///
  /// @param on New setting.
  void setAutoRenew(bool on) => _record({'type': 'autoRenew', 'on': on});

  // --- Radio, delegation, development team ------------------------------------

  /// Looks for an open radio question in today's races.
  void _refreshRadio() {
    radio = career.seasonOver || career.needsDecision != null
        ? null
        : career.nextRadioCall();
  }

  /// Answers the open radio question; afterwards the days continue.
  ///
  /// @param choice Index of the chosen option.
  /// @returns A future that completes when the days have stopped again.
  Future<void> answerRadio(int choice) async {
    final r = radio;
    if (r == null || busy) return;
    radio = null;
    _record({
      'type': 'radio',
      'race': r.race.race.info.id,
      'kind': r.call.kind.name,
      'choice': choice,
    });
    await next();
    // All questions of the day are answered and the stage is ridden: show
    // the result of the race the last question came from.
    if (radio == null && pending == null) {
      focusRace = r.race.race.info.id;
      jumpToRace = true;
      notifyListeners();
    }
  }

  /// Leaves an area to the staff or takes it back.
  ///
  /// @param key Area: `lineups`, `training`, `scouting` or `radio`.
  /// @param value true or false; for the radio the name of the [RadioMode].
  void delegate(String key, Object value) {
    _record({'type': 'delegate', 'key': key, 'value': value});
    _refreshRadio();
    notifyListeners();
  }

  /// Books a training camp.
  ///
  /// @param type Kind of camp.
  /// @param start First day.
  /// @param days Duration in days.
  /// @param riders Ids of the riders to send.
  /// @returns null on success, otherwise the reason.
  String? bookCamp(CampType type, DateTime start, int days, List<int> riders) {
    if (busy) return tr('The days are running right now.');
    final answer = career.camps.book(type, start, days, riders);
    if (answer == null) {
      _log.add({
        'type': 'camp',
        'camp': type.name,
        'month': start.month,
        'dayOfMonth': start.day,
        'days': days,
        'riders': riders,
        'day': _days,
      });
      _save();
    }
    notifyListeners();
    return answer;
  }

  /// Accepts a sponsor offer.
  ///
  /// @param slot Index of the expiring sponsor.
  /// @param index Index of the offer.
  /// @returns null on success, otherwise the reason.
  String? acceptSponsor(int slot, int index) {
    if (busy) return tr('The days are running right now.');
    final answer = career.economy.acceptSponsor(slot, index);
    if (answer == null) {
      _log.add({'type': 'sponsor', 'slot': slot, 'index': index, 'day': _days});
      _save();
    }
    notifyListeners();
    return answer;
  }

  /// Has the board look for a further sponsor offer.
  ///
  /// @param slot Index of the expiring sponsor.
  /// @returns null on success, otherwise the reason.
  String? searchSponsor(int slot) =>
      _act('sponsorSearch', 'slot', slot, career.economy.searchSponsor);

  /// Changes the entry for a race.
  ///
  /// @param raceId Id of the race.
  /// @param action `decline`, `restore` or `apply` (for a wildcard).
  /// @returns null on success, otherwise the reason.
  String? entry(int raceId, String action) {
    if (busy) return tr('The days are running right now.');
    final e = career.entries;
    final answer = switch (action) {
      'decline' => e.decline(raceId),
      'restore' => e.restore(raceId),
      _ => e.apply(raceId),
    };
    if (answer == null) {
      _log.add({
        'type': 'entry',
        'race': raceId,
        'action': action,
        'day': _days,
      });
      _save();
    }
    notifyListeners();
    return answer;
  }

  /// Promotes a rider from the development team for next season.
  ///
  /// @param riderId Id of the rider.
  /// @returns null on success, otherwise the reason.
  String? promote(int riderId) =>
      _act('promote', 'rider', riderId, career.devTeam.promote);

  /// Founds a development team for the player's team.
  ///
  /// @returns null on success, otherwise the reason.
  String? foundDevTeam() {
    if (busy) return tr('The days are running right now.');
    final answer = career.devTeam.found();
    if (answer == null) _save();
    notifyListeners();
    return answer;
  }

  /// Takes a rider of the development team on as a trainee.
  ///
  /// @param riderId Id of the rider.
  /// @returns null on success, otherwise the reason.
  String? takeStagiaire(int riderId) {
    if (busy) return tr('The days are running right now.');
    final answer = career.devTeam.takeStagiaire(riderId);
    if (answer == null) _save();
    notifyListeners();
    return answer;
  }

  /// Chooses another development team.
  ///
  /// @param teamId Team id, or null for none.
  /// @returns null on success, otherwise the reason.
  String? chooseDevTeam(int? teamId) {
    if (busy) return tr('The days are running right now.');
    final answer = career.devTeam.choose(teamId);
    if (answer == null) {
      _log.add({'type': 'devTeam', 'team': teamId, 'day': _days});
      _save();
    }
    notifyListeners();
    return answer;
  }

  /// Computes a pre-race forecast in a separate isolate.
  ///
  /// @param p The waiting race.
  /// @param lineup Own riders chosen so far.
  /// @param plan Own tactics, or null for the sports director's plan.
  /// @returns The forecast.
  Future<Forecast> forecast(
    PendingRace p,
    List<SimRider> lineup,
    TeamPlan? plan,
  ) {
    final routes = p.routes;
    final riders = [...p.others, ...lineup];
    final values = tuning.toMap();
    final plans = plan == null ? const <int, TeamPlan>{} : {team.id: plan};
    final seed = p.race.info.id + career.year;
    return Isolate.run(
      () => forecastRace(
        routes,
        riders,
        plans: plans,
        tuning: SimTuning(values),
        seed: seed,
      ),
    );
  }

  /// Closes the finished season and starts the next.
  void nextSeason() {
    if (career.seasonOver) _record({'type': 'season'});
  }

  /// Pencils a rider in for a race in the season plan, or removes him.
  ///
  /// @param raceId Id of the race.
  /// @param riderId Id of the rider.
  void toggleProgram(int raceId, int riderId) => _record({
    'type': 'program',
    'race': raceId,
    'rider': riderId,
    'on': !(career.program[raceId]?.contains(riderId) ?? false),
  });

  /// Race waiting for the player's line-up.
  PendingRace? get pending =>
      busy || career.delegation.lineups ? null : career.needsDecision;

  /// Key of a line-up decision: races return every year.
  ///
  /// @param raceId Id of the race.
  /// @returns `year:raceId`.
  String _raceKey(int raceId) => '${career.year}:$raceId';

  /// Confirms the line-up and lets the days continue.
  ///
  /// @param race The waiting race.
  /// @param lineup Chosen riders, in the order they were picked.
  /// @param plan Tactics for the whole race; without it the sports director
  ///   decides every stage.
  /// @param directorId Sports director to send; without it the best free one.
  /// @returns A future that completes when the days have stopped again.
  Future<void> confirmLineup(
    PendingRace race,
    List<SimRider> lineup, {
    TeamPlan? plan,
    PlanWish? wish,
    int? directorId,
  }) async {
    _decisions[_raceKey(race.race.info.id)] = {
      'riders': [for (final r in lineup) r.id],
      'plan': ?(plan == null ? null : planToJson(plan)),
      'wish': ?wish?.toJson(),
      'director': ?directorId,
    };
    career.confirm(
      race,
      lineup,
      plan: plan,
      wish: wish,
      directorId: directorId,
    );
    radio = null;
    _save();
    notifyListeners();
    await next();
  }

  /// Re-applies the line-ups of the time while replaying a save.
  ///
  /// @param onlySaved Only confirm races the player had confirmed himself;
  ///   leave the others waiting.
  void _applySavedDecisions({bool onlySaved = false}) {
    for (var p = career.needsDecision; p != null; p = career.needsDecision) {
      final saved = _decisions[_raceKey(p.race.info.id)];
      if (saved == null) {
        if (onlySaved) return;
        career.confirm(p, p.suggestedLineup);
        continue;
      }
      // Same order as back then: it decides which random number goes to which
      // rider, and thus the result.
      final byId = {for (final r in p.available) r.id: r};
      final lineup = [
        for (final id in (saved['riders'] as List).cast<int>()) ?byId[id],
      ];
      final plan = saved['plan'] as Map<String, dynamic>?;
      final wish = saved['wish'] as Map<String, dynamic>?;
      career.confirm(
        p,
        lineup,
        plan: plan == null ? null : planFromJson(plan),
        wish: wish == null ? null : PlanWish.fromJson(wish),
        directorId: saved['director'] as int?,
      );
    }
  }

  /// Messages, newest first.
  List<Message> get inbox => career.inbox.reversed.toList();

  /// Number of unread messages.
  int get unread => career.inbox.where((m) => !m.read).length;

  // --- Races ---------------------------------------------------------------------

  /// @param race A race.
  /// @returns Its stages.
  List<StageInfo> stagesOf(RaceInfo race) =>
      career.calendar.where((r) => r.info.id == race.id).firstOrNull?.stages ??
      world.stages(race.id);

  /// @param race A race.
  /// @returns The routes of its stages, cached.
  List<SimRoute> routesOf(RaceInfo race) {
    final stages = stagesOf(race);
    // The route of a championship changes with its venue, so the first
    // stage belongs to the key.
    return _routes.putIfAbsent(
      Object.hash(race.id, stages.firstOrNull?.id),
      () => [for (final s in stages) world.route(s.id)],
    );
  }

  /// @param race A race.
  /// @returns Its result from the career, otherwise a preview run, otherwise
  ///   null.
  RaceRun? runOf(RaceInfo race) {
    final p = career.progress[race.id];
    if (p != null && p.stagesDone > 0) {
      return RaceRun(
        race,
        stagesOf(race),
        routesOf(race),
        p.riders,
        p.run.result,
      );
    }
    return _previews[race.id];
  }

  // Races simulated outside the career. Nothing in the app starts one any
  // more; the screen tests use it to render a complete race report without
  // playing a season.
  final _previews = <int, RaceRun>{};

  /// Simulates a race outside the career, in a separate isolate. The result
  /// counts for nothing and is shown until the career has ridden the race.
  ///
  /// @param race The race.
  /// @returns A future that completes when the result is available.
  Future<void> simulatePreview(RaceInfo race) async {
    final routes = routesOf(race);
    final riders = world.startList(race.id);
    final values = tuning.toMap();
    final seed = DateTime.now().millisecondsSinceEpoch % 1000000000;
    final result = await Isolate.run(
      () => simulateStageRace(
        routes,
        riders,
        seed: seed,
        tuning: SimTuning(values),
      ),
    );
    _previews[race.id] = RaceRun(race, stagesOf(race), routes, riders, result);
    notifyListeners();
  }
}

/// A save file after parsing. Format 2 fills [state] and [races]; format 1
/// fills days, tuning and decisions instead.
typedef _Saved = ({
  int teamId,
  int seed,
  int days,
  SimTuning? tuning,
  Map<String, Map<String, dynamic>> decisions,
  Map<String, dynamic>? custom,
  Map<String, dynamic>? state,
  List<Map<String, dynamic>> races,
});
