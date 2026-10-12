import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';

// Label, short code (also the key of the scouting range, so that every
// screen shows the same estimate) and accessor.
const _attributes = <(String, String, double Function(Attributes))>[
  ('Flach', 'FL', _flat),
  ('Berg', 'BG', _mountain),
  ('Mittelgebirge', 'MB', _medium),
  ('Hügel', 'HÜ', _hill),
  ('Zeitfahren', 'ZF', _timeTrial),
  ('Prolog', 'PR', _prologue),
  ('Kopfsteinpflaster', 'KO', _cobble),
  ('Sprint', 'SP', _sprint),
  ('Antritt', 'ANT', _acceleration),
  ('Abfahrt', 'ABF', _downhill),
  ('Ausreißer', 'AUS', _breakaway),
  ('Ausdauer', 'AD', _endurance),
  ('Widerstand', 'WID', _resistance),
  ('Regeneration', 'REG', _recovery),
];

double _flat(Attributes a) => a.flat;
double _mountain(Attributes a) => a.mountain;
double _medium(Attributes a) => a.mediumMountain;
double _hill(Attributes a) => a.hill;
double _timeTrial(Attributes a) => a.timeTrial;
double _prologue(Attributes a) => a.prologue;
double _cobble(Attributes a) => a.cobble;
double _sprint(Attributes a) => a.sprint;
double _acceleration(Attributes a) => a.acceleration;
double _downhill(Attributes a) => a.downhill;
double _breakaway(Attributes a) => a.breakaway;
double _endurance(Attributes a) => a.endurance;
double _resistance(Attributes a) => a.resistance;
double _recovery(Attributes a) => a.recovery;

