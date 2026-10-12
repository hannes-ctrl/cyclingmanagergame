import 'package:sim/sim.dart';
import 'dart:math';

import 'career.dart';
import 'licence.dart';
import 'points.dart';

/// How the player's team stands with regard to a race.
enum EntryStatus {
  /// Obliged to start: WorldTeams must ride every WorldTour race.
  mandatory('Pflichtstart'),
  entered('Gemeldet'),

  /// Invited, but withdrawn by the player.
  declined('Abgesagt'),

  /// Not invited; applying for a wildcard is possible.
  open('Bewerbung möglich'),
  pending('Bewerbung läuft'),
  accepted('Wildcard erhalten'),
  rejected('Bewerbung abgelehnt'),

  /// Too late to apply, or already ridden without us.
  closed('Meldeschluss vorbei'),
  ineligible('Nicht startberechtigt');

  const EntryStatus(this._label);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);

  /// Whether the team is on the start list.
  bool get starts => this == mandatory || this == entered || this == accepted;
}

/// A wildcard application with the organiser's (still hidden) decision.
class Application {
  Application(this.answer, this.success);

  /// Day on which the organiser answers.
  final DateTime answer;
  final bool success;
  bool revealed = false;
}

/// Entries of the player's team: accept or decline invitations, apply for
/// wildcards.
///
/// Who may start where roughly follows the UCI rules: WorldTour races are
/// mandatory for WorldTeams and open to ProTeams by wildcard; ProSeries and
/// class 1 are open to all three licences, class 2 only to Pro and
/// Continental teams. An organiser decides on an application by team
/// strength, standing of the race and home advantage.
class Entries {
  Entries(this.c);
  final Career c;

  final declined = <int>{};
  final applications = <int, Application>{};

  /// Applications must arrive this many days before the start.
  static const deadlineDays = 21;

  static bool _top(RaceTier t) =>
      t == RaceTier.grandTour ||
      t == RaceTier.monument ||
      t == RaceTier.worldTour;

  /// @param r A race.
  /// @returns Whether the team's licence allows it to start there.
  bool eligible(RaceEntry r) {
    final licence = c.licences.of(c.teamId);
    return switch (r.tier) {
      RaceTier.championship || RaceTier.under23 => false,
      RaceTier.grandTour ||
      RaceTier.monument ||
      RaceTier.worldTour =>
        licence == Licence.worldTour || licence == Licence.pro,
      RaceTier.proSeries || RaceTier.class1 => licence != Licence.other,
      RaceTier.class2 =>
        licence == Licence.pro || licence == Licence.continental,
    };
  }

  /// @param r A race.
  /// @returns Whether the team is obliged to start.
  bool mandatory(RaceEntry r) =>
      _top(r.tier) && c.licences.of(c.teamId) == Licence.worldTour;

  bool _open(RaceEntry r) => r.start.difference(c.today).inDays >= deadlineDays;

  /// @param r A race.
  /// @returns The current state of the team's entry.
  EntryStatus status(RaceEntry r) {
    final id = r.info.id;
    // Championships are entered by the federation, not by the team.
    if (r.tier == RaceTier.championship) return EntryStatus.ineligible;
    final p = c.progress[id];
    if (p != null) {
      return p.riders.any((x) => x.teamId == c.teamId)
          ? (c.isInvited(r) ? EntryStatus.entered : EntryStatus.accepted)
          : EntryStatus.closed;
    }
    if (c.isInvited(r)) {
      return declined.contains(id)
          ? EntryStatus.declined
          : mandatory(r)
              ? EntryStatus.mandatory
              : EntryStatus.entered;
    }
    final a = applications[id];
    if (a != null) {
      return !a.revealed
          ? EntryStatus.pending
          : a.success
              ? EntryStatus.accepted
              : EntryStatus.rejected;
    }
    if (!eligible(r)) return EntryStatus.ineligible;
    return _open(r) && !r.start.isBefore(c.today)
        ? EntryStatus.open
        : EntryStatus.closed;
  }

  /// @param r A race the team is not invited to.
  /// @returns The chance of getting a wildcard, 0 to 1.
  double chance(RaceEntry r) {
    final strengths = [
      for (final id in c.invitedTeams(r)) c.teamStrength(id),
    ]..sort();
    // The yardstick is the weaker teams in the field, not the favourites.
    final reference =
        strengths.isEmpty ? 70.0 : strengths[(strengths.length * 0.2).floor()];
    var p = switch (r.tier) {
      RaceTier.grandTour => 0.25,
      RaceTier.monument => 0.35,
      RaceTier.worldTour => 0.45,
      RaceTier.proSeries => 0.6,
      _ => 0.75,
    };
    p += (c.teamStrength(c.teamId) - reference) * 0.07;
    if (c.teams[c.teamId]?.country == r.info.country) p += 0.2;
    return p.clamp(0.05, 0.95);
  }

