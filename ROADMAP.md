# Roadmap

Where the game goes after 0.6.1 alpha, and what it has to be before it is called a beta.

Nothing here is promised; priorities are set version by version. Ideas come from *Football Manager* (FM), *Pro Cycling Manager* (PCM) and the dev blogs of *Velo Victory* (VV), and from what their players ask for in the forums. Each item names its source in brackets; the links are at the end.

## Next up

The working list, in order. It is rewritten whenever something on it is done; the sections below hold the full plan.

1. **The 3D view, second step:** the simulation steps along with the viewer instead of being replayed, so that the race can be watched live; then the player's instructions to his riders from the viewer (attack, follow, ride tempo, wait), sent back over the same link. The first step is done: a Godot viewer (Windows, Linux, macOS) replays the recorded stages, with the real kits, the land beside the road, team cars and spectators.
2. **The beta test among friends** with the 0.6.1 zip: where strangers get stuck, what they do not understand, what breaks. It decides what the beta still needs.
3. **The race shape, in the model, as ongoing work.** It is good enough for the beta. The largest gaps after the calibration of 17 and 18 October: bunch sprints on flat days end in groups of 25 instead of 35; breakaways win 21 % of mountain stages instead of 36 %; 35 % of the sprinters finish outside the time limit on mountain stages instead of 17 %; on hilly days the tenth is 0:54 behind instead of 0:19; the leaders of a stage race lose 0:28 a stage instead of 0:17. Four tuning values sit at the edge of their range, so the search alone cannot close these gaps.
4. **Speed** beyond the beta condition: two thirds of the time go into the step of each rider through each segment; a real gain needs longer segments where nothing happens.
5. **Weather, third step:** real compass headings, once a source for the routes' directions is found; the WorldDB has none.

Done since the last version of this list: explanations for every figure and choice, the owners' skim removed, the save format with a version and a migration, the release zip, balance bands, render tests of every page in both languages, a money sink for the player, less text, rider profiles and the licence rules when founding a team, the intake of ordinary riders that the first hundred-season run asked for, every tool in English, the calibration from 2021 (see the CHANGELOG), the balance bands on three seeds; in the 3D view the real kits from the game, the land beside the road, team cars and motorbikes, spectators and the race's logo. The calibration now measures a real race on the riders the simulation has: the middle of the field and the favourite wins had been measured against riders the simulation does not have.

## Principles

Three rules decide the order.

1. **The world before the decisions.** A feature that gives the manager a choice is only worth building once the thing it acts on is believable. Morale that changes form needs a calibrated simulation; facilities need money that means something.
2. **Model first, screen second.** Every system is built in the `game` package with a test and a multi-season run, then gets its page. A system without a page is acceptable for one version; a page without a system is not.
3. **No busywork.** The loudest complaints about the models are not missing features but chores: yearly sponsor renewals, a full inbox, screens that need ten clicks, riders who sulk for no reason. Every new system must answer "what does the player decide here, and how often?" before it is built.

## What the forums say

The research in short, because it shapes the plan more than any feature list.

- **PCM players** complain most about the world reacting only to the player (the peloton chases his break and lets the others go), about quick simulation giving results that differ from played races, about money that piles up with nothing to spend it on, about a winter with nothing to do, and about sponsors whose wishes have nothing to do with the team. They ask for rider goals shown in the season planner, contract renewals at any time, sponsor goals met by what happens in the race, and objectives for small teams such as days in the break. [1][2][3][4]
- **FM players** turned on FM26 almost only because of the interface: twice the clicks for daily tasks, a back button that leads somewhere else, slow screens, lost hotkeys and lost custom views. Their wish list for FM27 is short of new systems and long on comfort: multi-select, saved views and filters, fewer e-mails, keyboard control, text scaling, a trophy room, data export. [5][6][7]
- **Velo Victory** (planned for April/May 2027, closed beta before) bets on the rider as a person: seven personal attributes that change over a career, mentoring by experienced riders, scouting in stages from a first report to a test at the team's base, transfers in which the other teams follow their own needs, a vacation mode, awards, the three-year ranking for licences, a stage creator and open modding tools. [8][9]