String _d(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

/// Opens the rider profile: attributes, condition, contract, results of the
/// season, honours and career. For riders of other teams the attributes are
/// shown as ranges until a scout has watched them.
///
/// @param context Build context.
/// @param state Application state.
/// @param riderId Id of the rider.
/// @returns A future that completes when the dialog is closed.
Future<void> showRiderDialog(
  BuildContext context,
  AppState state,
  int riderId,
) {
  // From a screen of the shell the profile opens as a full page; on top of
  // another route (founding a team) it stays a dialog.
  if (ModalRoute.of(context)?.isFirst ?? true) {
    state.openRider(riderId);
    return Future.value();
  }
  return showDialog<void>(
    context: context,
    builder: (context) => RiderPage(state: state, riderId: riderId),
  );
}

/// One line of a rider's season: a race and what he achieved there.
class _Result {
  _Result(this.race, this.text, this.good);
  final RaceEntry race;
  final String text;
  final bool good;
}

/// Profile of a rider, as a page of the shell or as a dialog.
class RiderPage extends StatelessWidget {
  /// Creates the profile.
  ///
  /// @param state Application state.
  /// @param riderId Id of the rider.
  /// @param page Whether it fills the content area instead of a dialog.
  const RiderPage({
    super.key,
    required this.state,
    required this.riderId,
    this.page = false,
  });
  final AppState state;
  final int riderId;
  final bool page;

  /// Collects the rider's results of the running season from the races.
  ///
  /// @param career The career.
  /// @returns One line per race he started, in calendar order.
  List<_Result> _results(Career career) {
    final out = <_Result>[];
    for (final p in career.progress.values) {
      if (p.stagesDone == 0 || !p.riders.any((r) => r.id == riderId)) continue;
      if (!p.race.isStageRace) {
        final at = p.run.results.first.placings.indexWhere(
          (x) => x.rider.id == riderId,
        );
        out.add(
          _Result(p.race, at < 0 ? 'nicht im Ziel' : '${at + 1}.', at == 0),
        );
        continue;
      }
      final stageWins = p.run.results
          .where((r) => r.placings.first.rider.id == riderId)
          .length;
      final gc = p.run.standings.last.general.indexWhere(
        (e) => e.rider.id == riderId,
      );
      out.add(
        _Result(
          p.race,
          '${gc < 0 ? 'aufgegeben' : '${gc + 1}. gesamt'}'
          '${p.finished ? '' : ' (läuft)'}'
          '${stageWins == 0
              ? ''
              : stageWins == 1
              ? ' · 1 Etappe'
              : ' · $stageWins Etappen'}',
          gc == 0 && p.finished || stageWins > 0,
        ),
      );
    }
    return out..sort((a, b) => a.race.start.compareTo(b.race.start));
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = s.colors;
    final career = s.career;
    final r = career.riderById[riderId];
    if (r == null) {
      return const AlertDialog(
        content: Text('Der Fahrer ist nicht mehr aktiv.'),
      );
    }
    final own = r.teamId == s.team.id;
    final book = career.staff;
    final exact = book.knowledge(r.id) >= 1;
    final shape = career.shapeOf(r.id);
    final k = career.economy.contracts[r.id];
    final team = career.teams[r.teamId];
    final titles = career.titlesHeld(r.id);
    final results = _results(career);
    final palmares = [...?career.palmares[r.id]].reversed.toList();
    final seasons = [...?career.riderSeasons[r.id]].reversed.toList();
    final planned = [
      for (final race in career.ownRaces)
        if (!career.progress.containsKey(race.info.id) &&
            (career.program[race.info.id]?.contains(r.id) ?? false))
          race,
    ];
    final injured = career.isInjured(r.id, career.today);
    // Development since the first record: the attributes as they were then,
    // and the mean of all attributes month by month.
    final growth = career.growth[r.id] ?? const <List<num>>[];
    Attributes? before;
    if (growth.isNotEmpty) {
      var i = 1;
      before = r.attributes.adjusted((_, _) => growth.first[i++].toDouble());
    }
    double mean(Attributes a) {
      var sum = 0.0, n = 0;
      a.adjusted((_, v) {
        sum += v;
        n++;
        return v;
      });
      return sum / n;
    }

    final means = [
      for (final line in growth)
        line.skip(1).fold<double>(0, (a, b) => a + b) / (line.length - 1),
      if (growth.isNotEmpty) mean(r.attributes),
    ];
    final outlook = career.outlook(r);
    final formLog = career.formLog[r.id] ?? const <List<num>>[];
    String signed(double v, [int digits = 1]) =>
        '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(digits).replaceAll('.', ',')}';

    Widget bar(String label, String code, double value, double? was) {
      final (low, high) = book.range(r.id, code, value);
      final change = was == null ? 0.0 : value - was;
      final shown = (low + high) / 2;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: [
            SizedBox(
              width: 128,
              child: withHelp(
                label,
                Text(label, style: const TextStyle(color: TeamColors.muted)),
              ),
            ),
            SizedBox(
              width: 46,
              child: Text(
                low == high ? '$low' : '$low–$high',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: low == high ? attributeColor(shown) : TeamColors.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                change.abs() < 0.05 ? '' : signed(change),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  color: change > 0 ? TeamColors.green : TeamColors.red,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Stack(
                children: [
                  Container(height: 6, color: c.panel2),
                  FractionallySizedBox(
                    widthFactor: ((shown - 50) / 36).clamp(0.02, 1.0),
                    child: Container(
                      height: 6,
                      color: low == high
                          ? attributeColor(shown)
                          : TeamColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget fact(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: withHelp(
                label,
                Text(label, style: const TextStyle(color: TeamColors.muted)),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color ?? TeamColors.text,
            ),
          ),
        ],
      ),
    );

    Widget line(String left, String right, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(left, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(right, style: TextStyle(color: color ?? TeamColors.muted)),
        ],
      ),
    );

    String percent(double form) =>
        '${form >= 1 ? '+' : ''}${((form - 1) * 100).toStringAsFixed(1).replaceAll('.', ',')} %';

    Widget tile(String label, String value, {Color? color}) => Container(
      width: 132,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: TeamColors.ground,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          withHelp(label, Label(label)),
          const SizedBox(height: 2),
          Text(value, style: headStyle(20, color: color)),
        ],
      ),
    );

    final body = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(career.fullName(r.id), style: headStyle(27)),
                    Row(
                      children: [
                        Flag(r.country, width: 20),
                        const SizedBox(width: 7),
                        Text(
                          '${r.country} · ${career.year - r.born ~/ 10000} Jahre · '
                          '${team?.division == 'Free' ? 'vereinslos' : team?.name ?? r.team}'
                          '${exact ? ' · ${riderType(r)}' : ''}',
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                      ],
                    ),
                    if (titles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final t in titles)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: TeamColors.gold),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'Meistertrikot · $t',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: TeamColors.gold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Jersey(dataDir: s.dataDir, abbr: s.jerseyOf(r.teamId), size: 64),
              const SizedBox(width: 12),
              TextButton(
                onPressed: page
                    ? state.closeRider
                    : () => Navigator.pop(context),
                child: Text(page ? 'Zurück' : 'Schließen'),
              ),
            ],
          ),
          if (page) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                tile('Alter', '${career.year - r.born ~/ 10000}'),
                tile(
                  'Stärke',
                  exact ? Economy.rating(r).round().toString() : '?',
                  color: exact ? attributeColor(Economy.rating(r)) : null,
                ),
                tile(
                  'Potenzial',
                  book.knowledge(r.id) < 0.6
                      ? '?'
                      : r.potential.toStringAsFixed(1),
                ),
                if (own)
                  tile(
                    'Form',
                    percent(shape.form),
                    color: shape.form >= 1 ? TeamColors.green : null,
                  ),
                tile('Renntage', '${shape.raceDays}'),
                tile(
                  'Punkte ${career.year}',
                  '${(career.riderPoints[r.id] ?? 0).round()}',
                ),
                tile(
                  'Siege ${career.year}',
                  '${career.winsOf(r.id, career.year)}',
                ),
                if (k != null) tile('Vertrag bis', '${k.endYear}'),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: ListView(
                    children: [
                      const Label('Werte'),
                      const SizedBox(height: 4),
                      for (final (label, code, pick) in _attributes)
                        bar(
                          label,
                          code,
                          pick(r.attributes),
                          before == null ? null : pick(before),
                        ),
                      if (own || means.length > 1) ...[
                        const SizedBox(height: 14),
                        const Label('Entwicklung'),
                        const SizedBox(height: 4),
                        fact(
                          'Aussicht für zwölf Monate',
                          book.knowledge(r.id) < 0.6
                              ? 'unbekannt'
                              : outlook.abs() < 0.05
                              ? 'hält sein Niveau'
                              : '${signed(outlook)} Punkte je Wert',
                          color: outlook > 0.05
                              ? TeamColors.green
                              : outlook < -0.05
                              ? TeamColors.red
                              : null,
                        ),
                        if (means.length > 1) ...[
                          fact(
                            'Seit ${_month(growth.first[0].toInt())}',
                            '${signed(means.last - means.first, 2)} im Schnitt',
                            color: means.last >= means.first
                                ? TeamColors.green
                                : TeamColors.red,
                          ),
                          const SizedBox(height: 4),
                          Sparkline(
                            values: means,
                            color: means.last >= means.first
                                ? TeamColors.green
                                : TeamColors.red,
                            label: (v) =>
                                v.toStringAsFixed(1).replaceAll('.', ','),
                          ),
                        ] else
                          const Text(
                            'Der Verlauf wird ab dem nächsten Monatsersten '
                            'aufgezeichnet.',
                            style: TextStyle(
                              fontSize: 12,
                              color: TeamColors.muted,
                            ),
                          ),
                      ],
                      if (!exact)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'Geschätzt. Ein Scout macht die Werte genau '
                            '(Transfers → Beobachten lassen).',
                            style: TextStyle(
                              fontSize: 12,
                              color: TeamColors.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 4,
                  child: ListView(
                    children: [
                      const Label('Zustand'),
                      const SizedBox(height: 4),
                      if (own) ...[
                        fact(
                          'Form',
                          percent(shape.form),
                          color: shape.form >= 1
                              ? TeamColors.green
                              : TeamColors.text,
                        ),
                        fact('Fitness', '${shape.fitness.round()}'),
                        fact('Ermüdung', '${shape.fatigue.round()}'),
                        fact(
                          'Frische',
                          '${shape.freshness >= 0 ? '+' : ''}${shape.freshness.round()}',
                          color: shape.freshness < -30
                              ? TeamColors.red
                              : TeamColors.text,
                        ),
                        fact(
                          'Training',
                          '${shape.load.label} · ${shape.focus.label}',
                        ),
                        if (formLog.length > 1) ...[
                          const SizedBox(height: 4),
                          Sparkline(
                            values: [
                              for (final x in formLog) x[1].toDouble(),
                              shape.form,
                            ],
                            color: TeamColors.text,
                            baseline: 1,
                            height: 44,
                            label: percent,
                          ),
                          const Text(
                            'Form im Saisonverlauf, Woche für Woche',
                            style: TextStyle(
                              fontSize: 11,
                              color: TeamColors.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ],
                      fact('Renntage ${career.year}', '${shape.raceDays}'),
                      fact(
                        'Status',
                        injured
                            ? 'fällt aus bis ${_d(shape.injuredUntil!)}'
                            : career.camps.campOf(r.id, career.today) != null
                            ? 'im Trainingslager'
                            : career.isBusy(r.id, career.today)
                            ? 'im Rennen'
                            : 'einsatzbereit',
                        color: injured ? TeamColors.red : null,
                      ),
                      const SizedBox(height: 12),
                      const Label('Vertrag'),
                      const SizedBox(height: 4),
                      fact(
                        'Potenzial',
                        book.knowledge(r.id) < 0.6
                            ? '?'
                            : r.potential.toStringAsFixed(1),
                      ),
                      if (own && k != null)
                        fact('Gehalt', '${euro(k.wage)} € im Jahr'),
                      fact(
                        'Marktwert',
                        exact
                            ? '${euro(career.economy.marketWage(r))} € im Jahr'
                            : 'unbekannt',
                      ),
                      if (k != null) fact('Läuft bis', '${k.endYear}'),
                      if (k?.nextTeam != null)
                        fact(
                          '${career.year + 1}',
                          k!.nextTeam == r.teamId
                              ? 'verlängert bis ${k.nextEnd}'
                              : 'wechselt zu ${career.teams[k.nextTeam]?.name ?? '?'}',
                          color: TeamColors.gold,
                        ),
                      if (planned.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Label('Geplante Rennen'),
                        const SizedBox(height: 4),
                        for (final race in planned.take(8))
                          line(race.info.name, _d(race.start)),
                      ],
                      if (seasons.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Label('Laufbahn'),
                        const SizedBox(height: 4),
                        for (final x in seasons)
                          line(
                            '${x[0]} · ${x[1]}',
                            '${(x[2] as num).round()} Punkte · ${x[3]} Siege · '
                                '${x[4]} Renntage',
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 5,
                  child: ListView(
                    children: [
                      Label(
                        'Saison ${career.year} · '
                        '${(career.riderPoints[r.id] ?? 0).round()} Punkte · '
                        '${career.winsOf(r.id, career.year)} Siege',
                      ),
                      const SizedBox(height: 4),
                      if (results.isEmpty)
                        const Text(
                          'Noch kein Rennen gefahren.',
                          style: TextStyle(color: TeamColors.muted),
                        ),
                      for (final x in results)
                        line(
                          '${_d(x.race.start)}  ${x.race.info.name}',
                          x.text,
                          color: x.good ? TeamColors.gold : null,
                        ),
                      const SizedBox(height: 12),
                      Label('Erfolge · ${palmares.length}'),
                      const SizedBox(height: 4),
                      if (palmares.isEmpty)
                        const Text(
                          'Noch keine Siege in dieser Karriere.',
                          style: TextStyle(color: TeamColors.muted),
                        ),
                      for (final p in palmares.take(40))
                        line(
                          '${p[0]}  ${p[1]}',
                          p[2] as String,
                          color:
                              (p[3] as int) <= RaceTier.worldTour.index &&
                                  !(p[2] as String).contains('.')
                              ? TeamColors.gold
                              : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (page) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Panel(colors: c, padding: 0, child: body),
      );
    }
    return Dialog(
      backgroundColor: c.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 680),
        child: body,
      ),
    );
  }
}

/// @param stamp Year times 100 plus month, as stored in the growth records.
/// @returns The month as text, e.g. "03/2027".
String _month(int stamp) =>
    '${(stamp % 100).toString().padLeft(2, '0')}/${stamp ~/ 100}';