  /// Withdraws from a race the team is invited to.
  ///
  /// @param raceId Id of the race.
  /// @returns null on success, otherwise the reason.
  String? decline(int raceId) {
    final r = _race(raceId);
    if (r == null || !c.isInvited(r))
      return tr('Dort sind wir nicht gemeldet.');
    if (mandatory(r))
      return tr('WorldTeams müssen alle WorldTour-Rennen fahren.');
    if (!r.start.isAfter(c.today)) return tr('Das Rennen hat schon begonnen.');
    declined.add(raceId);
    c.refreshEntries(raceId);
    return null;
  }

  /// Takes a withdrawal back.
  ///
  /// @param raceId Id of the race.
  /// @returns null on success, otherwise the reason.
  String? restore(int raceId) {
    final r = _race(raceId);
    if (r == null || !declined.contains(raceId)) return tr('Nicht abgesagt.');
    if (!r.start.isAfter(c.today)) return tr('Das Rennen hat schon begonnen.');
    declined.remove(raceId);
    c.refreshEntries(raceId);
    return null;
  }

  /// Applies for a wildcard. The answer arrives after ten days.
  ///
  /// @param raceId Id of the race.
  /// @returns null on success, otherwise the reason.
  String? apply(int raceId) {
    final r = _race(raceId);
    if (r == null) return tr('Rennen nicht gefunden.');
    if (c.isInvited(r)) return tr('Dort sind wir schon eingeladen.');
    if (applications.containsKey(raceId))
      return tr('Die Bewerbung liegt schon vor.');
    if (!eligible(r))
      return tr('Mit unserer Lizenz dürfen wir dort nicht starten.');
    if (!_open(r)) {
      return tr('Bewerbungen müssen {0} Tage vor dem Start eingehen.',
          [deadlineDays]);
    }
    final rng = Random(c.seed * 31 + raceId * 7 + c.year);
    applications[raceId] = Application(
        c.today.add(const Duration(days: 10)), rng.nextDouble() < chance(r));
    return null;
  }

  RaceEntry? _race(int id) =>
      c.calendar.where((r) => r.info.id == id).firstOrNull;

  /// Applies the player's decisions to a field.
  ///
  /// @param r The race.
  /// @param invited Teams invited before the player's decisions.
  /// @returns The teams that actually start.
  List<int> adjust(RaceEntry r, List<int> invited) {
    final id = r.info.id;
    if (declined.contains(id)) {
      return [
        for (final t in invited)
          if (t != c.teamId) t,
      ];
    }
    final a = applications[id];
    if (a != null && a.success && a.revealed && !invited.contains(c.teamId)) {
      return [...invited, c.teamId];
    }
    return invited;
  }

  /// Reveals the organisers' answers that are due today.
  void daily() {
    for (final e in applications.entries) {
      final a = e.value;
      if (a.revealed || a.answer.isAfter(c.today)) continue;
      a.revealed = true;
      c.refreshEntries(e.key);
      final r = _race(e.key);
      if (r == null) continue;
      c.inbox.add(Message(
        c.today,
        tr('Veranstalter'),
        a.success
            ? tr('Wildcard für {0}', [r.info.name])
            : tr('Keine Wildcard für {0}', [r.info.name]),
        a.success
            ? tr('Wir sind dabei. Das Rennen steht jetzt in der Saisonplanung.')
            : tr('Der Veranstalter hat sich für andere Teams entschieden.'),
        raceId: e.key,
      ));
    }
  }

  /// Clears all decisions at the start of a season.
  void reset() {
    declined.clear();
    applications.clear();
  }

  /// @returns The player's entry decisions as a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'declined': declined.toList(),
        'applications': {
          for (final e in applications.entries)
            '${e.key}': [
              e.value.answer.millisecondsSinceEpoch,
              e.value.success,
              e.value.revealed,
            ],
        },
      };

  /// Replaces the decisions with those of a snapshot.
  ///
  /// @param j A map written by [toJson].
  void load(Map<String, dynamic> j) {
    declined
      ..clear()
      ..addAll((j['declined'] as List).cast<int>());
    applications
      ..clear()
      ..addAll({
        for (final e in (j['applications'] as Map<String, dynamic>).entries)
          int.parse(e.key): Application(
            DateTime.fromMillisecondsSinceEpoch((e.value as List)[0] as int,
                isUtc: true),
            e.value[1] as bool,
          )..revealed = e.value[2] as bool,
      });
  }
}