Two conclusions. Radmanager has no race to play, so **the simulated result is the game**: it must be the same whether the player watches or skips, and the other teams must race for themselves. And comfort is not polish for the end; it is planned into every version below.

## The order

Each phase is one version. Every item stands under the version that brought it, whatever it was first planned for; what is still open stands under the version that is meant to bring it.

### 0.3.0 Races that hold up

*Released as 0.3.0 alpha on 14 October 2026. First, because every later system is judged by race results.*

**Races**

- **Finer physics.** Segments of 200 m, each rider's own weight and height, altitude, head-, tail- and crosswind; the physical tuning values are held within values from the literature.
- **Sector races.** Cobbled classics and gravel races have their own model: fight for position, the group as a line, splits behind a rider who lets go, wear from rough roads.
- **Incidents in the race.** Crashes, punctures and echelons happen on the road, with the surface, the rain and the size of the group as causes, and cost time or end the race. Illness and the time cut take riders out of stage races. [PCM]
- **Weather.** Each stage has weather by month and country, and a forecast that blurs the weather of the day and warns of echelons. [PCM, VV]
- **The fight for the break,** helpers who run empty, attacks inside the break, late on the flat, downhill and from far out.
- **Teams race for themselves.** One sports director logic for every team including the player's, whose decisions can be overruled. [1]
- **Time trials and stage races.** Fatigue, start order and changing wind in time trials; team time trials in a line; fatigue that levels off by recovery, and rest days.
- **One simulation.** A test guards that watching, skipping and "simulate until" give the same race. [3]
- **Partial plans.** Pin only a leader or an approach for a race; the sports director plans the rest stage by stage.
- **Race plan with roles** on one page: leader, helpers, sprinter, lead-out, tactics, director, tyres and time trial bike. [VV]
- **Race report in paragraphs:** how the day began, mishaps, the finale; power figures after every stage. [7]
- **The search** of the calibration: about three parameters per attempt instead of ten, race types weighted so that the few sector races are not sacrificed.

**The rider as a person**

- **Season plan by the sports director** for every team: importance of the races, suitability, an even load, replacements.
- **Season goals per rider:** up to three goal races, a sure start and a form peak there. [2, PCM]
- **Personal attributes:** professionalism, ambition, loyalty and consistency, with a summary term, shown through scouting. [VV]
- **Morale** for every rider, moved by programme, results and promises, acting on form. [2, FM]
- **Promises** for a race or, in contract talks, for a season. [FM]
- **Standing in the team,** from star to prospect, changeable for the player's riders.

**Team and market**

- **Shortlist** with messages only for what matters: available, renewed, signed elsewhere. [FM]
- **Comparison** of two riders: a second column on every rider page. [FM]
- **Equipment.** Bikes and tyres of the real suppliers with a small effect, contracts with offers, tyre and bike choice per race. [2]
- **Staff** with mechanics and physiotherapists for every team; team styles.

### 0.3.1 The race shape

*Released as 0.3.1 alpha on 15 October 2026.*

- **The calibration run** on the seasons 2023 to 2026: bunch sprints on flat stages fit (78 % against 77 %); what it could not reach is "Next up", item 1.
- **Riders who sit up,** groups that roll in, a gruppetto on hilly days; pace setters who only draft behind those who take turns.
- **Courses that change.** From the second season every race with routes of other years in the WorldDB (2021 to 2025, about 400 races) cycles through them.
- **The stage in fast motion** in the race report. [VV]
- **Facilities** for every team: training, medical, scouting, sports science and youth academy, five levels each, starting from the team's strength. [VV]
- **Prize money** after the real orders of magnitude; sponsor offers tied to the ranking.
- **The development team** on the market: young riders up to 22 can be signed for it; the other teams promote from theirs.
- **Hard training** that makes tired riders prone to illness, the load of the whole squad with one click.
- **Multi-season test.** `packages/game/bin/world.dart` plays seasons without a player; `bin/check.dart` checks every day of a season for broken rules.

