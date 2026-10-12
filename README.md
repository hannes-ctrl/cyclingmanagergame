# Radmanager

A cycling team management game for Windows in the spirit of *Pro Cycling Manager*, with a user interface modelled on *Football Manager 2024*. You run a professional road cycling team: build the squad, plan the season, pick line-ups and tactics, deal with sponsors and staff. Races are never played out in 3D. They are computed by a physics-based quick simulation that is meant to produce believable results.

The game runs on the community **WorldDB** for Pro Cycling Manager, so riders, teams, races and stage profiles are the real ones.

> **Status:** version 0.2.0 alpha. A private hobby project, playable end to end, not balanced. The interface is in English and German. Nothing in this repository is affiliated with Cyanide, Nacon, Sports Interactive or the UCI.

## Features

**Team**

- Start menu to continue, load a save, start a new career or change settings. Take over any WorldTeam or ProTeam, or found your own: pick 16 to 30 riders from the whole database, and the licence (Continental, ProTeam, WorldTeam) follows from the strength of that squad.
- Rider form from a fitness/fatigue model, training load and focus per rider, crashes and illness.
- Monthly development by age and potential: a rider grows mainly where he is already strong, slows down towards a ceiling set by his potential and declines from 31.
- Rider search over the whole database: name, team, country, level, age, strength, potential, any single attribute, rider type and contract; riders nobody has scouted show ranges.
- Rider page with photo (a neutral silhouette for riders without one), key figures, attributes, the change of each attribute since the rider joined, a twelve-month outlook, the form curve of the season, results, palmares and career seasons.
- Training camps, and a development team to promote riders from. The 24 development teams of the database are linked to their real professional teams; the link never changes, and a team without one (such as a newly founded team) can found its own.
- Stagiaires as in the real sport: from 1 August up to three riders of the own development team may start for the professional team in races below the WorldTour. The other teams use theirs as well.
- Staff (sports directors, coaches, doctors, scouts) with a job market that renews every month; the number of coaches matters as well as their skill. Scouting with value ranges for unknown riders.
- Delegate line-ups, in-race radio, training, scouting and contract renewals to staff.

**Racing**

- Full calendar of the WorldDB: Grand Tours, monuments, WorldTour, ProSeries, class 1 and 2, national, European and world championships. World and European championships move to another country every season.
- Simulate to a date: a click on the date opens a small calendar; optionally the sports director handles line-ups and radio until then.
- Race planner: see every race you are eligible for, withdraw from invitations, apply for wildcards, assign riders.
- Race preparation with line-up, eleven rider roles, team approach and breakaway policy, plus a pre-race forecast from a handful of quick runs.
- DS radio: up to three decision points per stage (breakaway formed, start of the finale, rival attack); after the last answer of the day the result opens. Can be switched off.
- Race report after every stage: a neutral press text, a chart of the time gaps along the route (head of the race, favourites, middle of the field) with the values under the pointer, a view of what each of your riders did (role, where he lost contact, kilometres on the front), and all classification tables.
- "What if": re-run any finished stage with the same random seed but different tactics.

**Season and career**

- Contracts and a transfer window from August, AI teams that renew and sign on their own, a yearly intake of young riders.
- Three sponsor contracts with staggered terms, offers and negotiations when one runs out, season goals and board confidence.
- Licences awarded on a three-year ranking with promotion and relegation.
- Inbox with topics, a topic filter and deletion.
- Named save games.

**Interface**

- Always dark, tinted in the team's colours; a light team colour never fills the sidebar. Buttons, fields, chips, menus and dialogs share one look on every screen.
- Race logos, team jerseys and country flags throughout; races are colour-coded by tier.
- Filter columns in the race planner and the transfer market (tier, entry state, rider, contract, age range, rider type), a season timeline and tier filter in the calendar, search in squad, races and rankings.
- The tiles of the home page lead to the area they summarise. Explanations of every figure (form, fitness, attributes, staff values) appear as tooltips on column headings and on the rider page.
- English and German, switched by flags in the settings of the start menu; English is the default.
- Settings for the size of the interface, page transitions and full screen.
- Debug mode (in the settings): exact values for every rider, internal figures on the rider page, the wildcard chance in per cent, and a debug page with the seed, the tuning values and test actions (simulate to the end of the season, add money, heal riders).

## Repository layout

