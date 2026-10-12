import 'dart:convert';
// Renders the main screens with the real data into image files
// (test/goldens) so that layouts can be checked without a running window.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game/game.dart';
import 'package:radmanager/app_state.dart';
import 'package:radmanager/main.dart';
import 'package:radmanager/settings.dart';

void main() {
  final dataDir = AppState.findDataDir();

  setUpAll(() async {
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

  testWidgets('Startmenü', skip: dataDir == null, (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(dataDir!, persist: false);
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
    // Continue leads into the game, the sidebar leads back.
    await tester.tap(find.text('FORTSETZEN'));
    await tester.pumpAndSettle();
    expect(find.text('Übersicht'), findsWidgets);
    await tester.tap(find.text('Hauptmenü'));
    await tester.pumpAndSettle();
    expect(find.text('FORTSETZEN'), findsOneWidget);
  });

  testWidgets('Kader und Rennbericht', skip: dataDir == null, (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(dataDir!, persist: false);
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
      await Future<void>.delayed(const Duration(seconds: 8));
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
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(state.career.ownPlans, contains(running.race.info.id));
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
    await tester.tap(find.text('Zurück'));
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
    await tester.runAsync(() => state.simulateTrial(tour));
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
    await tester.tap(find.text('Spielstände').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eigenes Team gründen …'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('name')), 'RSV Leipzig');
    await tester.enterText(find.byKey(const ValueKey('kuerzel')), 'rsl');
    // The 16 strongest riders of the list: enough for the WorldTour.
    for (var i = 0; i < 16; i++) {
      await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
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
    expect(state.squad.length, 16);
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
}
