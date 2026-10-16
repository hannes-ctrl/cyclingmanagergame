import 'package:sim/sim.dart';

import 'career.dart';
import 'economy.dart';
import 'points.dart';

/// Development team of the player's team.
///
/// The WorldDB does not link professional and development teams; the link is
/// recognised by name and can be changed by the player. The development team
/// rides its own programme. What the professional team gains: its riders are
/// known exactly, can be promoted without negotiation, train under the
/// team's own coaches, and new talents join every year.
class DevTeam {
  DevTeam(this.c) {
    _link();
    teamId = links[c.teamId];
  }

  /// Development team per professional team id. The link is fixed for the
  /// whole career: a professional team has one development team or none,
  /// and a development team belongs to one professional team only.
  final links = <int, int>{};

  /// The real partnerships of the 2026 season: abbreviation of the
  /// development team to that of its professional team. Teams that are not
  /// listed have no development team, and a few development teams of the
  /// database have no professional team.
  static const partners = {
    'APD': 'APT', // Alpecin-Premier Tech Development Team
    'LBK': 'EUS', // BBK-Euskadi
    'BVD': 'TBV', // Bahrain Victorious Development Team
    'CJA': 'CJR', // Caja Rural-Alea
    'DCD': 'DCT', // Decathlon CMA CGM Development Team
    'DPP': 'TPP', // Development Team Picnic PostNL
    'EFA': 'EFE', // EF Education - Aevolo
    'LIZ': 'EKP', // Equipo Finisher
    'CGF': 'GFC', // Groupama-FDJ United Équipe continentale
    'HBG': 'JAY', // Hagens Berman Jayco
    'IGA': 'NCI', // INEOS Grenadiers Racing Academy
    'LTF': 'LTK', // Lidl-Trek Future Racing
    'LWD': 'LOI', // Lotto - Groupe Wanty
    'MOY': 'MOV', // Movistar Team Academy
    'NDT': 'NSN', // NSN Development Team
    'RBC': 'RBH', // Red Bull - BORA - hansgrohe Rookies
    'SQD': 'SOQ', // Soudal Quick-Step Devo Team
    'TFD': 'TFT', // Team NIPPO Nuovacomauto Obor
    'TND': 'TNN', // Team Novo Nordisk Development
    'VLD': 'TVL', // Team Visma | Lease a Bike Development
    'TUU': 'TUD', // Tudor Pro Cycling Team U23
    'UAZ': 'UEX', // UAE Team Emirates Gen-Z
    'VDU': 'TEN', // Vendée U Primeo Energie
    'XAD': 'XAT', // XDS Astana Development Team
  };

  /// Links the development teams of the database to their professional teams.
  void _link() {
    final byAbbr = {for (final t in c.teams.values) t.abbr: t.id};
    for (final e in partners.entries) {
      final dev = byAbbr[e.key], pro = byAbbr[e.value];
      if (dev != null && pro != null) links[pro] = dev;
    }
  }

  /// @param devId Id of a development team.
  /// @returns The professional team it belongs to, or null.
  int? parentOf(int devId) =>
      links.entries.where((e) => e.value == devId).firstOrNull?.key;

  final Career c;
  int? teamId;

  /// Yearly subsidy to the development team.
  static const yearlyCost = 400000.0;

  /// The partner team, or null without one.
  TeamInfo? get team => c.teams[teamId];

  /// Riders of the development team.
  List<SimRider> get squad => [...?c.squads[teamId]];

  /// Yearly cost, 0 without a development team.
  double get cost => teamId == null ? 0 : yearlyCost;

  /// Team founded as a development team during the career, if any; such a
  /// team is not in the world database and has to be saved with the career.
  TeamInfo? founded;

  /// Whether the player's team may found a development team: it has none.
  bool get canFound => teamId == null;

  /// Founds a development team for the player's team: a new under-23 team
  /// with the eight most talented free riders of at most 21 years. The
  /// yearly cost is that of every development team.
  ///
  /// @returns null on success, otherwise the reason.
  String? found() {
    if (!canFound) return tr('The team already has a development team.');
    final own = c.teams[c.teamId]!;
    final free = c.teams.values.where((t) => t.division == 'Free').first.id;
    final id = c.teams.keys.reduce((a, b) => a > b ? a : b) + 1;
    final abbr = own.abbr.length >= 2 ? '${own.abbr.substring(0, 2)}D' : 'DEV';
    final info = TeamInfo(id, '${own.name} Development', abbr, 'Under23',
        own.country, own.color, own.color2, '');
    final pool = [
      for (final r in c.squads[free] ?? const <SimRider>[])
        if (c.year - r.born ~/ 10000 <= 21) r,
    ]..sort((a, b) {
        final p = b.potential.compareTo(a.potential);
        return p != 0 ? p : Economy.rating(b).compareTo(Economy.rating(a));
      });
    if (pool.length < 8)
      return tr('There are not enough young riders without a team.');
    c.teams[id] = info;
    founded = info;
    for (final r in pool.take(8)) {
      c.economy.move(r, id);
      c.economy.contracts[r.id]!.endYear = c.year + 2;
    }
    links[c.teamId] = id;
    teamId = id;
    c.inbox.add(Message(
      c.today,
      tr('Board'),
      tr('Development team founded'),
      tr('{0} starts with eight young riders. It costs {1} a year.',
          [info.name, '${(yearlyCost / 1000).round()}.000 €']),
    ));
    return null;
  }

  // --- Stagiaires ---------------------------------------------------------------
  // From 1 August a professional team may let riders of its own development
  // team ride for it as trainees. They stay with the development team, are
  // not paid by the professional team and may not start in WorldTour races.

