import 'dart:math';

import 'package:sim/sim.dart';

import 'career.dart';

/// A bike manufacturer as a supplier of teams. The effects are small, as
/// they are in the real peloton: about one per cent of drag between the
/// most and the least aerodynamic bike, a few hundred grams of weight.
class BikeBrand {
  const BikeBrand(this.name, this.aero, this.weightKg, this.prestige);

  /// Name of the brand.
  final String name;

  /// Factor on the drag area; below 1 is faster.
  final double aero;

  /// Weight of the bike above or below the average, in kg.
  final double weightKg;

  /// How much the brand is worth to a team, 1 to 5: the better known, the
  /// more it pays.
  final int prestige;

  /// Quality of the material, 0 to 1, for the stars on the screen.
  double get quality =>
      (0.7 * (1.012 - aero) / 0.027 + 0.3 * (0.25 - weightKg) / 0.4)
          .clamp(0.0, 1.0);
}

/// A tyre manufacturer as a supplier of teams.
class TyreBrand {
  const TyreBrand(this.name, this.rolling, this.punctures, this.prestige);

  /// Name of the brand.
  final String name;

  /// Factor on the rolling resistance; below 1 is faster.
  final double rolling;

  /// Factor on the puncture rate; below 1 punctures less.
  final double punctures;

  /// How much the brand is worth to a team, 1 to 5.
  final int prestige;

  /// Quality of the material, 0 to 1.
  double get quality =>
      (0.6 * (1.03 - rolling) / 0.06 + 0.4 * (1.1 - punctures) / 0.25)
          .clamp(0.0, 1.0);
}

/// The bike brands of the professional peloton.
const bikeBrands = [
  BikeBrand('Specialized', 0.986, 0.0, 5),
  BikeBrand('Cervélo', 0.985, 0.12, 5),
  BikeBrand('Colnago', 0.989, 0.05, 5),
  BikeBrand('Pinarello', 0.988, 0.1, 5),
  BikeBrand('Trek', 0.988, 0.0, 5),
  BikeBrand('Canyon', 0.990, -0.05, 4),
  BikeBrand('Cannondale', 0.992, -0.02, 4),
  BikeBrand('Giant', 0.993, -0.1, 4),
  BikeBrand('Scott', 0.992, -0.12, 4),
  BikeBrand('BMC', 0.991, 0.02, 4),
  BikeBrand('Factor', 0.992, 0.0, 3),
  BikeBrand('Wilier', 0.993, 0.05, 3),
  BikeBrand('Merida', 0.995, 0.0, 3),
  BikeBrand('Look', 0.995, 0.06, 3),
  BikeBrand('Orbea', 0.995, -0.05, 3),
  BikeBrand('Lapierre', 0.997, 0.1, 3),
  BikeBrand('Van Rysel', 0.996, 0.12, 3),
  BikeBrand('Ridley', 0.997, 0.1, 2),
  BikeBrand('Cube', 0.998, 0.06, 2),
  BikeBrand('Bianchi', 0.996, 0.08, 3),
  BikeBrand('Enve', 0.993, 0.0, 3),
  BikeBrand('Argon 18', 0.999, 0.1, 2),
  BikeBrand('BH', 0.999, 0.08, 2),
  BikeBrand('XDS', 1.001, 0.2, 2),
  BikeBrand('Dare', 1.002, 0.2, 2),
  BikeBrand('MMR', 1.004, 0.18, 1),
  BikeBrand('Cipollini', 1.003, 0.22, 1),
  BikeBrand('Basso', 1.006, 0.2, 1),
];

/// The tyre brands of the professional peloton.
const tyreBrands = [
  TyreBrand('Continental', 0.975, 0.95, 5),
  TyreBrand('Vittoria', 0.975, 1.0, 5),
  TyreBrand('Pirelli', 0.98, 0.95, 4),
  TyreBrand('Specialized', 0.98, 1.0, 4),
  TyreBrand('Michelin', 0.99, 0.9, 4),
  TyreBrand('Schwalbe', 0.985, 0.95, 4),
  TyreBrand('Goodyear', 1.0, 0.95, 3),
  TyreBrand('Cadex', 0.985, 1.0, 3),
  TyreBrand('Challenge', 1.02, 0.85, 2),
  TyreBrand('Hutchinson', 1.015, 1.0, 2),
  TyreBrand('Vredestein', 1.02, 1.0, 2),
];