### 0.4.0 A world that lasts ten seasons

*Released as 0.4.0 alpha on 17 October 2026. Over ten seasons the field keeps its level (WorldTour strength 77.4 to 78.0), the age stays at 28 to 29, licences and money hold. Second, because money and squad balance are the ground under transfers, staff, facilities and sponsors.*

**The world**

- **Money.** Every team keeps books by the player's rules, with a wage limit that includes savings, budgets from the ranking and the world's wage level, facilities bought from surpluses and worn down above what fits; owners take savings beyond a third of the budget. No yearly renewal chores. [2]
- **The top of the field.** Each new rider is made after a real one of 19 to 21, so a year is as strong as a real one; over ten seasons riders of 80 and more go from 14 to 21. Riders end their careers from 31.
- **The other teams act like teams.** Each plans its season like the player's sports director, signs for what it lacks (riders of its own country a little preferred) and lets riders go. [VV]
- **Licences on the three-year ranking,** as in reality: the 20 best riders of a team count, three seasons decide the WorldTour licences, the two best ProTeams are invited, ProTeam licences go yearly to those who can afford them, squads of 27 and 20 riders at least. [VV]
- **The winter has content.** The racing season ends with the last race (25 October) and its review; the young riders arrive on 1 November, free agents sign at any time, camps for January and February are booked from November and run over the turn of the year. [2]

**Scouting and the market**

- **Scouting in stages** with assignments by country, age and kind, up to a test at the base; riders of small teams are known far less well. [VV, FM]
- **Competition:** a rider answers after a week and weighs the player's offer against the best rival bid by wage, role, level and home; the rivals are named. [VV]
- **Contracts, first step:** renewal of the player's riders at any time. [2]

**The rider as a person**

- **Mentoring:** an experienced rider takes one or two young riders, in every team. [VV]
- **Talks** as a choice in the inbox with a visible effect, no press conferences: a rider who asks to leave, a rider who wants more races. [7]
- **Adaptability** as a fifth attribute: how fast a rider settles after a transfer.
- **Programme templates:** seven built in, own ones from a rider's programme. [PCM]

**The organisation**

