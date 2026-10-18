# Cycling Manager

*Working title: Radmanager.* A cycling team management game for Windows in the spirit of *Pro Cycling Manager*, with an interface modelled on *Football Manager*. You run a professional road team: build the squad, plan the season, pick line-ups and tactics, deal with sponsors, staff and money. Races are not played out in 3D; a physics-based simulation computes them and is calibrated against real results.

The game runs on the community **WorldDB** for Pro Cycling Manager, so riders, teams, races and stage profiles are the real ones.

> **Status:** version 0.6.1 alpha. A private hobby project, playable end to end, not balanced. English and German. Nothing in this repository is affiliated with Cyanide, Nacon, Sports Interactive or the UCI.

## Highlights

- **One simulation for everything.** Every stage is simulated in 200 m segments with each rider's power, weight, height and reserves, drafting, wind, altitude, cobbles, crashes and punctures. Watching a stage, skipping it and simulating to a date give the same result; the days run in the background.
- **Every team races and plans by the same rules,** the player's team included: sports directors who chase, attack, split the field in the crosswind and wait for a fallen leader; a season plan for every team; styles that shift what a team values.
- **Race day:** line-up with eleven roles, approach and break policy, a weather forecast, tyres and time trial bike, warnings before the start, radio calls at the decisive moments, the stage in fast motion, a race report and power figures for every rider.
- **The stage in 3D:** a viewer made with Godot shows the player's stages: lean road cyclists, each as tall as the real rider, pedalling on detailed road bikes in their team's real kit from the game, with helmets, glasses and cycling shoes, on asphalt, cobbles and gravel from photo textures, on a road laid out from the real profile with hairpins on the steep climbs, with team cars, motorbikes and cheering spectators; a director cuts between the motorbike, the helicopter and the finish line.
- **Riders as people:** a personality from what the WorldDB knows of each rider, morale, standing in the team, season goals, promises, mentoring and talks.
- **A world that moves on:** contracts with clauses and competing offers, a yearly intake, promotions from development teams, licences on a three-year ranking, books for every team, sponsors with wishes, real bike and tyre suppliers, staff and facilities.
- **A manager's career:** a reputation, a board that can dismiss you, job offers from other teams (optional), and a history of your seasons.
- **Comfort:** back and forward like a browser, keyboard control, bookmarks, multi-select, a vacation mode, the next season planned in the winter, filters that survive a restart, a help with a glossary, colour vision settings, autosaves and a one-click bug report.

All features in detail, with how the simulation and the calibration work: **[FEATURES.md](FEATURES.md)**. Plans: [ROADMAP.md](ROADMAP.md). Changes: [CHANGELOG.md](CHANGELOG.md). Concept: [docs/concept.html](docs/concept.html).

## Requirements

- Windows 10 or 11, x64
- Flutter 3.47 or later with Dart 3.13 or later
- Visual Studio 2022 Build Tools with "Desktop development with C++"
- *Pro Cycling Manager 2026* and the WorldDB 2026 mod from the Steam Workshop (not part of this repository)
- Optional: MinGW-w64 to build `ooz.dll`, needed only to extract files from the game's `.pak` archives
- Optional: Godot 4.7 with its export templates, for the 3D viewer

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

   Optional: `variants` adds the routes of 2021 to 2025 for the calibration; with `ooz.dll` built (`native/build_ooz.sh`), `game-stages`, `jerseys`, `kits`, `logos` and `photos` pull stage files, jerseys, the kits for the 3D viewer, race logos and rider photos from the `.pak` archives.
3. Build and run the app:

   ```bash
   cd app
   flutter pub get
   flutter build windows --release
   build\windows\x64\runner\Release\radmanager.exe
   ```

   The executable looks for a `data` folder next to itself or in a parent directory.

## The 3D viewer

The 3D view of a stage is a separate program in `viewer/`, made with Godot 4.7 in GDScript; it runs on Windows, Linux and macOS (Forward+ on Vulkan, Direct3D 12 or Metal, OpenGL where none of them is there). The game starts it from the button **3D** in the live view and the race report, and sends it the stage over a WebSocket on this machine: the route, the teams and riders, the events, and for every rider the time he passed each 200 m point and his place in his group. The simulation records this only for the races of the player's team, and only the race that is running keeps it. The road follows the real height profile and the directions the wind model uses; its bends and hairpins are made up, the same for a stage every time, because the WorldDB has no map of the routes.

```powershell
viewer\build.ps1                     # Windows, Linux and macOS builds into viewer/build
```

The game looks for `viewer/RadmanagerViewer(.exe)` next to itself, then for `viewer/build/<os>/` in the repository; during development `RADMANAGER_GODOT` may name the Godot editor instead, which then runs the project directly. A stage can also be exported to a file and watched without the game:

```bash
cd packages/sim
dart run bin/sim.dart viewer "Tour de France" 20 --team UAD --out ../../viewer/samples/tdf20.json
```

```powershell
viewer\build\windows\RadmanagerViewer.exe -- --race=viewer\samples\tdf20.json --km=150 --camera=tv
```

Keys: space pauses, + and − change the speed, C changes the camera, 1 to 5 pick a group, the right mouse button turns the camera, the wheel zooms. `--screenshot=file.png` saves a picture and quits, for checks without looking; `--camera=free --zoom=4 --orbit=1.6,0.15` puts the camera beside the riders, `--rider=<id>` follows one rider (with `--km` where he is), `--debug` prints the frame times.

