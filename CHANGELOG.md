# Changelog

## Unreleased (0.7.0)

- The stage in 3D: a viewer made with Godot (Windows, Linux, macOS) shows the player's stages from the button 3D, with every rider where the simulation had him, a road laid out from the real profile, hairpins in the mountains, cameras and a director.
- The simulation records for the races of the player's team where every rider was at each 200 m point; only the running race keeps it. `sim.dart viewer` exports a stage for the viewer.
- The release zip contains the viewer (`-NoViewer` leaves it out).
- The 3D viewer looks far better: riders made from a CC0 human model on a detailed road bike, pedalling with bending knees, kits in the team's colours with six designs, helmets and glasses; asphalt, cobbles and gravel from CC0 photo textures with sharp markings and the finish line; rounder bends; Forward+ rendering. The full field still draws in one go.
- The riders look like road cyclists: lean, as tall as the real riders, a natural position on the hoods with the hands round the brake hoods of a drop bar; helmets with vents and chin straps, sports glasses, cycling shoes, clean hems on the kit. A third, coarser level of detail keeps the field fast.
- No trees on the road any more, also in hairpins.
- Animations in the 3D viewer: riders stand on the pedals on climbs and when they attack (the bike rocks under them), sprint on the drops, tuck on descents, lean into bends, freewheel, and the winner raises his arms; time trials on time trial bikes in the aero position; crashes and punctures shown where they happen. Race events name the riders they are about, for the viewer.
- The real kits from the game in the 3D viewer (`worlddb kits`): every team in its jersey and shorts, socks, shoes, gloves, bar tape and bottle, the leaders of a stage race in their jerseys; helmets and bikes in the colours of the kit.
- Beside the road a verge, a ditch and an embankment or a cutting to the land, instead of a bench.
- Team cars behind the groups and behind every rider in a time trial, motorbikes with cameramen ahead; spectators who cheer by the road; the race's logo on the finish arch and the barriers.
- Live races: the stages of the player's team run live by default in the 3D viewer, in race time from real time to fast motion; **Simulate** rides one as before without the viewer, and a switch makes that the rule.
- Orders to the own riders during a stage, in the game and in the viewer, for one rider or several: attack, follow the moves, ride tempo, save energy, help the leader. Orders and radio answers are saved with the day.
- The simulation rides a stage in the order of the race clock, so it can stop at any moment and go on; a stage ridden in one go comes out as before.
- In the viewer: race numbers on the riders' backs, glances back over the shoulder, towns at the start and the finish and villages on the way, lakes, a team car behind a rider who punctured or crashed and its mechanic at a puncture; no more ground rising over the road between the legs of a hairpin, darker rock.

## 0.6.1 alpha (2026-10-18)

Every condition for the beta is met; this is the version for the test among friends.

- Every figure and every choice that has an effect explains it in a tooltip: column headings, panel labels, the rider page, race roles, the race approach and the break of the day. The glossary grows with them.
- The owners no longer take the player's savings at the turn of the year.

## 0.6.0 alpha (2026-10-18)

On the way to the beta: a world that lasts a hundred seasons, saves that stay valid, less text, a zip for friends.

**World and races**
- The intake keeps the number of riders where it began: beside the best 150 of a year come as many young riders of ordinary level as retired. Without them the smaller teams ran dry after about twelve seasons, and from then on WorldTeams had too few riders.
- In a big bunch sprint gaps of a second open behind the first riders; riders with nothing left to ride for roll in near the line; on hilly days teams pace a dropped sprinter back.
- The calibration measures a real race on the riders the simulation has, counts favourite wins only for 2026 (whose riders the ratings describe) and scores the time limit for sprinters; `--from 2021` brings the earlier seasons in.
- New tuning from an eight-hour calibration over 814 races from 2021 to 2026: error 7.03 → 6.55 on the races tuned on, 6.54 → 6.09 on the control races; sprinters outside the time limit on mountain stages 41 % → 35 % (real 17 %), breakaway wins on flat days 3 % → 6 % (real 12 %).

**Saves and installation**
- The save format has a version and a migration; a save the game cannot open is kept beside it instead of being overwritten.
- A founded team gets the staff and facilities its squad deserves (it got those of a team without riders); old saves are repaired on loading, and its budget covers them.
- `release.ps1` builds a zip that runs on a clean Windows, with the Visual C++ runtime, optionally with the world database (`-World`) and pictures (`-Art`). Without the database the program says where it belongs.

**Interface**
- Founding a team: the strength of the best eight decides the licence, the licence the squad size (WorldTeam 27–30, ProTeam 20–30, Continental 16–30); rider profiles; unique abbreviations.
- Less text: explanations behind an ⓘ, shorter messages; arrow keys in the inbox; race names in the rider matrix only for the Grand Tours, the others in the tooltip.
- Two facilities can be built at the same time; one that cannot be built now is greyed out, and its tooltip says why.
- The radio question shows the last kilometres before it in fast motion.
- Dates and plurals in the form of the language; tooltips for the figures of the home page.
- CSV export only in the debug page.
- At the turn of the year the owners take the player's savings beyond half the budget.

