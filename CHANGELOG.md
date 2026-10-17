# Changelog

## Unreleased (0.5.0)

The rider, the market and race day: what was planned for 0.5.0 to 0.7.0, in one version, and the manager's career.

- Road captain: leadership and race sense, from character and experience, decide how well a team carries out its plan; chosen in the race preparation.
- Contract clauses: signing bonus, win bonus, release clause (the other teams may pay it from August, the money goes to the player) and a guaranteed leader's role; each lowers the wage a rider asks.
- A comparison table of up to four riders, the best value of each line in green.
- The race preparation shows the sprint train; in a team time trial the line can wait for the leader.
- The leaders' jerseys in the colours of the Grand Tours in report and live view; the report names who takes a jersey.
- The manager's career: a reputation from results against what the team's strength promised. With the job market switched on under Delegation (off by default), the board warns on 1 November after a bad season and dismisses after a second, other teams offer a job in the inbox, and an accepted offer hands you the new team at the turn of the year. The history shows the team of every season.
- Personalities from the WorldDB: loyalty from a rider's contract loyalty, more professional and steadier with years as a professional, more ambitious with wins; the same personality in every career.
- ROADMAP and FEATURES name the version that brought each item.
- Fix: a switched-off inbox topic also swallowed talks, so a rider who asked to leave got no answer; messages that ask for a decision now always arrive.
- Fix: the Giro was never recognised, because the WorldDB gives it the same class as the Vuelta; its winner got 150,000 € instead of 265,000 €, and the Giro and Vuelta templates held the wrong Grand Tour.

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
