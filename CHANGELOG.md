# Changelog

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
