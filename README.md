# Cycling Manager

*Working title: Radmanager.* A cycling team management game for Windows in the spirit of *Pro Cycling Manager*, with an interface modelled on *Football Manager*. You run a professional road team: build the squad, plan the season, pick line-ups and tactics, deal with sponsors, staff and money. Races are not played out in 3D; a physics-based simulation computes them and is calibrated against real results.

The game runs on the community **WorldDB** for Pro Cycling Manager, so riders, teams, races and stage profiles are the real ones.

> **Status:** version 0.4.0 alpha. A private hobby project, playable end to end, not balanced. English and German. Nothing in this repository is affiliated with Cyanide, Nacon, Sports Interactive or the UCI.

## Highlights

- **One simulation for everything.** Every stage is simulated in 200 m segments with each rider's power, weight, height and reserves, drafting, wind, altitude, cobbles, crashes and punctures. Watching a stage, skipping it and simulating to a date give the same result; the days run in the background.
- **Every team races and plans by the same rules,** the player's team included: sports directors who chase, attack, split the field in the crosswind and wait for a fallen leader; a season plan for every team; styles that shift what a team values.
- **Race day:** line-up with eleven roles, approach and break policy, a weather forecast, tyres and time trial bike, warnings before the start, radio calls at the decisive moments, the stage in fast motion, a race report and power figures for every rider.
- **Riders as people:** a personality from what the WorldDB knows of each rider, morale, standing in the team, season goals, promises, mentoring and talks.
- **A world that moves on:** contracts with clauses and competing offers, a yearly intake, promotions from development teams, licences on a three-year ranking, books for every team, sponsors with wishes, real bike and tyre suppliers, staff and facilities.
- **A manager's career:** a reputation, a board that can dismiss you, job offers from other teams (optional), and a history of your seasons.
- **Comfort:** back and forward like a browser, keyboard control, filters that survive a restart, CSV export, a help with a glossary, colour vision settings, autosaves and a one-click bug report.

All features in detail, with how the simulation and the calibration work: **[FEATURES.md](FEATURES.md)**. Plans: [ROADMAP.md](ROADMAP.md). Changes: [CHANGELOG.md](CHANGELOG.md). Concept: [docs/concept.html](docs/concept.html).

## Requirements

- Windows 10 or 11, x64
- Flutter 3.47 or later with Dart 3.13 or later
- Visual Studio 2022 Build Tools with "Desktop development with C++"
- *Pro Cycling Manager 2026* and the WorldDB 2026 mod from the Steam Workshop (not part of this repository)
- Optional: MinGW-w64 to build `ooz.dll`, needed only to extract files from the game's `.pak` archives

## Getting started

1. Copy the WorldDB into `worlddb/` (`OfficialRelease.cdb`, `Stages/`, `Classifications/`).
2. Build the world database `data/world.sqlite`:

   ```bash
   cd packages/worlddb
   dart pub get
   dart run bin/worlddb.dart import
   dart run bin/worlddb.dart classifications
   dart run bin/worlddb.dart check
   ```

   Optional: `variants` adds the routes of 2021 to 2025 for the calibration; with `ooz.dll` built (`native/build_ooz.sh`), `game-stages`, `jerseys`, `logos` and `photos` pull stage files, jerseys, race logos and rider photos from the `.pak` archives.
3. Build and run the app:

   ```bash
   cd app
   flutter pub get
   flutter build windows --release
   build\windows\x64\runner\Release\radmanager.exe
   ```

   The executable looks for a `data` folder next to itself or in a parent directory.

## Repository layout

```
app/                Flutter Windows application (screens, save games, tests)
packages/
  worlddb/          Readers for the PCM data files, import into SQLite, DB browser
  sim/              Race simulation: physics, tactics, stage races, material
  game/             Career: calendar, season plan, form, people, economy, staff
  calibration/      Real results and the search for better tuning values
docs/concept.html   Concept: interface, requirements, decisions
data/               Tuning values (tracked); world database, saves and exports (not tracked)
kalibrieren.ps1     Runs the calibration, e.g. overnight
```

The packages are plain Dart without Flutter, so `sim` and `game` run from the command line.

## Command-line tools

| Command (inside the package folder) | Purpose |
| --- | --- |
| `worlddb`: `dart run bin/worlddb.dart serve` | Database browser on http://localhost:8765 |
| `sim`: `dart run bin/sim.dart stage \| race \| check` | Simulate a stage or race, self-checks |
| `game`: `dart run bin/world.dart [--seasons n] [--seed s] [--csv file]` | Multi-season test: squads, ages, top riders, licences, morale, money per season |
| `game`: `dart run bin/check.dart [--seed s] [--team ABBR]` | Plays a season and checks every day what must always hold |
| `game`: `dart run bin/season.dart [team] [seed]` · `bin/plan.dart` | A whole season headless · the season plan of a team |
| `calibration`: `dart run bin/calibrate.dart report [--sample k --runs n --types …] [--set name=value]` | Simulation against real results, quick checks of model changes |
| `calibration`: `dart run bin/calibrate.dart run [--hours h] [--runs n] [--margin m]` | Search better tuning values |
| `calibration`: `bin/compare.dart`, `bin/breaks.dart`, `bin/timecut.dart` | Compare tuning files; breakaways along the route; the time limit against reality |
| `calibration`: `dart run bin/fetch_results.dart <year>` | Load the WorldTour results of a season |

## Tests

```bash
cd app && flutter test                # every screen with real data, save and load, one simulation, plan, people, material, world
cd packages/sim && dart test          # the simulation on a synthetic field, without the world database
```

The screen tests write images to `app/test/goldens/` (`--update-goldens` refreshes them). Tests that need `data/world.sqlite` are skipped without it. `RADMANAGER_SEED` fixes the seed of a new career to reproduce a run.

## Languages and save games

Texts are written in English in the sources and wrapped in `tr('…')`; German is a translation table (`packages/sim/lib/src/i18n_de.dart`) keyed by the English text, and a further language would be one more table. The running career is saved to `data/savegame.json` after every action, named saves to `data/saves/<name>.rmsave`, and every Monday of the game an automatic save in four rotating files. A save is a snapshot of the career and its running races; it loads in a few seconds.

## Known limitations

- Calibrated on 534 real races of 2023 to 2026, the race shape fits well on flat stages and in time trials, less well elsewhere: the middle of the field finishes too close to the winner (0:52 against 1:36 behind on average), hilly stages end in a bunch sprint too rarely (6 % against 18 %), breaks in the mountains win too rarely (21 % against 31 %), and the favourites win too often (59 % against 47 %).
- The power figures of the strongest riders are a few per cent high: up to 585 W for Ganna in a long time trial, and up to 432 W on average over the whole of Paris-Roubaix, where about 350 W would be real. The speeds fit the real races, so the losses in the model (drag, rolling resistance on rough roads) are probably somewhat high.
- Material, staff, facilities and team styles act through small estimated factors, not calibrated yet. The suppliers follow what was known of 2026.
- Wages and budgets follow rider strength, the ranking and the wage level of the world, because the WorldDB contains none of them; they are plausible, not real. Every team keeps books and signs within its means; over ten seasons the balances, the strength of the field (WorldTour 77.4 to 78.0) and the age of the riders (28.3 to 28.9) hold, while the number of riders of 33 and more grows (169 to 227). The board never signs riders for the player; a team it runs only renews and builds facilities.
- The stage files carry no compass headings, so the wind comes from a random direction relative to the road.
- Staff other than the team managers named in the WorldDB is generated.