- **Sponsors** with staggered contracts, offers from the ranking and a wish per sponsor and season that the races can meet (a break at home, a win in the sponsor's country), with a bonus. [2]
- **Staff** who develop with age, have ambitions and are lured away by stronger teams, with a weekly note: "this is what I would change". [VV, FM]
- **The board builds** the facilities when the player delegates it.
- **History:** the season review after the last race and a history page with trophy room, seasons, records and retired riders. [7, VV]

**Race day**

- **Our stages live** in fast motion after each day of our races, with the favourites named; the radio still comes before the stage. [VV]
- **Combativity and days in the break** as counted results, with a ranking. [2]

### 0.5.0 The rider, the market and race day

*Released as 0.5.0 alpha on 17 October 2026. What used to be planned as 0.5.0 (the rider as a person), 0.6.0 (scouting and the market) and 0.7.0 (race day) and was not done by 0.4.0, the manager's career, and most of what was planned for 0.6.0.*

**The rider, the market and race day**

- **Leadership and race sense** of the road captain, which decide how well the plan is carried out; chosen in the race preparation. [2]
- **Contracts, second step:** signing bonus, win bonus, a release clause that the other teams may pay, a guaranteed leader's role; each lowers the wage asked. [2]
- **Comparison table** of up to four riders, the best value of each line marked. [FM]
- **Sprint train and team time trial order.** The sprint train as the roles make it, shown before the start; in a team time trial the line can wait for the leader. [PCM]
- **Jerseys** of the leaders in report and live view, in the colours of the Grand Tours; the report names who takes a jersey. [PCM]
- **Personalities from the WorldDB:** loyalty from a rider's contract loyalty, more professional and steadier with years as a professional, more ambitious with wins; the same personality in every career.
- **The manager's career.** Reputation from results against what the team's strength promised. With the job market switched on (off by default, so that nobody loses his team unasked): on 1 November the board judges the season, warns after a bad one and dismisses after two; other teams offer a job as a talk in the inbox, and an accepted offer hands the player the new team at the turn of the year. [FM]

**The organisation and comfort** (planned for 0.6.0)

- **Facilities, second step:** a marketing department; every level above three raises what sponsors pay by three per cent, measured against the level a team started with. [VV]
- **The season plan in the winter** for the next year: from the end of the racing the planner shows next season's races on next year's courses and next year's squad; the plan and the goals made there become the programme at the turn of the year. [2, PCM]
- **Vacation mode.** The staff take over training, scouting, the season plan, line-ups and the radio, also over the turn of the year; the assistant answers the riders or the player comes back for them; a job offer always brings him back; the board stays out of the market. [9]
- **Bookmarks** for pages, riders and teams, in the sidebar. [5]
- **Multi-select** in the squad, the rider search and the transfer market: pencil in for a race, training focus and load, a training camp, the shortlist, the comparison. [7]

**Races** (planned for 0.6.0)

- **Weather, second step:** riders cope differently with heat and cold, by build and home country. [PCM, VV]
- **The time limit with real fields** measured; dropped groups now watch it like the gruppetto, which rides for its weakest riders.
- **Older seasons** come back to the calibration with `--from 2021`: anonymous riders, typical of their team in that race, take the place of the finishers the database does not know (42 % in 2021, 33 % in 2022).
- **The race shape, second step:** a wider range for the form of the day and a calibration run of four hours; the control races improved a little (7.81 against 8.00), the shape of the races did not change.

### 0.6.0 What is left, and the way to the beta

*Released as 0.6.0 alpha on 18 October 2026. Fourth: what 0.5.0 left open, and the conditions for the beta below.*

**Done**

- **Saves that stay valid:** a version and a migration step for every change; a save the game cannot open is kept beside it.
- **A zip for a clean Windows** (`release.ps1`), optionally with the world database and the pictures for friends.
- **Balance bands** in `world.dart`, checked at the end of every run; **render tests** of every page in both languages, in the smallest window, at 4K and 21:9.
- **The intake keeps the world at its size:** the first run over a hundred seasons emptied the smaller teams after about twelve seasons, because only the best 150 of a year came in. With the young riders of ordinary level the second run held its size for all hundred seasons.
- **The race shape, third step:** sprint gaps in a big bunch, riders who roll in, sprinters paced back on hilly days; a fair measurement of the real races and the time limit in the calibration.
- **Less text, more tooltips;** two facilities built at the same time; founding a team by licence rules; a money sink for the player; dates and plurals per language; the radio in fast motion; CSV export in the debug page.

**Open**

- **The race shape and speed:** see "Next up".
- **Real compass headings** for the routes, once there is a source for them.

### 0.6.1 For the test among friends

*Released as 0.6.1 alpha on 18 October 2026. Every figure and choice explained in a tooltip, the owners no longer take the player's savings. With it every condition for the beta below is met.*

### 0.7.0 Beta

*Last: what the test among friends with 0.6.1 brings up, then the beta. See below. In progress: the stage in 3D, which Hannes asked for: a viewer made with Godot, so that it runs on Windows, Linux and macOS, and so that the player can one day steer his riders in it.*

**The 3D view**

- **Done:** the simulation records where every rider was at each 200 m point, for the races of the player's team; the game sends a stage over a WebSocket on the local machine to a viewer made with Godot 4.7; the viewer lays out the road from the profile and the directions of the wind model, with hairpins on steep climbs, builds the land around the camera, and replays the stage with every rider in his team's colours, cameras, a director, the groups and the profile.
- **Done, second step:** riders made from a human model (CC0, Quaternius) on road bikes made in code, pedalling by inverse kinematics and drawn from a vertex animation texture with a coarser version for the distance; the kit in the team's colours; the road with photo textures (CC0, Poly Haven), markings, finish line and rain; Forward+. Then the riders made into lean road cyclists on the hoods of a drop bar, scaled to their real height, with helmets, glasses and shoes, and three levels of detail.
- **Done, animations:** six stances baked into the animation texture (sitting, standing, sprinting, tucked, the salute, the time trial position on a time trial bike), chosen by every rider from the race; the bike rocking out of the saddle, cadence, freewheeling, leaning into bends; crashes and punctures where they happened.
- **Done, the picture:** the real kits from the game (every team, the leaders' jerseys), helmets and bikes in their colours; beside the road a finer strip with a verge, a ditch and an embankment or a cutting to the land instead of a bench; team cars behind the groups and every rider in a time trial, motorbikes ahead; spectators made from the base character who cheer; the race's logo on the finish arch and the barriers. The game's own helmets and bikes are meshes in a container the tools cannot read.
- **Next:** live: the simulation steps segment by segment while the viewer shows it, instead of a replay; then the player's instructions from the viewer (attack, follow, ride tempo, wait for the leader), sent back over the same link. PCM lets the player steer his riders in its 3D view; this is the reason for a real engine.
- **Later:** a rider getting a bottle or a new wheel from the car, looking back over his shoulder, numbers on the backs, towns and villages along the road, lakes and rivers, cleaner land on the inside of tight hairpins.

## Quality of life

These are spread over the versions above rather than saved for the end; each names the version that brought it.

**Navigation and speed**

- A back button and history that always return to the previous page, with filters, sorting and scroll position kept for the session. [5] *0.3.0.*
- Keyboard control: space to continue, arrow keys from rider to rider and through the rows of a list, Ctrl+F for the search, Esc to go back. [6] *0.3.0.*
- Every name is a link: rider, team, race, country, wherever it appears. *0.3.0 for the common cases:* riders and teams in race results, teams in the ranking and on the rider page, races on the rider page, a team's flag to the riders of its country.
- No screen waits for the simulation: the stages run on other isolates, and the header shows what is being simulated. *0.3.0.*
- Bookmarks for pages, riders and teams, in the sidebar; Ctrl+B or the star in the header. [5] *0.5.0.*

**Lists**

- Saved filters and saved column sets per list. PCM added saved search filters in a patch after its players asked. [10] *0.4.0,* for the rider search and the transfer market.
- Multi-select with checkboxes for actions on several riders: assign a programme, a camp, a training focus, put on the shortlist. [7] *A first step in 0.3.0:* a star per row for the shortlist. *0.5.0:* checkboxes in the squad, the rider search and the transfer market.
- Sorting by any column, remembered for the session. *0.3.0.*
- Export of the lists as CSV. [7] *0.3.0* for team pages; *0.6.0:* riders, teams, calendar, results and staff from the debug page, which is where a list export belongs in a game.

**The inbox**

- Fewer messages rather than more filters: one summary per day and topic, from three messages of a topic on a day. [6] *0.3.0.*
- Settings per topic: each topic can be switched off; summarising is one switch for all. *0.3.0.*
- Filters that stay set; those of the rider search also survive a restart. A filter that resets itself is among the oldest FM complaints. [6] *0.3.0.*
- Messages that ask for a decision carry it in them. *0.3.0:* every message leads to the page of its topic. *0.4.0:* talks with riders are answered in the message. *0.5.0:* job offers too.

**Continuing**

- "Simulate until" stops for what the player has chosen, by topic of the inbox. [9] *0.3.0.*
- **Vacation mode,** with rules for the riders' talks; the board stays out of the market. [9] *0.5.0.*
- Autosave in four weekly files that can be opened again. A PCM thread asks for a way to go back a few days. [4] *0.3.0.*
- Undo for the last line-up or plan change before it is confirmed. *0.4.0,* in the race preparation.

**Planning**

- The season planner shows conflicts at once. [2] *0.3.0:* riders entered twice. *0.4.0:* more than 85 race days, a goal race he is not planned for, more riders than places, and the rider matrix as a timeline that shows each race over its dates, in the manner of PCM.
- Copy a line-up from the last race or from a template. *0.3.0:* last year's line-up. *0.4.0:* saved line-up templates.
- An assistant's proposal for every chore, which the player accepts or changes. *0.3.0* for line-ups, tactics (pins), the season plan and training.

**Reading**

- Text scaling and layouts for wide and high-resolution screens. *0.3.0* as a scale; *0.6.0:* every page tested at 4K, at 21:9 and in the smallest window. [7]
- A clearer form display than the scale from −3 % to +4 %: steps with an arrow for the trend. *0.4.0.*
- Notes on a rider, written by the player. *0.3.0.*
- A glossary behind the tooltips, and a short introduction for new careers. *0.3.0:* the help page and a welcome message.
- English as the source language of all texts of the game, German as a translation table. *0.3.0.* *0.6.0:* singular and plural, and dates in the format of the language.

**Open data**

- The tuning file, the world database and the save format stay readable and documented. Editors and a stage import from GPX are not planned before the beta, but nothing is built that would shut them out. [8]

## The beta

The beta is the point from which a stranger can play ten seasons without help, without the debug mode and without hitting a dead end. From then on only balance, errors and comfort change, and save games stay valid.

### What the game is at that point

| Area | State at the start of the beta |
| --- | --- |
| Race simulation | Calibrated on 2021 to 2026 for all five race types; incidents, weather, time cut; other teams race for their own interest; the same result watched or skipped |
| Race day | Race plan with roles, stage in fast motion with radio, jerseys, written report with the decisive moments |
| World | Ten simulated seasons stay in balance: money, squad strength per tier, top riders, age structure; licences on the three-year ranking |
| Riders | Development with ceiling, season goals and form peaks, personal attributes, morale, promises, mentoring |
| Market | Scouting in stages, shortlist, comparison, competing bids with deadlines, contracts with clauses, other teams sign for their needs |
| Development | Linked development teams, stagiaires, promotion for the player and the other teams |
| Organisation | Sponsors over several years with wishes met in races, staff that develops, facilities, a balanced budget |
| Career | Reputation, job offers, dismissal; season review, awards, history |
| Comfort | Everything under "Quality of life" above, including vacation mode and the assistant's proposals |
| Languages | English and German complete, including everything the game writes |
| Start | Introduction and glossary |

### Conditions for calling it a beta

- **Stability.** A hundred seasons simulated without a player end without an error; a save game loads to exactly the same state at every point. *Done: a hundred seasons (2026–2125) without an error, every yearly save identical, the world at about 4,230 riders throughout, WorldTeams at 77.3–78.0, squads at 28.8. The player's team, which nobody signs riders for in such a run, drops down the ranking; that is the rule, not a fault.*
- **Compatibility.** The save format has a version and a migration; saves from the first beta open in every later one. *Done.*
- **Speed.** A day without the player's race takes under a second, a season without watching under five minutes. *Done: about three minutes a season for the whole world, half a second a day on average.*
- **Balance.** The figures of the multi-season test lie in bands written down beforehand, on three different seeds. *Done: seeds 3, 5 and 7 hold every band over ten seasons with the new tuning. Over a hundred seasons seed 3 left one band in three seasons after 2050 (30 or 31 riders from 80 instead of at most 28).*
- **Tests.** Every page has a rendering test in both languages; every system has a test of its rules. *Done.*
- **Installation.** An installer or a zip that runs on a clean Windows without the toolchain, with a way to supply the world database. *Done with `release.ps1`.*
- **No placeholders.** No value in the interface that has no effect, and no effect that is not explained in a tooltip. *Done: every value shown has an effect (checked for the rider, staff and personality values); every figure and choice that has one explains it in a tooltip.*

### Deliberately not in the beta


- A race the player rides himself, in 3D or 2D with direct control. The game is the manager's side.
- A mode as a single rider.
- Multiplayer.
- Editors for database and stages, and other platforms than Windows. Planned for after 1.0.
- Press conferences, social media, agents as persons. They are the parts of FM its players ask to have reduced. [7]

### Open question before a public beta

The world database is built from the WorldDB for Pro Cycling Manager, and rider photos, jerseys and logos are not ours. A beta among friends can use them as today, supplied by each player. A public one needs either a database of its own with real names from open sources, or generated names with an import for community databases. This decision should be taken before a public beta, because scouting and generated riders depend on it. For the beta among friends the WorldDB stays as it is (decided 18 October 2026).

## Versions at a glance

| Version | Theme | Depends on | Comfort that ships with it |
| --- | --- | --- | --- |
| 0.3.0 | Races that hold up *(released 14 October 2026)* | The calibration run | Back and history, keyboard, lists, inbox, shortlist, team pages, autosaves, help |
| 0.3.1 | The race shape *(released 15 October 2026)* | 0.3.0 | Facilities, dev-team signings, squad-wide training load, an even overview |
| 0.4.0 | A world that lasts *(released 17 October 2026)* | 0.3.0 | Timeline planner, templates, saved filters and columns, history, our stages live |
| 0.5.0 | The rider, the market and race day, the organisation *(released 17 October 2026)* | 0.4.0 | Comparison table, job offers in the inbox, vacation mode, multi-select, bookmarks, the winter plan |
| 0.6.0 | What is left, and the way to the beta *(released 18 October 2026)* | 0.5.0 | Less text, profiles when founding, a zip for friends |
| 0.6.1 | For the test among friends *(released 18 October 2026)* | 0.6.0 | A tooltip for every figure and choice |
| 0.7.0 | Beta | All | Introduction, glossary |

## Sources

1. [Steam, PCM 25: thread on AI that reacts only to the player](https://steamcommunity.com/app/2511310/discussions/0/600775301991020441)
2. [Steam, PCM 2023: career mode suggestions](https://steamcommunity.com/app/2063610/discussions/0/6226836983328514134)
3. [PCM.daily: "Too easy to play – Too difficult to simulate"](https://pcmdaily.com/forum/viewthread.php?thread_id=52615)
4. [PCM.daily: going back some days in career mode](https://pcmdaily.com/forum/viewthread.php?thread_id=41327) and [Steam, PCM 2023: fitness peak](https://steamcommunity.com/app/2063610/discussions/0/3812906855250540293/)
5. [FRVR: nine things FM26 needs to fix](https://frvr.com/blog/news/9-things-football-manager-26-needs-to-fix-immediately-to-get-back-on-side)
6. [Sports Interactive Community: "That dreaded inbox"](https://community.sports-interactive.com/forums/topic/592101-that-dreaded-inbox/)
7. [FM Scout: features wanted for FM27](https://www.fmscout.com/a-football-manager-2027-new-features-suggested.html)
8. [Steam: Velo Victory announcements and dev blogs](https://steamcommunity.com/app/3976980/allnews/)
9. [Steam: Velo Victory store page](https://store.steampowered.com/app/3976980/Velo_Victory/) and [the developer's posts](https://x.com/DavyDepuydt)
10. [SteamDB: PCM 25 patch notes with saved filters](https://steamdb.info/patchnotes/18928036)
