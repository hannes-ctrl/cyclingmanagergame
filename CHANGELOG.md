# Changelog

## Unreleased (0.3.0)

Race realism.

- Stages are cut into 200 m segments instead of 500 m; the steepest ramp of a categorised climb, which the profile smooths away, is put back.
- Physics: every rider rides with his own weight and height from the WorldDB; thinner air at altitude means less drag and less power; head-, tail- and crosswind.
- Weather by month and country: temperature, rain and wind. Heat and cold cost energy, rain makes descents slower and crashes more likely. The race report names the weather.
- The break of the day is fought for: the field rides hard until a move sticks, quickly on sprint stages, often for an hour on hard days.
- Helpers who have emptied themselves stop working, and a team stops chasing once its helpers are spent or its leader is gone.
- Position in the field before cobbled sectors, climbs, crosswind sections and the finish: helpers bring their leader to the front, at a cost. Position decides who gets through a sector and who finds shelter in an echelon, and helps the sprinters.
- Echelons in the crosswind.
- Attacks inside the break, late attacks on the flat, attacks downhill by good descenders and long-range attacks on climbs. Every rider descends at his own speed.
- Crashes and punctures during every stage, helpers who wait for their leader, injuries that cost form for days, abandons; the three-kilometre rule; crashes in bunch sprints.
- Time limit in stage races, with a reprieve when more than a fifth of the field is outside; the gruppetto rides to stay inside it.
- Time trials count the fatigue of earlier stages and of the effort itself, start in reverse order of the general classification and see the wind change over the day. Team time trials are ridden in a line; the time is taken on the fourth or fifth rider.
- Fatigue in stage races no longer runs into a common ceiling: it grows with the effort of the day and shrinks by a share that depends on recovery. Rest days help.
- Calibration: the physical tuning values are held within values from the literature; new terms for how often a top favourite wins and how much time the leaders of the general classification lose per stage. `tuning.json` holds start values that still need a calibration run.
- Tests for the simulation that need no world database (`packages/sim/test`), and tools to look at the simulation on synthetic routes (`packages/sim/tool`).
- Sector races: cobbled classics, gravel races and stages over many sectors are a race type of their own. On a sector the group rides as a line in the order of the fight for position: the back is harder, and a rider who lets the wheel go gaps everyone behind him. Rough roads wear down riders who are not made for them, and cobbles cause punctures and crashes in proportion to their difficulty. This replaces the fixed number of riders who got through a sector.
- One sports director logic for every team, the player's included: who chases (and who joins when the gap gets out of hand), who sits on in the break, who takes over when a leader is lost, and what a team does in the finale. The radio shows the director's recommendation; an unanswered question is decided by him, no longer by "stick to the plan".
- Dropped favourites are brought back by their helpers.
- The race preparation shows the weather of the first stage.
- Calibration: breakaway wins count again, per race and as a frequency per race type. Sector races are reported as their own type. The search changes about three parameters per attempt instead of ten, and the frequency terms weight the race types by the square root of their number of races.
- Calibration on the seasons 2023 to 2026 only: of the fields of 2021 and 2022 the database covers too little (58 % and 67 % of the finishers). `bin/seasons.dart` shows the coverage per season, and the report lists the error per season.
- Removed: what was left of the trial run in the race screen. A preview run remains in the application state for the screen tests only.
- A test guards that watching, skipping and "simulate to a date" give the same race (`app/test/one_simulation_test.dart`).
- Season plan by the sports director: all races of the season planned before the first day, by importance, suitability and an even load; leaders split over the Grand Tours; replacements when a rider drops out; "Replan the season" in the race planner; can be switched off under "Delegation". Every other team plans its season with the same planner. Tool `bin/plan.dart` prints a plan. The suitability of riders for routes is worked out from weights per stage that are stored in `data/route_fit.cache.json` (4.7 s the first time, under a second afterwards).
- Inbox: "Mark all read" and "Delete all" (asks once if several unread messages would go), topics that can be switched off, and one summary for three or more messages of a topic on a day.
- Season review with awards at the turn of the year.
- Arrow keys, Page Up/Down, Home, End and Enter in the list under the mouse.
- The race planner warns when a rider is entered for two races that overlap.
- Form trend in the squad; races on the rider page lead to their report.
- Shortlist with messages when a watched rider becomes available, renews or signs elsewhere; filter for it in the rider search.
- Rider comparison on the rider page, and a note of your own per rider.
- Team pages, reached from the team ranking and from a rider's page.
- Automatic saves every Monday of the game, four rotating files (`data/saves/auto-1…4.rmsave`).
- Partial plans: in the race preparation and in the tactics dialog during a race, only what the player changes is pinned (marked with a pin, released with a click on it). The sports director plans the rest for every stage. A pinned sprinter is a protected rider on stages that do not end in a sprint. With "Fix everything" the complete plan applies exactly as set and the sports director changes nothing; that was the only choice until now.
- Navigation: back and forward through the pages visited (header buttons, Alt+← / Alt+→, Esc, mouse side buttons). Pages stay alive for the session and keep their filters, sorting and scroll position.
- Keyboard: Space continues, Ctrl+F opens the rider search, the arrow keys step from rider to rider on the rider page.
- Rider names in stage results and classifications open the rider page.
- Fixed: a pace-setter on a sector could ride above his threshold on an empty reserve for as long as the sector lasted.

## 0.2.0 alpha

- Calibration on race dynamics only: size of the winner's group, gap of tenth place, gap of the middle of the field, average speed. Winners and breakaway wins no longer enter the error.
- Calibration data from the seasons 2021 to 2026 instead of 2026 alone; the routes of the earlier years come from the WorldDB's stage files (`worlddb variants`).

- English as a second language, switched by flags in the settings; English is the default. Covers the interface and everything the game writes (inbox, race reports, radio).
- One look for buttons, fields, chips, menus and dialogs on every screen; the last screens of the redesign are done.
- The gap chart of the race report shows the values under the pointer.
- Development teams linked to their real professional teams; a team without one can found its own.
- Stagiaires from 1 August, for the player and the other teams.
- Slower, more realistic rider development: growth concentrates on a rider's strengths and levels off at a ceiling set by his potential.
- Rider photos on the rider page, with a silhouette for riders without one.
- Rider search over the whole database with filters.
- Debug mode with a debug page and test actions.
- Cobbled races: two new tuning values (effort on the sectors, mishaps); first group and solo wins move towards reality.
- Fixed: a stage could crash when the break of the day took every rider of the leading group.

## 0.1.0 alpha

First tagged version. Playable end to end, not balanced.

- World database built from the WorldDB 2026 for Pro Cycling Manager: riders, teams, races, stage profiles, points scales, jerseys and race logos.
- Race simulation in 500 m segments with groups, drafting, breakaways, attacks, cobbles, sprints, gruppetto and time trials; calibrated once against 127 WorldTour results of 2026.
- Career: calendar with championships, form and development, contracts and transfers, sponsors and season goals, staff and scouting, licences with promotion and relegation, development team, training camps.
- Race planner with wildcard applications, race preparation with roles and tactics, DS radio, forecast, "what if", race report with gap chart.
- Windows app with start menu, settings, named save games, rider pages, filters and search, tooltips for every figure.

Known gaps: cobbled classics are too easy, money is not balanced, no stagiaires, no crashes during a stage.
