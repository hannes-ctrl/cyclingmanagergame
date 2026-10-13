# Roadmap

Where Radmanager goes after 0.2.0 alpha, and what it has to be before it is called a beta.

Nothing here is promised; priorities are set version by version. Ideas come from *Football Manager* (FM), *Pro Cycling Manager* (PCM) and the dev blogs of *Velo Victory* (VV), and from what their players ask for in the forums. Each item names its source in brackets; the links are at the end.

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

Each phase is one version. The reason for its place is given first.

### 0.3.0 Races that hold up

*First, because every later system is judged by race results.*

Done:

- **Finer physics.** Segments of 200 m, each rider's own weight and height, altitude, head-, tail- and crosswind; the physical tuning values are held within values from the literature.
- **Sector races.** Cobbled classics and gravel races have their own model: fight for position, the group as a line, splits behind a rider who lets go, wear from rough roads.
- **Incidents in the race.** Crashes, punctures and echelons happen on the road, with the surface, the rain and the size of the group as causes, and cost time or end the race. Illness and the time cut take riders out of stage races. [PCM]
- **Weather.** Each stage has weather by month and country; the race preparation shows it. [PCM, VV]
- **The fight for the break,** helpers who run empty, attacks inside the break, late on the flat, downhill and from far out.
- **Teams race for themselves.** One sports director logic for every team including the player's, whose decisions can be overruled. [1]
- **Time trials and stage races.** Fatigue, start order and changing wind in time trials; fatigue that levels off by recovery, and rest days.
- **One simulation.** A test guards that watching, skipping and "simulate until" give the same race. [3]
- **Partial plans.** Pin only a leader or an approach for a race; the sports director plans the rest stage by stage.
- **The search.** About three parameters per attempt instead of ten, and race types weighted so that the few sector races are not sacrificed.

Open:

- **The calibration run** for all of this: the tuning values are start values. After it, a look at what tuning cannot reach. Before the run the middle of the field finishes far too close to the winner (0:26 against 1:39 on average) and flat stages are too closed (91 % bunch finishes against 74 %).
- **Speed.** A stage takes two to three times as long as in 0.2.0, so a night holds only a few hundred attempts.
- **Older seasons.** Checked: the database covers 58 % of the finishers of 2021, 67 % of 2022, 75 % of 2023, 85 % of 2024 and 92 % of 2025. The calibration now uses 2023 to 2026 only. Filling the missing riders with anonymous ones of typical strength would bring the earlier seasons back.
- **Weather, second step.** Real compass headings for the routes, a forecast that can be wrong, riders who cope differently with heat and cold. [PCM, VV]

### 0.4.0 A world that lasts ten seasons

*Second, because money and squad balance are the ground under transfers, staff, facilities and sponsors.*

