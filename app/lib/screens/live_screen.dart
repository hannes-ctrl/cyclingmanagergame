import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../live_race.dart';
import '../ui.dart';
import '../widgets.dart';

/// A stage of the player's team watched live: the groups on the road with
/// their gaps, the profile with the groups on it, what happens, and the
/// player's riders with the strength they have left and the orders for
/// them. The 3D viewer shows the same race. Before the start the stage can
/// still be simulated as before, without the viewer.
class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key, required this.state, required this.live});
  final AppState state;
  final LiveRace live;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: live,
    builder: (context, _) => _LiveView(state: state, live: live),
  );
}

class _LiveView extends StatelessWidget {
  const _LiveView({required this.state, required this.live});
  final AppState state;
  final LiveRace live;

  @override
  Widget build(BuildContext context) {
    final c = state.colors;
    final stage = live.stage;
    final route = stage.route;
    final stageRace = live.stageNumber > 0;
    final groups = live.started ? stage.groups() : const <LiveGroup>[];
    final leadKm = groups.isEmpty ? 0.0 : groups.first.km;
    final toGo = max(0.0, route.raceKm - leadKm);
    final result = stage.result;
    final call = stage.openCall;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Panel(
        colors: c,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RaceLogo(dataDir: state.dataDir, race: live.info, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stageRace
                                ? tr('{0}, stage {1}', [
                                    live.info.name,
                                    live.stageIndex + 1,
                                  ])
                                : live.info.name,
                            style: headStyle(22),
                          ),
                          Text(
                            !live.started
                                ? tr('Live · {0} km', [route.raceKm.round()])
                                : result != null
                                ? tr('Finish · {0}', [_clock(stage.clock)])
                                : '${tr('{0} km to go', [toGo.toStringAsFixed(1)])} · '
                                      '${_clock(stage.clock)}',
                            style: const TextStyle(color: TeamColors.muted),
                          ),
                        ],
                      ),
                    ),
                    if (live.started && result == null) ..._speeds(c),
                    if (live.started) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: tr('Show the race in the 3D viewer'),
                        child: OutlinedButton.icon(
                          onPressed: () => _open3d(context),
                          icon: const Icon(LucideIcons.box, size: 16),
                          label: const Text('3D'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: c.onAccent,
                        ),
                        onPressed: state.busy ? null : state.endLive,
                        child: Text(
                          result != null
                              ? tr('To the result')
                              : tr('To the finish'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (!live.started)
                  Expanded(child: _start(context, c))
                else
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 150,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: ProfileView(
                                        route: route,
                                        colors: c,
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _GroupsOnProfile(
                                          route.raceKm,
                                          [for (final g in groups) g.km],
                                          {
                                            for (final (i, g) in groups.indexed)
                                              if (g.riders.any(_isOwn)) i,
                                          },
                                          c.accent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (result != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    tr('{0} wins', [
                                      state.career.fullName(
                                        result.placings.first.rider.id,
                                      ),
                                    ]),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: TeamColors.gold,
                                    ),
                                  ),
                                ),
                              Expanded(child: _groupList(c, groups)),
                              const SizedBox(height: 8),
                              _events(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 380,
                          child: _riders(context, c, groups),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (call != null) _radio(c, call),
          ],
        ),
      ),
    );
  }

  bool _isOwn(int id) => live.own.any((r) => r.id == id);

  String _name(int id) {
    for (final r in live.riders) {
      if (r.id == id) return r.name;
    }
    return '';
  }

  static String _clock(double s) {
    final t = max(0, s.round());
    return '${t ~/ 3600}:${(t % 3600 ~/ 60).toString().padLeft(2, '0')}:'
        '${(t % 60).toString().padLeft(2, '0')}';
  }

  static String _gap(double s) {
    final t = s.round();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  List<Widget> _speeds(TeamColors c) => [
    IconButton(
      tooltip: live.paused ? tr('Go on') : tr('Pause'),
      onPressed: live.togglePause,
      icon: Icon(live.paused ? LucideIcons.play : LucideIcons.pause, size: 18),
    ),
    for (final s in LiveRace.speeds)
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Pill(
          label: '×${s.round()}',
          selected: live.speed == s,
          onTap: () => live.setSpeed(s),
          colors: c,
        ),
      ),
  ];

  Future<void> _open3d(BuildContext context) async {
    final error = await live.open3d();
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// Before the start: the stage, and whether to watch it or have it
  /// simulated.
  Widget _start(BuildContext context, TeamColors c) {
    final weather = live.stage.weather;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileView(route: live.stage.route, colors: c),
        const SizedBox(height: 12),
        Text(
          tr('Weather: {0}', [weather.describe()]),
          style: const TextStyle(color: TeamColors.muted),
        ),
        const SizedBox(height: 4),
        Text(
          tr('Our riders: {0}', [live.own.map((r) => r.name).join(', ')]),
          style: const TextStyle(color: TeamColors.muted),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              onPressed: () async {
                final error = await live.start();
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error)));
                }
              },
              icon: const Icon(LucideIcons.play, size: 18),
              label: Text(tr('Watch live')),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              onPressed: state.busy
                  ? null
                  : () => state.endLive(watched: false),
              child: Text(tr('Simulate')),
            ),
            const SizedBox(width: 16),
            Text(
              tr('Watch our stages live'),
              style: const TextStyle(fontSize: 13),
            ),
            Switch(
              value: state.watchLive,
              activeThumbColor: c.accent,
              onChanged: state.setWatchLive,
            ),
          ],
        ),
        const SizedBox(height: 8),
        InfoTip(
          tr(
            'Live, the stage is ridden as you watch it, in the 3D viewer too. Your riders take orders: attack, follow the attacks, ride tempo, save energy, wait for the leader. Simulated, it is ridden at once as before, with the sports director asking over the radio.',
          ),
        ),
      ],
    );
  }

  Widget _groupList(TeamColors c, List<LiveGroup> groups) => ListView(
    children: [
      for (final (i, g) in groups.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  i == 0 ? tr('Head') : '+${_gap(g.gapS)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: i == 0 ? TeamColors.gold : TeamColors.text,
                  ),
                ),
              ),
              SizedBox(
                width: 92,
                child: Text(
                  g.riders.length == 1
                      ? tr('1 rider')
                      : tr('{0} riders', [g.riders.length]),
                  style: const TextStyle(color: TeamColors.muted),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (g.breakaway)
                        TextSpan(
                          text: '${tr('Break')}  ',
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                      if (g.gruppetto)
                        TextSpan(
                          text: '${tr('Gruppetto')}  ',
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                      for (final id in g.riders.where(_isOwn))
                        TextSpan(
                          text: '${_name(id)}  ',
                          style: TextStyle(
                            color: c.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      TextSpan(
                        text: [
                          for (final id in g.stars.take(6))
                            if (!_isOwn(id)) _name(id),
                        ].join(', '),
                      ),
                      if (g.riders.length <= 3)
                        TextSpan(
                          text: g.stars.isEmpty
                              ? g.riders
                                    .where((id) => !_isOwn(id))
                                    .map(_name)
                                    .join(', ')
                              : '',
                        ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _events() {
    final lines = [
      for (final e in live.stage.events)
        if (e.type != EventType.weather) e.text,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines.skip(max(0, lines.length - 5)))
          Text(
            line,
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
      ],
    );
  }

  /// The player's riders with what they have left, and the orders.
  Widget _riders(BuildContext context, TeamColors c, List<LiveGroup> groups) {
    final where = <int, int>{};
    for (final (i, g) in groups.indexed) {
      for (final id in g.riders) {
        where[id] = i;
      }
    }
    final timeTrial = live.stage.timeTrial;
    final open = live.stage.result == null && !timeTrial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Our riders'), style: headStyle(17)),
        const SizedBox(height: 6),
        Expanded(
          child: ListView(
            children: [
              for (final r in live.own)
                _riderRow(c, r, where[r.id], groups, open),
            ],
          ),
        ),
        if (open) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (o, label, tip) in _orders)
                Tooltip(
                  message: tr(tip),
                  child: OutlinedButton(
                    onPressed: live.selected.isEmpty
                        ? null
                        : () => live.order(o),
                    child: Text(tr(label)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            live.selected.isEmpty
                ? tr('Pick riders, then give an order.')
                : tr('{0} picked', [live.selected.length]),
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
        ],
        if (timeTrial)
          Text(
            tr('In a time trial every rider rides his own race.'),
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
      ],
    );
  }

  static const _orders = [
    (
      RiderOrder.attack,
      'Attack',
      'He attacks at once; before the break has gone, he goes with it.',
    ),
    (
      RiderOrder.follow,
      'Follow',
      'He goes with every attack out of his group, as long as he can.',
    ),
    (
      RiderOrder.tempo,
      'Tempo',
      'He rides on the front of his group, at least at his threshold, until he is empty.',
    ),
    (RiderOrder.save, 'Save energy', 'He sits in the wheels and does no work.'),
    (
      RiderOrder.help,
      'Wait for the leader',
      'He waits for the team\'s leader in a group behind and rides with him.',
    ),
    (
      RiderOrder.none,
      'Back to the plan',
      'He rides as the plan of the day says.',
    ),
  ];

  static const _orderLabels = {
    RiderOrder.attack: 'Attack',
    RiderOrder.follow: 'Follow',
    RiderOrder.tempo: 'Tempo',
    RiderOrder.save: 'Save energy',
    RiderOrder.help: 'Wait for the leader',
  };

  Widget _riderRow(
    TeamColors c,
    SimRider r,
    int? group,
    List<LiveGroup> groups,
    bool open,
  ) {
    final s = live.stage.rider(r.id);
    final out = s?.out ?? false;
    final picked = live.selected.contains(r.id);
    final place = out
        ? tr('out of the race')
        : group == null
        ? ''
        : group == 0
        ? tr('at the head')
        : '+${_gap(groups[group].gapS)}';
    final order = s == null ? null : _orderLabels[s.order];
    return InkWell(
      onTap: open && !out ? () => live.toggle(r.id) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: picked ? c.panel2 : null,
          border: Border.all(color: picked ? c.accent : c.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: out ? TeamColors.muted : TeamColors.text,
                    ),
                  ),
                ),
                if (order != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      tr(order),
                      style: TextStyle(fontSize: 12, color: c.accent),
                    ),
                  ),
                Text(
                  place,
                  style: const TextStyle(fontSize: 12, color: TeamColors.muted),
                ),
              ],
            ),
            if (s != null && !out) ...[
              const SizedBox(height: 4),
              _bar(tr('Energy'), s.energy, TeamColors.green),
              const SizedBox(height: 2),
              _bar(tr('Legs'), s.reserve, TeamColors.gold),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bar(String label, double value, Color colour) => Row(
    children: [
      SizedBox(
        width: 56,
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: TeamColors.muted),
        ),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 5,
            color: colour,
            backgroundColor: TeamColors.ground,
          ),
        ),
      ),
    ],
  );

  /// The radio question the race waits for.
  Widget _radio(TeamColors c, RadioCall call) => Positioned(
    left: 0,
    right: 0,
    top: 60,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Material(
          color: c.panel2,
          elevation: 8,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        tr('RADIO'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: c.onAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      tr('{0} km to go', [call.remainingKm.toStringAsFixed(1)]),
                      style: const TextStyle(color: TeamColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '„${call.text}"',
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 14),
                for (final (i, option) in call.options.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TeamColors.text,
                          backgroundColor: i == call.suggested ? c.panel : null,
                          side: BorderSide(color: c.line),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        onPressed: () => live.answer(i),
                        child: Text(
                          i == call.suggested
                              ? tr('{0}  ·  recommended', [option])
                              : option,
                        ),
                      ),
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

/// The groups as lines on the profile, the head of the race in gold and
/// the groups with riders of the player's team in his colour.
class _GroupsOnProfile extends CustomPainter {
  _GroupsOnProfile(this.raceKm, this.kms, this.own, this.accent);
  final double raceKm;
  final List<double> kms;
  final Set<int> own;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // The same margins as the profile.
    const left = 40.0, right = 10.0;
    final w = size.width - left - right;
    for (var i = kms.length - 1; i >= 0; i--) {
      final x = left + (kms[i] / raceKm).clamp(0.0, 1.0) * w;
      final paint = Paint()
        ..color = i == 0
            ? TeamColors.gold
            : own.contains(i)
            ? accent
            : TeamColors.text.withValues(alpha: 0.7)
        ..strokeWidth = i == 0 || own.contains(i) ? 2.5 : 1.2;
      canvas.drawLine(Offset(x, 26), Offset(x, size.height - 22), paint);
    }
  }

  @override
  bool shouldRepaint(_GroupsOnProfile old) => true;
}
