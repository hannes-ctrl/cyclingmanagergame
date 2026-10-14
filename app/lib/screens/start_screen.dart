import 'package:sim/sim.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../app_state.dart';
import '../settings.dart';
import '../ui.dart';
import '../widgets.dart';
import 'found_screen.dart';
import 'single_race_screen.dart';

/// Sections of the start menu.
enum _Section {
  load('Load game', LucideIcons.folderOpen),
  create('New career', LucideIcons.plus),
  single('Single race', LucideIcons.flag),
  settings('Settings', LucideIcons.settings);

  const _Section(this._label, this.icon);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
  final IconData icon;
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Start menu: continue the running career, load a save, start a new career
/// or change the settings of the app.
class StartScreen extends StatefulWidget {
  /// Creates the start menu.
  ///
  /// @param state Application state.
  /// @param settings Settings of the app.
  /// @param onPlay Called when the player enters the game.
  const StartScreen({
    super.key,
    required this.state,
    required this.settings,
    required this.onPlay,
  });
  final AppState state;
  final AppSettings settings;
  final VoidCallback onPlay;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

/// State of the menu: the open section and the team picked for a new career.
class _StartScreenState extends State<StartScreen> {
  var _section = _Section.load;
  int? _team;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;

    Widget entry(
      String label,
      IconData icon, {
      VoidCallback? onTap,
      bool on = false,
    }) => Material(
      color: on ? c.panel2 : Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: on ? TeamColors.text : c.line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 19, color: TeamColors.text),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(40),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 330,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('RADMANAGER', style: headStyle(44)),
                  Text(
                    tr('Cycling management game · version {0}', [appVersion]),
                    style: TextStyle(color: TeamColors.muted),
                  ),
                  const SizedBox(height: 34),
                  // Continue: the running career with team and date.
                  Material(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(5),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: widget.onPlay,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Jersey(
                              dataDir: s.dataDir,
                              abbr: s.jerseyOf(s.team.id),
                              size: 44,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr('RESUME'),
                                    style: TextStyle(
                                      fontFamily: headFont,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: c.onAccent,
                                    ),
                                  ),
                                  Text(
                                    '${s.team.name} · ${_date(s.career.today)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: c.onAccent.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              LucideIcons.arrowRight,
                              size: 20,
                              color: c.onAccent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final x in _Section.values) ...[
                    entry(
                      x.label,
                      x.icon,
                      on: x == _section,
                      onTap: () => setState(() {
                        _section = x;
                        _message = null;
                      }),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Spacer(),
                  entry(
                    tr('Quit'),
                    LucideIcons.logOut,
                    onTap: () {
                      s.flush();
                      windowManager.close();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 40),
            Expanded(
              child: Panel(
                colors: c,
                padding: 20,
                child: switch (_section) {
                  _Section.load => _load(),
                  _Section.create => _create(),
                  _Section.single => SingleRacePanel(state: widget.state),
                  _Section.settings => _settings(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// @returns The list of named saves.
  Widget _load() {
    final s = widget.state;
    final c = s.colors;
    final saves = s.saves();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Load game'), style: headStyle(24)),
        const SizedBox(height: 4),
        Text(
          _message ??
              tr(
                'You create named saves in the game under "Save games". Loading replaces the running career.',
              ),
          style: const TextStyle(color: TeamColors.muted),
        ),
        const SizedBox(height: 14),
        if (saves.isEmpty)
          Text(
            tr('No named save yet.'),
            style: TextStyle(color: TeamColors.muted),
          ),
        Expanded(
          child: ListView(
            children: [
              for (final info in saves)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: TeamColors.ground,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              tr('{0} · game date {1} · saved {2}', [
                                info.team,
                                _date(info.gameDate),
                                _date(info.savedAt),
                              ]),
                              style: const TextStyle(color: TeamColors.muted),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TeamColors.text,
                          side: BorderSide(color: c.line),
                        ),
                        onPressed: s.busy
                            ? null
                            : () async {
                                final error = await s.loadSave(info);
                                if (!mounted) return;
                                if (error == null) {
                                  widget.onPlay();
                                } else {
                                  setState(() => _message = error);
                                }
                              },
                        child: Text(tr('Load')),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// @returns The form to start a new career.
  Widget _create() {
    final s = widget.state;
    final c = s.colors;
    final teams = [
      for (final t in s.teams)
        if (t.division.startsWith('[1]') || t.division.startsWith('[2]')) t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('New career'), style: headStyle(24)),
        const SizedBox(height: 4),
        Text(
          tr(
            'Take over a WorldTeam or ProTeam, or found your own. The running career is replaced; save it under a name first if you want to keep it.',
          ),
          style: TextStyle(color: TeamColors.muted),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            children: [
              for (final t in teams)
                InkWell(
                  onTap: () => setState(() => _team = t.id),
                  child: Container(
                    color: _team == t.id ? c.panel2 : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        Jersey(
                          dataDir: s.dataDir,
                          abbr: s.jerseyOf(t.id),
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Flag(t.country, width: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(t.name)),
                        Text(
                          t.division.startsWith('[1]')
                              ? 'WorldTeam'
                              : 'ProTeam',
                          style: const TextStyle(color: TeamColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
              ),
              onPressed: _team == null
                  ? null
                  : () {
                      s.chooseTeam(teams.firstWhere((t) => t.id == _team));
                      widget.onPlay();
                    },
              child: Text(
                tr('START CAREER'),
                style: TextStyle(
                  fontFamily: headFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: TeamColors.text,
                side: BorderSide(color: c.line),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 15,
                ),
              ),
              onPressed: () async {
                final before = s.team.id;
                await showFoundScreen(context, s);
                if (mounted && s.team.id != before) widget.onPlay();
              },
              child: Text(tr('Found your own team …')),
            ),
          ],
        ),
      ],
    );
  }

  /// @returns The settings of the app.
  Widget _settings() {
    final c = widget.state.colors;
    final set = widget.settings;
    Widget row(String title, String text, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(text, style: const TextStyle(color: TeamColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );

    return ListenableBuilder(
      listenable: set,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Settings'), style: headStyle(24)),
          const SizedBox(height: 8),
          row(
            tr('Language'),
            tr(
              'Applies to all new texts. Messages and race reports that already exist keep their language.',
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final l in Lang.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Tooltip(
                      message: l.label,
                      child: InkWell(
                        onTap: () => set.lang = l,
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: set.lang == l
                                  ? TeamColors.text
                                  : Colors.transparent,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Opacity(
                            opacity: set.lang == l ? 1 : 0.55,
                            child: CountryFlag.fromCountryCode(
                              l.flag,
                              theme: const ImageTheme(
                                width: 42,
                                height: 28,
                                shape: RoundedRectangle(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          row(
            tr('Interface size'),
            tr('Draws the whole interface larger or smaller.'),
            Wrap(
              spacing: 6,
              children: [
                for (final v in AppSettings.scales)
                  Pill(
                    label: '${(v * 100).round()} %',
                    selected: set.scale == v,
                    colors: c,
                    onTap: () => set.scale = v,
                  ),
              ],
            ),
          ),
          row(
            tr('Page transitions'),
            tr('Fades pages in when you switch between them.'),
            Switch(
              value: set.animations,
              activeThumbColor: c.accent,
              onChanged: (v) => set.animations = v,
            ),
          ),
          row(
            tr('Full screen'),
            tr('Opens the window without a frame across the whole screen.'),
            Switch(
              value: set.fullScreen,
              activeThumbColor: c.accent,
              onChanged: (v) {
                set.fullScreen = v;
                windowManager.setFullScreen(v);
              },
            ),
          ),
          row(
            tr('Colour vision'),
            tr(
              'Shifts all colours so that red and green, or blue and yellow, can be told apart.',
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in ColorVision.values)
                  Pill(
                    label: v.label,
                    selected: set.vision == v,
                    colors: c,
                    onTap: () => set.vision = v,
                  ),
              ],
            ),
          ),
          row(
            tr('Debug mode'),
            tr(
              'Shows all rider values exactly, internal figures on the rider page and a debug page with test actions.',
            ),
            Switch(
              value: set.debug,
              activeThumbColor: c.accent,
              onChanged: (v) => set.debug = v,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              'Radio, line-ups, training and scouting are set per career in the game under "Delegation".',
            ),
            style: TextStyle(color: TeamColors.muted),
          ),
        ],
      ),
    );
  }
}