/// Suppliers of the WorldTeams and ProTeams of 2026 by team abbreviation,
/// as far as they were known when the game was made. Teams without an
/// entry get a supplier drawn per career.
const _knownSupply = {
  'APT': ('Canyon', 'Vittoria'),
  'TBV': ('Merida', 'Continental'),
  'DCT': ('Van Rysel', 'Hutchinson'),
  'EFE': ('Cannondale', 'Vittoria'),
  'GFC': ('Wilier', 'Continental'),
  'LTK': ('Trek', 'Pirelli'),
  'LOI': ('Orbea', 'Vittoria'),
  'MOV': ('Canyon', 'Continental'),
  'NSN': ('Factor', 'Pirelli'),
  'NCI': ('Pinarello', 'Continental'),
  'RBH': ('Specialized', 'Specialized'),
  'SOQ': ('Specialized', 'Specialized'),
  'JAY': ('Giant', 'Cadex'),
  'TPP': ('Lapierre', 'Vittoria'),
  'TVL': ('Cervélo', 'Vittoria'),
  'UEX': ('Colnago', 'Continental'),
  'UXM': ('Dare', 'Vredestein'),
  'XAT': ('XDS', 'Continental'),
  'BCS': ('Cipollini', 'Vittoria'),
  'BBH': ('BH', 'Vittoria'),
  'CJR': ('MMR', 'Vittoria'),
  'COF': ('Look', 'Michelin'),
  'EUS': ('Orbea', 'Vittoria'),
  'PQT': ('Pinarello', 'Pirelli'),
  'TFB': ('Ridley', 'Vittoria'),
  'TNN': ('Argon 18', 'Vittoria'),
  'TEN': ('Enve', 'Continental'),
  'TUD': ('BMC', 'Pirelli'),
};

/// A team's suppliers and how long the contracts run.
class Supply {
  Supply(this.bike, this.tyres, this.until, this.fee);

  /// Bike brand.
  BikeBrand bike;

  /// Tyre brand.
  TyreBrand tyres;

  /// Last season of the contracts.
  int until;

  /// What the suppliers pay the team per season, in euros.
  double fee;

  /// @returns The supply as a compact list.
  List<Object> toJson() => [bike.name, tyres.name, until, fee];

  /// @param j A list written by [toJson].
  /// @returns The supply.
  static Supply fromJson(List<dynamic> j) => Supply(
        _bike(j[0] as String),
        _tyre(j[1] as String),
        j[2] as int,
        (j[3] as num).toDouble(),
      );
}

BikeBrand _bike(String name) =>
    bikeBrands.firstWhere((b) => b.name == name, orElse: () => bikeBrands[12]);

TyreBrand _tyre(String name) =>
    tyreBrands.firstWhere((b) => b.name == name, orElse: () => tyreBrands[6]);

/// An offer of a bike and a tyre supplier for the coming seasons.
class SupplyOffer {
  SupplyOffer(this.bike, this.tyres, this.years, this.fee);
  final BikeBrand bike;
  final TyreBrand tyres;
  final int years;

  /// Payment per season, in euros.
  final double fee;

  /// @returns The offer as a compact list.
  List<Object> toJson() => [bike.name, tyres.name, years, fee];

  /// @param j A list written by [toJson].
  /// @returns The offer.
  static SupplyOffer fromJson(List<dynamic> j) => SupplyOffer(
      _bike(j[0] as String),
      _tyre(j[1] as String),
      j[2] as int,
      (j[3] as num).toDouble());
}

