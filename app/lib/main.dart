import 'package:sim/sim.dart';

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'screens/calendar_screen.dart';
import 'screens/camps_screen.dart';
import 'screens/delegation_screen.dart';
import 'screens/debug_screen.dart';
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
import 'screens/search_screen.dart';
import 'screens/squad_screen.dart';
import 'screens/staff_screen.dart';
import 'screens/start_screen.dart';
import 'screens/help_dialog.dart';
import 'screens/team_screen.dart';
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
      canvasColor: const Color(0xFF241F3D),
      dividerColor: const Color(0xFF3A3558),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: TeamColors.text,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(fontSize: 12.5, color: TeamColors.ground),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TeamColors.text,
          disabledForegroundColor: TeamColors.muted.withValues(alpha: 0.5),
          side: BorderSide(color: TeamColors.muted.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Barlow',
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: TeamColors.text,
          disabledForegroundColor: TeamColors.muted.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(
            fontFamily: 'Barlow',
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: TeamColors.ground,
        hintStyle: const TextStyle(color: TeamColors.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(
            color: TeamColors.muted.withValues(alpha: 0.45),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: TeamColors.text),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: TeamColors.text,
        selectionColor: Color(0x55A59FC8),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1E1B33),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: TeamColors.muted.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(6),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Barlow Semi Condensed',
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: TeamColors.text,
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(color: Color(0xFF241F3D)),
      checkboxTheme: CheckboxThemeData(
        side: const BorderSide(color: TeamColors.muted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(7),
        radius: const Radius.circular(4),
        thumbColor: WidgetStatePropertyAll(
          TeamColors.muted.withValues(alpha: 0.4),
        ),
      ),
    );
    return ListenableBuilder(
      listenable: settings ?? _noSettings,
      builder: (context, _) => _app(theme),
    );
  }

  static final _noSettings = ValueNotifier(0);

  /// @param theme The theme of the app.
  /// @returns The app in the current language.
  Widget _app(ThemeData theme) {
    return MaterialApp(
      title: 'Radmanager',
      debugShowCheckedModeBanner: false,
      // The arrow keys belong to lists and to the rider page. By default
      // they would also move the focus from button to button, and Enter
      // would then press whatever it landed on.
      shortcuts: {
        for (final e in WidgetsApp.defaultShortcuts.entries)
          if (e.value is! DirectionalFocusIntent) e.key: e.value,
      },
      locale: Locale(I18n.lang.name),
      supportedLocales: const [Locale('en'), Locale('de')],
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
            // Colours for colour-blind players, over everything.
            if (set.vision.matrix case final m?) {
              child = ColorFiltered(
                colorFilter: ColorFilter.matrix(m),
                child: child,
              );
            }
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
          ? Scaffold(
              body: Center(
                child: Text(
                  tr(
                    'The world database data\\world.sqlite was not found.\nIt is created with "worlddb import".',
                  ),
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
  home('Home', LucideIcons.house),
  inbox('Inbox', LucideIcons.mail),
  squad('Squad', LucideIcons.users),
  dev('Development team', LucideIcons.graduationCap),
  camps('Training camps', LucideIcons.mountain),
  calendar('Calendar', LucideIcons.calendarDays),
  planner('Race planner', LucideIcons.calendarCheck),
  races('Races', LucideIcons.flag),
  rankings('Rankings', LucideIcons.trophy),
  transfers('Transfers', LucideIcons.arrowLeftRight),
  search('Rider search', LucideIcons.search),
  finance('Finances and goals', LucideIcons.landmark),
  staff('Staff', LucideIcons.idCard),
  delegation('Delegation', LucideIcons.clipboardList),
  saves('Save games', LucideIcons.save),
  debug('Debug', LucideIcons.bug);

  const _Page(this._label, this.icon);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
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

/// A place the player has been: page, view inside it and open rider.
typedef _Place = ({_Page page, String? sub, int? rider, int? team});

/// State of the shell: selected page and whether race preparation is shown.
class _ShellState extends State<Shell> {
  var _page = _Page.home;

  // History of the places visited, for back and forward.
  final _back = <_Place>[];
  final _forward = <_Place>[];
  _Place? _here;
  var _moving = false;

  /// Notes where the player is now. A change that did not come from back
  /// or forward adds the place left to the history.
  ///
  /// @param now Page, view and rider currently shown.
  void _track(_Place now) {
    final s = widget.state;
    if (_here != null && now != _here && !_moving && !s.riderStepped) {
      _back.add(_here!);
      if (_back.length > 60) _back.removeAt(0);
      _forward.clear();
    }
    _moving = false;
    s.riderStepped = false;
    _here = now;
  }

  /// Shows a place from the history.
  void _show(_Place p) => setState(() {
    _moving = true;
    _page = p.page;
    _sub = p.sub;
    _showPrep = false;
    widget.state.riderPage = p.rider;
    widget.state.teamPage = p.team;
  });

  void _goBack() {
    if (_back.isEmpty || _here == null) return;
    _forward.add(_here!);
    _show(_back.removeLast());
  }

  void _goForward() {
    if (_forward.isEmpty || _here == null) return;
    _back.add(_here!);
    _show(_forward.removeLast());
  }

  /// What the continue button does at the moment, or null while it is off.
  VoidCallback? get _continue {
    final s = widget.state;
    if (s.busy || s.radio != null) return null;
    if (s.career.seasonOver) return s.nextSeason;
    if (s.pending != null) return () => setState(() => _showPrep = true);
    return s.next;
  }

  /// Keyboard shortcuts of the shell. They rest while a dialog is open and
  /// while the player is typing.
  ///
  /// @param e The key event.
  /// @returns Whether the key was used.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final s = widget.state;
    final key = e.logicalKey;
    final keys = HardwareKeyboard.instance;
    // Ctrl+S: a quick save with today's date in its name.
    if (keys.isControlPressed && key == LogicalKeyboardKey.keyS) {
      final answer = s.quickSave();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(answer ?? tr('Saved as a quick save.'))),
      );
      return true;
    }
    if (key == LogicalKeyboardKey.f1) {
      showHelpDialog(context, s);
      return true;
    }
    if (keys.isControlPressed && key == LogicalKeyboardKey.keyF) {
      setState(() {
        _page = _Page.search;
        _sub = null;
        _showPrep = false;
        s.riderPage = null;
        s.teamPage = null;
      });
      return true;
    }
    final focus = FocusManager.instance.primaryFocus;
    final typing =
        focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (typing) return false;
    if (key == LogicalKeyboardKey.escape ||
        keys.isAltPressed && key == LogicalKeyboardKey.arrowLeft) {
      _goBack();
      return true;
    }
    if (keys.isAltPressed && key == LogicalKeyboardKey.arrowRight) {
      _goForward();
      return true;
    }
    if (key == LogicalKeyboardKey.space) {
      _continue?.call();
      return true;
    }
    // The number keys open the first nine pages of the sidebar.
    final digit = _digits.indexOf(key);
    if (digit >= 0 && !keys.isControlPressed && !keys.isAltPressed) {
      setState(() {
        _page = _Page.values[digit];
        _sub = null;
        _showPrep = false;
        s.riderPage = null;
        s.teamPage = null;
      });
      return true;
    }
    // In a list the arrow keys move the cursor and Enter opens the row.
    if (s.riderPage == null && !_showPrep && DenseTable.handleKey(key)) {
      return true;
    }
    if (s.riderPage != null && !_showPrep) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowUp) {
        s.stepRider(-1);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowDown) {
        s.stepRider(1);
        return true;
      }
    }
    return false;
  }

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

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
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _openRace(int id) => setState(() {
    widget.state.focusRace = id;
    _page = _Page.races;
    _showPrep = false;
  });

  // Pages visited in this career stay alive, so that their filters, sorting
  // and scroll position are still there on return. Only the page in front
  // is rebuilt; the others keep the widget of their last visit.
  final _alive = <_Page, Widget>{};
  Object? _careerSeen;
  var _epoch = 0;

  /// @param s Application state.
  /// @returns All pages visited so far, the selected one visible unless a
  ///   rider or team page lies on top.
  List<Widget> _pages(AppState s) {
    if (!identical(_careerSeen, s.career)) {
      // Another career: nothing of the old pages applies any more.
      _careerSeen = s.career;
      _alive.clear();
      _epoch++;
    }
    final covered = s.riderPage != null || s.teamPage != null;
    _alive[_page] = _screen(_page, s)
        .animate(key: ValueKey(_page))
        .fadeIn(duration: widget.settings.animations ? 140.ms : Duration.zero);
    return [
      for (final e in _alive.entries)
        KeyedSubtree(
          key: ValueKey('page-$_epoch-${e.key.name}'),
          child: Offstage(
            offstage: e.key != _page || covered,
            child: TickerMode(
              enabled: e.key == _page && !covered,
              child: e.value,
            ),
          ),
        ),
    ];
  }

  /// @param page A page of the sidebar.
  /// @param s Application state.
  /// @returns Its screen.
  Widget _screen(_Page page, AppState s) => switch (page) {
    _Page.home => HomeScreen(
      state: s,
      onOpenRace: _openRace,
      onInbox: () => setState(() => _page = _Page.inbox),
      onNavigate: (target) => setState(() {
        // "page" or "page:view".
        final parts = target.split(':');
        _page = _Page.values.byName(parts[0]);
        _sub = parts.length > 1 ? parts[1] : null;
      }),
    ),
    _Page.inbox => InboxScreen(state: s, onOpenRace: _openRace),
    _Page.squad => SquadScreen(key: ValueKey(_sub), state: s, view: _sub),
    _Page.races => RacesScreen(state: s),
    _Page.rankings => RankingsScreen(state: s),
    _Page.planner => PlannerScreen(state: s),
    _Page.transfers => TransfersScreen(state: s),
    _Page.search => SearchScreen(state: s),
    _Page.debug => DebugScreen(state: s),
    _Page.finance => FinanceScreen(state: s),
    _Page.staff => StaffScreen(state: s),
    _Page.dev => DevScreen(state: s),
    _Page.camps => CampsScreen(state: s),
    _Page.calendar => CalendarScreen(state: s, onOpenRace: _openRace),
    _Page.delegation => DelegationScreen(state: s),
    _Page.saves => SavesScreen(state: s),
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final s = widget.state;
      final c = s.colors;
      final career = s.career;
      // Debug mode comes from the settings and reaches the screens and the
      // scouting through the state.
      s.debug = widget.settings.debug;
      career.staff.revealAll = s.debug;
      if (!s.debug && _page == _Page.debug) _page = _Page.home;
      // When one of our races starts, the game only continues after the line-up.
      final pending = s.pending;
      if (pending != null && _prepRace != pending.race.info.id) {
        _prepRace = pending.race.info.id;
        _showPrep = true;
      }
      // Another screen asked for a page.
      if (s.jumpToPage case final target?) {
        s.jumpToPage = null;
        final parts = target.split(':');
        _page = _Page.values.byName(parts[0]);
        _sub = parts.length > 1 ? parts[1] : null;
        _showPrep = false;
        s.riderPage = null;
        s.teamPage = null;
      }
      // After the last radio call of a stage the result is shown at once.
      if (s.jumpToRace) {
        s.jumpToRace = false;
        s.riderPage = null;
        s.teamPage = null;
        _page = _Page.races;
        _showPrep = false;
      }
      final prep = _showPrep ? pending : null;
      final loading = s.loading;
      _track((page: _page, sub: _sub, rider: s.riderPage, team: s.teamPage));
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
        // The back and forward buttons of the mouse.
        body: Listener(
          onPointerDown: (e) {
            if (e.buttons & kBackMouseButton != 0) _goBack();
            if (e.buttons & kForwardMouseButton != 0) _goForward();
          },
          // A button clicked with the mouse must not keep the focus:
          // otherwise the space bar would press it again instead of
          // continuing. Text fields keep theirs.
          onPointerUp: (_) => Future.microtask(() {
            final focus = FocusManager.instance.primaryFocus;
            if (focus == null || focus is FocusScopeNode) return;
            if (focus.context?.findAncestorWidgetOfExactType<EditableText>() ==
                null) {
              focus.unfocus();
            }
          }),
          child: Row(
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
                  s.teamPage = null;
                }),
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 58,
                      padding: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: c.panel2,
                        border: Border(bottom: BorderSide(color: c.line)),
                      ),
                      child: Row(
                        children: [
                          _NavArrow(
                            icon: LucideIcons.arrowLeft,
                            tooltip: tr('Back (Alt+←, Esc)'),
                            onPressed: _back.isEmpty ? null : _goBack,
                            bar: c.panel2,
                          ),
                          _NavArrow(
                            icon: LucideIcons.arrowRight,
                            tooltip: tr('Forward (Alt+→)'),
                            onPressed: _forward.isEmpty ? null : _goForward,
                            bar: c.panel2,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prep != null
                                    ? tr('Race preparation')
                                    : s.riderPage != null
                                    ? tr('Rider profile')
                                    : s.teamPage != null
                                    ? tr('Team profile')
                                    : _page == _Page.finance
                                    ? tr('Finances')
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
                          if (s.debug)
                            Container(
                              margin: const EdgeInsets.only(right: 16),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: TeamColors.gold),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'DEBUG · Seed ${career.seed}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: TeamColors.gold,
                                ),
                              ),
                            ),
                          // While days run: what is being simulated.
                          if (s.busy &&
                              (s.working != null || s.simulatingTo != null))
                            Padding(
                              padding: const EdgeInsets.only(right: 18),
                              child: Row(
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        tr('SIMULATING'),
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          letterSpacing: 0.8,
                                          color: TeamColors.gold,
                                        ),
                                      ),
                                      Text(
                                        s.working ?? tr('Days without races'),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      // Progress of a run to a date.
                                      if (s.simulatingTo != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 3,
                                          ),
                                          child: SizedBox(
                                            width: 120,
                                            child: LinearProgressIndicator(
                                              value: s.runProgress,
                                              minHeight: 3,
                                              color: TeamColors.gold,
                                              backgroundColor: c.line,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 10),
                                  Tooltip(
                                    message: tr('Stop after the current day'),
                                    child: IconButton(
                                      onPressed: s.stopRequested
                                          ? null
                                          : s.stopRun,
                                      icon: const Icon(
                                        LucideIcons.circleStop,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (next != null && !career.seasonOver)
                            Padding(
                              padding: const EdgeInsets.only(right: 18),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    tr('NEXT RACE'),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      letterSpacing: 0.8,
                                      color: TeamColors.muted,
                                    ),
                                  ),
                                  Text(
                                    '${next.info.name} · '
                                    '${days == 0
                                        ? tr('today')
                                        : days == 1
                                        ? tr('tomorrow')
                                        : tr('in {0} days', [days])}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          Container(width: 1, height: 34, color: c.line),
                          // The date opens a small calendar to simulate up
                          // to a chosen day.
                          Tooltip(
                            message: tr('Simulate to a date'),
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
                                          ? tr('Season {0} finished', [
                                              career.year,
                                            ])
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
                              onPressed: _continue,
                              child: Row(
                                children: [
                                  Text(
                                    loading != null
                                        ? tr('LOADING {0} %', [
                                            (loading * 100).round(),
                                          ])
                                        : s.busy
                                        ? tr('RUNNING …')
                                        : s.radio != null
                                        ? tr('RADIO …')
                                        : career.seasonOver
                                        ? tr('NEW SEASON')
                                        : pending != null
                                        ? tr('TO THE LINE-UP')
                                        : tr('CONTINUE'),
                                    style: const TextStyle(
                                      fontFamily: headFont,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  if (!s.busy && s.radio == null) ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      LucideIcons.arrowRight,
                                      size: 18,
                                    ),
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
                          : prep != null
                          ? PrepScreen(
                              key: ValueKey(prep.race.info.id),
                              state: s,
                              pending: prep,
                            )
                          // The page stays alive under the rider page, so that
                          // its filters, sorting and scroll position are still
                          // there on the way back.
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                ..._pages(s),
                                if (s.teamPage != null && s.riderPage == null)
                                  Positioned.fill(
                                    child: TeamPage(
                                      key: ValueKey('team-${s.teamPage}'),
                                      state: s,
                                      teamId: s.teamPage!,
                                    ),
                                  ),
                                if (s.riderPage != null)
                                  Positioned.fill(
                                    child: RiderPage(
                                      key: ValueKey(s.riderPage),
                                      state: s,
                                      riderId: s.riderPage!,
                                      page: true,
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
                        tr('Season {0}', [state.career.year]),
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
          group(tr('Races')),
          item(_Page.calendar),
          item(_Page.planner, badge: open > 0 ? '$open' : null),
          item(_Page.races),
          item(_Page.rankings),
          group(tr('Market')),
          item(_Page.transfers),
          item(_Page.search),
          group(tr('Management')),
          item(_Page.finance),
          item(_Page.staff),
          item(_Page.delegation),
          const Spacer(),
          Divider(height: 1, color: c.onSide.withValues(alpha: 0.18)),
          if (state.debug) item(_Page.debug),
          item(_Page.saves),
          InkWell(
            onTap: () => showHelpDialog(context, state),
            child: Container(
              height: 36,
              padding: const EdgeInsets.only(left: 16, right: 12),
              child: Row(
                children: [
                  Icon(LucideIcons.circleQuestionMark, size: 18, color: faded),
                  const SizedBox(width: 11),
                  Text(
                    tr('Help'),
                    style: TextStyle(fontSize: 14, color: c.onSide),
                  ),
                ],
              ),
            ),
          ),
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
                    tr('Main menu'),
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

const _weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

String _longDate(DateTime d) =>
    '${tr(_weekdays[d.weekday - 1])}, ${d.day.toString().padLeft(2, '0')}.'
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

/// Back or forward in the header: an arrow in a ring, light on a dark bar
/// and dark on a light one, so that it shows with every team colour.
class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.bar,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Colour of the bar the arrow sits on.
  final Color bar;

  @override
  Widget build(BuildContext context) {
    final ink = bar.computeLuminance() > 0.4
        ? const Color(0xFF16132A)
        : TeamColors.text;
    final color = onPressed == null ? ink.withValues(alpha: 0.3) : ink;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onPressed,
          radius: 20,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: onPressed == null ? 0.2 : 0.5),
              ),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}
