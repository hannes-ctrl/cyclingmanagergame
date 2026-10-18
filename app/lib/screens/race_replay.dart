import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';

/// The stage in fast motion: the profile with the head of the race moving
/// along it, the groups on the road by their gap, the riders of the team
/// in them, and the events as they happen.
class RaceReplay extends StatefulWidget {
  const RaceReplay({
    super.key,
    required this.result,
    required this.route,
    required this.names,
    required this.colors,
    this.others = const {},
    this.autoplay = false,
    this.onFinished,
    this.fromKm = 0,
    this.untilKm,
  });

  /// Kilometre the fast motion starts at.
  final double fromKm;

  /// Kilometre it stops at, the finish if null: a stage that is only
  /// ridden that far, up to a question of the team car.
  final double? untilKm;

  final StageResult result;
  final SimRoute route;

  /// Names of the riders of the team, by id.
  final Map<int, String> names;
  final TeamColors colors;

  /// Names of other riders to name in their group, the favourites, by id.
  final Map<int, String> others;

  /// Whether the stage starts running at once.
  final bool autoplay;

  /// Called once when the head of the race reaches the finish.
  final VoidCallback? onFinished;

  @override
  State<RaceReplay> createState() => _RaceReplayState();
}

class _RaceReplayState extends State<RaceReplay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  late var _km = widget.fromKm;

  /// Where the fast motion ends.
  double get _end => widget.untilKm ?? widget.route.raceKm;
  var _playing = false;
  var _speed = 1.0;
  var _finished = false;

  /// Seconds the whole stage takes at normal speed.
  static const _seconds = 45.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      setState(() {
        _km += widget.route.raceKm / _seconds * _speed * dt;
        if (_km >= _end) {
          _km = _end;
          _stop();
          if (!_finished) {
            _finished = true;
            widget.onFinished?.call();
          }
        }
      });
    });
    if (widget.autoplay) _play();
  }

  void _play() {
    if (_km >= _end) _km = widget.fromKm;
    _last = Duration.zero;
    _playing = true;
    _ticker.start();
  }

  void _stop() {
    _playing = false;
    _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// The last sample before the current kilometre.
  RaceSample? get _sample {
    RaceSample? at;
    for (final s in widget.result.timeline) {
      if (s.km > _km + 1e-6) break;
      at = s;
    }
    return at ?? widget.result.timeline.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final route = widget.route;
    final sample = _sample;
    final groups = sample?.groups ?? const <GroupSample>[];
    final events = [
      for (final e in widget.result.events)
        if (e.km <= _km && e.type != EventType.weather) e,
    ].reversed.take(6).toList();
    String label(GroupSample g, int i) {
      if (g.breakaway) return tr('Break');
      if (g.gruppetto) return tr('Gruppetto');
      if (i == 0) return tr('Head of the race');
      return g.favourites > 0 ? tr('Favourites') : tr('Group');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: _playing ? tr('Pause') : tr('Play'),
              onPressed: () => setState(() => _playing ? _stop() : _play()),
              icon: Icon(
                _playing ? LucideIcons.pause : LucideIcons.play,
                size: 18,
              ),
            ),
            for (final v in const [1.0, 2.0, 4.0])
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Pill(
                  label: '${v.round()}×',
                  selected: _speed == v,
                  colors: c,
                  onTap: () => setState(() => _speed = v),
                ),
              ),
            Expanded(
              child: Slider(
                value: _km.clamp(0, route.raceKm),
                max: route.raceKm,
                activeColor: c.accent,
                onChanged: (v) => setState(() => _km = v),
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                tr('km {0} · {1} to go', [
                  _km.round(),
                  max(0, (route.raceKm - _km).round()),
                ]),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 90,
          child: CustomPaint(
            painter: _ProfilePainter(route, _km, c),
            size: const Size(double.infinity, 90),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 70,
          child: CustomPaint(
            painter: _RoadPainter(groups, c),
            size: const Size(double.infinity, 70),
          ),
        ),
        const SizedBox(height: 6),
        for (final (i, g) in groups.take(6).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    i == 0 ? '' : '+${clock(g.gapS)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${label(g, i)} · ${g.size == 1 ? tr('1 rider') : trn(g.size, '{0} rider', '{0} riders')}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (g.favourites > 0)
                          TextSpan(
                            text:
                                ' · ${g.favourites == 1 ? tr('1 favourite') : tr('{0} favourites', [g.favourites])}',
                            style: const TextStyle(color: TeamColors.muted),
                          ),
                        if (g.watched.isNotEmpty)
                          TextSpan(
                            text:
                                ' · ${g.watched.map((id) => widget.names[id] ?? '?').join(', ')}',
                            style: TextStyle(color: c.accent),
                          ),
                        if ([
                              for (final id in g.stars)
                                if (widget.others.containsKey(id) &&
                                    !g.watched.contains(id))
                                  id,
                            ].take(4).toList()
                            case final named when named.isNotEmpty)
                          TextSpan(
                            text:
                                ' · ${named.map((id) => widget.others[id]).join(', ')}',
                            style: const TextStyle(color: TeamColors.text),
                          ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        if (groups.length > 6)
          Text(
            tr('{0} more groups behind', [groups.length - 6]),
            style: const TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
        const SizedBox(height: 8),
        for (final e in events)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    'km ${e.km.round()}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: TeamColors.muted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(e.text, style: const TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The profile with the part already ridden and the head of the race.
class _ProfilePainter extends CustomPainter {
  _ProfilePainter(this.route, this.km, this.colors);
  final SimRoute route;
  final double km;
  final TeamColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final segs = route.segments;
    if (segs.isEmpty) return;
    var lo = double.infinity, hi = -double.infinity;
    for (final s in segs) {
      lo = min(lo, s.altitudeM);
      hi = max(hi, s.altitudeM);
    }
    if (hi - lo < 100) hi = lo + 100;
    double x(double k) => k / route.raceKm * size.width;
    double y(double alt) =>
        size.height - 6 - (alt - lo) / (hi - lo) * (size.height - 14);
    Path area(double until) {
      final p = Path()..moveTo(0, size.height);
      for (final s in segs) {
        if (s.km > until) break;
        p.lineTo(x(s.km), y(s.altitudeM));
      }
      p
        ..lineTo(x(min(until, route.raceKm)), size.height)
        ..close();
      return p;
    }

    canvas
      ..drawPath(area(route.raceKm), Paint()..color = colors.panel2)
      ..drawPath(
        area(km),
        Paint()..color = colors.accent.withValues(alpha: 0.45),
      );
    final at = x(km);
    canvas.drawLine(
      Offset(at, 0),
      Offset(at, size.height),
      Paint()
        ..color = TeamColors.text
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_ProfilePainter old) => old.km != km || old.route != route;
}

/// The groups on the road: the head of the race on the right, the gaps to
/// the left, each group as large as it has riders.
class _RoadPainter extends CustomPainter {
  _RoadPainter(this.groups, this.colors);
  final List<GroupSample> groups;
  final TeamColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final line = Paint()
      ..color = colors.line
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), line);
    if (groups.isEmpty) return;
    final span = max(60.0, groups.map((g) => g.gapS).reduce(max) * 1.1);
    final text = TextPainter(textDirection: TextDirection.ltr);
    // From the head of the race backwards; a label that would overlap the
    // one before it is left out.
    var lastLabel = double.infinity;
    for (final g in groups) {
      final x = size.width - 18 - g.gapS / span * (size.width - 36);
      final r = min(5 + 2.2 * sqrt(g.size.toDouble()), mid - 14);
      final color = g.breakaway
          ? TeamColors.gold
          : g.gruppetto
          ? TeamColors.muted
          : g.favourites > 0
          ? colors.accent
          : TeamColors.text.withValues(alpha: 0.6);
      canvas.drawCircle(Offset(x, mid), r, Paint()..color = color);
      if (g.watched.isNotEmpty) {
        canvas.drawCircle(
          Offset(x, mid),
          r + 3,
          Paint()
            ..color = TeamColors.text
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      text
        ..text = TextSpan(
          text: '${g.size}',
          style: const TextStyle(fontSize: 10.5, color: TeamColors.text),
        )
        ..layout();
      if (x + text.width / 2 + 4 < lastLabel) {
        text.paint(
          canvas,
          Offset(x - text.width / 2, mid - r - 4 - text.height),
        );
        lastLabel = x - text.width / 2;
      }
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) => old.groups != groups;
}