/// Material of every team: the suppliers with their contracts, and for the
/// player's team the choices of the race day.
///
/// All teams ride on the material of their suppliers, and the sports
/// director of every team picks tyres and time trial bike by the same
/// rules; the player can overrule his.
class Equipment {
  Equipment(this.c) {
    _generate();
  }

  final Career c;

  /// Suppliers per team id.
  final supply = <int, Supply>{};

  /// Offers for the player's team while its contracts run out.
  final offers = <SupplyOffer>[];

  /// The offer the player accepted; it applies from the next season.
  SupplyOffer? accepted;

  /// The player's choice of tyres per race id; races without one get the
  /// sports director's choice.
  final ownTyres = <int, Tyres>{};

  /// The player's choice of bike for the time trials of a race.
  final ownTimeTrialBike = <int, bool>{};

  /// Payment per season by tier: a WorldTeam is worth more to a brand.
  static double _base(String division) => division.startsWith('[1]')
      ? 900000
      : division.startsWith('[2]')
          ? 300000
          : 70000;

  /// What a supplier pays: the better known the brand, the more; the better
  /// the material, the less, because the brand need not buy its way in.
  static double _fee(String division, BikeBrand b, TyreBrand t, Random r) =>
      (_base(division) * (0.55 + 0.15 * b.prestige - 0.35 * b.quality) +
          0.25 *
              _base(division) *
              (0.55 + 0.15 * t.prestige - 0.35 * t.quality)) *
      (0.9 + 0.2 * r.nextDouble()) ~/
      10000 *
      10000.0;

  void _generate() {
    final rng = Random(c.seed * 23 + 5);
    for (final team in c.teams.values) {
      if (team.division == 'Free') continue;
      final known = _knownSupply[team.abbr];
      final bike = known != null
          ? _bike(known.$1)
          : bikeBrands[rng.nextInt(bikeBrands.length)];
      final tyres = known != null
          ? _tyre(known.$2)
          : tyreBrands[rng.nextInt(tyreBrands.length)];
      supply[team.id] = Supply(bike, tyres, c.year + rng.nextInt(3),
          _fee(team.division, bike, tyres, rng));
    }
  }

  /// @param teamId Id of a team.
  /// @returns Its suppliers; average material for a team without any.
  Supply supplyOf(int teamId) => supply.putIfAbsent(
      teamId, () => Supply(bikeBrands[12], tyreBrands[6], c.year, 0));

  /// Tyres for a stage: the player's choice for his team, otherwise what
  /// the sports director picks.
  ///
  /// @param teamId Id of the team.
  /// @param raceId Id of the race.
  /// @param route The stage.
  /// @param weather Its weather as forecast.
  /// @returns The tyres.
  Tyres tyresFor(int teamId, int raceId, SimRoute route, Weather weather) =>
      (teamId == c.teamId ? ownTyres[raceId] : null) ??
      suggestTyres(route, weather);

  /// Whether a team rides a time trial on the time trial bike.
  ///
  /// @param teamId Id of the team.
  /// @param raceId Id of the race.
  /// @param route The time trial.
  /// @returns true for the time trial bike.
  bool timeTrialBikeFor(int teamId, int raceId, SimRoute route) =>
      (teamId == c.teamId ? ownTimeTrialBike[raceId] : null) ??
      suggestTimeTrialBike(route);

  // --- Contracts --------------------------------------------------------------

  /// On 1 September of the last season of the player's contracts: three
  /// offers for the next seasons, among them the renewal with the current
  /// suppliers. The other teams renew or change on their own at the turn
  /// of the year.
  void daily() {
    final t = c.today;
    final own = supplyOf(c.teamId);
    if (t.month == 9 && t.day == 1 && own.until <= c.year && offers.isEmpty) {
      _offer(own);
    }
  }

