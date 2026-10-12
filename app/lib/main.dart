import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'screens/calendar_screen.dart';
import 'screens/camps_screen.dart';
import 'screens/delegation_screen.dart';
import 'screens/dev_screen.dart';
import 'screens/finance_screen.dart';
import 'screens/home_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/planner_screen.dart';
import 'screens/prep_screen.dart';
import 'screens/races_screen.dart';
import 'screens/rider_dialog.dart';
import 'screens/simulate_dialog.dart';
import 'screens/radio_panel.dart';
import 'screens/rankings_screen.dart';
import 'screens/saves_screen.dart';
import 'screens/squad_screen.dart';
import 'screens/staff_screen.dart';
import 'screens/start_screen.dart';
import 'screens/transfers_screen.dart';
import 'settings.dart';
import 'ui.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    // The layout is built for a desktop window; below this size tables and
    // side panels no longer fit.
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Radmanager',
        minimumSize: Size(1280, 760),
        backgroundColor: TeamColors.ground,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  final dataDir = AppState.findDataDir();
  final settings = dataDir == null ? null : AppSettings(dataDir);
  if (Platform.isWindows && (settings?.fullScreen ?? false)) {
    await windowManager.setFullScreen(true);
  }
  runApp(
    RadmanagerApp(
      state: dataDir == null ? null : AppState(dataDir),
      settings: settings,
      menu: true,
    ),
  );
}

/// Root widget: theme and either the game shell or a hint that the world
/// database is missing.
class RadmanagerApp extends StatelessWidget {
  /// Creates the app.
  ///
  /// @param state Application state; null if the world database is missing.
  /// @param settings Settings of the app; defaults apply without them.
  /// @param menu Whether the app opens with the start menu instead of the
  ///   running career.
  const RadmanagerApp({
    super.key,
    required this.state,
    this.settings,
    this.menu = false,
  });
  final AppState? state;
  final AppSettings? settings;
  final bool menu;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: TeamColors.ground,
      fontFamily: 'Barlow',
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 14, color: TeamColors.text),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    );
    return MaterialApp(
      title: 'Radmanager',
      debugShowCheckedModeBanner: false,
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme,
      // The whole interface can be drawn larger or smaller.
      builder: (context, child) {
        final set = settings;
        if (set == null) return child!;
        return ListenableBuilder(
          listenable: set,
          builder: (context, _) {
            final k = set.scale;
            if (k == 1) return child!;
            final size = MediaQuery.sizeOf(context);
            return OverflowBox(
              minWidth: size.width / k,
              maxWidth: size.width / k,
              minHeight: size.height / k,
              maxHeight: size.height / k,
              child: Transform.scale(
                scale: k,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(size: size / k),
                  child: child!,
                ),
              ),
            );
          },
        );
      },
      home: state == null
          ? const Scaffold(
              body: Center(
                child: Text(
                  'Die Weltdatenbank data\\world.sqlite wurde nicht gefunden.\n'
                  'Sie entsteht mit "worlddb import".',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _Root(state: state!, settings: settings, menu: menu),
    );
  }
}

/// Pages of the sidebar with label and icon.
enum _Page {
  home('Übersicht', LucideIcons.house),
  inbox('Postfach', LucideIcons.mail),
  squad('Kader', LucideIcons.users),
  dev('Nachwuchsteam', LucideIcons.graduationCap),
  camps('Trainingslager', LucideIcons.mountain),
  calendar('Kalender', LucideIcons.calendarDays),
  planner('Rennplaner', LucideIcons.calendarCheck),
  races('Rennen', LucideIcons.flag),
  rankings('Ranglisten', LucideIcons.trophy),
  transfers('Transfers', LucideIcons.arrowLeftRight),
  finance('Finanzen und Ziele', LucideIcons.landmark),
  staff('Personal', LucideIcons.idCard),
  delegation('Aufgabenverteilung', LucideIcons.clipboardList),
  saves('Spielstände', LucideIcons.save);

  const _Page(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Window frame: sidebar, header with date and continue button, and the
/// selected page.
class _Root extends StatefulWidget {
  const _Root({
    required this.state,
    required this.settings,
    required this.menu,
  });
  final AppState state;
  final AppSettings? settings;
  final bool menu;

  @override
  State<_Root> createState() => _RootState();
}

/// Switches between the start menu and the game.
class _RootState extends State<_Root> {
  late var _playing = !widget.menu;
  late final _settings =
      widget.settings ?? AppSettings(widget.state.dataDir, persist: false);

  @override
  Widget build(BuildContext context) => _playing
      ? Shell(
          state: widget.state,
          settings: _settings,
          onMenu: () {
            widget.state.flush();
            setState(() => _playing = false);
          },
        )
      : ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) => StartScreen(
            state: widget.state,
            settings: _settings,
            onPlay: () => setState(() => _playing = true),
          ),
        );
}

class Shell extends StatefulWidget {
  const Shell({
    super.key,
    required this.state,
    required this.settings,
    required this.onMenu,
  });
  final AppState state;
  final AppSettings settings;

