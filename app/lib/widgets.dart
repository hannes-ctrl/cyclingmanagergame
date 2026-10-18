import 'dart:io';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sim/sim.dart';

import 'app_state.dart';
import 'ui.dart';

/// @param seconds A duration.
/// @returns `h:mm:ss`, or `m:ss` below one hour.
String clock(double seconds) {
  final t = seconds.round();
  final h = t ~/ 3600, m = t % 3600 ~/ 60, s = t % 60;
  final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

/// Formats an amount of money briefly, in German notation.
///
/// @param v Amount in euros.
/// @returns E.g. "1,25 Mio." or "180 T".
String euro(num v) => v.abs() >= 1000000
    ? tr('{0} m', [dec(v / 1000000, 2)])
    : '${(v / 1000).round()} T';

/// @param seconds Gap to the first rider.
/// @returns "gl. Zeit" (same time) or e.g. "+1:23".
String gap(double seconds) =>
    seconds.round() == 0 ? tr('s.t.') : '+${clock(seconds)}';

/// @param v A rider attribute.
/// @returns Its colour: green from 72, yellow from 78, pale below 65.
Color attributeColor(double v) => v >= 78
    ? TeamColors.gold
    : v >= 72
    ? TeamColors.green
    : v < 65
    ? TeamColors.muted
    : TeamColors.text;

/// Small upper-case heading of a panel.
class Label extends StatelessWidget {
  const Label(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1,
      color: TeamColors.muted,
    ),
  );
}

/// Card with a border in the team's tint; the building block of every screen.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.colors,
    required this.child,
    this.padding = 12,
  });
  final TeamColors colors;
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: colors.panel,
      border: Border.all(color: colors.line),
      borderRadius: BorderRadius.circular(6),
    ),
    child: child,
  );
}

/// Column of a dense table.
class Col<T> {
  const Col(
    this.title,
    this.width,
    this.cell, {
    this.numeric = false,
    this.sortKey,
  });
  final String title;
  final double width;
  final Widget Function(T row, int index) cell;
  final bool numeric;

  /// Value the column sorts by; null = not sortable.
  final Comparable<dynamic> Function(T row)? sortKey;
}

/// Table with fixed column widths and low rows, as is usual in management
/// games. Highlighted rows stand out.
class DenseTable<T> extends StatefulWidget {
  const DenseTable({
    super.key,
    required this.colors,
    required this.columns,
    required this.rows,
    this.highlight,
    this.onTap,
  });
  final TeamColors colors;
  final List<Col<T>> columns;
  final List<T> rows;
  final bool Function(T row)? highlight;
  final void Function(T row)? onTap;

  /// Moves the cursor of the table the mouse is over, or opens its row.
  ///
  /// @param key Arrow up, arrow down, page up, page down, home, end or enter.
  /// @returns Whether a table took the key.
  static bool handleKey(LogicalKeyboardKey key) {
    if (_activeTable?._key(key) ?? false) return true;
    // No table under the mouse: the one opened last that is in front.
    for (final table in _tables.reversed) {
      if (!identical(table, _activeTable) && table._key(key)) return true;
    }
    return false;
  }

  @override
  State<DenseTable<T>> createState() => _DenseTableState<T>();
}

/// The table that takes the arrow keys: the one the mouse entered last.
_TableKeys? _activeTable;

/// All tables alive, in the order they were opened.
final _tables = <_TableKeys>[];

/// What [DenseTable.handleKey] needs of a table, whatever its row type.
abstract class _TableKeys {
  bool _key(LogicalKeyboardKey key);
}

/// State of the table: sort column, direction and scroll position.
class _DenseTableState<T> extends State<DenseTable<T>> implements _TableKeys {
  int? _sortColumn;
  bool _descending = true;
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  /// Row the keyboard cursor is on, or null before the first key.
  int? _cursor;

  /// The rows as shown, after sorting.
  List<T> _shown = const [];

  static const _rowHeight = 28.0;