**Fixes**
- The save tests overwrote the weekly autosaves of the running game.
- Pages overflowed in the smallest window (sidebar, rider search, delegation).
- The calibration report showed gaps of 59.5 to 59.9 seconds as 0:00.

**Tools and docs**
- Every tool, report and script in English; `calibrate.ps1` replaces `kalibrieren.ps1`; old milestone scripts removed.
- `world.dart --roundtrip` saves and loads every season, the run ends with balance bands written down for the beta; `check.dart --seasons`. Three seeds hold the bands; a hundred seasons run without an error.
- Render tests of every page in both languages and in the smallest window, at 4K and at 21:9.

## 0.5.0 alpha (2026-10-17)

The rider, the market and race day (the plans of 0.5.0 to 0.7.0), the manager's career, and most of 0.6.0. Over ten simulated seasons the field keeps its level (WorldTour strength 77.5 to 78.0, riders of 80 and more 14 to 23), the age goes from 28.3 to 29.0, the WorldTeams' median balance from 2.3 to 10.1 million euros.

**The rider and the market**
- Personalities from the WorldDB (contract loyalty, years as a professional, wins), the same in every career.
- Contract clauses: signing bonus, win bonus, release clause, guaranteed leader's role; each lowers the wage asked.
- A comparison table of up to four riders.

**Race day**
- A road captain whose leadership and race sense decide how well the plan is carried out.
- The sprint train before the start; a team time trial that can wait for its leader.
- Leaders' jerseys in the Grand Tour colours in report and live view.
- Riders cope differently with heat and cold (build, home country); rider page and race preparation show it.

**The manager and the organisation**
- Reputation from results against the team's strength; an optional job market (Delegation): warning, dismissal, job offers, a change of teams at the turn of the year. The history shows team and reputation of every season.
- A marketing department: three per cent more from the sponsors per level above three.
- The next season in the winter: next year's races, courses and squad in the planner; the plan becomes the programme at the turn of the year.
- Vacation mode in "simulate to", also over the turn of the year; the board stays out of the market.
- Bookmarks (star in the header, Ctrl+B) and multi-select in squad, rider search and transfer market.

**Calibration and tools**
- `--from 2021` brings older seasons back with anonymous riders; the form of the day may spread up to 3 %. A four-hour run: control error 7.81 against 8.00, the spread stayed at 1.5 %.
- `bin/check.dart --switch / --seasons / --job-market`; ROADMAP and FEATURES name the version of each item.

**Fixes**
- A crash when our best rider of a stage was no longer in the general classification.
- AI teams renewed riders beyond a full squad (a WorldTeam with 32); promoted teams kept their old squad size; the academy overfilled a full development team.
- The Giro was taken for the Vuelta (prize 150,000 € instead of 265,000 €, wrong templates).
- A muted inbox topic swallowed talks; a save during "simulate without stops" kept the staff in charge after loading.
- A rider promised more races got a full race or a championship; ticked riders stayed ticked after leaving; dropped groups ignored the time limit.

## 0.4.0 alpha (2026-10-17)

A world that lasts ten seasons, and a manager's year with more to decide. Over ten simulated seasons the field keeps its level (WorldTour strength 77.4 to 78.0, riders of 80 and more 14 to 21), the age stays at 28 to 29 and the WorldTeams' balances hold.

**Money and market**
- Every team keeps books by the same rules: sponsor money from the ranking and the world's wage level, a quarter of the prize money, wages, staff, facilities and running costs. A wage limit for every team decides what it can sign; owners take savings beyond a third of the budget.
- Competing offers: a rider of another team answers after a week and weighs your offer against the best rival bid (wage, level, role, home). Free agents sign at any time and join at once; your own riders can be renewed at any time.
- Riders end their careers from 31; the intake is made after real riders of 19 to 21, so a year is as strong as a real one.
- The other teams sign for their needs, build facilities up to what fits their strength and let those above it wear down.
- Licences after the UCI rules: a season counts the 20 best riders of a team, three seasons decide the WorldTour licences, the two best ProTeams are invited to all WorldTour races, ProTeam licences go yearly to those who can afford them. WorldTeams need 27 riders, ProTeams 20.

**The manager's year**
- The winter: the season review after the last race, the young riders on 1 November, camps for January and February.
- Scouting in stages (first impression, detailed report, test at the base) and scout assignments by country, age and kind.
- Staff develop with age, are lured away by stronger teams and write a weekly note; mentoring of young riders; talks in the inbox with riders who want to leave or race more; adaptability after a transfer.
- Sponsors wish for something the races can meet (a break at home, a win at home, a stage of a Grand Tour …) and pay a bonus for it.
- Our stages live in fast motion before the result, with the favourites named.

**Planning and interface**
- The season planner as a timeline in the manner of PCM, with overlaps marked; balanced teams for stage races; more even race days; programme and line-up templates, undo, warnings.
- A history page (trophy room, seasons, records, retired riders); a breakaway ranking; saved filters and column sets; form as steps.
- The board can build up the facilities; races can be sorted by importance and date; the single race has filters; loading a save asks first.