```
app/                    Flutter Windows application (UI, save games, tests)
packages/
  worlddb/              Readers for PCM data files, import into SQLite, DB browser
  sim/                  Race simulation: physics, tactics, stage races
  game/                 Career logic: calendar, form, economy, staff, licences
  calibration/          Fetches real results and tunes the simulation against them
native/                 Build script and shim for the Oodle decompressor (ooz)
third_party/ooz/        Clone of zao/ooz (not tracked, see native/build_ooz.sh)
docs/konzept.html       Requirements, UI concept and roadmap (German)
data/                   Tuning values (tracked); generated and not tracked: world.sqlite,
                        jerseys, logos, photos, real results, save games, settings
worlddb/                Your copy of the WorldDB (not included)
kalibrieren.ps1         Runs the calibration, e.g. overnight
```

The app uses `fl_chart` (charts), `country_flags`, `lucide_icons_flutter`, `flutter_animate`, `window_manager` and `flutter_localizations`, and bundles the Barlow typeface (SIL Open Font License, see `app/assets/fonts/OFL.txt`).

The packages are plain Dart and have no Flutter dependency. `sim` and `game` can be driven from the command line, which is how the season loop and the calibration are tested.

## Requirements

- Windows 10 or 11, x64
- Flutter 3.47 or later with Dart 3.13 or later
- Visual Studio 2022 Build Tools with the "Desktop development with C++" workload (needed by `flutter build windows`)
- A copy of *Pro Cycling Manager 2026* and the WorldDB 2026 mod from the Steam Workshop. The game data is not part of this repository.
- Optional: MinGW-w64 to build `ooz.dll`, which is only needed to extract stage files from the base game's `.pak` archive

## Getting started

1. **Copy the WorldDB** into `worlddb/` so that `worlddb/OfficialRelease.cdb`, `worlddb/Stages/` and `worlddb/Classifications/` exist.

2. **Build the world database.** This reads the `.cdb` database and all stage files and writes `data/world.sqlite`:

   ```bash
   cd packages/worlddb
   dart pub get
   dart run bin/worlddb.dart import
   dart run bin/worlddb.dart classifications
   dart run bin/worlddb.dart check
   ```

   For the calibration, `dart run bin/worlddb.dart variants` adds the routes of the seasons 2021 to 2025 from the same stage files.

   `classifications` reads the points scales, mountain points and bonus seconds of every race. Some races refer to stage files that only ship with the base game. To pull those in, build the decompressor with `native/build_ooz.sh` and run `dart run bin/worlddb.dart game-stages <path to the game's .pak>` before the import. With the decompressor in place, `dart run bin/worlddb.dart jerseys <path to the mod's .pak>` extracts the team jerseys to `data/jerseys/`; without them teams are shown by their two colours. `dart run bin/worlddb.dart logos <path to the mod's .pak>` does the same for the race logos (`data/logos/`, named by race id); races without one show their abbreviation. `dart run bin/worlddb.dart photos <path to the mod's .pak>` extracts the rider photos (`data/photos/`, named by rider id, about 165 MB).

3. **Build and run the app:**

   ```bash
   cd app
   flutter pub get
   flutter build windows --release
   build\windows\x64\runner\Release\radmanager.exe
   ```

   The executable looks for a `data` folder next to itself or in any parent directory. App settings are stored in `data/settings.json`.

## Command-line tools

| Command (run inside the package folder) | Purpose |
| --- | --- |
| `dart run bin/worlddb.dart serve` | Database browser on http://localhost:8765 |
| `dart run bin/worlddb.dart sql "<query>"` | Query `data/world.sqlite` |
| `dart run bin/sim.dart stage \| race \| check` | Simulate one stage or race, run the simulator's self-checks |
| `dart run bin/season.dart [team] [seed]` | Play a whole season headless and print a summary |
| `dart run bin/step7.dart [team] [years]` | Exercise radio, forecast, what-if, licences, development team |
| `dart run bin/step8.dart [team \| NEU]` | Exercise championships, camps, sponsors, a founded team |
| `dart run bin/fetch_results.dart <year>` | Load the WorldTour results of a season from ProCyclingStats |
| `dart run bin/calibrate.dart report` | Compare the simulation with the real results since 2021 |
| `dart run bin/calibrate.dart run [--hours h] [--runs n] [--dry]` | Search better tuning values; `--dry` does not write them |
| `dart run bin/calibrate.dart reparse` | Rebuild the stored results from the cached result pages |
| `dart run bin/snapshot.dart` | Check that a saved and reloaded career continues identically |
| `dart run bin/growth.dart [seasons] [rider id]` | Play several seasons and print how the level of the riders moves, to balance development against decline |

## How the simulation works

A stage is cut into 500 m segments. Riders have a threshold power derived from their attributes for the terrain of each segment, an endurance reserve that drains over the day and a short-term reserve for efforts above threshold. Groups ride on a shared clock; drafting, rolling resistance and gradient decide who can hold a wheel. On top of that sit breakaway formation, the chase, attacks in the finale, cobbled sectors, sprints with lead-out trains, a gruppetto that forms on mountain stages and rides to the time limit, time trials and team time trials.

