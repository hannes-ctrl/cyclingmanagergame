# Changelog

## Unreleased (0.4.0)

A world that lasts ten seasons.

**Money**
- Every team keeps books: sponsor money, prize money, wages and the same running costs as the player's team (travel and material, staff, facilities, development team, less what the suppliers pay). Budgets start where each team covers its costs; prize money is profit, and the ranking moves the sponsor money a third of the way each year.
- A wage limit for every team, the player's included: what the budget leaves after the running costs, plus half of the savings beyond a reserve, minus half of a shortfall. The other teams renew, promote and sign only within it; free agents take up to two fifths less rather than stay without a team.
- Teams with savings to spare build up their weakest facility. Facility costs are shares of the budget, so small teams can afford small facilities.
- Sponsor money grows with the wage level of the whole world, so that a field that grows stronger and dearer does not run out of money.
- Teams keep a quarter of the prize money; as in real cycling, the riders share the rest.
- Riders and teams meet in the middle: a team that cannot pay the market wage offers what it can, and a rider takes it if it is four fifths of his worth. Teams keep money back for their own riders they still want to renew.
- Riders end their careers: from 31, a rider whose contract runs out retires with a chance that grows with age (15 % at 31, 90 % from 36), half as often if he is still among the best. Your own riders announce it on 1 August.
- The other teams build their facilities up to the level that fits their strength. Savings beyond a third of the budget go to their owners at the turn of the year.
- The free agents no longer take part in the transfer rounds as if they were a team. They used to "renew" with themselves, which kept riders over 30 from retiring after a season without a team; now that rule applies, and about 150 more free agents a year retire.
- Team pages show budget and balance. The multi-season test reports budgets, balances, teams in debt, facility levels and the riders in all divisions.

**The winter**
- The day of the last race (25 October) ends the racing season: the best of the season and a list of what the winter holds arrive at once, not on 31 December.
- The new young riders arrive on 1 November as free agents, so that they can be signed for next season, for the development team too; the academy's talents sign for your development team then.
- Riders without a team can be signed at any time and join at once; they ask about a quarter less than the market wage.
- From 1 November camps can be booked for January and February. A camp that runs over the turn of the year used to be lost with the old season; now it goes on.
- The other teams sign for their needs: a team that keeps fewer climbers, sprinters, puncheurs, time triallists or cobble riders near its level than it wants values them two points more, and a rider from its own country one point.
- Delegation: the board can build up the facilities, one at a time, while a tenth of the budget stays in the account. The multi-season test hands it over and reports the day the winter begins.

**Scouting, market and staff**
- Scouting in stages: a first impression, a detailed report with potential and character, and a test at the team's base (6,000 €) after which everything is known. Riders of small teams and free agents start with much wider ranges than those of WorldTeams.
- Scout assignments: a scout looks for two months for riders of a country, an age and a kind and reports on the two he rates highest every one to three weeks; a weaker scout errs more. A scouting view on the staff page lists assignments, riders being watched and all reports.
- Competing offers: a rider of another team takes a week to answer and hears what else is on offer. He chooses by wage against his worth, the level of the team, whether he would lead there, and home; his own team counts a little more for a loyal rider. While he decides, the other teams leave him alone.
- Your own riders can be renewed at any time, also with a running contract; the new terms apply from next season.
- Staff develop: people under 40 get better, those of 56 and more slowly worse. From 1 November stronger teams try to lure your best people with a third more; match the offer on the staff page by 31 December or they leave. The other teams replace their weakest people when the market has clearly better ones.
- A weekly note from the staff with what they would change: tired riders, races with places nobody is planned for, a young rider without a mentor, a rider on the market who would suit the team. Staff messages have their own topic in the inbox.

**Riders and plans**
- Mentoring: a rider of 28 or more looks after up to two young riders of 23 or less, also of the development team. They develop up to 8 % faster with a very professional mentor and take on some of his professionalism over the year. The other teams pair their most professional riders with their young ones each season.
- Programme templates: Cobbled classics, Ardennes classics, Giro programme, Tour helper, Vuelta programme, Sprinter's spring and Autumn classics follow the calendar of the season; own templates are saved from a rider's programme. A menu per rider in the rider matrix applies them.
- The season planner also warns of riders who would reach more than 85 race days, goal races a rider is not planned for, and races with more riders than places.
- Race preparation: line-ups can be saved as templates and applied again, and every change of the line-up or the tactics can be undone.
- Days in the break and combativity awards (the rider of the break who did the most work in front on each road stage) are counted, in a new ranking "Breakaways" and on the rider page.
- Form is shown as a step from poor to peak, with the trend arrow.

**Sponsors**
- Every sponsor has a wish for the season that the races can meet: a rider in the break at a race at home, a win at home, days in the break, combativity awards, a stage win at a Grand Tour or a top ten in a monument, by the size of the team. A met wish brings a tenth of his payment as a bonus at the end of the year.

**History and lists**
- A history page: the trophy room with the team's wins of big races, its seasons, records of all riders (points, wins and race days in a season, wins over the career) and every retired rider with his seasons and honours.
- Saved filters with a default in the rider search and the transfer market, and a column choice with named column sets.

**A field that keeps its level**
- The new riders of each year are made after real ones: the best 150 of every age from 19 to 21 in the WorldDB, set back to 18 or 19, each a little different. Before, a year's intake was about three points stronger at its top than a real year, and the field grew by 0.2 points a year (riders of 80 and more from 14 to 44 in ten seasons). The three exceptional talents a year are gone; the exceptional ones now come from the real models.
- Attributes slow down over the last ten points below a rider's ceiling instead of seven, so that the best of a year end where the best of a real year are.
- Over ten seasons (with the winter): WorldTour strength 77.5 to 77.9, riders of 80 and more 14 to 21, average age 28.3 to 28.8, riders in all divisions 4214 to 4222. `bin/cohorts.dart` compares the intake with the real riders of each age.

**Fixes in the calculations**
- Teams without ranking points counted as placed right behind the teams with points, so a small team without points was worth more to its sponsors every year. Now they rank behind them by strength; this also applies to the player's sponsor offers, and a season without points no longer shows place 0.
- The wage level of the world was first measured at the end of the first season, or at the first save: the first year's growth was lost, and a saved game indexed the budgets differently from one played on.
- A rider's chance to retire only alternated between two values from year to year and was tied to his wage demands, so some riders never retired.
- The season goals counted the free agents as a team when placing the player's team.
- Camps and facilities checked the balance without what was already booked for the month; two camps in one month could overdraw the account.
- A promotion from your development team ignored the wage limit.
- Amounts below minus one million were shown as thousands.

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