**Fixes**
- Teams without points were placed too high for their sponsors; the first year of the wage index was lost; the retirement roll alternated between two values; free agents counted as a team in the transfer rounds and the goals; camps and facilities ignored costs already booked; a camp over the turn of the year was lost; a promotion from the development team ignored the wage limit; the best riders could be unambitious.

**Tools**
- `bin/world.dart` reports money, facilities, all divisions and the start of the winter; `bin/cohorts.dart` compares the intake with real riders; `bin/check.dart` also checks squads, books, programmes and the turn of the year.

## 0.3.1 alpha (2026-10-15)

The race shape in the model, and the world over many seasons. Calibrated on 534 races of 2023 to 2026: error 7.65 to 6.61, on the control races 8.75 to 8.43. Bunch sprints on flat stages now fit (78 % against 77 %); the middle of the field still finishes too close to the winner, and the favourites win too often.

**Racing**
- Riders with nothing left to ride for sit up on hard days; groups in which nobody races roll in. A gruppetto also forms on hilly days.
- Pace setters only draft behind those who take turns with them, so a chasing field is no longer faster than the break by drafting alone.
- The front part of a split field presses on; in stage races the favourites' teams let harmless breaks go from stage 2.
- Crosswind only on open, flat roads in the plain, fixed per route and marked light blue on the profile.
- Climbing domestiques only on routes with real climbs; on cobbles the helpers are the best on the stones.
- Races change their course from year to year: from the second season every race with routes of other years in the WorldDB (about 400, the Grand Tours included) cycles through them.
- The stage in fast motion in the race report.

**Team and world**
- Facilities: training, medical, scouting, sports science and youth academy, five levels each, starting from the team's strength. Under Finances.
- Hard training makes tired riders prone to illness; the load of the whole squad is set with one click.
- Young riders (up to 22) can be signed for the development team.
- Market: strong riders move up to teams of their level, the very top no longer dies out. AI teams promote from their development teams; three exceptional talents a year.
- Prize money after the real orders of magnitude; sponsor offers tied to the ranking.

**Interface**
- Birth date, height and weight on the rider page; the founded team's country is chosen by flag.
- The overview is an even grid of six tiles.
- Header arrows visible with every team colour; table headings and the rider page's tiles no longer overflow.

**Tools and docs**
- Calibration run of 15 October: 364 attempts, 18 improvements; five tuning values at the edge of their range (drafting in large groups, form of the day, power per point).
- `bin/world.dart` plays seasons without a player; `bin/check.dart` checks every day of a season for broken rules.
- Calibration: `report --sample/--set`, `bin/breaks.dart`, `bin/timecut.dart`.
- README shortened, details in FEATURES.md; the concept is in English (`docs/concept.html`).

**Fixes**
- Ranking points of a stage race with fewer than three finishers.
- Facilities started a whole team a level too low instead of varying single facilities.
- The season planner judged riders by their attributes at the start of the season; replacements after an injury now use the current ones, and a loaded game plans exactly like the one played on.

## 0.3.0 alpha (2026-10-14)

Races that hold up better, riders as people, a season plan for every team, material and staff. Calibrated on 2023 to 2026; not balanced.

**Simulation**
- 200 m segments; every rider with his own weight and height; altitude; head-, tail- and crosswind; weather by month and country.
- The fight for the break, helpers who empty themselves, positioning before key points, echelons, attacks of every kind, descents at each rider's speed.
- Crashes and punctures with injuries and abandons, the 3 km rule, the time limit with gruppetto.
- Time trials with fatigue, reverse start order and changing wind; team time trials in a line.
- Sector races (cobbles, gravel) as a race type of their own.
- One sports director logic for every team, the player's included; the radio shows his recommendation.
- Stages simulated in the background, all races of a day at once.

**Riders and team**
- Personality, morale, standing in the team, season goals and promises.
- Season plan for every team by its sports director.
- Mechanics and physiotherapists; material of real suppliers; team styles.
- Power figures after every stage; weather forecast, tyres and time trial bike in the race preparation.

**Interface**
- Back and forward, keyboard control, autosaves, shortlist, rider comparison, notes, team pages, help with glossary, CSV export, colour vision setting, bug report as ZIP, single race from the start menu.
- English source texts with German as a translation table.

**Calibration**
- Physical values held within the literature; terms for breakaway and favourite wins and the GC riders' losses; candidates must beat the current setting by a margin.

## 0.2.0 alpha

- Calibration on race dynamics (group sizes, gaps, speed) over the seasons 2021 to 2026.
- English as a second language; one look across all screens.
- Development teams tied to their real teams, stagiaires, slower rider development.
- Rider photos, rider search, debug mode, harder cobbled races.

## 0.1.0 alpha

First tagged version: world database from the WorldDB 2026, race simulation in 500 m segments, a full career (calendar, form, contracts, sponsors, staff, licences, development team) and the Windows app. Playable end to end, not balanced.