The riders are the CC0 base character of Quaternius, made leaner, with longer arms and smaller hands, and seated on a road bike made in code: the back bent, the elbows a little bent, the hands round the brake hoods of a drop bar; the legs follow the pedals by inverse kinematics. He is baked in six stances: sitting, standing on the pedals, sprinting on the drops, tucked on a descent, the victory salute and the time trial position on a time trial bike with extensions, a disc wheel and an aero helmet. Each stance has sixteen positions of the cranks in a vertex animation texture; the shader blends between them and rolls the bike with each pedal stroke out of the saddle, so the whole field is drawn in one go. Every rider chooses his stance from the race: out of the saddle now and then on climbs and when he attacks, sprinting in the last 400 m, tucked and freewheeling on fast descents, the winner's arms in the air at the line; he turns the cranks at his own cadence and leans into bends. A crash throws the riders down where it happened for the time the race says they lost, a puncture stops a rider at the side of the road. Riders further away use two coarser versions of the same mesh. Each rider is scaled to his real height, a little broader when he is heavy. With the kits from the game (`worlddb kits` writes them to `data/kits`) every team rides in its real jersey and shorts, with its socks, shoes, gloves, bar tape and bottle, and the leaders of a stage race in their jerseys; the helmet and the bike take the main colours of the kit. Without them the shader paints the kit in the team's colours, with six designs. It decides per pixel from where a point lies on the body standing, so every hem is a clean line. The helmet has vents, foam inside and a chin strap. Beside the road lies a verge with a ditch, then an embankment or a cutting to the land; team cars follow the groups and every rider in a time trial, motorbikes with cameramen ride ahead, spectators made from the same base character cheer by the road, and the finish arch and the barriers carry the race's logo. The road surfaces are CC0 photo textures from Poly Haven. Sources and licences: [viewer/assets/CREDITS.md](viewer/assets/CREDITS.md).

## Sharing with friends

`.\release.ps1` builds `dist/Radmanager-<version>-windows.zip`: the program with the Visual C++ runtime, the tuning values and the 3D viewer, nothing to install (`-NoViewer` leaves the viewer out). `-World` adds the world database, `-Art` the jerseys, kits, race logos and rider photos. Both come from the WorldDB for Pro Cycling Manager and from the game itself; pass them on privately at most. Without the database the program shows where to copy `world.sqlite`.

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
viewer/             3D viewer (Godot 4.7, GDScript): project, scripts, build.ps1
calibrate.ps1       Runs the calibration, e.g. overnight
release.ps1         Builds the release zip for a clean Windows
```

The packages are plain Dart without Flutter, so `sim` and `game` run from the command line.

## Command-line tools

| Command (inside the package folder) | Purpose |
| --- | --- |
| `worlddb`: `dart run bin/worlddb.dart serve` | Database browser on http://localhost:8765 |
| `worlddb`: `dart run bin/worlddb.dart kits <file.pak>` | The teams' kits and the races' leader jerseys from the graphics pack, for the 3D viewer (`data/kits`) |
| `sim`: `dart run bin/sim.dart stage \| race \| check` | Simulate a stage or race, self-checks |
| `sim`: `dart run bin/sim.dart viewer "<race>" [stage] [--team ABBR] [--out file]` | A stage as a message for the 3D viewer |
| `app`: `dart run tool/viewer_demo.dart <race.json>` | Starts the 3D viewer through the game's link and sends it a race |
| `viewer`: `godot --path . --script tools/rider_shot.gd -- --out=x.png [--head\|--hands\|--bike\|--close]` | The rider alone from six sides, for checking pose and kit |
| `viewer`: `godot --headless --path . --script tools/tree_check.gd -- --race=<json>` | Builds the land along a stage and reports the trees nearest to the road |
| `viewer`: `godot --headless --path . --script tools/stops.gd -- --race=<json>` | Lists where crashes and punctures stop riders, with the race clock |
| `viewer`: `godot --path . --script tools/rider_shot.gd -- --out=x.png --stances [--view=0..5]` | The six stances of the rider side by side |
| `game`: `dart run bin/world.dart [--seasons n] [--seed s] [--csv file] [--roundtrip]`, `--bands file.csv` | Multi-season test: squads, ages, top riders, licences, morale, money per season |
| `game`: `dart run bin/check.dart [--seed s] [--team ABBR] [--switch ABBR] [--seasons n] [--job-market]` | Plays a season and checks every day what must always hold |
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

- Calibrated on 814 real races of 2021 to 2026, the race shape fits well on flat stages and in time trials, less well elsewhere: the middle of the field finishes too close to the winner (1:09 against 1:33 behind on average), hilly stages end in a bunch sprint too rarely (6 % against 18 %), breaks in the mountains win too rarely (21 % against 36 %), and too many sprinters finish outside the time limit on mountain stages (35 % against 17 %). The favourites win about as often as in reality (55 % against 54 % in 2026).
- The power figures of the strongest riders are a few per cent high: up to 585 W for Ganna in a long time trial, and up to 432 W on average over the whole of Paris-Roubaix, where about 350 W would be real. The speeds fit the real races, so the losses in the model (drag, rolling resistance on rough roads) are probably somewhat high.
- Material, staff, facilities and team styles act through small estimated factors, not calibrated yet. The suppliers follow what was known of 2026.
- Wages and budgets follow rider strength, the ranking and the wage level of the world, because the WorldDB contains none of them; they are plausible, not real. Every team keeps books and signs within its means; over ten seasons the balances, the strength of the field (WorldTour 77.4 to 78.0) and the age of the riders (28.3 to 28.9) hold, while the number of riders of 33 and more grows (169 to 227). The board never signs riders for the player; a team it runs only renews and builds facilities.
- The stage files carry no compass headings, so the wind comes from a random direction relative to the road.
- Staff other than the team managers named in the WorldDB is generated.
