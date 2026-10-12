import 'package:sim/sim.dart';

import 'career.dart';
import 'economy.dart';
import 'licence.dart';

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

  /// Pairs professional teams with development teams that carry their name.
  void _link() {
    final pros = [
      for (final t in c.teams.values)
        if (c.licences.of(t.id) == Licence.worldTour ||
            c.licences.of(t.id) == Licence.pro)
          t,
    ];
    final devs = [
      for (final t in c.teams.values)
        if ((t.division == 'Under23' ||
                c.licences.of(t.id) == Licence.continental) &&
            (c.squads[t.id]?.isNotEmpty ?? false))
          t,
    ];
    final pairs = <({int pro, int dev, int score})>[];
    for (final p in pros) {
      final words = _tokens(p.name);
      for (final d in devs) {
        final shared = _tokens(d.name).intersection(words).length;
        if (shared == 0) continue;
        pairs.add((
          pro: p.id,
          dev: d.id,
          score: 3 * shared + (d.country == p.country ? 1 : 0),
        ));
      }
    }
    // Best matches first; ties go to the lower ids so the result is stable.
    pairs.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      final p = a.pro.compareTo(b.pro);
      return p != 0 ? p : a.dev.compareTo(b.dev);
    });
    final taken = <int>{};
    for (final x in pairs) {
      if (links.containsKey(x.pro) || taken.contains(x.dev)) continue;
      links[x.pro] = x.dev;
      taken.add(x.dev);
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

  static const _stop = {
    'team',
    'pro',
    'cycling',
    'development',
    'the',
    'racing'
  };

  static Set<String> _tokens(String name) => {
        for (final w in name.toLowerCase().split(RegExp(r'[^a-z0-9à-ÿ]+')))
          if (w.length >= 3 && !_stop.contains(w)) w,
      };

  /// @returns Teams that qualify as a development team, best match first.
  List<TeamInfo> candidates() {
    final own = c.teams[c.teamId]!;
    final words = _tokens(own.name);
    int score(TeamInfo t) =>
        3 * _tokens(t.name).intersection(words).length +
        (t.country == own.country ? 1 : 0);
    return [
      for (final t in c.teams.values)
        if (t.id != c.teamId &&
            (t.division == 'Under23' ||
                c.licences.of(t.id) == Licence.continental) &&
            (c.squads[t.id]?.isNotEmpty ?? false))
          t,
    ]..sort((a, b) {
        final s = score(b).compareTo(score(a));
        return s != 0
            ? s
            : c.teamStrength(b.id).compareTo(c.teamStrength(a.id));
      });
  }

  /// Chooses another development team.
  ///
  /// @param id Team id, or null for none.
  /// @returns null on success, otherwise the reason.
  String? choose(int? id) =>
      'Das Nachwuchsteam ist fest mit dem Team verbunden und lässt sich '
      'nicht wechseln.';

  /// @param riderId Id of a rider.
  /// @returns Whether he rides for the development team.
  bool has(int riderId) =>
      teamId != null && c.riderById[riderId]?.teamId == teamId;

  /// @param riderId Id of a rider.
  /// @returns Whether he has already been promoted for next season.
  bool promoted(int riderId) =>
      c.economy.contracts[riderId]?.nextTeam == c.teamId;

  /// Promotes a rider of the development team to the professional team for
  /// next season. He always accepts, at the market wage.
  ///
  /// @param riderId Id of the rider.
  /// @returns null on success, otherwise the reason.
  String? promote(int riderId) {
    final r = c.riderById[riderId];
    final k = c.economy.contracts[riderId];
    if (r == null || k == null || !has(riderId)) {
      return 'Er fährt nicht im Nachwuchsteam.';
    }
    if (k.nextTeam == c.teamId) return 'Er ist schon für nächstes Jahr geholt.';
    if (k.nextTeam != null) return 'Er hat schon woanders unterschrieben.';
    if (!c.economy.windowOpen) {
      return 'Verträge für die nächste Saison gibt es erst ab dem 1. August.';
    }
    if (c.economy.squadNextSeason(c.teamId) >= 30) {
      return 'Der Kader für die nächste Saison ist mit 30 Fahrern voll.';
    }
    final wage = c.economy.marketWage(r);
    k
      ..nextTeam = c.teamId
      ..nextWage = wage
      ..nextEnd = c.year + 2;
    c.inbox.add(Message(
      c.today,
      'Nachwuchsteam',
      '${r.name} rückt ${c.year + 1} auf',
      '${c.fullName(r.id)} kommt aus dem Nachwuchsteam und hat bis '
          '${k.nextEnd} unterschrieben.',
    ));
    return null;
  }

  /// At the turn of the season the development team of a professional team
  /// attracts talent: the two most gifted free agents of the new intake join.
  ///
  /// @param freeTeam Id of the pseudo team holding the free agents.
  void intake(int freeTeam) {
    final id = teamId;
    if (id == null) return;
    final pool = [
      for (final r in c.squads[freeTeam] ?? const <SimRider>[])
        if (c.year + 1 - r.born ~/ 10000 <= 20) r,
    ]..sort((a, b) {
        final p = b.potential.compareTo(a.potential);
        return p != 0 ? p : Economy.rating(b).compareTo(Economy.rating(a));
      });
    final names = <String>[];
    for (final r in pool.take(2)) {
      c.economy.move(r, id);
      c.economy.contracts[r.id]!.endYear = c.year + 2;
      names.add(c.fullName(r.id));
    }
    if (names.isEmpty) return;
    c.inbox.add(Message(
      c.today,
      'Nachwuchsteam',
      'Neue Talente im Nachwuchsteam',
      'Neu bei ${team?.name}: ${names.join(', ')}.',
    ));
  }
}