  /// Most trainees a team may take per season.
  static const maxStagiaires = 3;

  /// The player's trainees of the running season, by rider id.
  final stagiaires = <int>{};

  /// Whether trainees may ride on a day: from 1 August to the end of the year.
  ///
  /// @param date A day.
  /// @returns true from 1 August on.
  bool window(DateTime date) => date.month >= 8;

  /// Whether a race is open to trainees: everything below the WorldTour,
  /// championships excluded.
  ///
  /// @param tier Tier of the race.
  /// @returns true if trainees may start.
  static bool allows(RaceTier tier) =>
      tier == RaceTier.proSeries ||
      tier == RaceTier.class1 ||
      tier == RaceTier.class2 ||
      tier == RaceTier.under23;

  /// Takes a rider of the development team on as a trainee.
  ///
  /// @param riderId Id of the rider.
  /// @returns null on success, otherwise the reason.
  String? takeStagiaire(int riderId) {
    if (!has(riderId)) return tr('He does not ride for the development team.');
    if (!window(c.today))
      return tr('Stagiaires are only available from 1 August.');
    if (stagiaires.contains(riderId)) return tr('He is already a stagiaire.');
    if (stagiaires.length >= maxStagiaires) {
      return tr('More than {0} stagiaires are not allowed.', [maxStagiaires]);
    }
    stagiaires.add(riderId);
    return null;
  }

  /// The trainees a professional team can call on for a race on a day. The
  /// player chooses his; every other team with a development team takes its
  /// two strongest riders there.
  ///
  /// @param proTeam Id of the professional team.
  /// @param date Day of the race.
  /// @returns The riders, still as members of the development team.
  List<SimRider> stagiairesOf(int proTeam, DateTime date) {
    final dev = links[proTeam];
    if (dev == null || !window(date)) return const [];
    final squad = c.squads[dev] ?? const <SimRider>[];
    if (proTeam == c.teamId) {
      return [
        for (final r in squad)
          if (stagiaires.contains(r.id)) r,
      ];
    }
    return ([...squad]
          ..sort((a, b) => Economy.rating(b).compareTo(Economy.rating(a))))
        .take(2)
        .toList();
  }

  /// Chooses another development team.
  ///
  /// @param id Team id, or null for none.
  /// @returns null on success, otherwise the reason.
  String? choose(int? id) =>
      tr('The development team is tied to the team and cannot be changed.');

  /// @param riderId Id of a rider.
  /// @returns Whether he rides for the development team.
  bool has(int riderId) =>
      teamId != null && c.riderById[riderId]?.teamId == teamId;

  /// @param riderId Id of a rider.
  /// @returns Whether he has already been promoted for next season.
  bool promoted(int riderId) =>
      c.economy.contracts[riderId]?.nextTeam == c.teamId;

  /// Promotes a rider of the development team to the professional team for
  /// next season. He always accepts, at the market wage, if the board
  /// approves it within the wage limit.
  ///
  /// @param riderId Id of the rider.
  /// @returns null on success, otherwise the reason.
  String? promote(int riderId) {
    final r = c.riderById[riderId];
    final k = c.economy.contracts[riderId];
    if (r == null || k == null || !has(riderId)) {
      return tr('He does not ride for the development team.');
    }
    if (k.nextTeam == c.teamId)
      return tr('He has already been signed for next year.');
    if (k.nextTeam != null) return tr('He has already signed elsewhere.');
    if (!c.economy.windowOpen) {
      return tr('Contracts for next season are only available from 1 August.');
    }
    if (c.economy.squadNextSeason(c.teamId) >= 30) {
      return tr('The squad for next season is full with 30 riders.');
    }
    final wage = c.economy.marketWage(r);
    if (c.economy.wageBill(c.teamId, nextSeason: true) + wage >
        c.finances.wageLimit(c.teamId)) {
      return tr(
          'The board does not approve the wage: the wage budget would be exceeded.');
    }
    k
      ..nextTeam = c.teamId
      ..nextWage = wage
      ..nextEnd = c.year + 2;
    c.inbox.add(Message(
      c.today,
      tr('Development team'),
      tr('{0} moves up in {1}', [r.name, c.year + 1]),
      tr('{0} comes from the development team and has signed until {1}.',
          [c.fullName(r.id), k.nextEnd]),
    ));
    return null;
  }

  /// When the new young riders arrive on 1 November, the development team
  /// of the player's team attracts talent: the most gifted of them sign for
  /// next season, as many as the academy brings.
  ///
  /// @param freeTeam Id of the pseudo team holding the free agents.
  void intake(int freeTeam) {
    final id = teamId;
    if (id == null) return;
    final pool = [
      for (final r in c.squads[freeTeam] ?? const <SimRider>[])
        if (c.year + 1 - r.born ~/ 10000 <= 20 &&
            c.economy.contracts[r.id]?.nextTeam == null)
          r,
    ]..sort((a, b) {
        final p = b.potential.compareTo(a.potential);
        return p != 0 ? p : Economy.rating(b).compareTo(Economy.rating(a));
      });
    final names = <String>[];
    // The academy decides how many of the new talents come.
    for (final r in pool.take(c.facilities.academyIntake(c.teamId))) {
      c.economy.contracts[r.id]!
        ..nextTeam = id
        ..nextWage = 20000
        ..nextEnd = c.year + 2;
      names.add(c.fullName(r.id));
    }
    if (names.isEmpty) return;
    c.inbox.add(Message(
      c.today,
      tr('Development team'),
      tr('New talents in the development team'),
      tr('New at {0} from {1}: {2}.',
          [team?.name, c.year + 1, names.join(', ')]),
    ));
  }
}
