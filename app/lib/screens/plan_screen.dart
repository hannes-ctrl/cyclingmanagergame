import 'dart:math';

import 'package:sim/sim.dart';
import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_state.dart';
import '../widgets.dart';

/// The season plan as a timeline, in the manner of PCM: the head shows
/// every race of the team as a bar over its real dates, stacked in lanes;
/// below, each rider's row shows the races he is planned for, so that the
/// length of a race and overlaps are seen at once. Pick a race in the head,
/// then click riders to pencil them in or out; a right click on a race in a
/// rider's row makes it one of his season goals.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.state});
  final AppState state;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

/// State of the timeline: scroll positions, filters and the chosen race.
class _PlanScreenState extends State<PlanScreen> {
  final _horizontal = ScrollController();
  final _names = ScrollController();
  final _body = ScrollController();
  var _onlyBig = true;
  var _onlyAhead = false;

  /// The race riders are pencilled in for by a click in their row.
  int? _selected;

  static const _day = 9.0;
  static const _rowHeight = 26.0;
  static const _nameWidth = 300.0;
  static const _monthHeight = 20.0;
  static const _laneHeight = 19.0;

  @override
  void initState() {
    super.initState();
    // The rider column and the rows scroll as one.
    void follow(ScrollController from, ScrollController to) {
      from.addListener(() {
        if (to.hasClients && to.offset != from.offset) to.jumpTo(from.offset);
      });
    }

    follow(_names, _body);
    follow(_body, _names);
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _names.dispose();
    _body.dispose();
    super.dispose();
  }

  static Color _tierColor(RaceTier tier) => switch (tier) {
    RaceTier.grandTour => TeamColors.gold,
    RaceTier.monument => TeamColors.red,
    RaceTier.worldTour => const Color(0xFF6DB3FF),
    _ => const Color(0xFF8A93A6),
  };

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

