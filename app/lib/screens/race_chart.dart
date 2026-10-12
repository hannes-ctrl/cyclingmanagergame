import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../widgets.dart';

/// Course of a stage as a chart: time gaps to the favourites' group along the
/// route, and below it how many riders that group still holds.
class RaceChart extends StatefulWidget {
  /// Creates the chart.
  ///
  /// @param result The stage result with its timeline.
  /// @param route The stage.
  /// @param colors Team colours.
  const RaceChart({
    super.key,
    required this.result,
    required this.route,
    required this.colors,
  });
  final StageResult result;
  final SimRoute route;
  final TeamColors colors;

  @override
  State<RaceChart> createState() => _RaceChartState();
}

/// State of the chart: the kilometre under the pointer.
class _RaceChartState extends State<RaceChart> {
  double? _km;

  @override
  Widget build(BuildContext context) {
    final result = widget.result, route = widget.route;
    // The sample closest to the pointer.
    RaceSample? at;
    if (_km case final km?) {
      for (final s in result.timeline) {
        if (at == null || (s.km - km).abs() < (at.km - km).abs()) at = s;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) => MouseRegion(
            onHover: (e) => setState(() {
              final x =
                  (e.localPosition.dx - _ChartPainter.left) /
                  (box.maxWidth - _ChartPainter.left - _ChartPainter.right);
              _km = x < 0 || x > 1 ? null : x * route.raceKm;
            }),
            onExit: (_) => setState(() => _km = null),
            child: CustomPaint(
              painter: _ChartPainter(result, route, widget.colors, at?.km),
              size: const Size(double.infinity, 190),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 18,
          child: at == null
              ? Wrap(
                  spacing: 14,
                  children: [
                    _legend(TeamColors.gold, tr('Spitze vor den Favoriten')),
                    _legend(TeamColors.red, tr('Mitte des Feldes')),
                    _legend(
                      widget.colors.accent,
                      tr('Fahrer in der Favoritengruppe'),
                    ),
                  ],
                )
              : Text(
                  tr(
                    'km {0} · {1} · Feldmitte {2} · {3} in der Favoritengruppe',
                    [
                      at.km.round(),
                      at.frontGapS < 1
                          ? tr('Favoriten an der Spitze')
                          : tr('Spitze ({0}) {1} voraus', [
                              at.frontSize,
                              clock(at.frontGapS),
                            ]),
                      at.lastGapS < 1
                          ? tr('bei den Favoriten')
                          : tr('{0} zurück', [clock(at.lastGapS)]),
                      at.mainSize,
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
        ),
      ],
    );
  }

  /// @param color Colour of the line.
  /// @param text What the line shows.
  /// @returns One entry of the legend.
  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 3, color: color),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(fontSize: 11, color: TeamColors.muted)),
    ],
  );
}

/// Paints the chart.
class _ChartPainter extends CustomPainter {
  _ChartPainter(this.result, this.route, this.colors, this.markKm);
  final StageResult result;
  final SimRoute route;
  final TeamColors colors;

  /// Kilometre under the pointer, drawn as a vertical line.
  final double? markKm;

  static const left = 58.0, right = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 6.0, bottom = 18.0, sizeH = 44.0;
    final line = result.timeline;
    final w = size.width - left - right;
    final gapH = size.height - top - bottom - sizeH - 10;
    final ahead = max(60.0, line.map((x) => x.frontGapS).reduce(max));
    final behind = max(60.0, line.map((x) => x.lastGapS).reduce(max));
    // The zero line sits where the two ranges meet, but never at the edge.
    final zero = top + gapH * (ahead / (ahead + behind)).clamp(0.2, 0.8);
    final upScale = (zero - top) / ahead;
    final downScale = (top + gapH - zero) / behind;
    double x(double km) => left + km / route.raceKm * w;

