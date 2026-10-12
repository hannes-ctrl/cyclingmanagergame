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
  if (s == 0) return 'zeitgleich';
  final m = s ~/ 60, rest = s % 60;
  return m == 0
      ? '$s Sekunden zurück'
      : '$m:${rest.toString().padLeft(2, '0')} Minuten zurück';
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
    headline = '${winner.name} gewinnt das Zeitfahren in $place';
  } else if (result.breakSurvived) {
    headline = firstGroup == 1
        ? '${winner.name} vollendet die Flucht als Solist'
        : '${winner.name} gewinnt aus der Ausreißergruppe';
  } else if (firstGroup == 1) {
    headline = '${winner.name} siegt in $place als Solist';
  } else if (firstGroup <= 10) {
    headline = '${winner.name} gewinnt den Sprint einer kleinen Gruppe';
  } else {
    headline = '${winner.name} gewinnt den Massensprint in $place';
  }

  final paragraphs = <String>[];
  final lead =
      StringBuffer('${winner.name} (${winner.team}) hat in $place gewonnen.');
  if (second != null) {
    lead.write(' Zweiter wurde ${second.rider.name} (${second.rider.team}), '
        '${_gap(gapToSecond)}');
    if (p.length > 2) {
      lead.write(', Dritter ${p[2].rider.name} (${p[2].rider.team})');
    }
    lead.write('.');
  }
  if (route.kind == StageKind.road && firstGroup > 10) {
    lead.write(' $firstGroup Fahrer kamen in der ersten Gruppe ins Ziel.');
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
        story.write('Die Gruppe des Tages bildete sich nach '
            '${e.km.round()} Kilometern: ${after(e)}. ');
      case EventType.maxGap:
        story.write(
            'Der größte Vorsprung der Spitze betrug ${after(e)} Minuten. ');
      case EventType.caught:
        final rest = RegExp(r'(\d+)[.,]\d km').firstMatch(e.text)?[1];
        story.write(rest == null
            ? 'Die Ausreißer wurden gestellt. '
            : 'Rund $rest Kilometer vor dem Ziel war die Flucht beendet. ');
      case EventType.gruppetto:
      case EventType.attack:
      case EventType.dropped:
        // These texts are already whole sentences in the present tense.
        story.write('${e.text}. ');
      case EventType.points:
      case EventType.finish:
        break;
    }
  }
  if (result.breakSurvived) {
    story.write('Das Feld kam nicht mehr heran.');
  }
  // Abbreviated first names end in a full stop; no double full stop at the end.
  if (story.isNotEmpty) {
    paragraphs.add(story.toString().trim().replaceAll('..', '.'));
  }

  final close = StringBuffer();
  if (standings != null && standings.general.length > 1) {
    final gc = standings.general;
    close.write(finalStage
        ? '${gc.first.rider.name} (${gc.first.rider.team}) gewinnt '
            '${raceName ?? 'die Rundfahrt'}, ${gc[1].rider.name} wird '
            'Zweiter, ${_gap(gc[1].timeS - gc.first.timeS)}. '
        : 'In der Gesamtwertung führt ${gc.first.rider.name} '
            '(${gc.first.rider.team}), ${gc[1].rider.name} liegt '
            '${_gap(gc[1].timeS - gc.first.timeS)}. ');
  }
  if (teamId != null) {
    final own = p.indexWhere((x) => x.rider.teamId == teamId);
    if (own > 0) {
      close.write('Bester Fahrer des eigenen Teams war ${p[own].rider.name} '
          'auf Platz ${own + 1}.');
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
      team.write('${leader.$2.rider.name} verlor '
          '${rest < 1 ? 'auf dem letzten Kilometer' : '${rest.round()} Kilometer vor dem Ziel'} '
          'den Anschluss an die Favoriten und wurde ${leader.$1 + 1}. ');
    }
    final escapees = [
      for (final x in mine)
        if (x.$3?.inBreak ?? false) x.$2.rider.name,
    ];
    if (escapees.isNotEmpty) {
      team.write('${escapees.join(' und ')} '
          '${escapees.length == 1 ? 'war' : 'waren'} in der Gruppe des Tages. ');
    }
    final worker = mine
        .where((x) => x.$3 != null && !x.$3!.inBreak && x.$3!.role.works)
        .fold<(int, Placing, RiderTrace?)?>(
            null,
            (best, x) =>
                best == null || x.$3!.frontKm > best.$3!.frontKm ? x : best);
    if (worker != null && worker.$3!.frontKm >= 20) {
      team.write('${worker.$2.rider.name} führte das Feld über '
          '${worker.$3!.frontKm.round()} Kilometer an.');
    }
    if (team.isNotEmpty) paragraphs.add(team.toString().trim());
  }
  return RaceArticle(headline, paragraphs);
}
