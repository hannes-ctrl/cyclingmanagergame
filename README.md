# Radmanager

A cycling team management game for Windows in the spirit of *Pro Cycling Manager*, with a user interface modelled on *Football Manager 2024*. You run a professional road cycling team: build the squad, plan the season, pick line-ups and tactics, deal with sponsors and staff. Races are never played out in 3D. They are computed by a physics-based quick simulation that is meant to produce believable results.

The game runs on the community **WorldDB** for Pro Cycling Manager, so riders, teams, races and stage profiles are the real ones.

> **Status:** version 0.3.0 alpha. A private hobby project, playable end to end, not balanced. The interface is in English and German. Nothing in this repository is affiliated with Cyanide, Nacon, Sports Interactive or the UCI.

## Features

**Team**

- Start menu to continue, load a save, start a new career or change settings. Take over any WorldTeam or ProTeam, or found your own: pick 16 to 30 riders from the whole database, and the licence (Continental, ProTeam, WorldTeam) follows from the strength of that squad.
- Rider form from a fitness/fatigue model, training load and focus per rider, crashes and illness.
- Monthly development by age and potential: a rider grows mainly where he is already strong, slows down towards a ceiling set by his potential and declines from 31.
- Rider search over the whole database: name, team, country, level, age, strength, potential, any single attribute, rider type and contract; riders nobody has scouted show ranges.
- Rider page with photo (a neutral silhouette for riders without one), key figures, attributes, the change of each attribute since the rider joined, a twelve-month outlook, the form curve of the season, results, palmares and career seasons.
- Riders as people. Every rider has a personality (professionalism, ambition, loyalty, consistency), summed up in one term as in football management games, from "model professional" and "loyal" through "balanced" to "mercenary", "slack" and "temperamental"; about a quarter are balanced, a fifth difficult. It is drawn per rider and career, a little more professional past thirty and a little more ambitious for young riders of great potential, and shown for riders your scouts know well. It changes how fast he develops, how strongly he reacts, what he asks to renew and how evenly he performs.
- Morale for the riders of every team: wins and podiums lift it, too few race days lower it, and it shifts form and wage demands. For your riders your decisions move it as well: promises kept or broken, and whether a rider rides in the part his standing lets him expect. A rider who is injured or ill does not blame you for the race he misses.
- Standing in the team (star, leader, key domestique, domestique, prospect): follows from strength and age and can be changed for your riders. A star used as a helper in a race that matters is displeased; a helper allowed to ride for himself is pleased.
- Promises: a start or a leading role in one race, once per season, or, in contract talks, for the whole first season of the contract (a start in a Grand Tour, the lead in a WorldTour race). With such a promise a rider asks eight per cent less; it is settled at the end of that season.
- Season goals: up to three races a rider builds his season around. He is sure to start there and is a good one per cent stronger, a touch weaker elsewhere. The sports directors set them from the season plan, for every team; on the rider page the target changes them, in the rider matrix a right click does, and the plan follows. Goals you set stay yours; the sports director leaves them alone. Goals of sponsor and board raise the importance of the races they concern.
- Shortlist: a star on the rider page puts a rider on it. A message arrives when the signing period opens and he is available, and when he renews or signs elsewhere; the rider search can show the shortlist alone.
- Compare two riders: remember one with the scales on his page, and his values appear as a second column on every other rider page. A note of your own can be kept for every rider.
- Team pages for every team: licence, place and points of the season, wins and the squad, with strengths as ranges where your scouts do not know a rider. Reached from the rankings and from a rider's page.
- Training camps, and a development team to promote riders from. The 24 development teams of the database are linked to their real professional teams; the link never changes, and a team without one (such as a newly founded team) can found its own.
- Stagiaires as in the real sport: from 1 August up to three riders of the own development team may start for the professional team in races below the WorldTour. The other teams use theirs as well.
- Staff (sports directors, coaches, doctors, scouts, mechanics, physiotherapists) with a job market that renews every month; the number of coaches matters as well as their skill. Scouting with value ranges for unknown riders. Mechanics change wheels and bikes faster and prevent punctures and defects; physiotherapists help the riders recover overnight in stage races. Every team has them, by its tier.
- Delegate line-ups, in-race radio, training, scouting and contract renewals to staff.
- Material of real suppliers: every team rides the bikes and tyres of its brand (Specialized, Colnago, Canyon, Continental, Vittoria and others, as far as the suppliers of 2026 were known when the game was made). Bikes differ a little in drag and weight, tyres in rolling resistance and punctures; the suppliers pay the team. When the contracts run out, three offers arrive on 1 September: better material against more money. On the race day the sports director of every team chooses the tyres (narrow, standard, wide) and, in time trials, the time trial or the road bike, by the same rules; you can overrule him in the race preparation.
- Team styles (all-round, sprint, general classification, classics, youth, experience), from the squad of every team: they shift what the season planner values, whom a team signs and how it races. For your team the style follows the squad or is set under "Delegation".