    void text(String s, Offset at, {bool end = false, Color? color}) {
      final p = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontFamily: 'Barlow',
            fontSize: 10.5,
            color: color ?? TeamColors.muted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, at - Offset(end ? p.width : 0, p.height / 2));
    }

    final grid = Paint()
      ..color = colors.line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, zero), Offset(left + w, zero), grid);
    text(tr('Favoriten'), Offset(left - 5, zero), end: true);
    text('+${clock(ahead)}', Offset(left - 5, top + 5), end: true);
    text('−${clock(behind)}', Offset(left - 5, top + gapH - 5), end: true);

    Path path(double Function(RaceSample) y) {
      final p = Path()..moveTo(x(0), y(line.first));
      for (final s in line) {
        p.lineTo(x(s.km), y(s));
      }
      return p;
    }

    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      path((s) => zero + s.lastGapS * downScale),
      stroke(TeamColors.red),
    );
    canvas.drawPath(
      path((s) => zero - s.frontGapS * upScale),
      stroke(TeamColors.gold),
    );

    // Attacks and the catch as marks on the zero line.
    for (final e in result.events) {
      final mark = switch (e.type) {
        EventType.attack => TeamColors.text,
        EventType.caught => TeamColors.gold,
        EventType.gruppetto => TeamColors.red,
        _ => null,
      };
      if (mark == null) continue;
      canvas.drawCircle(Offset(x(e.km), zero), 3, Paint()..color = mark);
    }

    // Size of the favourites' group.
    final base = size.height - bottom;
    final most = line.map((s) => s.mainSize).reduce(max).toDouble();
    final area = Path()..moveTo(x(0), base);
    for (final s in line) {
      area.lineTo(x(s.km), base - s.mainSize / most * sizeH);
    }
    area
      ..lineTo(x(line.last.km), base)
      ..close();
    canvas.drawPath(
      area,
      Paint()..color = colors.accent.withValues(alpha: 0.45),
    );
    canvas.drawLine(Offset(left, base), Offset(left + w, base), grid);
    text('${most.round()}', Offset(left - 5, base - sizeH + 4), end: true);
    text('${line.last.mainSize}', Offset(left - 5, base - 5), end: true);

    if (markKm case final km?) {
      canvas.drawLine(
        Offset(x(km), top),
        Offset(x(km), base),
        Paint()
          ..color = TeamColors.text.withValues(alpha: 0.55)
          ..strokeWidth = 1,
      );
    }

    final step = route.raceKm > 120 ? 50 : 20;
    for (var km = 0; km < route.raceKm; km += step) {
      text('$km', Offset(x(km.toDouble()), base + 10));
    }
    text('km', Offset(left + w, base + 10), end: true);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.result != result || old.markKm != markKm;
}

/// The own team's riders after a stage: place, role and how their race went.
class OwnRiders extends StatelessWidget {
  /// Creates the list.
  ///
  /// @param result The stage result with its rider traces.
  /// @param route The stage.
  /// @param teamId The own team.
  const OwnRiders({
    super.key,
    required this.result,
    required this.route,
    required this.teamId,
  });
  final StageResult result;
  final SimRoute route;
  final int teamId;

  /// @param t A rider's trace.
  /// @returns What happened to him, in a few words.
  String _note(RiderTrace t) {
    final parts = <String>[
      if (t.inBreak) tr('in der Gruppe des Tages'),
      if (t.gruppetto)
        tr('im Gruppetto')
      else if (t.lostKm case final km?)
        tr('abgehängt {0} km vor dem Ziel', [(route.raceKm - km).round()])
      else if (!t.inBreak)
        tr('bei den Favoriten'),
      if (t.frontKm >= 10) tr('{0} km Führungsarbeit', [t.frontKm.round()]),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final p = result.placings;
    return Column(
      children: [
        for (var i = 0; i < p.length; i++)
          if (p[i].rider.teamId == teamId)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${i + 1}.',
                      style: const TextStyle(
                        color: TeamColors.muted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p[i].rider.name),
                        if (result.traces[p[i].rider.id] case final t?)
                          Text(
                            '${t.role.label} · ${_note(t)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: TeamColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    i == 0
                        ? clock(p[i].timeS)
                        : gap(
                            p[i].timeS.roundToDouble() -
                                result.winnerTimeS.roundToDouble(),
                          ),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
