import 'dart:math';

import 'career.dart';

/// Kind of training camp with its focus, price and effect.
enum CampType {
  altitude('Höhenlager', TrainingFocus.climbing, 260, 0.012),
  classics('Klassiker-Lager', TrainingFocus.classics, 180, 0.006),
  timeTrial('Zeitfahr-Lager', TrainingFocus.timeTrial, 190, 0.006),
  sprint('Sprint-Lager', TrainingFocus.sprint, 170, 0.006),
  base('Grundlagen-Lager', TrainingFocus.stamina, 140, 0.006);

  const CampType(this.label, this.focus, this.costPerDay, this.peak);
  final String label;

  /// Which attributes the camp improves.
  final TrainingFocus focus;

  /// Cost per rider and day in euros.
  final int costPerDay;

  /// Form gain in the weeks after the camp (share of power).
  final double peak;
}

/// One booked training camp.
class Camp {
  Camp(this.type, this.start, this.days, this.riders);
  final CampType type;
  final DateTime start;
  final int days;
  final Set<int> riders;
  bool closed = false;

  /// First day after the camp.
  DateTime get end => start.add(Duration(days: days));

  /// Total cost in euros.
  int get cost => type.costPerDay * days * riders.length;

  /// @param date A day.
  /// @returns Whether the camp is running on that day.
  bool covers(DateTime date) => !date.isBefore(start) && date.isBefore(end);

  /// @param from First day of a period.
  /// @param to Last day of the period.
  /// @returns Whether the camp overlaps the period.
  bool overlaps(DateTime from, DateTime to) =>
      !to.isBefore(start) && from.isBefore(end);
}

/// Training camps of the player's team.
///
/// A camp ties up its riders for its duration, loads them hard, improves the
/// attributes of its focus and raises form between day 6 and day 28 after
/// it. Camps are booked in advance and paid with the next monthly statement.
class Camps {
  Camps(this.c);
  final Career c;
  final all = <Camp>[];

  static const minDays = 7, maxDays = 21, maxRiders = 12;

  /// @param riderId Id of a rider.
  /// @param date A day.
  /// @returns The camp the rider is in on that day, or null.
  Camp? campOf(int riderId, DateTime date) => all
      .where((k) => k.riders.contains(riderId) && k.covers(date))
      .firstOrNull;

  /// @param riderId Id of a rider.
  /// @param from First day of a period.
  /// @param to Last day of the period.
  /// @returns Whether the rider is in a camp at any point of the period.
  bool blocks(int riderId, DateTime from, DateTime to) =>
      all.any((k) => k.riders.contains(riderId) && k.overlaps(from, to));

  /// Form bonus from earlier camps.
  ///
  /// @param riderId Id of a rider.
  /// @param date Day of the race.
  /// @returns A factor on form, 1.0 without a recent camp.
  double peak(int riderId, DateTime date) {
    var best = 0.0;
    for (final k in all) {
      if (!k.riders.contains(riderId)) continue;
      final since = date.difference(k.end).inDays;
      if (since >= 6 && since <= 28) best = max(best, k.type.peak);
    }
    return 1 + best;
  }

  /// Books a camp.
  ///
  /// @param type Kind of camp.
  /// @param start First day.
  /// @param days Duration, [minDays] to [maxDays].
  /// @param riderIds Riders to send, at most [maxRiders].
  /// @returns null on success, otherwise the reason as shown to the player.
  String? book(CampType type, DateTime start, int days, List<int> riderIds) {
    final riders = riderIds.toSet();
    if (start.isBefore(c.today))
      return 'Der Beginn liegt in der Vergangenheit.';
    if (start.year != c.year)
      return 'Lager gibt es nur in der laufenden Saison.';
    if (days < minDays || days > maxDays) {
      return 'Ein Lager dauert $minDays bis $maxDays Tage.';
    }
    if (riders.isEmpty) return 'Kein Fahrer gewählt.';
    if (riders.length > maxRiders) {
      return 'Mehr als $maxRiders Fahrer passen nicht in ein Lager.';
    }
    final end = start.add(Duration(days: days - 1));
    for (final id in riders) {
      final r = c.riderById[id];
      if (r == null || r.teamId != c.teamId) return 'Fahrer nicht im Team.';
      if (c.isBusy(id, start)) {
        return '${r.name} ist zu Beginn des Lagers nicht verfügbar.';
      }
      if (blocks(id, start, end)) {
        return '${r.name} ist in dieser Zeit schon in einem anderen Lager.';
      }
    }
    final camp = Camp(type, start, days, riders);
    if (camp.cost > c.economy.balance) {
      return 'Das Lager kostet ${camp.cost ~/ 1000}.000 €, so viel ist nicht in der Kasse.';
    }
    all.add(camp);
    c.economy.charge(camp.cost.toDouble());
    return null;
  }

  /// Closes camps that end today: the trained attributes go up.
  void daily() {
    for (final k in all) {
      if (k.closed || k.end.isAfter(c.today)) continue;
      k.closed = true;
      final focus = k.type.focus.attributes;
      final coach = c.staff.coachFactor(c.teamId);
      final names = <String>[];
      for (final id in k.riders) {
        final r = c.riderById[id];
        if (r == null || r.teamId != c.teamId) continue;
        final age = c.year - r.born ~/ 10000;
        final byAge = age <= 24
            ? 1.0
            : age <= 28
                ? 0.6
                : age <= 32
                    ? 0.3
                    : 0.1;
        final gain = 0.35 * k.days / 14 * (r.potential / 5) * byAge * coach;
        c.replaceRider(r.withAttributes(r.attributes.adjusted((name, v) =>
            focus.contains(name) ? (v + gain).clamp(50.0, 86.0) : v)));
        names.add(r.name);
      }
      c.inbox.add(Message(
        c.today,
        'Trainer',
        '${k.type.label} beendet',
        'Zurück aus dem Lager: ${names.join(', ')}. Die beste Form ist in '
            'ein bis vier Wochen zu erwarten.',
      ));
    }
  }

  /// @returns All camps as a JSON-encodable list.
  List<dynamic> toJson() => [
        for (final k in all)
          [
            k.type.index,
            k.start.millisecondsSinceEpoch,
            k.days,
            k.riders.toList(),
            k.closed,
          ],
      ];

  /// Replaces the camps with those of a snapshot.
  ///
  /// @param j A list written by [toJson].
  void restore(List<dynamic> j) {
    all
      ..clear()
      ..addAll([
        for (final k in j.cast<List<dynamic>>())
          Camp(
            CampType.values[k[0] as int],
            DateTime.fromMillisecondsSinceEpoch(k[1] as int, isUtc: true),
            k[2] as int,
            (k[3] as List).cast<int>().toSet(),
          )..closed = k[4] as bool,
      ]);
  }
}