  void _offer(Supply own) {
    final rng = Random(c.seed * 41 + c.year);
    final division = c.teams[c.teamId]?.division ?? '[3]';
    offers
      ..clear()
      ..add(SupplyOffer(
          own.bike, own.tyres, 2, _fee(division, own.bike, own.tyres, rng)));
    final taken = {own.bike.name};
    while (offers.length < 3) {
      final b = bikeBrands[rng.nextInt(bikeBrands.length)];
      if (!taken.add(b.name)) continue;
      // A small team does not get the brands of the big ones.
      if (b.prestige >= 5 && !division.startsWith('[1]')) continue;
      final tyre = tyreBrands[rng.nextInt(tyreBrands.length)];
      offers.add(SupplyOffer(
          b, tyre, 1 + rng.nextInt(3), _fee(division, b, tyre, rng)));
    }
    c.inbox.add(Message(
      c.today,
      tr('Board'),
      tr('New material for next season'),
      tr('The contracts with {0} and {1} end with this season. Three suppliers have made offers; you choose under Finances. Without a choice the board renews with the current ones.',
          [own.bike.name, own.tyres.name]),
    ));
  }

  /// The player leaves for another team: his choices of material and the
  /// suppliers' offers end; the new team rides what it has.
  void handOver() {
    offers.clear();
    accepted = null;
    ownTyres.clear();
    ownTimeTrialBike.clear();
  }

  /// Accepts an offer for the next season.
  ///
  /// @param index Position in [offers].
  /// @returns null on success, otherwise the reason.
  String? accept(int index) {
    if (index < 0 || index >= offers.length) {
      return tr('There is no such offer.');
    }
    accepted = offers[index];
    return null;
  }

  /// At the turn of the season: the accepted offer or the renewal applies
  /// to the player's team, the other teams renew or change suppliers.
  void closeSeason() {
    final rng = Random(c.seed * 43 + c.year);
    for (final e in supply.entries) {
      final s = e.value;
      if (s.until > c.year) continue;
      if (e.key == c.teamId) {
        final o = accepted ?? (offers.isNotEmpty ? offers.first : null);
        if (o != null) {
          supply[e.key] = Supply(o.bike, o.tyres, c.year + o.years, o.fee);
        } else {
          s.until = c.year + 2;
        }
        continue;
      }
      // Most stay with their brand; now and then one changes.
      if (rng.nextDouble() < 0.2) {
        s
          ..bike = bikeBrands[rng.nextInt(bikeBrands.length)]
          ..tyres = tyreBrands[rng.nextInt(tyreBrands.length)];
      }
      s.until = c.year + 1 + rng.nextInt(3);
    }
    offers.clear();
    accepted = null;
    ownTyres.clear();
    ownTimeTrialBike.clear();
  }

  // --- Saving -----------------------------------------------------------------

  /// @returns Everything as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'supply': {
          for (final e in supply.entries) '${e.key}': e.value.toJson()
        },
        'offers': [for (final o in offers) o.toJson()],
        if (accepted != null) 'accepted': accepted!.toJson(),
        'tyres': {for (final e in ownTyres.entries) '${e.key}': e.value.index},
        'tt': {
          for (final e in ownTimeTrialBike.entries) '${e.key}': e.value,
        },
      };

  /// @param j A map written by [toJson], or null for a save from before
  ///   teams had suppliers: then the suppliers are drawn as for a new
  ///   career.
  void restore(Map<String, dynamic>? j) {
    supply.clear();
    offers.clear();
    accepted = null;
    ownTyres.clear();
    ownTimeTrialBike.clear();
    if (j == null) {
      _generate();
      return;
    }
    for (final e in (j['supply'] as Map<String, dynamic>).entries) {
      supply[int.parse(e.key)] = Supply.fromJson(e.value as List);
    }
    offers.addAll([
      for (final o in j['offers'] as List) SupplyOffer.fromJson(o as List),
    ]);
    if (j['accepted'] != null) {
      accepted = SupplyOffer.fromJson(j['accepted'] as List);
    }
    for (final e in (j['tyres'] as Map<String, dynamic>).entries) {
      ownTyres[int.parse(e.key)] = Tyres.values[e.value as int];
    }
    for (final e in (j['tt'] as Map<String, dynamic>).entries) {
      ownTimeTrialBike[int.parse(e.key)] = e.value as bool;
    }
  }
}
