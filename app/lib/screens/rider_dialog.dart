import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'compare_dialog.dart';
import 'scout_button.dart';

// Label, short code (also the key of the scouting range, so that every
// screen shows the same estimate) and accessor.
const _attributes = <(String, String, double Function(Attributes))>[
  ('Flat', 'FL', _flat),
  ('Mountain', 'MTN', _mountain),
  ('Medium mountain', 'MED', _medium),
  ('Hill', 'HIL', _hill),
  ('Time trial', 'TT', _timeTrial),
  ('Prologue', 'PRL', _prologue),
  ('Cobbles', 'COB', _cobble),
  ('Sprint', 'SPR', _sprint),
  ('Acceleration', 'ACC', _acceleration),
  ('Downhill', 'DH', _downhill),
  ('Breakaway', 'BRK', _breakaway),
  ('Stamina', 'STA', _endurance),
  ('Resistance', 'RES', _resistance),
  ('Recovery', 'REC', _recovery),
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
  int riderId, {
  List<int>? among,
}) {
  // From a screen of the shell the profile opens as a full page; on top of
  // another route (founding a team) it stays a dialog.
  if (ModalRoute.of(context)?.isFirst ?? true) {
    state.openRider(riderId, among: among);
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

/// Lets the player promise a rider something for one of his planned races.
///
/// @param context Build context.
/// @param s Application state.
/// @param r The rider.
/// @param races His planned races.
/// @returns A future that completes when the dialog is closed.
Future<void> _promiseDialog(
  BuildContext context,
  AppState s,
  SimRider r,
  List<RaceEntry> races,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(tr('Promise to {0}', [r.name])),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'A promise lifts his morale at once. Keep it and it rises again; break it and it falls far, and he remembers. One promise per rider and season is possible.',
            ),
            style: const TextStyle(fontSize: 13, color: TeamColors.muted),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final race in races.take(14))
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          race.info.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      for (final kind in PromiseKind.values)
                        TextButton(
                          onPressed: () {
                            s.promise(r.id, race.info.id, kind);
                            Navigator.pop(context);
                          },
                          child: Text(kind.label),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
    ],
  ),
);