**Racing**

- Full calendar of the WorldDB: Grand Tours, monuments, WorldTour, ProSeries, class 1 and 2, national, European and world championships. World and European championships move to another country every season.
- Simulate to a date: a click on the date opens a small calendar; optionally the sports director handles line-ups and radio until then.
- Season plan by the sports director: before the first day he assigns the riders to every race of the season. The races are planned in the order of their importance (the Tour first, then the other Grand Tours, the monuments, the WorldTour and so on, a race in the team's own country counting more), with the riders who suit the stages best. A rider who already carries more than his share of the season is taken less readily, the more so the smaller the race, so the programme spreads over the squad. Young riders get fewer race days and no or only one Grand Tour, a second Grand Tour is the exception, and of a team's five best Grand Tour riders at most two start together. When a rider is injured or ill, the director takes him out of the races he misses and names a replacement. Every entry can be changed by hand, "Replan the season" starts over, and the whole task can be switched off under "Delegation". The sports directors of all other teams plan their seasons in the same way, so their leaders no longer start in every race they are fit for.
- Race planner: see every race you are eligible for, withdraw from invitations, apply for wildcards, assign riders. A warning names riders who are entered for two races at the same time.
- Race preparation with line-up, eleven rider roles, team approach and breakaway policy, plus a pre-race forecast from a handful of quick runs. What you change is pinned for the whole race; everything else the sports director plans anew for every stage, so a pinned leader stays leader in the mountains and on the flat while the helpers around him change with the terrain. "Fix everything" overrides the sports director completely: every role and both instructions apply exactly as set on every stage. The weather service gives a forecast that blurs the real weather of the day, the more the further ahead, including a warning of echelons; the approach "split in the crosswind" lets a team with strong rouleurs ride in the gutter. Before the start the game warns of empty places, a leader who would ride his third race in nine days, sprint stages without a sprinter, tired riders and riders with too many race days. "Line-up of last year" takes over who rode the race for the team a year before.
- Weather by month and country: heat, cold, rain and wind, with echelons in the crosswind. Crashes, punctures, the three-kilometre rule and the time limit happen during the stage; riders crash out, fall ill or miss the cut.
- DS radio: four decision points per stage (breakaway formed, start of the finale, rival attack, a crash or puncture of a leader: two helpers wait, the whole team waits, or nobody). Every team's sports director decides at these points by the same rules; yours shows his recommendation, and you can overrule it. After the last answer of the day the result opens. Can be switched off.
- Race report after every stage: a neutral press text, a chart of the time gaps along the route (head of the race, favourites, middle of the field) with the values under the pointer, a view of what each of your riders did (role, where he lost contact, kilometres on the front), and all classification tables.
- Power figures after every stage, as from a power meter: average and normalised power, watts per kilogram, intensity, kilojoules, the time in six zones, and the effort on every categorised climb with W/kg, VAM and time. Kept for your riders and the first ten.
- Roles for jersey hunters: a mountains jersey hunter goes into the breaks of mountain stages and takes the points on the climbs, a points jersey hunter does the same on flat stages. Teams without a leader for the overall send one on the hard days of a stage race.
- Single race in the start menu: any race of the season with any WorldTeam or ProTeam, your approach, break policy and tyres, and a seed; the same simulation, fresh riders, nothing reaches the career.
- "What if": re-run any finished stage with the same random seed but different tactics.

**Season and career**

- Contracts and a transfer window from August, AI teams that renew and sign on their own, a yearly intake of young riders.
- Three sponsor contracts with staggered terms, offers and negotiations when one runs out, season goals and board confidence.
- Licences awarded on a three-year ranking with promotion and relegation.
- Inbox with topics and a topic filter. Mark everything read, delete the read messages or delete all of them, for one topic or for all. Topics can be switched off, and three or more messages of one topic on one day arrive as a single summary.
- At the end of a season a review names the rider of the year, the best young rider, the rider with the most wins and the team of the year.
- Named save games, and an automatic save every Monday of the game in four rotating files, so that you can go back up to four weeks. Ctrl+S makes a quick save.

**Interface**

- Always dark, tinted in the team's colours; a light team colour never fills the sidebar. Buttons, fields, chips, menus and dialogs share one look on every screen.
- Race logos, team jerseys and country flags throughout; races are colour-coded by tier.
- Filter columns in the race planner and the transfer market (tier, entry state, rider, contract, age range, rider type), a season timeline and tier filter in the calendar, search in squad, races and rankings.
- The tiles of the home page lead to the area they summarise. Explanations of every figure (form, fitness, attributes, staff values) appear as tooltips on column headings and on the rider page.
- Back and forward through the pages visited (buttons in the header, Alt+← and Alt+→, Esc, the side buttons of the mouse). Every page keeps its filters, sorting and scroll position for the session, whether a rider page lies on top of it or you come back to it from another page.
- Keyboard: Space is the continue button, Ctrl+F opens the rider search, Ctrl+S saves, the keys 1 to 9 open the first nine pages of the sidebar and F1 the help. In the list under the mouse the arrow keys, Page Up/Down, Home and End move a cursor and Enter opens the row; on a rider page the arrow keys step through the list he was opened from. Rider names in race results lead to the rider page, races on a rider's page to their report.
- The form in the squad shows where it is heading (↗ → ↘) since the last weekly record.
- Help in the sidebar: how a season goes in a few steps, and a glossary of every figure. A new career starts with a welcome message.
- Lists can be exported as CSV (rider search, team pages), into `data/export`. The filters of the rider search survive a restart (`data/ui_state.json`).
- A message in the inbox leads to the page where its topic is dealt with; teams in result tables lead to the team page and a team's flag to the riders of its country.
- "Simulate to a date" can stop on the day a message on chosen topics arrives. The header shows the progress and has a button to stop after the current day, and after a week or more one message sums up what happened: races, wins, points, injuries, messages by topic.
- English and German, switched by flags in the settings of the start menu; English is the default.
- Settings for the size of the interface, page transitions, full screen and colour vision (colours shifted for deuteranopia, protanopia or tritanopia).
- Bug report with one click in the help: the running save, the settings, the tuning values and a note with version and seed in one ZIP file in `data/export`.
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
| `dart run bin/calibrate.dart report` | Compare the simulation with the real results since 2023; `--sample 3 --runs 3 --types Hügel,Berg` for a quick check on part of them, `--set name=value` to try a tuning value |
| `dart run bin/breaks.dart` | How breaks fare along the route in the simulation, against how often they win in reality |
| `dart run bin/timecut.dart` | Riders and sprinters outside the time limit on the hilly and mountain stages of stage races, real against simulated |
| `dart run bin/compare.dart a.json b.json …` | Compare tuning files on the same fresh random numbers, on all races and on the held-back ones (`standard` = default values) |
| `dart run bin/calibrate.dart run [--hours h] [--runs n] [--dry]` | Search better tuning values; `--dry` does not write them |
| `dart run bin/calibrate.dart reparse` | Rebuild the stored results from the cached result pages |
| `dart run bin/snapshot.dart` | Check that a saved and reloaded career continues identically |
| `dart run bin/plan.dart [team] [seed]` | Print the season plan the sports director draws up: the line-ups of the big races and the race days per rider |
| `dart run bin/growth.dart [seasons] [rider id]` | Play several seasons and print how the level of the riders moves, to balance development against decline |

## How the simulation works

A stage is cut into 200 m segments; where the profile smooths away the steepest ramp of a categorised climb, the ramp is put back. Riders have a threshold power derived from their attributes for the terrain of each segment, an endurance reserve that drains over the day and a short-term reserve for efforts above threshold. Groups ride on a shared clock; drafting, rolling resistance, gradient, air density and wind decide who can hold a wheel.

- **Body and altitude.** Every rider rides with his own weight and height from the WorldDB. The attributes keep their meaning (watts per kilogram uphill, watts per drag area on the flat), but descents and rolling roads feel the real build. Above 500 m the air gets thinner: less drag, and less power for the riders.
- **Weather.** Temperature, rain and wind follow month and country. The road turns as it goes, so the wind comes from ahead, behind or the side; heat and cold cost energy, rain makes descents slower and crashes more likely.
- **The fight for the break.** The field rides hard until a move sticks: on sprint stages after a few kilometres, on hard days often only after an hour, and on a climb the strongest get away.
- **Sitting up.** On a hard day, once the race is on, a rider with nothing left to ride for lets the group go on the climbs and rolls in with others like him; a helper keeps going as long as his leader is with him and he still has a job. A gruppetto forms in the mountains and on hilly days.
- **The chase.** Only the riders who take turns on the front share its wind, so a field that lets a group go does not catch it by drafting alone. Helpers spend themselves on the front; once empty they drop back and their team stops chasing. A team whose leader is no longer in the field does not chase either.
- **Position.** Before cobbled sectors, the foot of a climb, open roads in the crosswind and in the last kilometres the teams fight for the front: helpers bring their leader up, strong riders hold their place more easily, and staying in front costs energy. Position decides who gets through a narrow sector, who finds shelter in an echelon and how well a sprinter is placed.
- **Sectors.** A race with enough cobbles or gravel (a classic, Strade Bianche, a stage over many sectors) is a *sector race*. On a sector the group is a line in the order of the fight for position. The further back a rider is, the harder he has to ride; when one lets the wheel go, everyone behind him is gapped unless he has the punch to come round. Rough roads wear down riders who are not made for them, so every sector counts towards the end, and the finale starts at the first very hard sector of the second half, or where half of the sectors are done.
- **Sports directors.** During the race every team is run by the same logic, the player's team included. A team joins the chase when the gap gets out of hand and it has a favourite to ride for. A rider in the break does not pull when his leader is a favourite behind. A team that loses its leader lets its best remaining rider ride for himself. At the start of the finale each team decides whether to sacrifice its helpers, to send its leader on the attack because he would lose a sprint, or to keep things together because he would win it. Dropped favourites are brought back by their helpers. For the player's team each decision can be overruled over the radio; whatever the player leaves alone is decided as for every other team. Each team races in its style; with a strong crosswind in the forecast the teams with the strongest rouleurs set out to split the field.
- **Attacks.** Favourites attack on climbs and cobbles, late on the flat and, if they descend well, downhill; a clearly stronger rider may go from far out. In the break the riders attack each other as the finish nears. Every rider descends at his own speed.
- **Crashes and punctures.** They happen during the stage, more often in a nervous bunch, on descents, on cobbles and in the rain. Helpers wait for a leader and pace him back behind the team cars; a crash can cost form for days or end the race. Inside the last three kilometres a rider keeps the time of his group. Tyres and mechanics count: wide tyres puncture less on cobbles, narrow ones more; a good mechanic halves part of the time lost. When a leader crashes or punctures, his team decides how many helpers wait.
- **Sprints** with lead-out trains, position and the occasional crash; **uphill finishes** ridden with whatever is left.
- **Time trials** with start order and a wind that changes over the day; fatigue counts. A team time trial is ridden in a line; whoever cannot hold the wheel is let go, and the time is taken on the fourth or fifth rider. The bike of the day counts: the time trial bike is faster on the flat, the lighter road bike can be faster on a mountain time trial.
- **Stage races.** Fatigue grows with the effort of the day and shrinks by a share that depends on the recovery attribute, more on rest days. Riders outside the time limit leave the race unless more than a fifth of the field is; the gruppetto rides to stay inside it.

Each team rides to a plan: a role per rider, an approach (wait, control, make the race hard) and a breakaway policy. AI teams derive their plan from the route, their riders and the general classification. The quality of the sports director in the car changes how well the plan is executed.

- **In the background.** In the game the stages of a day are simulated on other isolates, all races of the day at the same time, while the window stays free; the header shows what is being computed. A stage is handed over as a job (`StageJob`) holding everything that decides it, so the result is the same as on the main thread. Watching a stage, skipping it and simulating to a date all go through `StageRaceRun`; tests check both.

Everything is deterministic for a given seed. 48 tuning parameters live in `data/calibration/tuning.json`. The physical ones (threshold power, the gain per attribute point, drafting, the spread of the daily form) are held within values from the literature, so that the calibration tunes how teams race rather than physics.

## Calibration

The calibration package compares the simulation with real WorldTour results of the seasons 2023 to 2026 and searches for better tuning values (`kalibrieren.ps1`, typically overnight). The results are not part of the repository: `dart run bin/fetch_results.dart <year>` in `packages/calibration` loads a season into `data/results/<year>/`, and the script does that itself before every run. Races of earlier seasons are simulated on the route of their year (`worlddb variants`) with the riders of the real result who are in the database, at their strength of 2026.

Only the dynamics of a race are scored, by five figures: the size of the winner's group, the gap of tenth place, the gap of the middle of the field, the average speed, and whether the early breakaway won. Two further terms check how often one of the three riders best suited to the route wins, per race type, and how much time the ten best of the general classification lose on a stage. Which rider wins is deliberately not part of the score: the best riders do not start everywhere, and crashes, illness and form of the day decide a single real result. That is also why older seasons are usable although their fields were different.

The error has three parts: an error per race in those figures and the time loss of the classification leaders (capped, except for the breakaway), per race type the difference in how often a breakaway wins and how often the winner's group falls into each size class (solo, duo, small group, bunch), which keeps the search from giving up on rare outcomes, and per race type the difference in how often a top favourite wins. The race types are flat, hilly, mountain, sector races and time trials; the frequency terms weight them by the square root of their number of races, so that the few sector races are not sacrificed. The real weather of a race day is not known; each run draws one for the country and the month.

The earlier a season, the less of its field the database covers, because it knows the riders of 2026: of the real finishers of 2021 only 58 % are found, of 2023 75 %, of 2025 92 % (`dart run bin/seasons.dart`). Those fields are smaller in the simulation than they were, and a fifth to a third of their riders were much younger then or are past their best now. The calibration therefore uses the seasons from 2023 on (`firstSeason` in `dataset.dart`), 534 races, and the report lists the error per season. The search changes about three tuning values per attempt. The real figures are measured on all finishers, so a winner who has since retired still counts; a big first group is scaled to the part of the field that is simulated. A fifth of the races is held back as a control set, and an improvement only counts if it holds on a second set of random numbers. Races that cannot be matched, such as parade stages, are listed in `data/calibration/exclude.txt`. The report also names tuning values that sit at the edge of their range.

## Languages

Texts are written in English in the sources and wrapped in `tr('…')` (`packages/sim/lib/src/i18n.dart`). Every other language is a translation: the German texts live in one table, `packages/sim/lib/src/i18n_de.dart`, keyed by the English text; a text without an entry is shown in English. Placeholders are `{0}`, `{1}` and so on, and `dec()` formats numbers with the decimal mark of the language.

To add a text: write `tr('New text {0}', [value])` and add the German line to the table. A further language is one more table of the same shape. Enum labels and constant tables keep their English text as a constant and are translated where they are shown. Texts that the game has already written, such as inbox messages and race reports, keep the language they were written in; code that recognises such a text uses `isText()`. The command-line tools of the other packages (calibration, world database) still print German.

## Save games

The running career is saved automatically to `data/savegame.json` shortly after every action. Named saves are written to `data/saves/<name>.rmsave`.

Both use file format 2: UTF-8 text with one JSON document per line. Line 1 is a small header (`format`, `name`, `savedAt`, `teamName`, `gameDate`), line 2 the complete state of the career (riders, squads, contracts, sponsors, staff, licences, rankings, the state of the random generator), and every further line one race of the running season with its results. A save is a snapshot: loading takes a couple of seconds regardless of how many seasons were played, and a later change to the simulation does not alter what already happened. A mid-season save is around 20 MB.

Format 1 files from earlier versions, which stored a log of the player's decisions and replayed the career on loading, can still be opened.

## Tests

```bash
cd app
flutter test test/save_test.dart            # save -> load yields the identical state
flutter test test/screens_test.dart         # renders every screen with real data
flutter test test/one_simulation_test.dart  # watching, skipping and simulating to a date are one race
flutter test test/plan_test.dart            # the sports director's season plan
flutter test test/people_test.dart          # goals, promises, morale, personality
```

`screens_test.dart` writes images to `app/test/goldens/`. They exist to check layouts without opening a window; pass `--update-goldens` to refresh them. Both tests need `data/world.sqlite` and are skipped without it.

The simulation has tests of its own that need no world database: they ride a synthetic field of 22 teams over synthetic routes (flat, hilly, mountain, cobbles, time trials, a Grand Tour).

```bash
cd packages/sim
dart test                                  # behaviour that must hold regardless of tuning
dart run tool/explore.dart [runs] [tuning.json] [route] [name=value ...]   # key figures per route type
dart run tool/grand_tour.dart [tuning.json]   # a synthetic Grand Tour: fatigue, abandons, time limit
dart run tool/trace_run.dart <route> <seed> [tuning.json]   # events and gaps of one run
```

A career starts from a random seed. Set the environment variable `RADMANAGER_SEED` to a number to reproduce a run, for example a failing test.

See [ROADMAP.md](ROADMAP.md) for what is planned and [CHANGELOG.md](CHANGELOG.md) for what changed.

`one_simulation_test.dart` checks three things: a preview, the stage that counts and a replay give the same result; seventy days of a career played with the radio on (answering every call as recommended), with the radio off and with the staff in charge end in identical results for every stage; and no file in the game or the app simulates a stage other than through `StageRaceRun`.

## Known limitations

- Calibrated on 534 races of the seasons 2023 to 2026 (error 9.1), the race shape still differs where tuning cannot reach: the middle of the field finishes too close to the winner (on hilly days 1:27 behind instead of 5:39, in the mountains 12:28 instead of 22:04), breakaways win 7 % of the road races instead of 19 %, the first group on flat stages is too big (64 riders instead of 38), and sector races end solo in 32 % instead of 74 %. In the simulation nobody sits up once his work is done, and the gruppetto forms almost only in the mountains.
- The time limit as a whole takes as many riders out as in reality, but sprinters too often in the mountains (36 % of their starts on mountain stages finish outside it, against 21 % in reality).
- A stage takes two to three times as long to simulate as in 0.2.0 (finer segments, per-rider physics), and so does the calibration.
- Material and staff act through small factors that are not calibrated yet: drag of the bike, rolling resistance and punctures of the tyre, the time lost at a wheel change, the recovery overnight. The calibration races without them.
- The suppliers of the teams follow what was known of 2026 when the game was made and may be outdated.
- The stage files carry no compass headings, so the wind comes from a random direction relative to the route and the road turns at random.
- AI teams do not yet promote riders from their development teams.
- Few riders reach the very top (a best attribute of 84 or more) after several seasons: the stars of 2026 age and their successors arrive slowly.
- Money is not balanced: salaries, budgets, sponsor offers and camp costs are placeholders derived from rider strength, because the WorldDB contains none of them.
- Prize money from the WorldDB is not used yet.
- Staff other than the team managers named in the WorldDB is generated.
