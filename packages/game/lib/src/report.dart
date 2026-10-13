import 'package:sim/sim.dart';

/// Race report in the tone of a cycling news site: headline and paragraphs.
class RaceArticle {
  RaceArticle(this.headline, this.paragraphs);
  final String headline;
  final List<String> paragraphs;
}

/// @param seconds A time gap.
/// @returns The gap as German prose, e.g. "1:23 Minuten".
String _gap(double seconds) {
  final s = seconds.round();
  if (s == 0) return tr('zeitgleich');
  final m = s ~/ 60, rest = s % 60;
  return m == 0
      ? tr('{0} Sekunden zurück', [s])
      : tr('{0}:{1} Minuten zurück', [m, rest.toString().padLeft(2, '0')]);
}

/// Writes a neutral report from the result and the events of a stage.
///
/// @param route The stage.
/// @param result Its result.
/// @param standings Adds the state of the general classification for stage races.
/// @param teamId Adds a sentence about this team.
/// @param raceName Name of the race, for the sentence about its winner.
/// @param finalStage Whether this was the last stage of a stage race.
/// @returns The article.
RaceArticle writeArticle({
  required SimRoute route,
  required StageResult result,
  Standings? standings,
  int? teamId,
  String? raceName,
  bool finalStage = false,
}) {
  final p = result.placings;
  final winner = p.first.rider;
  final second = p.length > 1 ? p[1] : null;
  final firstGroup = p.where((x) => x.group == p.first.group).length;
  // The finish town is the part after the separator in the stage name.
  final place = route.name.split(RegExp(r' > | - ')).last.trim();
  final gapToSecond = second == null
      ? 0.0
      : second.timeS.roundToDouble() - p.first.timeS.roundToDouble();

  final String headline;
  if (route.kind != StageKind.road) {
    headline = tr('{0} gewinnt das Zeitfahren in {1}', [winner.name, place]);
  } else if (result.breakSurvived) {
    headline = firstGroup == 1
        ? tr('{0} vollendet die Flucht als Solist', [winner.name])
        : tr('{0} gewinnt aus der Ausreißergruppe', [winner.name]);
  } else if (firstGroup == 1) {
    headline = tr('{0} siegt in {1} als Solist', [winner.name, place]);
  } else if (firstGroup <= 10) {
    headline = tr('{0} gewinnt den Sprint einer kleinen Gruppe', [winner.name]);
  } else {
    headline = tr('{0} gewinnt den Massensprint in {1}', [winner.name, place]);
  }

  final paragraphs = <String>[];
  final lead = StringBuffer(
      tr('{0} ({1}) hat in {2} gewonnen.', [winner.name, winner.team, place]));
  if (second != null) {
    lead.write(tr(' Zweiter wurde {0} ({1}), {2}',
        [second.rider.name, second.rider.team, _gap(gapToSecond)]));
    if (p.length > 2) {
      lead.write(tr(', Dritter {0} ({1})', [p[2].rider.name, p[2].rider.team]));
    }
    lead.write('.');
  }
  if (route.kind == StageKind.road && firstGroup > 10) {
    lead.write(
        tr(' {0} Fahrer kamen in der ersten Gruppe ins Ziel.', [firstGroup]));
  }
  paragraphs.add(lead.toString());

  // Course of the race from the events of the simulation.
  final story = StringBuffer();

  /// @param e An event.
  /// @returns Its text after the leading label.
  String after(RaceEvent e) => e.text.substring(e.text.indexOf(': ') + 2);
  for (final e in result.events) {
    switch (e.type) {
      case EventType.breakaway:
        story.write(tr(
            'Die Gruppe des Tages bildete sich nach {0} Kilometern: {1}. ',
            [e.km.round(), after(e)]));
      case EventType.maxGap:
        story.write(tr('Der größte Vorsprung der Spitze betrug {0} Minuten. ',
            [after(e)]));
      case EventType.caught:
        final rest = RegExp(r'(\d+)[.,]\d km').firstMatch(e.text)?[1];
        story.write(rest == null
            ? tr('Die Ausreißer wurden gestellt. ')
            : tr('Rund {0} Kilometer vor dem Ziel war die Flucht beendet. ',
                [rest]));
      case EventType.weather:
        story.write(tr('Gefahren wurde bei {0}. ', [after(e)]));
      case EventType.gruppetto:
      case EventType.attack:
      case EventType.dropped:
      case EventType.crash:
      case EventType.puncture:
      case EventType.echelon:
      case EventType.abandon:
      case EventType.timeCut:
        // These texts are already whole sentences in the present tense.
        story.write('${e.text}. ');
      case EventType.points:
      case EventType.finish:
        break;
    }
  }
  if (result.breakSurvived) {
    story.write(tr('Das Feld kam nicht mehr heran.'));
  }
  // Abbreviated first names end in a full stop; no double full stop at the end.
  if (story.isNotEmpty) {
    paragraphs.add(story.toString().trim().replaceAll('..', '.'));
  }

  final close = StringBuffer();
  if (standings != null && standings.general.length > 1) {
    final gc = standings.general;
    close.write(finalStage
        ? tr('{0} ({1}) gewinnt {2}, {3} wird Zweiter, {4}. ', [
            gc.first.rider.name,
            gc.first.rider.team,
            raceName ?? tr('die Rundfahrt'),
            gc[1].rider.name,
            _gap(gc[1].timeS - gc.first.timeS)
          ])
        : tr('In der Gesamtwertung führt {0} ({1}), {2} liegt {3}. ', [
            gc.first.rider.name,
            gc.first.rider.team,
            gc[1].rider.name,
            _gap(gc[1].timeS - gc.first.timeS)
          ]));
  }
  if (teamId != null) {
    final own = p.indexWhere((x) => x.rider.teamId == teamId);
    if (own > 0) {
      close.write(tr('Bester Fahrer des eigenen Teams war {0} auf Platz {1}.',
          [p[own].rider.name, own + 1]));
    }
  }
  if (close.isNotEmpty) paragraphs.add(close.toString().trim());

  // How the own team's race went: where the leader lost contact, who was in
  // the break and who did the work.
  if (teamId != null && result.traces.isNotEmpty) {
    final team = StringBuffer();
    final mine = [
      for (var i = 0; i < p.length; i++)
        if (p[i].rider.teamId == teamId)
          (i, p[i], result.traces[p[i].rider.id]),
    ];
    final leader =
        mine.where((x) => x.$3?.role.ridesForHimself ?? false).firstOrNull;
    if (leader != null && leader.$3!.lostKm != null) {
      final rest = route.raceKm - leader.$3!.lostKm!;
      team.write(
          tr('{0} verlor {1} den Anschluss an die Favoriten und wurde {2}. ', [
        leader.$2.rider.name,
        rest < 1
            ? tr('auf dem letzten Kilometer')
            : tr('{0} Kilometer vor dem Ziel', [rest.round()]),
        leader.$1 + 1
      ]));
    }
    final escapees = [
      for (final x in mine)
        if (x.$3?.inBreak ?? false) x.$2.rider.name,
    ];
    if (escapees.isNotEmpty) {
      team.write(tr('{0} {1} in der Gruppe des Tages. ', [
        escapees.join(tr(' und ')),
        escapees.length == 1 ? tr('war') : tr('waren')
      ]));
    }
    final worker = mine
        .where((x) => x.$3 != null && !x.$3!.inBreak && x.$3!.role.works)
        .fold<(int, Placing, RiderTrace?)?>(
            null,
            (best, x) =>
                best == null || x.$3!.frontKm > best.$3!.frontKm ? x : best);
    if (worker != null && worker.$3!.frontKm >= 20) {
      team.write(tr('{0} führte das Feld über {1} Kilometer an.',
          [worker.$2.rider.name, worker.$3!.frontKm.round()]));
    }
    if (team.isNotEmpty) paragraphs.add(team.toString().trim());
  }
  return RaceArticle(headline, paragraphs);
}