  /// Called when the player returns to the start menu.
  final VoidCallback onMenu;

  @override
  State<Shell> createState() => _ShellState();
}

/// State of the shell: selected page and whether race preparation is shown.
class _ShellState extends State<Shell> {
  var _page = _Page.home;

  /// View to open inside the selected page, e.g. a tab of the squad.
  String? _sub;

  /// Race preparation lies on top of the selected page, but can be left to
  /// look something up in the squad or the planner.
  var _showPrep = false;
  int? _prepRace;

  @override
  void initState() {
    super.initState();
    // Replay the saved state as soon as the window is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.state.restore());
  }

  void _openRace(int id) => setState(() {
    widget.state.focusRace = id;
    _page = _Page.races;
    _showPrep = false;
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final s = widget.state;
      final c = s.colors;
      final career = s.career;
      // When one of our races starts, the game only continues after the line-up.
      final pending = s.pending;
      if (pending != null && _prepRace != pending.race.info.id) {
        _prepRace = pending.race.info.id;
        _showPrep = true;
      }
      // After the last radio call of a stage the result is shown at once.
      if (s.jumpToRace) {
        s.jumpToRace = false;
        s.riderPage = null;
        _page = _Page.races;
        _showPrep = false;
      }
      final prep = _showPrep ? pending : null;
      final loading = s.loading;
      // What comes next is shown beside the date.
      final next = career.ownRaces
          .where(
            (r) =>
                !r.start.isBefore(career.today) &&
                !career.progress.containsKey(r.info.id),
          )
          .firstOrNull;
      final days = next?.start.difference(career.today).inDays;
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(
              state: s,
              page: prep != null ? null : _page,
              onMenu: widget.onMenu,
              onPage: (p) => setState(() {
                _page = p;
                _sub = null;
                _showPrep = false;
                s.riderPage = null;
              }),
            ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 58,
                    padding: const EdgeInsets.only(left: 18),
                    decoration: BoxDecoration(
                      color: c.panel2,
                      border: Border(bottom: BorderSide(color: c.line)),
                    ),
                    child: Row(
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              prep != null
                                  ? 'Rennvorbereitung'
                                  : s.riderPage != null
                                  ? 'Fahrerprofil'
                                  : _page == _Page.finance
                                  ? 'Finanzen'
                                  : _page.label,
                              style: headStyle(23),
                            ),
                            Text(
                              '${s.team.name} · '
                              '${career.licences.of(s.team.id).label}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: TeamColors.muted,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (next != null && !career.seasonOver)
                          Padding(
                            padding: const EdgeInsets.only(right: 18),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'NÄCHSTES RENNEN',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    letterSpacing: 0.8,
                                    color: TeamColors.muted,
                                  ),
                                ),
                                Text(
                                  '${next.info.name} · '
                                  '${days == 0
                                      ? 'heute'
                                      : days == 1
                                      ? 'morgen'
                                      : 'in $days Tagen'}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        Container(width: 1, height: 34, color: c.line),
                        // The date opens a small calendar to simulate up
                        // to a chosen day.
                        Tooltip(
                          message: 'Bis zu einem Datum simulieren',
                          child: InkWell(
                            onTap: s.busy || career.seasonOver
                                ? null
                                : () => showSimulateDialog(context, s),
                            child: Container(
                              height: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    LucideIcons.calendarClock,
                                    size: 17,
                                    color: TeamColors.muted,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    career.seasonOver
                                        ? 'Saison ${career.year} beendet'
                                        : _longDate(career.today),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.accent,
                              foregroundColor: c.onAccent,
                              disabledBackgroundColor: c.panel,
                              shape: const RoundedRectangleBorder(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 26,
                              ),
                            ),
                            onPressed: s.busy || s.radio != null
                                ? null
                                : career.seasonOver
                                ? s.nextSeason
                                : pending != null
                                ? () => setState(() => _showPrep = true)
                                : s.next,
                            child: Row(
                              children: [
                                Text(
                                  loading != null
                                      ? 'LÄDT ${(loading * 100).round()} %'
                                      : s.busy
                                      ? 'LÄUFT …'
                                      : s.radio != null
                                      ? 'FUNK …'
                                      : career.seasonOver
                                      ? 'NEUE SAISON'
                                      : pending != null
                                      ? 'ZUM AUFGEBOT'
                                      : 'WEITER',
                                  style: const TextStyle(
                                    fontFamily: headFont,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                if (!s.busy && s.radio == null) ...[
                                  const SizedBox(width: 6),
                                  const Icon(LucideIcons.arrowRight, size: 18),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: s.radio != null && !s.busy
                        ? RadioPanel(state: s)
                        : s.riderPage != null && prep == null
                        ? RiderPage(
                            key: ValueKey(s.riderPage),
                            state: s,
                            riderId: s.riderPage!,
                            page: true,
                          )
                        : prep != null
                        ? PrepScreen(
                            key: ValueKey(prep.race.info.id),
                            state: s,
                            pending: prep,
                          )
                        : (switch (_page) {
                                _Page.home => HomeScreen(
                                  state: s,
                                  onOpenRace: _openRace,
                                  onInbox: () =>
                                      setState(() => _page = _Page.inbox),
                                  onNavigate: (target) => setState(() {
                                    // "page" or "page:view".
                                    final parts = target.split(':');
                                    _page = _Page.values.byName(parts[0]);
                                    _sub = parts.length > 1 ? parts[1] : null;
                                  }),
                                ),
                                _Page.inbox => InboxScreen(
                                  state: s,
                                  onOpenRace: _openRace,
                                ),
                                _Page.squad => SquadScreen(
                                  key: ValueKey(_sub),
                                  state: s,
                                  view: _sub,
                                ),
                                _Page.races => RacesScreen(state: s),
                                _Page.rankings => RankingsScreen(state: s),
                                _Page.planner => PlannerScreen(state: s),
                                _Page.transfers => TransfersScreen(state: s),
                                _Page.finance => FinanceScreen(state: s),
                                _Page.staff => StaffScreen(state: s),
                                _Page.dev => DevScreen(state: s),
                                _Page.camps => CampsScreen(state: s),
                                _Page.calendar => CalendarScreen(
                                  state: s,
                                  onOpenRace: _openRace,
                                ),
                                _Page.delegation => DelegationScreen(state: s),
                                _Page.saves => SavesScreen(state: s),
                              })
                              .animate(key: ValueKey(_page))
                              .fadeIn(
                                duration: widget.settings.animations
                                    ? 140.ms
                                    : Duration.zero,
                              ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Sidebar with the team block and the navigation.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.state,
    required this.page,
    required this.onPage,
    required this.onMenu,
  });
  final AppState state;
  final _Page? page;
  final void Function(_Page) onPage;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final c = state.colors;
    final faded = c.onSide.withValues(alpha: 0.62);

    Widget item(_Page target, {String? badge}) {
      final selected = target == page;
      return Material(
        color: selected ? c.accent : Colors.transparent,
        child: InkWell(
          onTap: () => onPage(target),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? c.onAccent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.only(left: 13, right: 12),
            child: Row(
              children: [
                Icon(
                  target.icon,
                  size: 18,
                  color: selected ? c.onAccent : faded,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    target.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? c.onAccent : c.onSide,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? c.onAccent : c.accent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? c.accent : c.onAccent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget group(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 3),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: faded,
        ),
      ),
    );

    final open = state.career.calendar
        .where((r) => state.career.entries.status(r).name == 'pending')
        .length;

    return Container(
      width: 224,
      color: c.side,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 58,
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: c.onSide.withValues(alpha: 0.18)),
              ),
            ),
            child: Row(
              children: [
                Jersey(
                  dataDir: state.dataDir,
                  abbr: state.jerseyOf(state.team.id),
                  size: 38,
                  fallback: _Badge(
                    color: TeamColors.parse(state.team.color),
                    second: TeamColors.parse(state.team.color2),
                    outline: faded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.team.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: headFont,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: c.onSide,
                        ),
                      ),
                      Text(
                        'Saison ${state.career.year}',
                        style: TextStyle(fontSize: 11.5, color: faded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          item(_Page.home),
          item(_Page.inbox, badge: state.unread > 0 ? '${state.unread}' : null),
          group('Team'),
          item(_Page.squad),
          item(_Page.dev),
          item(_Page.camps),
          group('Rennen'),
          item(_Page.calendar),
          item(_Page.planner, badge: open > 0 ? '$open' : null),
          item(_Page.races),
          item(_Page.rankings),
          group('Markt'),
          item(_Page.transfers),
          group('Führung'),
          item(_Page.finance),
          item(_Page.staff),
          item(_Page.delegation),
          const Spacer(),
          Divider(height: 1, color: c.onSide.withValues(alpha: 0.18)),
          item(_Page.saves),
          InkWell(
            onTap: state.busy ? null : onMenu,
            child: Container(
              height: 36,
              padding: const EdgeInsets.only(left: 16, right: 12),
              child: Row(
                children: [
                  Icon(LucideIcons.logOut, size: 18, color: faded),
                  const SizedBox(width: 11),
                  Text(
                    'Hauptmenü',
                    style: TextStyle(fontSize: 14, color: c.onSide),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Small team badge in the two team colours, until real jerseys are available.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.second,
    required this.outline,
  });
  final Color color;
  final Color second;
  final Color outline;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 34,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: outline),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(4),
        bottom: Radius.circular(12),
      ),
    ),
    child: Align(
      alignment: const Alignment(0, -0.2),
      child: Container(height: 8, color: second),
    ),
  );
}

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

String _longDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Heading above tables, used by the screens.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Label(title),
      const Spacer(),
      if (trailing != null)
        Text(
          trailing!,
          style: const TextStyle(fontSize: 12, color: TeamColors.muted),
        ),
    ],
  );
}