  @override
  void initState() {
    super.initState();
    _tables.add(this);
  }

  @override
  void dispose() {
    _tables.remove(this);
    if (identical(_activeTable, this)) _activeTable = null;
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  bool _key(LogicalKeyboardKey key) {
    // A table on a page that is not in front does not react.
    if (!mounted || _shown.isEmpty) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;
    final last = _shown.length - 1;
    final page = _vertical.hasClients
        ? (_vertical.position.viewportDimension / _rowHeight).floor() - 1
        : 10;
    final at = _cursor;
    int? to;
    if (key == LogicalKeyboardKey.arrowDown) {
      to = at == null ? 0 : at + 1;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      to = at == null ? 0 : at - 1;
    } else if (key == LogicalKeyboardKey.pageDown) {
      to = (at ?? 0) + page;
    } else if (key == LogicalKeyboardKey.pageUp) {
      to = (at ?? 0) - page;
    } else if (key == LogicalKeyboardKey.home) {
      to = 0;
    } else if (key == LogicalKeyboardKey.end) {
      to = last;
    } else if (key == LogicalKeyboardKey.enter && at != null) {
      if (widget.onTap == null || at > last) return false;
      widget.onTap!(_shown[at]);
      return true;
    }
    if (to == null) return false;
    final row = to.clamp(0, last);
    setState(() => _cursor = row);
    // Keep the cursor in view.
    if (_vertical.hasClients) {
      final top = row * _rowHeight;
      final view = _vertical.position;
      if (top < view.pixels) {
        _vertical.jumpTo(top);
      } else if (top + _rowHeight > view.pixels + view.viewportDimension) {
        _vertical.jumpTo(top + _rowHeight - view.viewportDimension);
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    var rows = widget.rows;
    final sort = _sortColumn == null
        ? null
        : widget.columns[_sortColumn!].sortKey;
    if (sort != null) {
      rows = [...rows]
        ..sort(
          (a, b) => _descending
              ? sort(b).compareTo(sort(a))
              : sort(a).compareTo(sort(b)),
        );
    }
    _shown = rows;
    if (_cursor != null && _cursor! >= rows.length) _cursor = null;
    final width = widget.columns.fold<double>(0, (s, x) => s + x.width);

    Widget cellBox(Col<T> col, Widget child) => SizedBox(
      width: col.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(
          alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      ),
    );

    final header = Row(
      children: [
        for (var i = 0; i < widget.columns.length; i++)
          InkWell(
            onTap: widget.columns[i].sortKey == null
                ? null
                : () => setState(() {
                    _descending = _sortColumn == i ? !_descending : true;
                    _sortColumn = i;
                  }),
            child: SizedBox(
              height: 28,
              child: withHelp(
                widget.columns[i].title,
                cellBox(
                  widget.columns[i],
                  // A long title shrinks rather than breaking over two lines.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: widget.columns[i].numeric
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Label(
                      widget.columns[i].title +
                          (_sortColumn == i ? (_descending ? ' ▼' : ' ▲') : ''),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return MouseRegion(
      onEnter: (_) => _activeTable = this,
      child: LayoutBuilder(
        builder: (context, box) => Scrollbar(
          controller: _horizontal,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: max(width, box.maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: c.line)),
                    ),
                    child: header,
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _vertical,
                      itemCount: rows.length,
                      itemExtent: _rowHeight,
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        final own = widget.highlight?.call(row) ?? false;
                        final cursor = i == _cursor;
                        return InkWell(
                          onTap: widget.onTap == null
                              ? null
                              : () {
                                  _cursor = i;
                                  widget.onTap!(row);
                                },
                          child: Container(
                            decoration: BoxDecoration(
                              color: cursor
                                  ? c.accent.withValues(alpha: 0.22)
                                  : own
                                  ? c.panel2
                                  : null,
                              border: Border(bottom: BorderSide(color: c.line)),
                            ),
                            // Painted over the row, so that the bar takes
                            // no width from the cells.
                            foregroundDecoration: cursor
                                ? BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: c.accent,
                                        width: 3,
                                      ),
                                    ),
                                  )
                                : null,
                            child: Row(
                              children: [
                                for (final col in widget.columns)
                                  cellBox(col, col.cell(row, i)),
                              ],
                            ),
                          ),
                        );
                      },
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

/// Builds a single-line table cell.
///
/// @param text Cell text.
/// @param color Text colour; defaults to the normal text colour.
/// @param bold Whether to emphasise the text.
/// @returns The text widget.
Widget cellText(String text, {Color? color, bool bold = false}) => Text(
  text,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(
    fontSize: 13,
    color: color ?? TeamColors.text,
    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
    fontFeatures: const [FontFeature.tabularFigures()],
  ),
);

/// Elevation profile of a stage with mountain prizes, sprints, cobbled
/// sectors and the roads open to the crosswind (light blue at the bottom).
class ProfileView extends StatelessWidget {
  const ProfileView({super.key, required this.route, required this.colors});
  final SimRoute route;
  final TeamColors colors;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ProfilePainter(route, colors),
    size: const Size(double.infinity, 210),
  );
}

/// Paints the profile.
class _ProfilePainter extends CustomPainter {
  _ProfilePainter(this.route, this.colors);
  final SimRoute route;
  final TeamColors colors;

  static const _categories = ['', 'HC', '1', '2', '3', '4'];

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, right = 10.0, top = 34.0, bottom = 22.0;
    final w = size.width - left - right, h = size.height - top - bottom;
    // Sum up altitudes from the gradients of the segments.
    final km = <double>[0], alt = <double>[route.startAltitudeM];
    for (final s in route.segments) {
      km.add(s.km + s.lengthM / 1000);
      alt.add(alt.last + s.grade * s.lengthM);
    }
    final scale = max(500.0, (alt.reduce(max) / 500).ceil() * 500.0);
    double x(double k) => left + k / route.raceKm * w;
    double y(double a) => top + h - max(a, 0) / scale * h;
    double altitudeAt(double k) =>
        alt[(k / route.raceKm * (alt.length - 1)).round().clamp(
          0,
          alt.length - 1,
        )];

    void text(
      String s,
      Offset at, {
      Color? color,
      double size = 11,
      bool center = false,
      bool end = false,
      bool bold = false,
    }) {
      final p = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontFamily: 'Barlow',
            fontSize: size,
            color: color ?? TeamColors.muted,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(
        canvas,
        at -
            Offset(
              center
                  ? p.width / 2
                  : end
                  ? p.width
                  : 0,
              p.height / 2,
            ),
      );
    }

    final grid = Paint()..color = colors.line;
    for (var a = 0.0; a <= scale; a += scale > 2000 ? 1000 : 500) {
      canvas.drawLine(Offset(left, y(a)), Offset(left + w, y(a)), grid);
      text(a.round().toString(), Offset(left - 6, y(a)), end: true);
    }
    final step = route.raceKm > 120
        ? 20
        : route.raceKm > 40
        ? 10
        : 5;
    for (var k = 0; k <= route.raceKm; k += step) {
      text('$k', Offset(x(k.toDouble()), top + h + 12), center: true);
    }

    // Roads open to the wind, light blue as in the classic manager games:
    // where a crosswind can split the field.
    final open = exposedSegments(route);
    for (var i = 0; i < route.segments.length; i++) {
      if (!open[i]) continue;
      final s = route.segments[i];
      canvas.drawRect(
        Rect.fromLTRB(
          x(s.km),
          top + h - 8,
          max(x(s.km) + 1, x(s.km + s.lengthM / 1000)),
          top + h,
        ),
        Paint()..color = const Color(0xFF7FD1FF).withValues(alpha: 0.75),
      );
    }

    for (final s in route.segments) {
      if (s.cobble == 0 && s.unpaved == 0) continue;
      final difficulty = max(s.cobble, s.unpaved);
      canvas.drawRect(
        Rect.fromLTRB(
          x(s.km),
          top,
          max(x(s.km) + 1.5, x(s.km + s.lengthM / 1000)),
          top + h,
        ),
        Paint()
          ..color = (s.cobble > 0 ? TeamColors.red : TeamColors.gold)
              .withValues(alpha: 0.2 + difficulty * 0.1),
      );
    }

    final path = Path()..moveTo(x(0), y(0));
    for (var i = 0; i < km.length; i++) {
      path.lineTo(x(km[i]), y(alt[i]));
    }
    path
      ..lineTo(x(route.raceKm), y(0))
      ..close();
    canvas.drawPath(path, Paint()..color = colors.panel2);
    final outline = Path()..moveTo(x(km[0]), y(alt[0]));
    for (var i = 1; i < km.length; i++) {
      outline.lineTo(x(km[i]), y(alt[i]));
    }
    canvas.drawPath(
      outline,
      Paint()
        ..color = TeamColors.text
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    void marker(double k, String label, Color color) {
      final cx = x(k.clamp(0, route.raceKm));
      canvas.drawLine(
        Offset(cx, y(altitudeAt(k))),
        Offset(cx, top - 6),
        Paint()..color = color.withValues(alpha: 0.6),
      );
      canvas.drawCircle(Offset(cx, top - 15), 9, Paint()..color = color);
      text(
        label,
        Offset(cx, top - 15),
        color: TeamColors.ground,
        size: 10,
        center: true,
        bold: true,
      );
    }

    for (final p in route.sprints) {
      marker(p.km, 'S', TeamColors.green);
    }
    for (final p in route.climbTops) {
      marker(p.km, _categories[p.category.clamp(0, 5)], TeamColors.red);
    }
  }

  @override
  bool shouldRepaint(_ProfilePainter old) =>
      old.route != route || old.colors != colors;
}

/// Row of underlined tabs as used at the top of a page in Football Manager.
class TabStrip<T> extends StatelessWidget {
  /// Creates a tab strip.
  ///
  /// @param colors Team colours.
  /// @param tabs Tab values with their labels, in display order.
  /// @param value The selected tab.
  /// @param onChanged Called with the tab the player clicked.
  /// @param trailing Optional widget at the right end of the strip.
  const TabStrip({
    super.key,
    required this.colors,
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.trailing,
  });
  final TeamColors colors;
  final Map<T, String> tabs;
  final T value;
  final void Function(T) onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: colors.panel,
      border: Border(bottom: BorderSide(color: colors.line)),
    ),
    child: Row(
      children: [
        for (final e in tabs.entries)
          InkWell(
            onTap: () => onChanged(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: e.key == value ? colors.accent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                e.value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: e.key == value ? TeamColors.text : TeamColors.muted,
                ),
              ),
            ),
          ),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

/// Names a rider's type after his strongest main attribute.
///
/// @param r The rider.
/// @returns A label such as "Climber" or "Sprinter", untranslated.
String riderType(SimRider r) {
  final a = r.attributes;
  final best = {
    'Climber': a.mountain,
    'Puncheur': a.hill,
    'Sprinter': a.sprint,
    'Time trialist': a.timeTrial,
    'Cobbles specialist': a.cobble,
    'Rouleur': a.flat,
  }.entries.reduce((x, y) => y.value > x.value ? y : x);
  // An all-rounder has no attribute that clearly stands out.
  final second = [a.mountain, a.hill, a.sprint, a.timeTrial, a.cobble, a.flat]
    ..sort((x, y) => y.compareTo(x));
  return second[0] - second[3] < 4 ? 'All-rounder' : best.key;
}

/// Team jersey from the WorldDB's graphics pack, exported to `data/jerseys`
/// by `worlddb jerseys`. Shows [fallback] for teams without a picture.
class Jersey extends StatelessWidget {
  /// Creates a jersey picture.
  ///
  /// @param dataDir The data folder of the app.
  /// @param abbr Team abbreviation; the file is named after it.
  /// @param size Edge length in logical pixels.
  /// @param fallback Shown when there is no picture.
  const Jersey({
    super.key,
    required this.dataDir,
    required this.abbr,
    this.size = 28,
    this.fallback,
  });
  final String dataDir;
  final String abbr;
  final double size;
  final Widget? fallback;

  // Whether a file exists, per path; checked once.
  static final _exists = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final path = '$dataDir/jerseys/${abbr.toLowerCase()}.png';
    if (!_exists.putIfAbsent(path, () => File(path).existsSync())) {
      return fallback ?? SizedBox(width: size, height: size);
    }
    return Image.file(
      File(path),
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) =>
          fallback ?? SizedBox(width: size, height: size),
    );
  }
}

/// Small line chart without axes, with the first and last value written at
/// its ends.
class Sparkline extends StatelessWidget {
  /// Creates the chart.
  ///
  /// @param values The series, oldest first; needs at least two values.
  /// @param color Colour of the line.
  /// @param label Formats a value for the labels at both ends.
  /// @param height Height of the chart.
  /// @param baseline Optional value drawn as a thin reference line.
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    required this.label,
    this.height = 54,
    this.baseline,
  });
  final List<double> values;
  final Color color;
  final String Function(double) label;
  final double height;
  final double? baseline;

  /// @returns The chart definition: one line, no axes, the value under the
  ///   pointer as a tooltip.
  LineChartData _data() {
    final all = [...values, ?baseline];
    final low = all.reduce(min), high = all.reduce(max);
    final pad = (high - low < 1e-9 ? 1.0 : high - low) * 0.12;
    return LineChartData(
      minY: low - pad,
      maxY: high + pad,
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          if (baseline case final b?)
            HorizontalLine(
              y: b,
              color: TeamColors.muted.withValues(alpha: 0.35),
              strokeWidth: 1,
            ),
        ],
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => TeamColors.ground,
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                label(s.y),
                TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [for (final (i, v) in values.indexed) FlSpot(i.toDouble(), v)],
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: color.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label(values.first),
        style: const TextStyle(fontSize: 12, color: TeamColors.muted),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: SizedBox(height: height, child: LineChart(_data())),
      ),
      const SizedBox(width: 8),
      Text(
        label(values.last),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    ],
  );
}

/// Photo of a rider from the WorldDB's graphics pack, exported to
/// `data/photos` by `worlddb photos`. Riders without one, such as generated
/// young riders, show a neutral silhouette.
class RiderPhoto extends StatelessWidget {
  /// Creates a rider photo.
  ///
  /// @param dataDir The data folder of the app.
  /// @param riderId Id of the rider; the file is named after it.
  /// @param size Edge length in logical pixels.
  const RiderPhoto({
    super.key,
    required this.dataDir,
    required this.riderId,
    this.size = 64,
  });
  final String dataDir;
  final int riderId;
  final double size;

  // Whether a file exists, per path; checked once.
  static final _exists = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final path = '$dataDir/photos/$riderId.png';
    final blank = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2B2745),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      // Head and shoulders, cut off by the frame.
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: size * 0.2,
            child: Container(
              width: size * 0.34,
              height: size * 0.34,
              decoration: const BoxDecoration(
                color: Color(0xFF6E6894),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: size * 0.62,
            child: Container(
              width: size * 0.72,
              height: size * 0.72,
              decoration: const BoxDecoration(
                color: Color(0xFF6E6894),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
    if (!_exists.putIfAbsent(path, () => File(path).existsSync())) {
      return blank;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => blank,
      ),
    );
  }
}

/// An explanation behind a small info symbol: shown when the pointer rests
/// on it, so that the pages stay calm.
class InfoTip extends StatelessWidget {
  const InfoTip(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 250),
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      textStyle: const TextStyle(fontSize: 13, color: TeamColors.ground),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Icon(Icons.info_outline, size: 16, color: TeamColors.muted),
      ),
    ),
  );
}