/// Star that puts a rider on the shortlist or takes him off it, for the
/// rows of a list. Riders of the player's own team get none.
///
/// @param s Application state.
/// @param r The rider.
/// @returns The star, or an empty box.
Widget watchStar(AppState s, SimRider r) {
  if (r.teamId == s.team.id) return const SizedBox();
  final watched = s.career.watch.contains(r.id);
  return Tooltip(
    message: watched
        ? tr('Remove from the shortlist')
        : tr('Add to the shortlist'),
    child: InkWell(
      onTap: () => s.toggleWatch(r.id),
      child: Icon(
        LucideIcons.star,
        size: 15,
        color: watched
            ? TeamColors.gold
            : TeamColors.muted.withValues(alpha: 0.45),
      ),
    ),
  );
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
          _Result(
            p.race,
            at < 0 ? tr('did not finish') : '${at + 1}.',
            at == 0,
          ),
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
          '${gc < 0 ? tr('abandoned') : tr('{0}. in GC', [gc + 1])}'
          '${p.finished ? '' : tr(' (in progress)')}'
          '${stageWins == 0
              ? ''
              : stageWins == 1
              ? tr(' · 1 stage')
              : tr(' · {0} stages', [stageWins])}',
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
      return AlertDialog(content: Text(tr('The rider is no longer active.')));
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
    // The rider remembered for comparison, if his values are known.
    final rival = s.compareWith == null || s.compareWith == r.id
        ? null
        : career.riderById[s.compareWith];
    final rivalKnown =
        rival != null &&
        (rival.teamId == s.team.id || book.knowledge(rival.id) >= 1);
    final watched = career.watch.contains(r.id);
    final people = career.people;
    final person = people.of(r.id);
    final goals = people.goals[r.id] ?? const <int>{};
    final promise = people.promiseOf(r.id, career.year);
    final nextPromise = people.promiseOf(r.id, career.year + 1);
    String raceName(int id) =>
        career.calendar.where((x) => x.info.id == id).firstOrNull?.info.name ??
        '?';
    String promiseText(RiderPromise p) => p.raceId == 0
        ? People.seasonText(p.kind)
        : '${p.kind.label} · ${raceName(p.raceId)}';
    // Without a team there is no contract to show.
    final free = team?.division == 'Free';
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
        '${v >= 0 ? '+' : '−'}${dec(v.abs(), digits)}';

    Widget bar(
      String label,
      String code,
      double value,
      double? was, [
      double? than,
    ]) {
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
                Text(
                  tr(label),
                  style: const TextStyle(color: TeamColors.muted),
                ),
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
            if (rival != null)
              SizedBox(
                width: 54,
                child: Text(
                  than == null ? '?' : '${than.round()}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: than == null
                        ? TeamColors.muted
                        : than > shown + 0.5
                        ? TeamColors.red
                        : than < shown - 0.5
                        ? TeamColors.green
                        : TeamColors.muted,
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

    Widget line(
      String left,
      String right, {
      Color? color,
      VoidCallback? onTap,
    }) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(left, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text(right, style: TextStyle(color: color ?? TeamColors.muted)),
          ],
        ),
      ),
    );

    String percent(double form) =>
        '${form >= 1 ? '+' : ''}${dec((form - 1) * 100)} %';

    // The tiles share the width of the page, at most 142 px each with the gap, and
    // shrink their texts rather than break them.
    Widget tile(String label, String value, {Color? color}) => Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 142),
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: TeamColors.ground,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: withHelp(label, Label(label)),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: headStyle(20, color: color)),
              ),
            ],
          ),
        ),
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
                    // The line leads to the page of his team.
                    InkWell(
                      onTap: page && team != null
                          ? () => s.openTeam(r.teamId)
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flag(r.country, width: 20),
                          const SizedBox(width: 7),
                          Text(
                            tr('{0} · born {1} · {2} years · {3}{4}', [
                              r.country,
                              birthDate(r.born),
                              ageOn(r.born, career.today),
                              team?.division == 'Free'
                                  ? tr('free agent')
                                  : team?.name ?? r.team,
                              exact ? ' · ${tr(riderType(r))}' : '',
                            ]),
                            style: const TextStyle(color: TeamColors.muted),
                          ),
                        ],
                      ),
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
                                  tr('Champion\'s jersey · {0}', [t]),
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
              if (page) ...[
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    key: ValueKey('note-${r.id}'),
                    initialValue: career.notes[r.id] ?? '',
                    onChanged: (v) => s.setNote(r.id, v),
                    maxLines: 3,
                    minLines: 3,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: tr('Note on this rider'),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    IconButton(
                      tooltip: watched
                          ? tr('Remove from the shortlist')
                          : tr('Add to the shortlist'),
                      onPressed: () => s.toggleWatch(r.id),
                      icon: Icon(
                        LucideIcons.star,
                        size: 20,
                        color: watched ? TeamColors.gold : TeamColors.muted,
                      ),
                    ),
                    IconButton(
                      tooltip: s.compareWith == r.id
                          ? tr('End comparison')
                          : tr(
                              'Remember for comparison: his values then appear on every other rider page',
                            ),
                      onPressed: () =>
                          s.compare(s.compareWith == r.id ? null : r.id),
                      icon: Icon(
                        LucideIcons.scale,
                        size: 20,
                        color: s.compareWith == r.id
                            ? c.accent
                            : TeamColors.muted,
                      ),
                    ),
                    IconButton(
                      tooltip: s.compareList.contains(r.id)
                          ? tr('In the comparison table ({0} of 4) – open it', [
                              s.compareList.length,
                            ])
                          : tr('Add to the comparison table ({0} of 4)', [
                              s.compareList.length,
                            ]),
                      onPressed: () {
                        if (!s.compareList.contains(r.id) &&
                            !s.toggleCompare(r.id)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                tr('The comparison table holds four riders.'),
                              ),
                            ),
                          );
                        }
                        showComparison(context, s);
                      },
                      icon: Icon(
                        LucideIcons.columns4,
                        size: 20,
                        color: s.compareList.contains(r.id)
                            ? c.accent
                            : TeamColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
              RiderPhoto(dataDir: s.dataDir, riderId: r.id, size: 76),
              const SizedBox(width: 12),
              Jersey(dataDir: s.dataDir, abbr: s.jerseyOf(r.teamId), size: 64),
              if (!page) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Close')),
                ),
              ],
            ],
          ),
          if (page) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                tile(tr('Age'), '${ageOn(r.born, career.today)}'),
                tile(tr('Height'), '${dec(r.heightM, 2)} m'),
                tile(tr('Weight'), '${r.massKg.round()} kg'),
                tile(
                  tr('Strength'),
                  exact ? Economy.rating(r).round().toString() : '?',
                  color: exact ? attributeColor(Economy.rating(r)) : null,
                ),
                tile(
                  tr('Potential'),
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
                tile(tr('Race days'), '${shape.raceDays}'),
                tile(
                  tr('Points {0}', [career.year]),
                  '${(career.riderPoints[r.id] ?? 0).round()}',
                ),
                tile(
                  tr('Wins {0}', [career.year]),
                  '${career.winsOf(r.id, career.year)}',
                ),
                if (k != null && !free)
                  tile(tr('Contract until'), contractEnd(k.endYear)),
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
                      if (rival != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tr(
                                    'Compared with {0}: his values are in the second column, green where {1} is better.',
                                    [career.fullName(rival.id), r.lastName],
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: TeamColors.muted,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => s.compare(null),
                                child: Text(tr('End comparison')),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(child: Label(tr('Attributes'))),
                          if (before != null)
                            Tooltip(
                              message: tr(
                                'The small figure beside each attribute shows how it has changed since {0} – the start of the career or the day the rider joined the team.',
                                [_month(growth.first[0].toInt())],
                              ),
                              child: Text(
                                tr('Change since {0}', [
                                  _month(growth.first[0].toInt()),
                                ]),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: TeamColors.muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      for (final (label, code, pick) in _attributes)
                        bar(
                          label,
                          code,
                          pick(r.attributes),
                          before == null ? null : pick(before),
                          rivalKnown ? pick(rival.attributes) : null,
                        ),
                      if (own || means.length > 1) ...[
                        const SizedBox(height: 14),
                        Label(tr('Development')),
                        const SizedBox(height: 4),
                        fact(
                          tr('Outlook for twelve months'),
                          book.knowledge(r.id) < 0.6
                              ? tr('unknown')
                              : outlook.abs() < 0.05
                              ? tr('holds his level')
                              : tr('{0} points per attribute', [
                                  signed(outlook),
                                ]),
                          color: outlook > 0.05
                              ? TeamColors.green
                              : outlook < -0.05
                              ? TeamColors.red
                              : null,
                        ),
                        if (means.length > 1) ...[
                          fact(
                            tr('Since {0}', [_month(growth.first[0].toInt())]),
                            tr('{0} on average', [
                              signed(means.last - means.first, 2),
                            ]),
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
                            label: (v) => dec(v),
                          ),
                        ] else
                          Text(
                            tr(
                              'The history is recorded from the first of next month.',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: TeamColors.muted,
                            ),
                          ),
                      ],
                      if (s.debug) ...[
                        const SizedBox(height: 14),
                        const Label('Debug'),
                        const SizedBox(height: 4),
                        fact('ID', '${r.id}'),
                        fact(
                          tr('Ceiling of the attributes'),
                          dec(Career.ceiling(r)),
                        ),
                        fact(
                          tr('Development per year (best attribute)'),
                          dec(outlook, 2),
                        ),
                        fact(tr('Form factor'), shape.form.toStringAsFixed(4)),
                        fact(
                          tr('Fitness / fatigue'),
                          '${dec(shape.fitness)} / ${dec(shape.fatigue)}',
                        ),
                        fact(
                          tr('Scouting knowledge'),
                          career.staff.scouted.contains(r.id)
                              ? tr('scouted')
                              : tr('revealed by debug mode'),
                        ),
                      ],
                      if (!exact && !own)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: ScoutButton(
                            state: s,
                            riderId: r.id,
                            onAnswer: (text) => ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(text))),
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
                      Label(tr('Condition')),
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
                        fact(tr('Fatigue'), '${shape.fatigue.round()}'),
                        fact(
                          tr('Freshness'),
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
                          Text(
                            tr('Form over the season, week by week'),
                            style: TextStyle(
                              fontSize: 11,
                              color: TeamColors.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ],
                      fact(
                        tr('Race days {0}', [career.year]),
                        '${shape.raceDays}',
                      ),
                      if ((career.breakDays[r.id] ?? 0) > 0)
                        fact(
                          tr('Days in the break'),
                          (career.combative[r.id] ?? 0) > 0
                              ? tr('{0}, most combative {1} times', [
                                  career.breakDays[r.id],
                                  career.combative[r.id],
                                ])
                              : '${career.breakDays[r.id]}',
                        ),
                      fact(
                        'Status',
                        injured
                            ? tr('out until {0}', [_d(shape.injuredUntil!)])
                            : career.camps.campOf(r.id, career.today) != null
                            ? tr('in a training camp')
                            : career.isBusy(r.id, career.today)
                            ? tr('racing')
                            : tr('available'),
                        color: injured ? TeamColors.red : null,
                      ),
                      if (own || exact) ...[
                        const SizedBox(height: 12),
                        Label(tr('Person')),
                        const SizedBox(height: 4),
                        fact(
                          tr('Personality'),
                          person.label,
                          color: person.tone > 0
                              ? TeamColors.green
                              : person.tone < 0
                              ? TeamColors.red
                              : null,
                        ),
                        if (own)
                          PopupMenuButton<TeamRole>(
                            tooltip: tr('Change his standing in the team'),
                            onSelected: (role) => s.setTeamRole(r.id, role),
                            itemBuilder: (context) => [
                              for (final role in TeamRole.values)
                                PopupMenuItem(
                                  value: role,
                                  child: Text(role.label),
                                ),
                            ],
                            child: fact(
                              tr('Standing in the team'),
                              '${people.roleOf(r.id).label} ▾',
                            ),
                          )
                        else
                          fact(
                            tr('Standing in the team'),
                            people.roleOf(r.id).label,
                          ),
                        fact(
                          tr('Morale'),
                          People.moraleWord(people.moraleOf(r.id)),
                          color: people.moraleOf(r.id) >= 0.4
                              ? TeamColors.green
                              : people.moraleOf(r.id) <= -0.4
                              ? TeamColors.red
                              : null,
                        ),
                        if (own) ...[
                          // What moved it last.
                          for (final note
                              in (people.notes[r.id] ?? const []).reversed.take(
                                3,
                              ))
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: line(
                                note[0] as String,
                                (note[1] as num) >= 0 ? '▲' : '▼',
                                color: (note[1] as num) >= 0
                                    ? TeamColors.green
                                    : TeamColors.red,
                              ),
                            ),
                          if (promise != null)
                            fact(
                              tr('Promise'),
                              promiseText(promise),
                              color: TeamColors.gold,
                            )
                          else if (page && planned.isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () =>
                                    _promiseDialog(context, s, r, planned),
                                child: Text(tr('Make a promise …')),
                              ),
                            ),
                        ],
                        if (own && nextPromise != null)
                          fact(
                            tr('Promised for {0}', [career.year + 1]),
                            promiseText(nextPromise),
                            color: TeamColors.gold,
                          ),
                        fact(
                          tr('Professionalism'),
                          Personality.word(people.professionalism(r.id)),
                        ),
                        ..._mentoring(context, s, r, fact),
                        fact(tr('Ambition'), Personality.word(person.ambition)),
                        fact(tr('Loyalty'), Personality.word(person.loyalty)),
                        fact(
                          tr('Adaptability'),
                          people.settlingDays(r.id) > 0
                              ? tr('{0} · settling in, {1} days to go', [
                                  Personality.word(person.adaptability),
                                  people.settlingDays(r.id),
                                ])
                              : Personality.word(person.adaptability),
                        ),
                        fact(
                          tr('Consistency'),
                          Personality.word(person.consistency),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Label(tr('Contract')),
                      const SizedBox(height: 4),
                      fact(
                        tr('Potential'),
                        book.knowledge(r.id) < 0.6
                            ? '?'
                            : r.potential.toStringAsFixed(1),
                      ),
                      if (own && k != null)
                        fact(tr('Wage'), tr('{0} € a year', [euro(k.wage)])),
                      fact(
                        tr('Market value'),
                        exact
                            ? tr('{0} € a year', [
                                euro(career.economy.marketWage(r)),
                              ])
                            : tr('unknown'),
                      ),
                      if (k != null && !free)
                        fact(tr('Runs until'), contractEnd(k.endYear)),
                      if (k != null && !k.clauses.isEmpty)
                        fact(
                          tr('Clauses'),
                          [
                            if (k.clauses.winBonus > 0)
                              tr('{0} € per win', [euro(k.clauses.winBonus)]),
                            if (k.clauses.release > 0)
                              tr('release clause {0} €', [
                                euro(k.clauses.release),
                              ]),
                            if (k.clauses.leader) tr('guaranteed leader'),
                            if (k.clauses.signing > 0)
                              tr('signing bonus {0} €', [
                                euro(k.clauses.signing),
                              ]),
                          ].join(' · '),
                        ),
                      if (k?.nextTeam != null)
                        fact(
                          '${career.year + 1}',
                          k!.nextTeam == r.teamId
                              ? tr('renewed until {0}', [
                                  contractEnd(k.nextEnd),
                                ])
                              : tr('moves to {0}', [
                                  career.teams[k.nextTeam]?.name ?? '?',
                                ]),
                          color: TeamColors.gold,
                        ),
                      if (planned.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        withHelp(
                          'Season goals',
                          Label(
                            tr('Planned races · goals {0}/{1}', [
                              goals.length,
                              People.maxGoals,
                            ]),
                          ),
                        ),
                        const SizedBox(height: 4),
                        for (final race in planned.take(12))
                          Row(
                            children: [
                              // The target makes the race a season goal.
                              InkWell(
                                onTap: page && own
                                    ? () {
                                        final answer = s.toggleGoal(
                                          r.id,
                                          race.info.id,
                                        );
                                        if (answer != null) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                SnackBar(content: Text(answer)),
                                              );
                                        }
                                      }
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(
                                    LucideIcons.target,
                                    size: 14,
                                    color: goals.contains(race.info.id)
                                        ? TeamColors.gold
                                        : TeamColors.muted.withValues(
                                            alpha: 0.4,
                                          ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: line(race.info.name, _d(race.start)),
                              ),
                            ],
                          ),
                      ],
                      if (seasons.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Label(tr('Career so far')),
                        const SizedBox(height: 4),
                        for (final x in seasons)
                          line(
                            '${x[0]} · ${x[1]}',
                            tr('{0} points · {1} wins · {2} race days', [
                              (x[2] as num).round(),
                              x[3],
                              x[4],
                            ]),
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
                        tr('Season {0} · {1} points · {2} wins', [
                          career.year,
                          (career.riderPoints[r.id] ?? 0).round(),
                          career.winsOf(r.id, career.year),
                        ]),
                      ),
                      const SizedBox(height: 4),
                      if (results.isEmpty)
                        Text(
                          tr('No race ridden yet.'),
                          style: TextStyle(color: TeamColors.muted),
                        ),
                      if (results.any((x) => x.good))
                        Text(
                          tr('Gold: won, the race, the overall or a stage.'),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: TeamColors.muted,
                          ),
                        ),
                      for (final x in results)
                        line(
                          '${_d(x.race.start)}  ${x.race.info.name}',
                          x.text,
                          color: x.good ? TeamColors.gold : null,
                          // The line leads to the report of the race.
                          onTap: page ? () => s.showRace(x.race.info.id) : null,
                        ),
                      const SizedBox(height: 12),
                      Label(tr('Honours · {0}', [palmares.length])),
                      const SizedBox(height: 4),
                      if (palmares.isEmpty)
                        Text(
                          tr('No wins in this career yet.'),
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

/// @param born Birth date as yyyymmdd.
/// @returns `dd.mm.yyyy`, or only the year where day and month are unknown.
String birthDate(int born) {
  final y = born ~/ 10000, m = born ~/ 100 % 100, d = born % 100;
  if (m == 0 || d == 0) return '$y';
  return '${d.toString().padLeft(2, '0')}.${m.toString().padLeft(2, '0')}.$y';
}

/// @param born Birth date as yyyymmdd.
/// @param day The day to count to.
/// @returns Full years of age on that day.
int ageOn(int born, DateTime day) {
  final y = born ~/ 10000, md = born % 10000;
  return day.year - y - (day.month * 100 + day.day < md ? 1 : 0);
}

/// Mentoring lines of the rider page: a young rider's mentor, chosen from
/// the team, or the young riders an older one looks after.
///
/// @param context Where messages are shown.
/// @param s Application state.
/// @param r The rider.
/// @param fact Builds one line of the page.
/// @returns The lines, empty if mentoring does not apply to him.
List<Widget> _mentoring(
  BuildContext context,
  AppState s,
  SimRider r,
  Widget Function(String, String, {Color? color}) fact,
) {
  final career = s.career;
  final people = career.people;
  final own = r.teamId == s.team.id || career.devTeam.has(r.id);
  if (!own) return const [];
  final age = career.year - r.born ~/ 10000;
  final mentees = people.menteesOf(r.id);
  if (age <= People.menteeAge) {
    final mentor = people.mentorOf(r.id);
    final candidates =
        [
          for (final x in s.squad)
            if (x.id != r.id && people.mentorReason(x.id) == null) x,
        ]..sort(
          (a, b) => people
              .professionalism(b.id)
              .compareTo(people.professionalism(a.id)),
        );
    return [
      PopupMenuButton<int>(
        tooltip: tr('Choose a mentor'),
        onSelected: (id) {
          final answer = s.setMentor(r.id, id < 0 ? null : id);
          if (answer != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(answer)));
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: -1, child: Text(tr('none'))),
          for (final x in candidates)
            PopupMenuItem(
              value: x.id,
              child: Text(
                '${x.name} · ${Personality.word(people.professionalism(x.id))} · ${people.menteesOf(x.id).length}/${People.maxMentees}',
              ),
            ),
        ],
        child: fact(
          'Mentor',
          '${mentor == null ? tr('none') : career.riderById[mentor]?.name ?? ''} ▾',
        ),
      ),
    ];
  }
  if (mentees.isEmpty) return const [];
  return [
    fact(
      tr('Mentor of'),
      mentees.map((id) => career.riderById[id]?.name ?? '').join(', '),
    ),
  ];
}