- **Multi-season test.** A tool plays ten seasons without a player and reports finances, squad strength per tier, licence moves, age structure and the number of top riders. It runs before each release.
- **Money.** Salaries, sponsor income, prize money from the WorldDB, camp and staff costs are set against real orders of magnitude. The budget is planned once per season; a surplus carries over and can be spent (signing bonuses, facilities later). No yearly renewal chores. [2]
- **The top of the field.** The yearly intake brings a few exceptional talents, so that riders with a best value of 84 or more do not die out.
- **The other teams act like teams.** They promote from their development teams, sign for their needs (a sprinter when theirs leaves, riders from the sponsor's country) and let riders go. [VV]
- **Licences on the three-year ranking,** as in reality. [VV]
- **The winter has content:** training camps, contract talks, the season plan and the intake fall into the weeks without races. [2]

### 0.5.0 The rider as a person

*Third, because it is the largest gap to the models, and it needs believable results to react to.*

- **Season plan by the sports director.** *Done* for the player's team and every other team: importance of the races, suitability, an even load, replacements. Still open: the importance follows the tier of a race only, not sponsor goals or a rider's own goals.
- **Season goals per rider.** In the season planner each rider gets up to three goal races; training builds form towards them. The planner shows a rider's goals and favourite races in the same view, so planning needs one screen. [2, PCM]
- **Personal attributes.** A small set, visible only through scouting and time: professionalism (development and fitness), ambition (wants a role and results), loyalty (contract talks), consistency (spread of the form of the day), adaptability (settling in after a transfer). [VV]
- **Morale.** One value per rider, moved by role, programme, results and promises, acting on form within a narrow band. A rider is never unhappy for not racing while he is resting towards a goal. [2, FM]
- **Promises.** "Leader at the Tour", "a free role in the classics", made in contract talks, checked at the end of the season. [FM]
- **Mentoring.** An experienced rider takes one or two young riders, including from the development team; they develop a little faster and take on some of his professionalism. [VV]
- **Leadership and race sense** as attributes of the road captain, which decide how well the plan is carried out without radio. [2]
- **Programme templates.** "Classics", "Grand Tour helper", "sprinter's spring" assigned with one click. [PCM]

Talks are kept small on purpose: a choice in the inbox with a visible effect, no press conferences with repeated questions. [7]

### 0.6.0 Scouting and the transfer market

*Fourth, because it needs balanced money (0.4.0) and riders with a will of their own (0.5.0).*

- **Scouting in stages.** A scout gets an assignment (region, age, profile) and delivers reports; each report narrows the range of a rider's values and potential, up to a test at the team's base. Scouts have skills and a limited number of riders they can follow. [VV, FM]
- **Shortlist.** A watch list with messages only for what matters: contract running out, rider available, another team bidding. [FM] *Done in a first form:* available at the start of the signing period, renewed, signed elsewhere.
- **Comparison** of two or more riders side by side. [FM] *Done for two riders,* as a second column on the rider page.
- **Competition.** Other teams bid at the same time, offers have deadlines, a rider chooses by wage, role, team level and distance from home. [VV]
- **Contracts.** Renewal at any time, clauses (role, bonus, release clause), a signing bonus. [2]
- **Lower tiers.** Riders outside the scouted area are shown with wide ranges, so that looking there pays. [VV]

### 0.7.0 Race day

*Fifth, because the result is the game, and watching it is what brings the player back. It comes after the systems so that it has something to show.*

- **The stage in fast motion.** The stage runs across the profile as a bar with groups, gaps and incidents; speed is adjustable, key moments stop the clock when the player wants them to. The radio decisions sit in this view. [VV]
- **Race plan with roles.** Leader, second leader, attackers, sprinter, lead-out, road captain, set before the start and changed by radio. Most exists; it becomes one page. [VV]
- **Sprint train and team time trial order.** [PCM]
- **Jerseys** of the WorldDB for the leaders in report and race view. [PCM]
- **Combativity and days in the break** as counted results, so that small teams have goals they can meet. [2]
- **A written report as a news item,** with the decisive moments named. Exists; it gains incidents and weather. [7]

### 0.8.0 The organisation

*Sixth, because investments that pay off over years can only be balanced once the money has been stable for many seasons.*

- **Sponsors.** Contracts over several years, income that follows tier and results, wishes that are met by the race itself (jersey in the break at the home race, a win in the sponsor's country) instead of abstract targets. Offers fit the team: nationality of riders and where it wins. [2]
- **Staff.** Coaches, directors, scouts and doctors improve, have ambitions and can be lured away. A weekly note from the staff: "this is what I would change". [VV, FM]
- **Facilities.** Medical, training, scouting, marketing, equipment, each with a few levels and a cost per season. [VV]
- **Equipment.** The supplier's material with a small effect on time trials and cobbles, or none at all; decided after the money test. [2]
- **The manager's career.** Reputation, offers from other teams, dismissal when goals are missed. [FM]
- **History.** Season review, awards, a trophy room, records, the career of every retired rider. [7, VV] *Started:* a review message with four awards at the turn of the year.

### 0.9.0 Beta

*Last: no new systems. See below.*

## Quality of life

These are spread over the versions above rather than saved for the end. The first group has no dependencies and goes into 0.3.0 and 0.4.0.

**Navigation and speed**

- A back button and history that always return to the previous page. [5] *Done for 0.3.0,* with filters, sorting and scroll position kept for the session.
- Keyboard control: space to continue, arrow keys from rider to rider, Ctrl+F for the search, Esc to go back. [6] *Done for 0.3.0,* including the rows of a list.
- Every name is a link: rider, team, race, country, wherever it appears. *Started:* riders in race results, teams in the ranking and on the rider page (the team page exists now).
- No screen waits for the simulation; a day simulates in the background with a visible progress.
- Bookmarks for pages the player uses often. [5]

**Lists**

- Saved filters and saved column sets per list, with a default the player chooses. PCM added saved search filters in a patch after its players asked. [10]
- Multi-select with checkboxes for actions on several riders: assign a programme, a camp, a training focus, put on the shortlist. [7]
- Sorting by any column, remembered per list.
- Export of any list as CSV. [7]

**The inbox**

- Fewer messages rather than more filters: one summary per day and topic, not one message per event. [6] *Done:* from three messages of a topic on a day.
- Settings per topic: show, summarise, or do not send. *Done:* each topic can be switched off; summarising is one switch for all.
- Filters that stay set. A filter that resets itself is among the oldest FM complaints. [6]
- Messages that ask for a decision are marked and carry the decision in them.

**Continuing**

- "Simulate until" stops for what the player has chosen: own race, contract offer, injury, transfer deadline. [9]
- **Vacation mode.** The assistant takes over for a period, with rules for what he may decide. [9]
- Autosave with several rolling files; a weekly save can be opened again. A PCM thread asks for a way to go back a few days. [4] *Done:* four weekly files.
- Undo for the last line-up or plan change before it is confirmed.

**Planning**

- The season planner shows conflicts at once: rider entered twice, too many race days, a goal race without the leader. [2] *Started:* riders entered for two overlapping races.
- Copy a line-up from the last race or from a template.
- An assistant's proposal for every chore (line-up, programme, training), which the player accepts or changes. Nothing has to be done by hand that the player does not care about.

**Reading**

- Text scaling and layouts for wide and high-resolution screens. Exists as a scale; needs a check at 4K and 21:9. [7]
- A clearer form display than the scale from −3 % to +4 %: steps with an arrow for the trend. *Started:* the trend arrow in the squad.
- Notes on a rider, written by the player. *Done.*
- A glossary behind the tooltips, and a short introduction for new careers.
- Singular and plural in English, dates in the format of the language, command-line tools in English.

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
| Start | Introduction, glossary, three difficulty levels that change money and expectations, not the simulation |

### Conditions for calling it a beta

- **Stability.** A hundred seasons simulated without a player end without an error; a save game loads to exactly the same state at every point.
- **Compatibility.** The save format has a version and a migration; saves from the first beta open in every later one.
- **Speed.** A day without the player's race takes under a second, a season without watching under five minutes.
- **Balance.** The figures of the multi-season test lie in bands written down beforehand, on three different seeds.
- **Tests.** Every page has a rendering test in both languages; every system has a test of its rules.
- **Installation.** An installer or a zip that runs on a clean Windows without the toolchain, with a way to supply the world database.
- **No placeholders.** No value in the interface that has no effect, and no effect that is not explained in a tooltip.

### Deliberately not in the beta

- A race the player rides himself, in 3D or 2D with direct control. The game is the manager's side.
- A mode as a single rider.
- Multiplayer.
- Editors for database and stages, and other platforms than Windows. Planned for after 1.0.
- Press conferences, social media, agents as persons. They are the parts of FM its players ask to have reduced. [7]

### Open question before a public beta

The world database is built from the WorldDB for Pro Cycling Manager, and rider photos, jerseys and logos are not ours. A beta among friends can use them as today, supplied by each player. A public one needs either a database of its own with real names from open sources, or generated names with an import for community databases. This decision should be taken by 0.6.0, because scouting and generated riders depend on it.

## Versions at a glance

| Version | Theme | Depends on | Comfort that ships with it |
| --- | --- | --- | --- |
| 0.3.0 | Races that hold up (in progress) | New calibration run | Back and history, keyboard, links everywhere |
| 0.4.0 | A world that lasts | 0.3.0 | Saved filters and columns, rolling autosaves, inbox summaries |
| 0.5.0 | The rider as a person | 0.3.0, 0.4.0 | Planner with conflicts, templates, multi-select, notes |
| 0.6.0 | Scouting and market | 0.4.0, 0.5.0 | Shortlist messages, comparison, export |
| 0.7.0 | Race day | 0.3.0, 0.5.0 | Stops in "simulate until", assistant's proposals |
| 0.8.0 | The organisation | 0.4.0, 0.6.0 | Vacation mode, history pages |
| 0.9.0 | Beta | All | Introduction, glossary, difficulty, installer |

## Sources

1. [Steam, PCM 25: thread on AI that reacts only to the player](https://steamcommunity.com/app/2511310/discussions/0/600775301991020441)
2. [Steam, PCM 2023: career mode suggestions](https://steamcommunity.com/app/2063610/discussions/0/6226836983328514134)
3. [PCM.daily: "Too easy to play – Too difficult to simulate"](https://pcmdaily.com/forum/viewthread.php?thread_id=52615) and [Steam, PCM 25: difficulty levels](https://steamcommunity.com/app/2511310/discussions/0/592901971597389958/)
4. [PCM.daily: going back some days in career mode](https://pcmdaily.com/forum/viewthread.php?thread_id=41327) and [Steam, PCM 2023: fitness peak](https://steamcommunity.com/app/2063610/discussions/0/3812906855250540293/)
5. [FRVR: nine things FM26 needs to fix](https://frvr.com/blog/news/9-things-football-manager-26-needs-to-fix-immediately-to-get-back-on-side)
6. [Sports Interactive Community: "That dreaded inbox"](https://community.sports-interactive.com/forums/topic/592101-that-dreaded-inbox/)
7. [FM Scout: features wanted for FM27](https://www.fmscout.com/a-football-manager-2027-new-features-suggested.html)
8. [Steam: Velo Victory announcements and dev blogs](https://steamcommunity.com/app/3976980/allnews/)
9. [Steam: Velo Victory store page](https://store.steampowered.com/app/3976980/Velo_Victory/) and [the developer's posts](https://x.com/DavyDepuydt)
10. [SteamDB: PCM 25 patch notes with saved filters](https://steamdb.info/patchnotes/18928036)
