// Exercises championships, training camps, sponsors and a founded team
// without a user interface.
//
// Usage: dart run bin/step8.dart [team abbreviation | NEU]
import 'dart:io';

import 'package:game/game.dart';
import 'package:sim/sim.dart';

void main(List<String> args) {
  final root = Platform.script.resolve('../../../data/').toFilePath();
  final world = World('${root}world.sqlite');
  final abbr = args.isEmpty ? 'RBH' : args[0];
  final tuning = SimTuning.load('${root}calibration/tuning.json');
  final custom = abbr == 'NEU'
      ? TeamInfo(
          world.teams().map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1,
          'Testteam Leipzig',
          'TTL',
          '[3] Continental Tour',
          'GER',
          '204080',
          'F0C000',
          '')
      : null;
  final team = custom ?? world.teams().firstWhere((t) => t.abbr == abbr);
  final c =
      Career(world, teamId: team.id, seed: 5, tuning: tuning, custom: custom)
        ..delegation.radio = RadioMode.off;
  final squad = c.squads[team.id]!;
  print(
      '${team.name}: ${squad.length} Fahrer, Stärke ${c.teamStrength(team.id).toStringAsFixed(1)}, '
      'Budget ${c.economy.budget.round()}, Gehälter ${c.economy.wageBill(team.id)}, '
      '${c.ownRaces.length} Rennen im Programm');
  print(
      'Sponsoren: ${c.economy.sponsors.map((s) => '${s.name} ${s.amount.round()} bis ${s.endYear}').join(' | ')}');
  print(
      'Erste Rennen: ${c.ownRaces.take(6).map((r) => r.info.name).join(' | ')}');

  // Training camp in February for the five best climbers.
  final climbers = [...squad]
    ..sort((a, b) => b.attributes.mountain.compareTo(a.attributes.mountain));
  final ids = climbers.take(5).map((r) => r.id).toList();
  final before = {
    for (final id in ids) id: c.riderById[id]!.attributes.mountain
  };
  print(
      'Lager: ${c.camps.book(CampType.altitude, DateTime.utc(c.year, 2, 2), 14, ids) ?? 'gebucht'}'
      ' · doppelt: ${c.camps.book(CampType.base, DateTime.utc(c.year, 2, 10), 7, ids.take(1).toList())}');

  final watch = Stopwatch()..start();
  var searched = false;
  while (!c.seasonOver) {
    c.advance();
    if (c.today == DateTime.utc(c.year, 2, 5)) {
      print(
          '  5.2. im Lager: ${ids.where((id) => c.isBusy(id, c.today)).length} von 5, '
          'Ermüdung ${c.shapeOf(ids.first).fatigue.round()}');
    }
    if (c.today == DateTime.utc(c.year, 3, 1)) {
      print(
          '  Berg nach dem Lager: ${ids.map((id) => '${before[id]!.toStringAsFixed(1)}→${c.riderById[id]!.attributes.mountain.toStringAsFixed(1)}').join(', ')}'
          ' · Formfaktor ${c.camps.peak(ids.first, c.today)}');
    }
    if (!searched && c.economy.offers.isNotEmpty) {
      searched = true;
      for (final e in c.economy.offers.entries) {
        print('  Angebote für ${c.economy.sponsors[e.key].name}: '
            '${e.value.map((o) => '${o.name} ${o.amount.round()}/${o.years}J${o.demandPlace == null ? '' : ' Platz≤${o.demandPlace}'}').join(' | ')}');
        print('  Suche: ${c.economy.searchSponsor(e.key) ?? 'läuft'}');
      }
    }
    if (c.today == DateTime.utc(c.year, 9, 1) && c.economy.offers.isNotEmpty) {
      final slot = c.economy.offers.keys.first;
      print('  Annehmen (${c.economy.offers[slot]!.length} Angebote): '
          '${c.economy.acceptSponsor(slot, c.economy.offers[slot]!.length - 1) ?? 'ok'}');
    }
  }
  final champs = c.progress.values
      .where((p) => p.race.tier == RaceTier.championship)
      .toList();
  final national =
      champs.where((p) => p.race.info.raceClass.startsWith('National')).length;
  print(
      '\nSaison in ${watch.elapsed.inSeconds} s · ${c.progress.length} Rennen gefahren, '
      'davon ${champs.length} Meisterschaften ($national national)');
  for (final p
      in champs.where((p) => !p.race.info.raceClass.startsWith('National'))) {
    final r = p.run.results.last;
    print('  ${p.race.info.name.padRight(46)} ${p.riders.length} Fahrer · '
        '${r.placings.take(3).map((x) => '${x.rider.name} (${x.rider.team})').join(', ')}');
  }
  final ownTitles =
      c.titles.where((t) => c.riderById[t.riderId]?.teamId == team.id);
  print(
      'Titel fürs Team: ${ownTitles.map((t) => '${c.riderById[t.riderId]!.name}: ${t.race}').join(' | ')}');
  final ranking = c.teamPoints.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  print(
      'Teamrangliste: Platz ${ranking.indexWhere((e) => e.key == team.id) + 1} mit '
      '${(c.teamPoints[team.id] ?? 0).round()} Punkten · Kasse ${c.economy.balance.round()}');
  c.startNextSeason();
  print(
      'Sponsoren ${c.year}: ${c.economy.sponsors.map((s) => '${s.name} ${s.amount.round()} bis ${s.endYear}').join(' | ')}'
      ' · Budget ${c.economy.budget.round()}');
  print(c.inbox.lastWhere((m) => m.subject.startsWith('Saisonbilanz')).body);
  world.close();
}