Each team rides to a plan: a role per rider, an approach (wait, control, make the race hard) and a breakaway policy. AI teams derive their plan from the route, their riders and the general classification. The quality of the sports director in the car changes how well the plan is executed.

Everything is deterministic for a given seed. 37 tuning parameters live in `data/calibration/tuning.json`; among them the effort on cobbled sectors and the rate of punctures and crashes there.

## Calibration

The calibration package compares the simulation with real WorldTour results of the seasons 2021 to 2026 and searches for better tuning values (`kalibrieren.ps1`, typically overnight). The results are not part of the repository: `dart run bin/fetch_results.dart <year>` in `packages/calibration` loads a season into `data/results/<year>/`, and the script does that itself before every run. Races of earlier seasons are simulated on the route of their year (`worlddb variants`) with the riders of the real result who are in the database, at their strength of 2026.

Only the dynamics of a race are scored, by four figures: the size of the winner's group, the gap of tenth place, the gap of the middle of the field and the average speed. Who wins, and whether he comes from the breakaway, is deliberately not part of the score: the best riders do not start everywhere, and crashes, illness and form of the day decide a single real result. That is also why older seasons are usable although their fields were different.

The error has two parts: a capped error per race in the four figures, and per race type the difference in how often the winner's group falls into each size class (solo, duo, small group, bunch), which keeps the search from giving up on rare outcomes. The real figures are measured on all finishers, so a winner who has since retired still counts; a big first group is scaled to the part of the field that is simulated. A fifth of the races is held back as a control set, and an improvement only counts if it holds on a second set of random numbers. Races that cannot be matched, such as parade stages, are listed in `data/calibration/exclude.txt`. The report also names tuning values that sit at the edge of their range.

## Languages

Texts are written in German in the sources and wrapped in `tr('…')` (`packages/sim/lib/src/i18n.dart`). The English texts live in one table, `packages/sim/lib/src/i18n_en.dart`, keyed by the German text; a text without an entry is shown in German. Placeholders are `{0}`, `{1}` and so on, and `dec()` formats numbers with the decimal mark of the language.

To add a text: write `tr('Neuer Text {0}', [value])` and add the English line to the table. Enum labels and constant tables keep their German text as a constant and are translated where they are shown. Texts that the game has already written, such as inbox messages and race reports, keep the language they were written in; code that recognises such a text uses `isText()`. The command-line tools of the other packages print German only.

## Save games

The running career is saved automatically to `data/savegame.json` shortly after every action. Named saves are written to `data/saves/<name>.rmsave`.

Both use file format 2: UTF-8 text with one JSON document per line. Line 1 is a small header (`format`, `name`, `savedAt`, `teamName`, `gameDate`), line 2 the complete state of the career (riders, squads, contracts, sponsors, staff, licences, rankings, the state of the random generator), and every further line one race of the running season with its results. A save is a snapshot: loading takes a couple of seconds regardless of how many seasons were played, and a later change to the simulation does not alter what already happened. A mid-season save is around 20 MB.

Format 1 files from earlier versions, which stored a log of the player's decisions and replayed the career on loading, can still be opened.

## Tests

```bash
cd app
flutter test test/save_test.dart       # save -> load yields the identical state
flutter test test/screens_test.dart    # renders every screen with real data
```

`screens_test.dart` writes images to `app/test/goldens/`. They exist to check layouts without opening a window; pass `--update-goldens` to refresh them. Both tests need `data/world.sqlite` and are skipped without it.

A career starts from a random seed. Set the environment variable `RADMANAGER_SEED` to a number to reproduce a run, for example a failing test.

See [ROADMAP.md](ROADMAP.md) for what is planned and [CHANGELOG.md](CHANGELOG.md) for what changed.

## Known limitations

- Cobbled classics are still too easy, though less so since the sectors are ridden above threshold and cost riders through mishaps (solo wins 33 % against 67 % in reality before the next calibration run). Hilly stages produce too few bunch finishes. A calibration round over more seasons is planned.
- Crashes and punctures during a stage, and the time cut, are not simulated.
- AI teams do not yet promote riders from their development teams.
- Few riders reach the very top (a best attribute of 84 or more) after several seasons: the stars of 2026 age and their successors arrive slowly.
- Money is not balanced: salaries, budgets, sponsor offers and camp costs are placeholders derived from rider strength, because the WorldDB contains none of them.
- Prize money from the WorldDB is not used yet.
- Staff other than the team managers named in the WorldDB is generated.
