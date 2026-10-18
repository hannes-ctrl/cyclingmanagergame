import 'dart:convert';
// Renders the main screens with the real data into image files
// (test/goldens) so that layouts can be checked without a running window.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game/game.dart';
import 'package:radmanager/app_state.dart';
import 'package:radmanager/live_race.dart';
import 'package:radmanager/main.dart';
import 'package:radmanager/screens/found_screen.dart';
import 'package:radmanager/settings.dart';
import 'package:radmanager/widgets.dart';
import 'package:sim/sim.dart';

void main() {
  final dataDir = AppState.findDataDir();

  setUpAll(() async {
    // The screens are checked in German; one test below switches to English.
    I18n.lang = Lang.de;
    // The app's own fonts and the icon font of the lucide package.
    Future<void> load(String family, List<String> paths) async {
      final loader = FontLoader(family);
      for (final p in paths) {
        loader.addFont(
          Future.value(ByteData.sublistView(File(p).readAsBytesSync())),
        );
      }
      await loader.load();
    }

    await load('Barlow', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
        'assets/fonts/Barlow-$w.ttf',
    ]);
    await load('Barlow Semi Condensed', [
      for (final w in ['SemiBold', 'Bold'])
        'assets/fonts/BarlowSemiCondensed-$w.ttf',
    ]);
    // Where the package lives is written down by pub.
    final packages =
        (jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
                as Map<String, dynamic>)['packages']
            as List;
    final root = packages
        .cast<Map<String, dynamic>>()
        .where((p) => p['name'] == 'lucide_icons_flutter')
        .map((p) => Uri.parse(p['rootUri'] as String).toFilePath())
        .firstOrNull;
    final lucide = root == null ? null : Directory(root);
    if (lucide != null) {
      await load('packages/lucide_icons_flutter/Lucide', [
        '${lucide.path}/assets/lucide.ttf',
      ]);
    }
    // Icons of the sidebar; without the font only boxes appear.
    final icons = File(
      '${Platform.environment['FLUTTER_ROOT'] ?? ''}'
      '/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  });

  testWidgets('Start menu', skip: dataDir == null, (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(dataDir!, persist: false)..watchLive = false;
    await tester.pumpWidget(
      RadmanagerApp(
        state: state,
        settings: AppSettings(dataDir, persist: false),
        menu: true,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/startmenue.png'),
    );
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('110 %'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/einstellungen.png'),
    );
    await tester.tap(find.text('100 %'));
    await tester.pumpAndSettle();
    // A single race outside the career.
    await tester.tap(find.text('Einzelrennen'));
    await tester.pumpAndSettle();
    expect(find.text('Rennen starten'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/einzelrennen.png'),
    );
    // Continue leads into the game, the sidebar leads back.
    await tester.tap(find.text('FORTSETZEN'));
    await tester.pumpAndSettle();
    expect(find.text('Übersicht'), findsWidgets);
    await tester.tap(find.text('Hauptmenü'));
    await tester.pumpAndSettle();
    expect(find.text('FORTSETZEN'), findsOneWidget);
  });

  testWidgets('Back, forward and keys', skip: dataDir == null, (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(dataDir!, persist: false)..watchLive = false;
    await tester.pumpWidget(RadmanagerApp(state: state));
    await tester.pumpAndSettle();
    bool enabled(String tooltip) =>
        tester
            .widget<InkResponse>(
              find.descendant(
                of: find.byTooltip(tooltip),
                matching: find.byType(InkResponse),
              ),
            )
            .onTap !=
        null;
    const back = 'Zurück (Alt+←, Esc)', forward = 'Vor (Alt+→)';
    expect(enabled(back), isFalse);

    // Page to page: back returns, forward goes there again.
    await tester.tap(find.text('Kalender').first);
    await tester.pumpAndSettle();
    expect(find.text('Saisonziele'), findsNothing);
    expect(enabled(back), isTrue);
    await tester.tap(find.byTooltip(back));
    await tester.pumpAndSettle();
    expect(enabled(back), isFalse);
    expect(enabled(forward), isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(enabled(forward), isFalse);

    // Rider page: the arrow keys step through the squad without filling the
    // history, Escape leads back to the page underneath.
    final first = state.squad[0].id, second = state.squad[1].id;
    state.openRider(first);
    await tester.pumpAndSettle();
    expect(find.text('Fahrerprofil'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(state.riderPage, second);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(state.riderPage, isNull);
    expect(enabled(forward), isTrue);

    // A team page lies on top like a rider page; its riders open from it,
    // and back leads to the team again.
    state.openTeam(state.team.id);
    await tester.pumpAndSettle();
    expect(find.text('Teamprofil'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/team.png'),
    );
    // With the mouse over the table the arrow keys move a cursor through
    // its rows and Enter opens the rider.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(DenseTable<SimRider>)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(state.riderPage, isNotNull);
    expect(state.squad.map((r) => r.id), contains(state.riderPage));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Teamprofil'), findsOneWidget);
    // Shortlist, note and comparison on the rider page.
    state.toggleWatch(second);
    state.compare(first);
    state.openRider(second);
    await tester.pumpAndSettle();
    expect(find.textContaining('Vergleich mit'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Stark am Berg');
    expect(state.career.notes[second], 'Stark am Berg');
    expect(state.career.watch, contains(second));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/fahrer_vergleich.png'),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(state.riderPage, isNull);
    expect(find.text('Teamprofil'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(state.teamPage, isNull);
    state.compare(null);

    // Space is the continue button.
    final day = state.career.today;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    // The days run on other isolates and need real time; between the days
    // the loop yields to the window, which needs a frame here.
    for (var i = 0; i < 1200 && state.busy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.pumpAndSettle();
    expect(state.career.today.isAfter(day) || state.pending != null, isTrue);

    // Ctrl+F opens the rider search.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Fahrersuche'), findsWidgets);
    expect(enabled(back), isTrue);

    // Inbox: mark everything read, then empty it; topics can be muted.
    await tester.tap(find.text('Postfach').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Einstellungen des Postfachs'), findsOneWidget);
    if (state.inbox.isNotEmpty) {
      await tester.tap(find.text('Alle gelesen'));
      await tester.pumpAndSettle();
      expect(state.unread, 0);
      await tester.tap(find.text('Alle löschen'));
      await tester.pumpAndSettle();
      expect(state.inbox, isEmpty);
    }
    state.setTopic('Medizin', false);
    expect(state.career.mutedTopics, contains('Medizin'));
  });

  testWidgets('Debug and rider search', skip: dataDir == null, (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(dataDir!, persist: false)..watchLive = false;
    final settings = AppSettings(dataDir, persist: false)..debug = true;
    await tester.pumpWidget(RadmanagerApp(state: state, settings: settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/debug.png'),
    );
    // In debug mode every rider is known exactly: no ranges in the search.
    await tester.tap(find.text('Fahrersuche').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('–8'), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/fahrersuche_debug.png'),
    );
    // Without debug mode the page is gone and other teams show ranges.
    settings.debug = false;
    await tester.pumpAndSettle();
    expect(find.text('Debug'), findsNothing);
    await tester.tap(find.text('Fahrersuche').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/fahrersuche.png'),
    );
  });

  testWidgets('English', skip: dataDir == null, (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    I18n.lang = Lang.en;
    addTearDown(() => I18n.lang = Lang.de);

    final state = AppState(dataDir!, persist: false)..watchLive = false;
    await tester.pumpWidget(RadmanagerApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(state.next);
      await tester.pumpAndSettle();
      if (state.pending != null) break;
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/en_start.png'),
    );
    for (final (page, file) in [
      ('Squad', 'en_squad'),
      ('Race planner', 'en_planner'),
      ('Inbox', 'en_inbox'),
      ('Transfers', 'en_transfers'),
      ('Finances and goals', 'en_finance'),
    ]) {
      await tester.tap(find.text(page).first);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$file.png'),
      );
    }
  });

  testWidgets('Squad and race report', skip: dataDir == null, (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(dataDir!, persist: false)..watchLive = false;
    await tester.pumpWidget(RadmanagerApp(state: state));
    await tester.pumpAndSettle();
    // Career: "continue" runs until the first message for the player's team.
    // The first race of the team stops the days and asks for a line-up. A sick
    // note may stop them before that, hence several steps.
    for (var i = 0; i < 10 && state.pending == null; i++) {
      await tester.runAsync(state.next);
    }
    await tester.pumpAndSettle();
    expect(state.pending, isNotNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/rennvorbereitung.png'),
    );
    // Forecast: a few quick runs in a separate isolate.
    await tester.runAsync(() async {
      await tester.tap(find.text('Prognose'));
      // The runs take a few seconds, longer on a busy machine.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        await tester.pump();
        if (find.text('Gegner zeigen').evaluate().isNotEmpty) break;
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('Gegner zeigen'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/prognose.png'),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('BESTÄTIGEN UND STARTEN'));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();
    // The sports director calls in over the radio as soon as a road stage is
    // due; after the first answer the radio is switched off so that the rest
    // of the test runs through.
    for (var i = 0; i < 10 && state.radio == null; i++) {
      await tester.runAsync(() async {
        final p = state.pending;
        if (p != null) {
          await state.confirmLineup(p, p.suggestedLineup);
        } else {
          await state.next();
        }
      });
    }
    await tester.pumpAndSettle();
    expect(state.radio, isNotNull);
    if (state.radio != null) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/funk.png'),
      );
      final kind = state.radio!.call.kind;
      await tester.runAsync(() async {
        await tester.tap(find.byType(OutlinedButton).at(1));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
      expect(state.radio?.call.kind, isNot(kind));
    }
    state.delegate('radio', RadioMode.off.name);
    expect(state.radio, isNull);
    await tester.pumpAndSettle();
    expect(state.inbox, isNotEmpty);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/uebersicht.png'),
    );
    await tester.tap(find.text('Postfach').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/postfach.png'),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        final p = state.pending;
        if (p != null) {
          await state.confirmLineup(p, p.suggestedLineup);
        } else {
          await state.next();
        }
      });
    }
    // Stage race in progress with our riders: tactics for the next stage.
    RaceProgress? runningOwn() => state.career.progress.values
        .where(
          (p) =>
              p.race.isStageRace &&
              !p.finished &&
              p.stagesDone > 1 &&
              p.run.riders.any((r) => r.teamId == state.team.id),
        )
        .firstOrNull;
    for (var i = 0; i < 40 && runningOwn() == null; i++) {
      await tester.runAsync(() async {
        final p = state.pending;
        if (p != null) {
          await state.confirmLineup(p, p.suggestedLineup);
        } else {
          await state.next();
        }
      });
    }
    final running = runningOwn();
    expect(running, isNotNull);
    if (running != null) {
      state.focusRace = running.race.info.id;
      await tester.tap(find.text('Rennen').first);
      await tester.pumpAndSettle();
      // What if: a ridden stage once more with different tactics.
      if (find.text('Was wäre wenn?').evaluate().isNotEmpty) {
        await tester.tap(find.text('Was wäre wenn?'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rennen schwer machen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Durchrechnen'));
        await tester.pumpAndSettle();
        // Radio questions of the second run: the last option each time.
        for (
          var i = 0;
          i < 4 && find.text('GEFAHREN').evaluate().isEmpty;
          i++
        ) {
          final options = find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(OutlinedButton),
          );
          await tester.tap(options.at(options.evaluate().length - 2));
          await tester.pumpAndSettle();
        }
        expect(find.text('GEFAHREN'), findsOneWidget);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/waswaerewenn.png'),
        );
        await tester.tap(find.text('Schließen'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Taktik für die nächste Etappe'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/taktik.png'),
      );
      // Pin the approach; the roles stay with the sports director.
      await tester.tap(find.text('Rennen schwer machen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      final wish = state.career.ownWishes[running.race.info.id];
      expect(wish?.approach, Approach.makeHard);
      expect(wish?.roles, isEmpty);
      // Fix everything: the complete plan replaces the pins.
      await tester.tap(find.text('Taktik für die nächste Etappe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alles festlegen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(state.career.ownPlans, contains(running.race.info.id));
      expect(state.career.ownWishes, isNot(contains(running.race.info.id)));
    }

    await tester.tap(find.text('Personal').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/personal.png'),
    );
    // Hire a free staff member.
    final before = state.career.staff.of(state.team.id).length;
    await tester.tap(find.text('Einstellen').first);
    await tester.pumpAndSettle();
    expect(state.career.staff.of(state.team.id).length, before + 1);

    await tester.tap(find.text('Aufgabenverteilung'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(state.career.delegation.training, isTrue);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/aufgaben.png'),
    );
    await tester.tap(find.text('Nachwuchsteam').first);
    await tester.pumpAndSettle();
    expect(state.career.devTeam.teamId, isNotNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/nachwuchs.png'),
    );

    // Book a training camp, then the camp and calendar screens.
    final campStart = state.career.today.add(const Duration(days: 20));
    final campers = state.squad
        .where((r) => !state.career.isBusy(r.id, campStart))
        .take(4)
        .map((r) => r.id)
        .toList();
    expect(state.bookCamp(CampType.altitude, campStart, 10, campers), isNull);
    await tester.tap(find.text('Trainingslager').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/lager.png'),
    );
    await tester.tap(find.text('Kalender').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/kalender.png'),
    );

    await tester.tap(find.text('Finanzen und Ziele'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/finanzen.png'),
    );
    await tester.tap(find.text('Transfers').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markt'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/transfers.png'),
    );

    await tester.tap(find.text('Ranglisten').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/ranglisten.png'),
    );
    await tester.tap(find.text('Lizenzen'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/lizenzen.png'),
    );

    // Race planner: look at the entries, decline a race, apply for a wildcard;
    // then the matrix, in which a cell pencils the rider in.
    await tester.tap(find.text('Rennplaner').first);
    await tester.pumpAndSettle();
    final entries = state.career.entries;
    final declinable = state.career.calendar.firstWhere(
      (r) =>
          entries.status(r) == EntryStatus.entered &&
          r.start.isAfter(state.career.today),
    );
    expect(state.entry(declinable.info.id, 'decline'), isNull);
    expect(entries.status(declinable), EntryStatus.declined);
    expect(state.career.ownRaces, isNot(contains(declinable)));
    final open = state.career.calendar
        .where((r) => entries.status(r) == EntryStatus.open)
        .firstOrNull;
    if (open != null) {
      expect(state.entry(open.info.id, 'apply'), isNull);
      expect(entries.status(open), EntryStatus.pending);
    }
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/rennplaner.png'),
    );
    expect(state.entry(declinable.info.id, 'restore'), isNull);
    await tester.pumpAndSettle();
    expect(entries.status(declinable), EntryStatus.entered);
    await tester.tap(find.text('Fahrer-Matrix'));
    await tester.pumpAndSettle();
    final tourId = state.career.ownRaces
        .firstWhere((r) => r.info.name == 'Tour de France')
        .info
        .id;
    state.toggleProgram(tourId, state.squad.first.id);
    await tester.pumpAndSettle();
    expect(state.career.program[tourId], contains(state.squad.first.id));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/saisonplanung.png'),
    );

    await tester.tap(find.text('Kader').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Form und Training'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/form.png'),
    );
    await tester.tap(find.text('Werte'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/kader.png'),
    );
    // Rider profile: a click on a row opens it.
    await tester.tap(find.text(state.career.fullName(state.squad.first.id)));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/fahrer.png'),
    );
    state.closeRider();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saison'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/kader_saison.png'),
    );

    // Save games: store under a name.
    await tester.tap(find.text('Spielstände').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Testlauf Ansichten');
    await tester.pumpAndSettle();
    await tester.tap(find.text('SPEICHERN'));
    await tester.pumpAndSettle();
    final stored = state
        .saves()
        .where((x) => x.name == 'Testlauf Ansichten')
        .toList();
    expect(stored, hasLength(1));
    addTearDown(() => state.deleteSave(stored.single));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/spielstaende.png'),
    );

    // Light team colour: the interface stays dark, the sidebar takes the
    // secondary colour.
    state.chooseTeam(state.teams.firstWhere((t) => t.abbr == 'UEX'));
    await tester.pumpAndSettle();
    expect(state.colors.side.computeLuminance(), lessThan(0.4));
    expect(state.colors.onSide, Colors.white);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/kader_hell.png'),
    );

    await tester.tap(find.text('Rennen').first);
    await tester.pumpAndSettle();
    final tour = state.races.firstWhere((r) => r.name == 'Tour de France');
    await tester.runAsync(() => state.simulatePreview(tour));
    await tester.pumpAndSettle();
    expect(state.runOf(tour)!.result.stages.length, 21);
    await tester.tap(find.text('20').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/rennbericht.png'),
    );
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/rennverlauf.png'),
    );
    await tester.tap(find.text('Unser Team'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/rennen_team.png'),
    );
    // What the power meters showed.
    await tester.tap(find.text('Leistung').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/leistung.png'),
    );
    // The stage in fast motion, halfway.
    await tester.tap(find.text('Zeitraffer').first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(30, 0));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/zeitraffer.png'),
    );
    // The same stage live, a good way into it, a rider told to ride tempo.
    final run = state.runOf(tour)!;
    final live = LiveRace(
      state,
      info: tour,
      stageIndex: 19,
      stageNumber: run.stages[19].number,
      riders: run.riders,
      standings: run.result.standings,
      stage: liveStage(
        run.routes[19],
        run.riders,
        seed: 7,
        radioTeam: state.team.id,
      ),
    )..started = true;
    live.stage.advanceTo(3 * 3600);
    live.toggle(live.own.first.id);
    live.order(RiderOrder.tempo);
    live.stage.advanceTo(3 * 3600 + 30);
    state.showLive(live);
    await tester.pump(const Duration(seconds: 1));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/live.png'),
    );
    state.showLive(null);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Berg'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/bergwertung.png'),
    );

    // Found a team: squad from all riders, licence by strength.
    // The date in the header opens the calendar to simulate up to a day.
    await tester.tap(find.byTooltip('Bis zu einem Datum simulieren'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/simulieren.png'),
    );
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    // Without stops the days run exactly to the chosen date, and the
    // delegation is as before afterwards.
    final target = state.career.today.add(const Duration(days: 25));
    await tester.runAsync(() => state.simulateUntil(target, auto: true));
    await tester.pumpAndSettle();
    expect(state.career.today, target);
    expect(state.career.delegation.lineups, isFalse);
    expect(state.career.delegation.radio, RadioMode.all);
    // Founding a team: from the start menu in the game, opened directly here.
    showFoundScreen(tester.element(find.text('Spielstände').first), state);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('name')), 'RSV Leipzig');
    await tester.enterText(find.byKey(const ValueKey('kuerzel')), 'rsl');
    // The 27 strongest riders of the list: enough for the WorldTour.
    for (var i = 0; i < 27; i++) {
      final box = find.byIcon(Icons.check_box_outline_blank).first;
      await tester.ensureVisible(box);
      await tester.pump();
      await tester.tap(box);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('WorldTeam'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/gruendung.png'),
    );
    await tester.tap(find.text('TEAM GRÜNDEN'));
    await tester.pumpAndSettle();
    expect(state.team.name, 'RSV Leipzig');
    expect(state.squad.length, 27);
    expect(state.career.licences.of(state.team.id), Licence.worldTour);
    expect(
      state.career.ownRaces.map((r) => r.info.name),
      contains('Tour de France'),
    );
    await tester.tap(find.text('Kader').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/kader_eigenes_team.png'),
    );
  });

  testWidgets(
    'Multi-select, bookmarks, vacation and winter plan',
    skip: dataDir == null,
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final state = AppState(dataDir!, persist: false)..watchLive = false;
      await tester.pumpWidget(RadmanagerApp(state: state));
      await tester.pumpAndSettle();

      // Multi-select in the squad: tick one, then all shown, and give all of
      // them a training focus at once.
      await tester.tap(find.text('Kader').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('1 ausgewählt'), findsOneWidget);
      await tester.tap(find.text('Alle angezeigten wählen'));
      await tester.pumpAndSettle();
      expect(find.text('${state.squad.length} ausgewählt'), findsOneWidget);
      await tester.tap(find.text('Trainingsschwerpunkt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zeitfahren').last);
      await tester.pumpAndSettle();
      expect(
        state.squad.every(
          (r) => state.career.shapeOf(r.id).focus == TrainingFocus.timeTrial,
        ),
        isTrue,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/mehrfachauswahl.png'),
      );

      // A bookmark of the squad appears in the sidebar.
      await tester.tap(find.byTooltip('Seite als Lesezeichen (Strg+B)'));
      await tester.pumpAndSettle();
      expect(find.text('LESEZEICHEN'), findsOneWidget);
      expect(state.bookmarks, hasLength(1));

      // The vacation in the calendar of "simulate to".
      await tester.tap(find.byTooltip('Bis zu einem Datum simulieren'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Urlaub:'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Der Assistent antwortet'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/urlaub.png'),
      );
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      // In the winter the rider matrix shows the next season too.
      state.career.racingOver = true;
      await tester.tap(find.text('Rennplaner').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fahrer-Matrix'));
      await tester.pumpAndSettle();
      final next = 'Saison ${state.career.year + 1}';
      expect(find.text(next), findsOneWidget);
      await tester.tap(find.text(next));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/winterplan.png'),
      );
    },
  );

  // Every page and every view in both languages, on a small screen, the
  // usual one, a 4K screen at double scale and a 21:9 one: a page that
  // overflows or throws fails the test.
  for (final (lang, size, ratio) in [
    (Lang.de, const Size(1600, 900), 1.0),
    (Lang.en, const Size(1600, 900), 1.0),
    // The smallest window the app allows.
    (Lang.de, const Size(1280, 760), 1.0),
    (Lang.de, const Size(3840, 2160), 2.0),
    (Lang.en, const Size(3440, 1440), 1.0),
  ]) {
    testWidgets(
      'All pages: ${lang.name} ${size.width.round()}×${size.height.round()}',
      skip: dataDir == null,
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = ratio;
        addTearDown(tester.view.reset);
        I18n.lang = lang;
        addTearDown(() => I18n.lang = Lang.de);
        final settings = AppSettings(dataDir!, persist: false)
          ..debug = true
          ..lang = lang;
        final state = AppState(dataDir, persist: false)..watchLive = false;
        await tester.pumpWidget(
          RadmanagerApp(state: state, settings: settings),
        );
        await tester.pumpAndSettle();
        // A few days, so that there are results, messages and a race.
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(state.next);
          await tester.pumpAndSettle();
          if (state.pending != null) break;
        }
        Future<void> open(String key) async {
          final f = find.text(tr(key));
          // On a low window the sidebar scrolls.
          if (f.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              f,
              80,
              scrollable: find.byType(Scrollable).first,
            );
          }
          expect(f, findsWidgets, reason: key);
          await tester.tap(f.first);
          await tester.pumpAndSettle();
        }

        final views = <String, List<String>>{
          'Home': [],
          'Inbox': [],
          'Squad': ['Form and training', 'Contracts', 'Season'],
          'Development team': [],
          'Training camps': [],
          'Calendar': [],
          'Race planner': ['Rider matrix'],
          'Races': ['Date'],
          'Rankings': ['Breakaways', 'Licences', 'Archive'],
          'Transfers': ['Market'],
          'Rider search': [],
          'Finances and goals': [],
          'Staff': [],
          'Delegation': [],
          'History': ['Seasons', 'Records', 'Retired riders'],
          'Save games': [],
          'Debug': [],
        };
        for (final e in views.entries) {
          await open(e.key);
          for (final view in e.value) {
            await open(view);
          }
        }
        // Rider page and team page lie on top of the pages.
        state.openRider(state.squad.first.id);
        await tester.pumpAndSettle();
        expect(find.text(tr('Rider profile')), findsWidgets);
        state.closeRider();
        state.teamPage = state.career.teams.values
            .firstWhere(
              (t) => t.id != state.team.id && t.division.startsWith('['),
            )
            .id;
        state.goTo('home');
        await tester.pumpAndSettle();
      },
    );
  }
}
