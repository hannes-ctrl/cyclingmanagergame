import 'package:sim/sim.dart';

import 'points.dart';

/// Race report in the tone of a cycling news site: headline and paragraphs.
class RaceArticle {
  RaceArticle(this.headline, this.paragraphs);
  final String headline;
  final List<String> paragraphs;
}

/// @param seconds A time gap.
/// @returns The gap as prose, e.g. "1:23 minutes".
String _gap(double seconds) {
  final s = seconds.round();
  if (s == 0) return tr('same time');
  final m = s ~/ 60, rest = s % 60;
  return m == 0
      ? tr('{0} seconds back', [s])
      : tr('{0}:{1} minutes back', [m, rest.toString().padLeft(2, '0')]);
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
/// The leader's jerseys of a race as the organisers name them: the three
/// Grand Tours have their own, every other race the yellow one.
///
/// @param tour Which Grand Tour the race is, or null.
/// @returns Translation keys of the general, points and mountains jerseys.
({String general, String points, String mountains}) jerseyNames(
        GrandTour? tour) =>
    switch (tour) {
      GrandTour.giro => (
          general: 'pink jersey',
          points: 'cyclamen jersey',
          mountains: 'blue jersey',
        ),
      GrandTour.vuelta => (
          general: 'red jersey',
          points: 'green jersey',
          mountains: 'polka-dot jersey',
        ),
      _ => (
          general: 'yellow jersey',
          points: 'green jersey',
          mountains: 'polka-dot jersey',
        ),
    };

RaceArticle writeArticle({
  required SimRoute route,
  required StageResult result,
  Standings? standings,
  Standings? before,
  GrandTour? grandTour,
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
    headline = tr('{0} wins the time trial in {1}', [winner.name, place]);
  } else if (result.breakSurvived) {
    headline = firstGroup == 1
        ? tr('{0} completes the breakaway solo', [winner.name])
        : tr('{0} wins from the breakaway', [winner.name]);
  } else if (firstGroup == 1) {
    headline = tr('{0} wins solo in {1}', [winner.name, place]);
  } else if (firstGroup <= 10) {
    headline = tr('{0} wins the sprint of a small group', [winner.name]);
  } else {
    headline = tr('{0} wins the bunch sprint in {1}', [winner.name, place]);
  }

  final paragraphs = <String>[];
  final lead = StringBuffer(
      tr('{0} ({1}) has won in {2}.', [winner.name, winner.team, place]));
  if (second != null) {
    lead.write(tr(' {0} ({1}) was second, {2}',
        [second.rider.name, second.rider.team, _gap(gapToSecond)]));
    if (p.length > 2) {
      lead.write(tr(', {0} ({1}) third', [p[2].rider.name, p[2].rider.team]));
    }
    lead.write('.');
  }
  if (route.kind == StageKind.road && firstGroup > 10) {
    lead.write(tr(' {0} riders finished in the first group.', [firstGroup]));
  }
  paragraphs.add(lead.toString());

  // Course of the race from the events of the simulation, in three short
  // paragraphs: how the day began, what went wrong, how it was decided.

  /// @param e An event.
  /// @returns Its text after the leading label.
  String after(RaceEvent e) => e.text.substring(e.text.indexOf(': ') + 2);

  /// Joins sentences into a paragraph. Abbreviated first names end in a
  /// full stop, so a doubled one is taken out.
  void paragraph(List<String> sentences) {
    if (sentences.isEmpty) return;
    paragraphs.add(sentences
        .map((s) => s.trim().endsWith('.') ? s.trim() : '${s.trim()}.')
        .join(' ')
        .replaceAll('..', '.'));
  }

  List<RaceEvent> of(EventType type) => [
        for (final e in result.events)
          if (e.type == type) e
      ];

  // 1. The start of the day: weather, the break and how far it got.
  final opening = <String>[];
  for (final e in of(EventType.weather)) {
    opening.add(tr('The race was ridden in {0}', [after(e)]));
  }
  final moves = of(EventType.breakaway);
  // The first event names the group; later ones are riders who bridged.
  final formed = moves.where((e) => e.text.contains(': ')).firstOrNull;
  if (formed != null) {
    opening.add(tr('The break of the day formed after {0} kilometres: {1}',
        [formed.km.round(), after(formed)]));
  }
  for (final e in moves) {
    if (!identical(e, formed)) opening.add(e.text);
  }
  for (final e in of(EventType.maxGap)) {
    opening
        .add(tr('The biggest lead of the front was {0} minutes', [after(e)]));
  }
  for (final e in of(EventType.echelon)) {
    opening.add(e.text);
  }
  paragraph(opening);

  // 2. Mishaps: a few are told, many are counted; whoever had to stop
  // racing is always named.
  final mishaps = <String>[];
  final crashes = of(EventType.crash);
  if (crashes.length <= 2) {
    mishaps.addAll(crashes.map((e) => e.text));
  } else {
    mishaps.add(tr(
        'There were {0} crashes, the last one {1} km from the finish',
        [crashes.length, (route.raceKm - crashes.last.km).round()]));
  }
  final flats = of(EventType.puncture);
  if (flats.length <= 2) {
    mishaps.addAll(flats.map((e) => e.text));
  } else {
    mishaps.add(tr('{0} of the favourites had a puncture', [flats.length]));
  }
  mishaps.addAll(of(EventType.abandon).map((e) => e.text));
  mishaps.addAll(of(EventType.timeCut).map((e) => e.text));
  paragraph(mishaps);

  // 3. The finale: the first attack, the last ones, who was dropped and
  // where the break was caught.
  final finale = <String>[];
  final attacks = of(EventType.attack);
  if (attacks.length <= 3) {
    finale.addAll(attacks.map((e) => e.text));
  } else {
    finale
      ..add(attacks.first.text)
      ..add(tr('{0} more attacks followed', [attacks.length - 2]))
      ..add(attacks.last.text);
  }
  finale.addAll(of(EventType.dropped).map((e) => e.text));
  finale.addAll(of(EventType.gruppetto).map((e) => e.text));
  final caught = of(EventType.caught).lastOrNull;
  if (caught != null) {
    final rest = RegExp(r'(\d+)[.,]\d km').firstMatch(caught.text)?[1];
    finale.add(rest == null
        ? tr('The breakaway was caught')
        : tr('The breakaway was over about {0} kilometres from the finish',
            [rest]));
  }
  if (result.breakSurvived)
    finale.add(tr('The field did not get back to them'));
  paragraph(finale);

  final close = StringBuffer();
  if (standings != null && standings.general.length > 1) {
    final gc = standings.general;
    close.write(finalStage
        ? tr('{0} ({1}) wins {2}, {3} is second, {4}. ', [
            gc.first.rider.name,
            gc.first.rider.team,
            raceName ?? tr('the race'),
            gc[1].rider.name,
            _gap(gc[1].timeS - gc.first.timeS)
          ])
        : tr('{0} ({1}) leads the general classification, {2} is {3}. ', [
            gc.first.rider.name,
            gc.first.rider.team,
            gc[1].rider.name,
            _gap(gc[1].timeS - gc.first.timeS)
          ]));
    // A jersey that changes hands is the news of the day.
    final names = jerseyNames(grandTour);
    void changed(List<dynamic> now, List<dynamic>? then, String jersey) {
      if (now.isEmpty || then == null || then.isEmpty) return;
      final a = now.first.rider, b = then.first.rider;
      if (a.id == b.id) return;
      close.write(
          tr('{0} takes the {1} from {2}. ', [a.name, tr(jersey), b.name]));
    }

    if (!finalStage) {
      changed(gc, before?.general, names.general);
      changed(standings.points, before?.points, names.points);
      changed(standings.mountains, before?.mountains, names.mountains);
    }
  }
  if (teamId != null) {
    final own = p.indexWhere((x) => x.rider.teamId == teamId);
    if (own > 0) {
      close.write(tr('The best rider of our team was {0} in place {1}.',
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
      team.write(tr(
          '{0} lost contact with the favourites {1} and finished in place {2}. ',
          [
            leader.$2.rider.name,
            rest < 1
                ? tr('in the final kilometre')
                : tr('{0} kilometres from the finish', [rest.round()]),
            leader.$1 + 1
          ]));
    }
    final escapees = [
      for (final x in mine)
        if (x.$3?.inBreak ?? false) x.$2.rider.name,
    ];
    if (escapees.isNotEmpty) {
      team.write(tr('{0} {1} in the break of the day. ', [
        escapees.join(tr(' and ')),
        escapees.length == 1 ? tr('was') : tr('were')
      ]));
    }
    final worker = mine
        .where((x) => x.$3 != null && !x.$3!.inBreak && x.$3!.role.works)
        .fold<(int, Placing, RiderTrace?)?>(
            null,
            (best, x) =>
                best == null || x.$3!.frontKm > best.$3!.frontKm ? x : best);
    if (worker != null && worker.$3!.frontKm >= 20) {
      team.write(tr('{0} led the peloton for {1} kilometres.',
          [worker.$2.rider.name, worker.$3!.frontKm.round()]));
    }
    if (team.isNotEmpty) paragraphs.add(team.toString().trim());
  }
  return RaceArticle(headline, paragraphs);
}