  /// Spreads the races over lanes so that none overlaps another in its
  /// lane.
  ///
  /// @param races The races, sorted by start.
  /// @returns The lane of every race id, and the number of lanes.
  static (Map<int, int>, int) _lanes(List<RaceEntry> races) {
    final ends = <DateTime>[];
    final lane = <int, int>{};
    for (final r in races) {
      var at = ends.indexWhere((e) => e.isBefore(r.start));
      if (at < 0) {
        ends.add(r.end);
        at = ends.length - 1;
      } else {
        ends[at] = r.end;
      }
      lane[r.info.id] = at;
    }
    return (lane, max(1, ends.length));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final people = career.people;
    final year = career.year;
    final first = DateTime.utc(year, 1, 1);
    final days = DateTime.utc(year + 1, 1, 1).difference(first).inDays;
    double x(DateTime d) => d.difference(first).inDays * _day;
    double width(RaceEntry r) => (r.end.difference(r.start).inDays + 1) * _day;
    final races = [
      for (final r in career.ownRaces)
        if ((!_onlyBig || r.tier.factor >= 5) &&
            (!_onlyAhead || !career.progress.containsKey(r.info.id)))
          r,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final byId = {for (final r in career.ownRaces) r.info.id: r};
    final selected = byId[_selected];
    final (lane, lanes) = _lanes(races);
    // By standing in the team, the strongest first.
    final squad = [...s.squad]
      ..sort((a, b) {
        final byRole = people
            .roleOf(a.id)
            .index
            .compareTo(people.roleOf(b.id).index);
        return byRole != 0
            ? byRole
            : Economy.rating(b).compareTo(Economy.rating(a));
      });

    /// The races a rider is planned for or has ridden, by start.
    List<RaceEntry> riderRaces(int riderId) => [
      for (final r in career.ownRaces)
        if ((career.program[r.info.id]?.contains(riderId) ?? false) ||
            (career.progress[r.info.id]?.riders.any((x) => x.id == riderId) ??
                false))
          r,
    ]..sort((a, b) => a.start.compareTo(b.start));

    int plannedDays(int riderId) {
      var n = 0;
      for (final r in career.ownRaces) {
        if (career.progress.containsKey(r.info.id)) continue;
        if (career.program[r.info.id]?.contains(riderId) ?? false) {
          n += r.stages.length;
        }
      }
      return n;
    }

    /// A race as a bar; the label takes the room up to [room] pixels.
    Widget bar(
      RaceEntry r, {
      required double room,
      bool faded = false,
      bool clash = false,
      bool goal = false,
      bool promised = false,
      bool chosen = false,
    }) {
      final color = _tierColor(r.tier);
      final w = width(r);
      // Without room for a few letters the bar stays unlabelled.
      final label = max(w, room) < 22
          ? ''
          : r.info.abbr.isNotEmpty && room < 70
          ? r.info.abbr
          : r.info.name;
      return Tooltip(
        waitDuration: const Duration(milliseconds: 300),
        message:
            '${r.info.name}\n${_date(r.start)}'
            '${r.isStageRace ? '–${_date(r.end)}' : ''} · '
            '${tr('{0} stages', [r.stages.length])} · '
            '${tr('{0} of {1} pencilled in', [career.program[r.info.id]?.length ?? 0, career.world.raceField(r.info.id).ridersPerTeam])}',
        child: SizedBox(
          width: max(w, room),
          height: _laneHeight - 3,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: w,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: faded ? 0.3 : 0.85),
                  borderRadius: BorderRadius.circular(3),
                  border: chosen
                      ? Border.all(color: TeamColors.text, width: 2)
                      : clash
                      ? Border.all(color: TeamColors.red, width: 2)
                      : promised
                      ? Border.all(color: TeamColors.text, width: 1.5)
                      : null,
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Row(
                    children: [
                      if (goal)
                        const Padding(
                          padding: EdgeInsets.only(right: 2),
                          child: Icon(
                            LucideIcons.target,
                            size: 11,
                            color: TeamColors.text,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: w >= 30
                                ? TeamColors.ground
                                : TeamColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    /// Room for a label after a race: up to the next race in the same row.
    double roomAfter(RaceEntry r, List<RaceEntry> row) {
      final next = row
          .where((o) => o.start.isAfter(r.end))
          .map((o) => x(o.start))
          .fold<double>(days * _day, min);
      return min(next - x(r.start) - 2, 160);
    }

    final todayX = x(career.today);
    final band = selected == null
        ? null
        : Positioned(
            left: x(selected.start),
            top: 0,
            bottom: 0,
            width: width(selected),
            child: IgnorePointer(
              child: Container(color: TeamColors.text.withValues(alpha: 0.07)),
            ),
          );

    Widget head() {
      final inLane = <int, List<RaceEntry>>{};
      for (final r in races) {
        inLane.putIfAbsent(lane[r.info.id]!, () => []).add(r);
      }
      return SizedBox(
        width: days * _day,
        height: _monthHeight + lanes * _laneHeight + 6,
        child: Stack(
          children: [
            for (var m = 1; m <= 12; m++)
              Positioned(
                left: x(DateTime.utc(year, m, 1)),
                top: 0,
                width:
                    DateTime.utc(
                      year,
                      m + 1,
                      1,
                    ).difference(DateTime.utc(year, m, 1)).inDays *
                    _day,
                height: _monthHeight,
                child: Container(
                  padding: const EdgeInsets.only(left: 5),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: c.panel2,
                    border: Border(
                      left: const BorderSide(color: TeamColors.muted),
                      bottom: BorderSide(color: c.line),
                    ),
                  ),
                  child: Text(
                    tr(_months[m - 1]),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: TeamColors.muted,
                    ),
                  ),
                ),
              ),
            ?band,
            for (final r in races)
              Positioned(
                left: x(r.start),
                top: _monthHeight + 3 + lane[r.info.id]! * _laneHeight,
                child: GestureDetector(
                  onTap: () => setState(
                    () => _selected = _selected == r.info.id ? null : r.info.id,
                  ),
                  child: bar(
                    r,
                    room: roomAfter(r, inLane[lane[r.info.id]!]!),
                    faded: career.progress.containsKey(r.info.id),
                    chosen: r.info.id == _selected,
                  ),
                ),
              ),
            Positioned(
              left: todayX,
              top: 0,
              bottom: 0,
              width: 1.5,
              child: Container(color: TeamColors.green),
            ),
          ],
        ),
      );
    }

    Widget row(int i) {
      final r = squad[i];
      final mine = riderRaces(r.id);
      final goals = people.goals[r.id] ?? const <int>{};
      bool clashes(RaceEntry a) => mine.any(
        (b) =>
            b != a &&
            !career.progress.containsKey(b.info.id) &&
            !career.progress.containsKey(a.info.id) &&
            !b.start.isAfter(a.end) &&
            !a.start.isAfter(b.end),
      );
      final injured = career.shapeOf(r.id).injuredUntil;
      final camps = career.camps.all.where((k) => k.riders.contains(r.id));
      RaceEntry? at(double dx) => mine
          .where((x0) => dx >= x(x0.start) && dx <= x(x0.start) + width(x0))
          .firstOrNull;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final hit = at(d.localPosition.dx);
          if (hit != null && hit.info.id != _selected) {
            setState(() => _selected = hit.info.id);
            return;
          }
          final race = selected;
          if (race == null || career.progress.containsKey(race.info.id)) {
            return;
          }
          s.toggleProgram(race.info.id, r.id);
        },
        onSecondaryTapUp: (d) {
          final hit = at(d.localPosition.dx);
          if (hit == null || career.progress.containsKey(hit.info.id)) return;
          final answer = s.toggleGoal(r.id, hit.info.id);
          if (answer != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(answer)));
          }
        },
        child: Container(
          width: days * _day,
          height: _rowHeight,
          decoration: BoxDecoration(
            color: i.isOdd ? c.panel2.withValues(alpha: 0.45) : null,
            border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
          ),
          child: Stack(
            children: [
              if (injured != null && injured.isAfter(career.today))
                Positioned(
                  left: todayX,
                  width: max(0, x(injured) - todayX),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    color: TeamColors.red.withValues(alpha: 0.18),
                  ),
                ),
              for (final k in camps)
                Positioned(
                  left: x(k.start),
                  width: k.days * _day,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    color: TeamColors.green.withValues(alpha: 0.18),
                  ),
                ),
              ?band,
              for (final race in mine)
                if (byId.containsKey(race.info.id))
                  Positioned(
                    left: x(race.start),
                    top: 5,
                    child: bar(
                      race,
                      room: roomAfter(race, mine),
                      faded: career.progress.containsKey(race.info.id),
                      clash: clashes(race),
                      goal: goals.contains(race.info.id),
                      promised: people.promises.any(
                        (p) => p.riderId == r.id && p.raceId == race.info.id,
                      ),
                    ),
                  ),
              // Goals that are not planned yet show as an outline.
              for (final g in goals)
                if (byId[g] case final race?)
                  if (!mine.contains(race))
                    Positioned(
                      left: x(race.start),
                      top: 5,
                      width: width(race),
                      height: _laneHeight - 3,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: TeamColors.gold),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
              Positioned(
                left: todayX,
                top: 0,
                bottom: 0,
                width: 1.5,
                child: Container(
                  color: TeamColors.green.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget name(int i) {
      final r = squad[i];
      final total = career.shapeOf(r.id).raceDays + plannedDays(r.id);
      final injured = career.isInjured(r.id, career.today);
      final planned =
          selected != null &&
          (career.program[selected.info.id]?.contains(r.id) ?? false);
      return Container(
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: planned
              ? _tierColor(selected.tier).withValues(alpha: 0.22)
              : i.isOdd
              ? c.panel2.withValues(alpha: 0.45)
              : null,
          border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () =>
                    s.openRider(r.id, among: [for (final x in squad) x.id]),
                child: cellText(
                  career.fullName(r.id),
                  color: injured ? TeamColors.red : null,
                ),
              ),
            ),
            _TemplateMenu(state: s, rider: r),
            SizedBox(
              width: 84,
              child: Text(
                people.roleOf(r.id).label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: TeamColors.muted),
              ),
            ),
            SizedBox(
              width: 30,
              child: Align(
                alignment: Alignment.centerRight,
                // Race days ridden plus race days planned.
                child: cellText(
                  '$total',
                  color: total > 80
                      ? TeamColors.red
                      : total > 65
                      ? TeamColors.gold
                      : TeamColors.muted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget swatch(Color color, String text) => Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
        ],
      ),
    );

    Widget toggle(String text, bool value, ValueChanged<bool> onChanged) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: const TextStyle(fontSize: 13)),
        Switch(value: value, activeThumbColor: c.accent, onChanged: onChanged),
      ],
    );

    final headHeight = _monthHeight + lanes * _laneHeight + 6;
    final chosenCount = selected == null
        ? 0
        : career.program[selected.info.id]?.length ?? 0;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  selected == null
                      ? tr(
                          'Click a race at the top, then click riders to pencil them in or out. A right click on a race in a rider\'s row makes it one of his season goals.',
                        )
                      : tr(
                          '{0} · {1} · {2} stages · {3} of {4} pencilled in. Click riders to pencil them in or out.',
                          [
                            selected.info.name,
                            selected.isStageRace
                                ? '${_date(selected.start)}–${_date(selected.end)}'
                                : _date(selected.start),
                            selected.stages.length,
                            chosenCount,
                            career.world
                                .raceField(selected.info.id)
                                .ridersPerTeam,
                          ],
                        ),
                  style: TextStyle(
                    color: selected == null
                        ? TeamColors.muted
                        : TeamColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              toggle(
                tr('Upcoming only'),
                _onlyAhead,
                (v) => setState(() => _onlyAhead = v),
              ),
              const SizedBox(width: 8),
              toggle(
                tr('WorldTour only'),
                _onlyBig,
                (v) => setState(() => _onlyBig = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Panel(
              colors: c,
              padding: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The riders: the head stays, the rows follow the timeline.
                  Container(
                    width: _nameWidth,
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: c.line)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: headHeight,
                          alignment: Alignment.bottomLeft,
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 5),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: c.line)),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Label(tr('Rider'))),
                              SizedBox(width: 84, child: Label(tr('Standing'))),
                              SizedBox(
                                width: 30,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Label(tr('Days')),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context)
                                .copyWith(scrollbars: false),
                            child: SingleChildScrollView(
                              controller: _names,
                              child: Column(
                                children: [
                                  for (var i = 0; i < squad.length; i++)
                                    name(i),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // The races over the year, and below them the riders.
                  Expanded(
                    child: Scrollbar(
                      controller: _horizontal,
                      child: SingleChildScrollView(
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: days * _day,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: c.line),
                                  ),
                                ),
                                child: head(),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  controller: _body,
                                  child: Column(
                                    children: [
                                      for (var i = 0; i < squad.length; i++)
                                        row(i),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            runSpacing: 4,
            children: [
              swatch(TeamColors.gold, 'Grand Tour'),
              swatch(TeamColors.red, 'Monument'),
              swatch(const Color(0xFF6DB3FF), 'WorldTour'),
              swatch(const Color(0xFF8A93A6), tr('Smaller races')),
              swatch(TeamColors.muted.withValues(alpha: 0.3), tr('Ridden')),
              swatch(
                TeamColors.green.withValues(alpha: 0.35),
                tr('Training camp'),
              ),
              swatch(TeamColors.red.withValues(alpha: 0.3), tr('Out')),
              Text(
                tr(
                  'Red border: overlaps another race. White border: promise. Target: season goal; a gold outline is a goal he is not planned for. Green line: today.',
                ),
                style: const TextStyle(fontSize: 12, color: TeamColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Programme templates for one rider: apply a built-in or own template,
/// save his programme as one, or delete an own one.
class _TemplateMenu extends StatelessWidget {
  const _TemplateMenu({required this.state, required this.rider});
  final AppState state;
  final SimRider rider;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final career = s.career;
    return SizedBox(
      width: 24,
      child: PopupMenuButton<String>(
        tooltip: tr('Programme templates'),
        padding: EdgeInsets.zero,
        iconSize: 15,
        icon: const Icon(LucideIcons.listPlus, color: TeamColors.muted),
        enabled: !s.busy,
        onSelected: (choice) async {
          final messenger = ScaffoldMessenger.of(context);
          void say(String text) =>
              messenger.showSnackBar(SnackBar(content: Text(text)));
          if (choice == '+save') {
            final name = await _askName(context, s);
            if (name == null) return;
            say(
              s.saveTemplate(name, rider.id) ??
                  tr('Template {0} saved.', [name]),
            );
          } else if (choice.startsWith('-')) {
            s.deleteTemplate(choice.substring(1));
            say(tr('Template {0} deleted.', [choice.substring(1)]));
          } else {
            final added = s.applyTemplate(choice, rider.id);
            say(tr('{0}: {1} races added.', [rider.name, added]));
          }
        },
        itemBuilder: (context) => [
          for (final t in career.templates)
            PopupMenuItem(
              value: t.key,
              child: Text(tr('Apply: {0}', [t.name])),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: '+save',
            child: Text(tr('Save his programme as a template …')),
          ),
          for (final t in career.ownTemplates)
            PopupMenuItem(
              value: '-${t.key}',
              child: Text(
                tr('Delete: {0}', [t.name]),
                style: const TextStyle(color: TeamColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  /// Asks for the name of a new template.
  static Future<String?> _askName(BuildContext context, AppState s) {
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: s.colors.panel,
        title: Text(tr('Save as template')),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('Name')),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
  }
}
