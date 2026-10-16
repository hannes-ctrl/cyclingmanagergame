import 'package:sim/sim.dart';
import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_state.dart';
import '../widgets.dart';

/// Season plan as a matrix of riders and the team's races. A click pencils
/// a rider in for a race, a right click makes the race one of his season
/// goals. The head with the races and the column with the riders stay in
/// place while the matrix scrolls.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.state});
  final AppState state;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

/// State of the matrix: scroll positions, filters and the field under the
/// pointer.
class _PlanScreenState extends State<PlanScreen> {
  final _horizontal = ScrollController();
  final _names = ScrollController();
  final _body = ScrollController();

  /// Row and column under the pointer, or null.
  final _hover = ValueNotifier<(int, int)?>(null);
  var _onlyBig = true;
  var _onlyAhead = false;

  static const _cell = 30.0;
  static const _rowHeight = 26.0;
  static const _nameWidth = 300.0;
  static const _monthHeight = 20.0;
  static const _headHeight = 170.0;

  @override
  void initState() {
    super.initState();
    // The rider column and the matrix scroll as one.
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
    _hover.dispose();
    super.dispose();
  }

  Color _tierColor(RaceTier tier) => switch (tier) {
    RaceTier.grandTour => TeamColors.gold,
    RaceTier.monument => TeamColors.red,
    RaceTier.worldTour => const Color(0xFF6DB3FF),
    _ => TeamColors.muted,
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

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final people = career.people;
    final races = [
      for (final r in career.ownRaces)
        if ((!_onlyBig || r.tier.factor >= 5) &&
            (!_onlyAhead || !career.progress.containsKey(r.info.id)))
          r,
    ];
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
    final sizes = {
      for (final r in races)
        r.info.id: career.world.raceField(r.info.id).ridersPerTeam,
    };
    // Where a new month begins, and how many races it has.
    final monthStart = <int, int>{};
    for (var i = 0; i < races.length; i++) {
      if (i == 0 || races[i].start.month != races[i - 1].start.month) {
        monthStart[i] = 1;
      } else {
        final first = monthStart.keys.last;
        monthStart[first] = monthStart[first]! + 1;
      }
    }

    int plannedDays(int riderId) {
      var days = 0;
      for (final r in career.ownRaces) {
        if (career.progress.containsKey(r.info.id)) continue;
        if (career.program[r.info.id]?.contains(riderId) ?? false) {
          days += r.stages.length;
        }
      }
      return days;
    }

    BorderSide left(int column) => BorderSide(
      color: monthStart.containsKey(column) ? TeamColors.muted : c.line,
      width: monthStart.containsKey(column) ? 1 : 0.5,
    );

    Widget header(int column) {
      final r = races[column];
      final planned = career.program[r.info.id]?.length ?? 0;
      final started = career.progress.containsKey(r.info.id);
      final size = sizes[r.info.id]!;
      final date =
          '${r.start.day.toString().padLeft(2, '0')}.'
          '${r.start.month.toString().padLeft(2, '0')}.';
      return Tooltip(
        waitDuration: const Duration(milliseconds: 350),
        message:
            '${r.info.name}\n$date · '
            '${tr('{0} stages', [r.stages.length])} · '
            '${tr('{0} of {1} pencilled in', [planned, size])}',
        child: ValueListenableBuilder(
          valueListenable: _hover,
          builder: (context, hover, _) => Container(
            width: _cell,
            height: _headHeight,
            decoration: BoxDecoration(
              color: hover?.$2 == column ? c.panel2 : null,
              border: Border(left: left(column)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(
                              date,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: TeamColors.muted,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              r.info.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: r.tier.factor >= 5
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: started
                                    ? TeamColors.muted
                                    : TeamColors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 4,
                  width: _cell - 6,
                  color: _tierColor(r.tier),
                ),
                SizedBox(
                  height: 22,
                  child: Center(
                    child: Text(
                      started ? '–' : '$planned/$size',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: started
                            ? TeamColors.muted
                            : planned == size
                            ? TeamColors.green
                            : planned > size
                            ? TeamColors.red
                            : planned > 0
                            ? TeamColors.gold
                            : TeamColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget cell(int row, int column) {
      final r = races[column];
      final riderId = squad[row].id;
      final id = r.info.id;
      final p = career.progress[id];
      final rode = p?.riders.any((x) => x.id == riderId) ?? false;
      final planned = career.program[id]?.contains(riderId) ?? false;
      final goal = people.goals[riderId]?.contains(id) ?? false;
      final promised = people.promises.any(
        (x) => x.riderId == riderId && x.raceId == id,
      );
      final out = p == null && career.isInjured(riderId, r.start);
      final tier = _tierColor(r.tier);
      return MouseRegion(
        onEnter: (_) => _hover.value = (row, column),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: p != null ? null : () => s.toggleProgram(id, riderId),
          onSecondaryTap: p != null
              ? null
              : () {
                  final answer = s.toggleGoal(riderId, id);
                  if (answer != null) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(answer)));
                  }
                },
          child: Container(
            width: _cell,
            height: _rowHeight,
            decoration: BoxDecoration(
              color: out
                  ? TeamColors.red.withValues(alpha: 0.14)
                  : row.isOdd
                  ? c.panel2.withValues(alpha: 0.45)
                  : null,
              border: Border(
                left: left(column),
                bottom: BorderSide(color: c.line, width: 0.5),
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: rode || planned
                ? Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rode
                          ? tier.withValues(alpha: 0.28)
                          : tier.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(3),
                      border: promised
                          ? Border.all(color: TeamColors.text, width: 1.5)
                          : null,
                    ),
                    child: goal
                        ? Icon(
                            LucideIcons.target,
                            size: 13,
                            color: rode ? TeamColors.text : TeamColors.ground,
                          )
                        : null,
                  )
                : null,
          ),
        ),
      );
    }

    Widget name(int row) {
      final r = squad[row];
      final days = career.shapeOf(r.id).raceDays + plannedDays(r.id);
      final injured = career.isInjured(r.id, career.today);
      return ValueListenableBuilder(
        valueListenable: _hover,
        builder: (context, hover, _) => InkWell(
          onTap: () => s.openRider(r.id, among: [for (final x in squad) x.id]),
          child: Container(
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hover?.$1 == row
                  ? c.panel2
                  : row.isOdd
                  ? c.panel2.withValues(alpha: 0.45)
                  : null,
              border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: cellText(
                    career.fullName(r.id),
                    color: injured ? TeamColors.red : null,
                  ),
                ),
                _TemplateMenu(state: s, rider: r),
                SizedBox(
                  width: 84,
                  child: Text(
                    people.roleOf(r.id).label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: TeamColors.muted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Align(
                    alignment: Alignment.centerRight,
                    // Race days ridden plus race days planned.
                    child: cellText(
                      '$days',
                      color: days > 80
                          ? TeamColors.red
                          : days > 65
                          ? TeamColors.gold
                          : TeamColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget swatch(Color color, String text, {Widget? child}) => Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
            child: child,
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(
                    'A click pencils the rider in for the race, a right click makes it one of his season goals. Below every race: how many riders are pencilled in, of how many places.',
                  ),
                  style: const TextStyle(color: TeamColors.muted),
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
              child: MouseRegion(
                onExit: (_) => _hover.value = null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The riders: the head stays, the rows follow the matrix.
                    Container(
                      width: _nameWidth,
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: c.line)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            height: _monthHeight + _headHeight,
                            alignment: Alignment.bottomLeft,
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 5),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: c.line)),
                            ),
                            child: Row(
                              children: [
                                Expanded(child: Label(tr('Rider'))),
                                SizedBox(
                                  width: 84,
                                  child: Label(tr('Standing')),
                                ),
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
                    // The races: months, names, and below them the matrix.
                    Expanded(
                      child: Scrollbar(
                        controller: _horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: races.length * _cell,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: _monthHeight,
                                  child: Row(
                                    children: [
                                      for (final e in monthStart.entries)
                                        Container(
                                          width: e.value * _cell,
                                          alignment: Alignment.centerLeft,
                                          padding: const EdgeInsets.only(
                                            left: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.panel2,
                                            border: Border(
                                              left: const BorderSide(
                                                color: TeamColors.muted,
                                              ),
                                              bottom: BorderSide(color: c.line),
                                            ),
                                          ),
                                          child: Text(
                                            // A month with one race has room
                                            // for three letters only.
                                            e.value < 3
                                                ? tr(
                                                    _months[races[e.key]
                                                            .start
                                                            .month -
                                                        1],
                                                  ).substring(0, 3)
                                                : tr(
                                                    _months[races[e.key]
                                                            .start
                                                            .month -
                                                        1],
                                                  ),
                                            maxLines: 1,
                                            overflow: TextOverflow.clip,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: TeamColors.muted,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(color: c.line),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      for (var i = 0; i < races.length; i++)
                                        header(i),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: _body,
                                    child: Column(
                                      children: [
                                        for (
                                          var row = 0;
                                          row < squad.length;
                                          row++
                                        )
                                          Row(
                                            children: [
                                              for (
                                                var i = 0;
                                                i < races.length;
                                                i++
                                              )
                                                cell(row, i),
                                            ],
                                          ),
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
          ),
          const SizedBox(height: 8),
          Wrap(
            runSpacing: 4,
            children: [
              swatch(TeamColors.gold, 'Grand Tour'),
              swatch(TeamColors.red, 'Monument'),
              swatch(const Color(0xFF6DB3FF), 'WorldTour'),
              swatch(TeamColors.muted, tr('Smaller races')),
              swatch(TeamColors.muted.withValues(alpha: 0.28), tr('Ridden')),
              swatch(
                TeamColors.muted,
                tr('Season goal'),
                child: const Icon(
                  LucideIcons.target,
                  size: 11,
                  color: TeamColors.ground,
                ),
              ),
              swatch(
                TeamColors.red.withValues(alpha: 0.2),
                tr('Out on race day'),
              ),
              Text(
                tr(
                  'White border: promise. Days above 65 yellow, above 80 red.',
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
