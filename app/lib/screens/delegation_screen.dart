import 'package:sim/sim.dart';
import 'package:flutter/material.dart';
import 'package:game/game.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';

/// Delegation: what the player decides himself and what his staff handles
/// without asking.
class DelegationScreen extends StatelessWidget {
  const DelegationScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = s.colors;
    final career = s.career;
    final d = career.delegation;
    final book = career.staff;

    String best(StaffRole role) {
      final people = book.of(s.team.id, role).toList()
        ..sort((a, b) => b.skill.compareTo(a.skill));
      return people.isEmpty
          ? tr('nobody in the team')
          : '${people.first.name} (${people.first.skill})';
    }

    Widget row(
      String title,
      String who,
      String self,
      String delegated,
      bool on,
      void Function(bool) onChanged,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 230,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  who,
                  style: const TextStyle(fontSize: 12, color: TeamColors.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              on ? delegated : self,
              style: TextStyle(color: on ? TeamColors.text : TeamColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            on ? tr('Staff') : tr('Myself'),
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 24,
            child: Switch(
              value: on,
              activeThumbColor: c.accent,
              onChanged: s.busy ? null : onChanged,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: SingleChildScrollView(
            child: Panel(
              colors: c,
              padding: 18,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Label(tr('Delegation')),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      'What you hand over, the staff handles without asking. How well depends on the people.',
                    ),
                    style: TextStyle(color: TeamColors.muted),
                  ),
                  const SizedBox(height: 8),
                  row(
                    tr('Line-ups'),
                    tr('Sports director: {0}', [best(StaffRole.director)]),
                    tr('Before every race you pick riders, roles and tactics.'),
                    tr(
                      'The sports director picks the line-up and plans every stage; he still respects the season plan.',
                    ),
                    d.lineups,
                    (v) => s.delegate('lineups', v),
                  ),
                  Divider(height: 1, color: c.line),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 230,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('Race radio'),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                tr('Sports director: {0}', [
                                  best(StaffRole.director),
                                ]),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: TeamColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            tr(
                              'The director calls up to three times per stage: when the break of the day has formed, at the start of the finale and when a rival attacks.',
                            ),
                            style: TextStyle(color: TeamColors.muted),
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<RadioMode>(
                          value: d.radio,
                          isDense: true,
                          underline: const SizedBox(),
                          dropdownColor: c.panel2,
                          style: const TextStyle(
                            fontFamily: 'Barlow',
                            fontSize: 13,
                            color: TeamColors.text,
                          ),
                          onChanged: s.busy
                              ? null
                              : (v) => s.delegate('radio', v!.name),
                          items: [
                            for (final m in RadioMode.values)
                              DropdownMenuItem(value: m, child: Text(m.label)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  row(
                    'Training',
                    tr('Coach: {0}', [best(StaffRole.coach)]),
                    tr('You set load and focus per rider in the squad.'),
                    tr(
                      'Every Monday the coach sets the load by freshness and age, eases off before planned races and picks the focus by the rider\'s strength.',
                    ),
                    d.training,
                    (v) => s.delegate('training', v),
                  ),
                  Divider(height: 1, color: c.line),
                  row(
                    'Scouting',
                    'Scout: ${best(StaffRole.scout)}',
                    tr(
                      'You send out the scouts one by one in the transfer market.',
                    ),
                    tr(
                      'From June free scouts watch riders with expiring contracts who suit the team, of their own accord.',
                    ),
                    d.scouting,
                    (v) => s.delegate('scouting', v),
                  ),
                  Divider(height: 1, color: c.line),
                  row(
                    tr('Season plan'),
                    tr('Sports director'),
                    tr('You plan yourself which rider rides which race.'),
                    tr(
                      'At the start of the season the sports director plans all races, the most important first and evenly across the squad, and replaces riders who drop out. You can change every entry in the race planner.',
                    ),
                    d.planning,
                    (v) => s.delegate('planning', v),
                  ),
                  Divider(height: 1, color: c.line),
                  row(
                    tr('Facilities'),
                    tr('Board'),
                    tr('You decide yourself which facility is built up.'),
                    tr(
                      'On the first of every month the board builds up the weakest facility, one at a time, as long as a tenth of the budget stays in the account.',
                    ),
                    d.facilities,
                    (v) => s.delegate('facilities', v),
                  ),
                  Divider(height: 1, color: c.line),
                  row(
                    tr('Contract renewals'),
                    tr('Board'),
                    tr('You negotiate expiring contracts yourself.'),
                    tr(
                      'On 1 August the board renews everyone who belongs to the core or is young and gifted.',
                    ),
                    career.economy.autoRenew,
                    s.setAutoRenew,
                  ),
                  Divider(height: 1, color: c.line),
                  row(
                    tr('Job market'),
                    tr('Board'),
                    tr(
                      'You stay with your team whatever happens; your reputation is still kept.',
                    ),
                    tr(
                      'On 1 November the board judges the season: after a bad one it warns you, after a second one it dismisses you at the end of the year. Other teams offer you jobs; an accepted offer takes effect at the turn of the year.',
                    ),
                    d.jobMarket,
                    (v) => s.delegate('jobMarket', v),
                  ),
                  Divider(height: 1, color: c.line),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 230,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('Team style'),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                tr('Sports directors'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: TeamColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  Pill(
                                    label: tr('From the squad: {0}', [
                                      Career.styleFromSquad(
                                        s.squad,
                                        career.year,
                                      ).label,
                                    ]),
                                    selected: career.ownStyle == null,
                                    colors: c,
                                    onTap: () => s.setOwnStyle(null),
                                  ),
                                  for (final st in TeamStyle.values)
                                    Pill(
                                      label: st.label,
                                      selected: career.ownStyle == st,
                                      colors: c,
                                      onTap: () => s.setOwnStyle(st),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              InfoTip(
                                tr(
                                  'How the sports directors race and plan, the same for every team: a sprint team controls the flat stages and values races with many of them, a team built for the general classification makes the mountains hard and values stage races, a classics team the one-day races. Youth and experience tell the planner whom to prefer on the market.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
