import 'package:sim/sim.dart';
import 'package:flutter/material.dart';
import 'package:game/game.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'simulate_dialog.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', //
  'September', 'October', 'November', 'December',
];
const _days = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

/// Calendar: one month as a grid with the races of each day. Own races and
/// training camps are highlighted; a click opens the race.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.state,
    required this.onOpenRace,
  });
  final AppState state;
  final void Function(int raceId) onOpenRace;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

/// State of the calendar: the month shown and the filters.
class _CalendarScreenState extends State<CalendarScreen> {
  int? _month;
  var _groups = <TierGroup>{};
  var _onlyOwn = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final career = s.career;
    final today = career.today;
    final month = _month ?? (career.seasonOver ? 12 : today.month);
    final first = DateTime.utc(career.year, month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final weeks =
        (DateTime.utc(career.year, month + 1, 0).day + first.weekday - 1 + 6) ~/
        7;
    final ownIds = {for (final r in career.ownRaces) r.info.id};
    final ownCountries = {for (final r in s.squad) r.country};

    bool mine(RaceEntry r) =>
        ownIds.contains(r.info.id) ||
        // Championships in which our riders may be at the start.
        (r.tier == RaceTier.championship &&
            (!r.info.raceClass.startsWith('National') ||
                ownCountries.contains(r.info.country)));

    bool shown(RaceEntry r) =>
        (_groups.isEmpty || _groups.contains(TierGroup.of(r.tier))) &&
        (!_onlyOwn || mine(r));

    Widget chip(RaceEntry r, DateTime date) {
      final own = mine(r);
      final at = r.stages.indexWhere(
        (x) => x.month == date.month && x.day == date.day,
      );
      final short = r.info.abbr.isNotEmpty && r.info.name.length > 20
          ? r.info.abbr
          : r.info.name;
      final done = career.progress[r.info.id]?.finished ?? false;
      return InkWell(
        onTap: () => widget.onOpenRace(r.info.id),
        child: Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          // Every race in the colour of its tier; the team's own races are
          // strong, the others pale.
          decoration: BoxDecoration(
            color: tierColor(r.tier).withValues(alpha: own ? 0.42 : 0.12),
            border: Border(
              left: BorderSide(color: tierColor(r.tier), width: 3),
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            r.isStageRace ? '$short · ${at + 1}' : short,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: own ? FontWeight.w600 : FontWeight.w400,
              color: done
                  ? TeamColors.muted
                  : own
                  ? TeamColors.text
                  : TeamColors.text.withValues(alpha: 0.8),
            ),
          ),
        ),
      );
    }

    Widget cell(DateTime date) {
      final inMonth = date.month == month;
      final races = career.racesOn(date).where(shown).toList()
        ..sort((a, b) {
          final own = (mine(b) ? 1 : 0) - (mine(a) ? 1 : 0);
          return own != 0 ? own : b.tier.factor.compareTo(a.tier.factor);
        });
      // Own and big races individually, the rest as a number; with a group
      // filter every race of the chosen groups is named.
      final listed = [
        for (final r in races)
          if (_groups.isNotEmpty || mine(r) || r.tier.factor >= 5) r,
      ].take(4).toList();
      final camps = career.camps.all.where((k) => k.covers(date)).toList();
      final isToday = date == today;
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
          decoration: BoxDecoration(
            color: inMonth ? c.panel : Colors.transparent,
            border: Border.all(
              color: isToday ? TeamColors.gold : c.line,
              width: isToday ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: !inMonth
              ? null
              : ClipRect(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          // A click on a coming day offers to simulate up to it.
                          InkWell(
                            onTap: !date.isAfter(today) || s.busy
                                ? null
                                : () => showSimulateDialog(
                                    context,
                                    s,
                                    initial: date,
                                  ),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: date.isBefore(today)
                                      ? TeamColors.muted
                                      : TeamColors.text,
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (races.length > listed.length)
                            Text(
                              '+${races.length - listed.length}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: TeamColors.muted,
                              ),
                            ),
                        ],
                      ),
                      for (final k in camps)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: TeamColors.gold),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '${k.type.label} · ${k.riders.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: TeamColors.gold,
                            ),
                          ),
                        ),
                      for (final r in listed)
                        Flexible(flex: 0, child: chip(r, date)),
                    ],
                  ),
                ),
        ),
      );
    }

    Widget arrow(IconData icon, int target) => IconButton(
      onPressed: target < 1 || target > 12
          ? null
          : () => setState(() => _month = target),
      icon: Icon(icon, size: 20),
      color: TeamColors.text,
      disabledColor: TeamColors.muted.withValues(alpha: 0.4),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Panel(
            colors: c,
            padding: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SeasonTimeline(
                year: career.year,
                races: [
                  for (final r in career.calendar)
                    if (mine(r) &&
                        (_groups.isEmpty ||
                            _groups.contains(TierGroup.of(r.tier))))
                      r,
                ],
                colors: c,
                month: month,
                today: today,
                onMonth: (m) => setState(() => _month = m),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              arrow(LucideIcons.chevronLeft, month - 1),
              SizedBox(
                width: 170,
                child: Text(
                  '${tr(_months[month - 1])} ${career.year}',
                  textAlign: TextAlign.center,
                  style: headStyle(22),
                ),
              ),
              arrow(LucideIcons.chevronRight, month + 1),
              TextButton(
                onPressed: () => setState(() => _month = null),
                child: Text(tr('Today')),
              ),
              const Spacer(),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: TeamColors.text,
                  side: BorderSide(color: c.line),
                ),
                onPressed: s.busy || career.seasonOver
                    ? null
                    : () => showSimulateDialog(
                        context,
                        s,
                        initial: DateTime.utc(career.year, month + 1, 1),
                      ),
                icon: const Icon(LucideIcons.fastForward, size: 16),
                label: Text(tr('Simulate to …')),
              ),
              const SizedBox(width: 10),
              Pill(
                label: tr('Own races only'),
                selected: _onlyOwn,
                colors: c,
                dot: c.accent,
                onTap: () => setState(() => _onlyOwn = !_onlyOwn),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TierPills(
              selected: _groups,
              colors: c,
              onChanged: (g) => setState(() => _groups = g),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final d in _days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Label(tr(d)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          for (var w = 0; w < weeks; w++)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var d = 0; d < 7; d++)
                    cell(start.add(Duration(days: w * 7 + d))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
