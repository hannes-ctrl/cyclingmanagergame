// Checks material, staff and styles in a career: suppliers for every team,
// styles that differ, kits from material and staff, the weather forecast,
// the warnings before a line-up, supplier offers, the single race, and
// that all of it survives a save.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:game/game.dart';
import 'package:radmanager/app_state.dart';
import 'package:sim/sim.dart';

void main() {
  final dataDir = AppState.findDataDir();

  test(
    'Material, Personal und Teamstile',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 10)),
    () {
      I18n.lang = Lang.de;
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final team = world.teams().firstWhere((t) => t.abbr == 'RBH').id;
      final career = Career(world, teamId: team, seed: 7);

      // Suppliers for every team, the real ones where they are known.
      final supply = career.equipment.supplyOf(team);
      expect(supply.bike.name, 'Specialized');
      expect(supply.tyres.name, 'Specialized');
      expect(supply.fee, greaterThan(0));
      final pros = [
        for (final t in career.teams.values)
          if (t.division.startsWith('[1]') || t.division.startsWith('[2]')) t,
      ];
      for (final t in pros) {
        expect(career.equipment.supply.containsKey(t.id), isTrue);
      }

      // Styles differ between teams.
      expect(
        {for (final t in pros) career.styleOf(t.id)}.length,
        greaterThanOrEqualTo(3),
      );

      // Mechanics and physiotherapists: better in the big teams.
      double mean(String prefix, double Function(int) of) {
        final ids = [
          for (final t in pros)
            if (t.division.startsWith(prefix)) t.id,
        ];
        return ids.fold(0.0, (s, id) => s + of(id)) / ids.length;
      }

      final mech = career.staff.mechanicQuality;
      expect(mean('[1]', mech), greaterThan(mean('[2]', mech)));
      for (final t in pros) {
        expect(mech(t.id), inInclusiveRange(0, 1));
      }

      // A kit from material and staff.
      final race = career.ownRaces.firstWhere(
        (r) => r.tier != RaceTier.championship,
      );
      final route = world.route(race.stages.first.id);
      final kit = career.kitFor(team, race.info.id, route, const Weather());
      expect(kit.aero, supply.bike.aero);
      expect(kit.mechanics, career.staff.mechanicQuality(team));
      expect(kit.style, career.styleOf(team));
      career.equipment.ownTyres[race.info.id] = Tyres.wide;
      expect(
        career.kitFor(team, race.info.id, route, const Weather()).tyres,
        Tyres.wide,
      );
      career.equipment.ownTyres.remove(race.info.id);

      // A forecast that blurs the real weather.
      final forecast = career.forecastOf(race)!;
      expect(forecast.rainChance, inInclusiveRange(0, 100));
      expect(forecast.describe(), isNotEmpty);
      expect(
        forecast.temperatureC,
        closeTo(career.weatherOf(race)!.temperatureC, 15),
      );

      // Warnings: a line-up of three riders leaves places empty.
      final squad = career.squads[team]!;
      final warnings = career.lineupWarnings(race, squad.take(3).toList(), 7);
      expect(warnings.first, tr('Only {0} of {1} places are taken.', [3, 7]));

      // Offers for new material when the contracts run out, and the choice
      // applies from the next season.
      supply.until = career.year;
      career.today = DateTime.utc(career.year, 9, 1);
      career.equipment.daily();
      expect(career.equipment.offers, hasLength(3));
      expect(career.equipment.accept(2), isNull);
      final chosen = career.equipment.offers[2];
      career.equipment.closeSeason();
      expect(career.equipment.supplyOf(team).bike.name, chosen.bike.name);
      expect(career.equipment.supplyOf(team).fee, chosen.fee);

      // An older save without mechanics gets them.
      career.staff.all.removeWhere(
        (s) => s.role == StaffRole.mechanic || s.role == StaffRole.physio,
      );
      career.staff.restore(
        jsonDecode(jsonEncode(career.staff.toJson())) as Map<String, dynamic>,
      );
      expect(career.staff.mechanicQuality(team), greaterThan(0));

      // Material and styles survive a save.
      career.ownStyle = TeamStyle.classics;
      final json =
          jsonDecode(jsonEncode(career.toJson())) as Map<String, dynamic>;
      final copy = Career(world, teamId: team, seed: 7)
        ..restore(json, const []);
      expect(copy.styleOf(team), TeamStyle.classics);
      expect(copy.equipment.supplyOf(team).bike.name, chosen.bike.name);
      for (final t in pros) {
        expect(copy.styleOf(t.id), career.styleOf(t.id));
      }
    },
  );

  test(
    'Einzelrennen außerhalb der Karriere',
    skip: dataDir == null,
    timeout: const Timeout(Duration(minutes: 10)),
    () {
      I18n.lang = Lang.de;
      final world = World('$dataDir/world.sqlite');
      addTearDown(world.close);
      final team = world.teams().firstWhere((t) => t.abbr == 'UXM').id;
      final career = Career(world, teamId: team, seed: 3);
      final race = career.calendar.firstWhere(
        (r) => r.info.name == 'Paris-Roubaix',
        orElse: () => career.calendar.firstWhere(
          (r) => !r.isStageRace && r.tier == RaceTier.monument,
        ),
      );
      List<int> ride(int seed) {
        final single = SingleRace(
          career,
          race,
          seed: seed,
          wish: const PlanWish(approach: Approach.makeHard),
        );
        // The team starts even if the race did not invite it.
        expect(single.riders.any((r) => r.teamId == team), isTrue);
        while (!single.finished) {
          final job = single.nextJob();
          single.take(job, job.run());
        }
        final result = single.run.results.last;
        expect(
          result.power.keys.where((id) => career.riderById[id]?.teamId == team),
          isNotEmpty,
        );
        return [for (final p in result.placings.take(10)) p.rider.id];
      }

      // The same seed rides the same race.
      expect(ride(4), ride(4));
      // The running season is untouched.
      expect(career.progress, isEmpty);
    },
  );
}
