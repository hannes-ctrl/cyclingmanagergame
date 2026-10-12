# Roadmap

Where Radmanager goes after 0.2.0 alpha. The order follows what depends on what: a believable simulation first, then the systems that give the manager decisions to make, then depth and presentation. Nothing here is promised; priorities are set version by version.

Ideas were collected from *Football Manager*, *Pro Cycling Manager* and the store description of *Velo Victory*; each item names its source in brackets.

## 1. Foundation: believable races and a stable world

Everything else builds on races that look real and on a world that stays in balance over many seasons.

- **Calibration over the seasons 2021 to 2026.** The simulation is tuned on race dynamics only: size of the winner's group, gap of tenth place, gap of the middle of the field, average speed. *In progress with 0.2.0.*
- **Cobbled races.** Sectors as the place where the race is decided, fights for position before them, punctures and crashes. The first two tuning values are in; the model needs more.
- **Crashes, punctures and the time cut in every race.** Today riders are only injured after a stage. [PCM]
- **Breakaways on hard days.** The peloton lets harmless groups go too far.
- **Weather and wind.** Rain, heat and crosswinds as a factor of the race. [PCM]
- **Multi-season test.** Play five to ten seasons automatically and check that finances, squad strength and licences stay stable. The tool for rider development exists (`growth.dart`); money and licences are missing.
- **Money.** Salaries, budgets, sponsor money, camp costs and prize money (which the WorldDB contains) are placeholders and need balancing. Precondition for sections 4 and 5.
- **Top of the field.** After several seasons too few riders reach a best attribute of 84 or more; the yearly intake needs more exceptional talents.

## 2. The rider as a person

The largest gap compared with the models: riders have attributes and form, but no will of their own.

- **Season goals per rider.** Set form peaks for chosen races; the training plan works towards them. [PCM]
- **Personality and morale.** Satisfaction with role, race programme and wage; morale acts on form. [FM]
- **Promises.** "Leader at the Tour", "a free role in the classics", with consequences when they are broken. [FM]
- **Talks.** One-to-one talks and a team briefing before big races. [FM]
- **Team dynamics.** Hierarchy, groups, the influence of leaders on young riders. [FM]
- **Race programme templates.** "Classics rider", "Grand Tour helper" assigned with one click. [PCM]

## 3. Scouting and the transfer market

- **Scouting assignments.** Scouts get regions or profiles ("under-23 climbers in Colombia") and deliver lists of recommendations. [FM]
- **Scouting the lower tiers.** Find talents there before the big teams do. [Velo Victory]
- **Shortlists.** A watch list with a message when a contract runs out or a rider becomes available. [FM]
- **Comparison of two riders** side by side, with a chart of their attributes. [FM]
- **Competition for riders.** Other teams bid at the same time, deadlines run out. [Velo Victory]
- **Development teams of the other teams.** They promote their own riders, as the player does.

## 4. Staff and the organisation

- **Staff with ambitions and development.** Directors and coaches improve and want to move up. [Velo Victory]
- **A second value for coaches.** Load management: less fatigue and fewer lay-offs under hard training.
- **Staff recommendations.** A weekly report: "this is what I would change". [FM]
- **Facilities.** Investments in medical care, training, scouting, marketing and equipment that pay off over years. [Velo Victory] *Needs balanced money.*
- **Equipment.** Frames, wheels and time trial material from the supplier, with a small effect on performance. [PCM] *Needs balanced money.*

## 5. Sponsors, media and the manager's career

- **Sponsor wishes per race.** "Show the jersey in the break at the home race", with a bonus. [PCM]
- **Media and press.** Headlines and rumours in the inbox, press questions before Grand Tours. [FM]
- **Season review and awards.** Rider of the year, best neo-pro, records, a hall of fame. [FM]
- **The manager's career.** Offers from other teams, dismissal when goals are missed, a reputation of his own. [FM]

## 6. Race day

- **Stage in fast motion.** The stage runs as a bar across the profile, with groups and gaps, instead of showing the result at once.
- **Line-up for team time trials and the sprint train.** Set the order. [PCM]
- **Jerseys in the race report.** The classification jerseys of the WorldDB for the leaders. [PCM]

## 7. Getting started and polish

- **Introduction for new careers.** A short tour of the most important pages.
- **Form display.** The scale from −3 % to +4 % is hard to read; steps or a bar would be clearer.
- **Singular and plural in English**, and date formats that follow the language.
- **Command-line tools in English.**

## Suggested next versions

| Version | Theme | Main items |
| --- | --- | --- |
| 0.3.0 | Race realism | Crashes and punctures, time cut, cobbles, breakaways on hard days, multi-season test |
| 0.4.0 | Riders | Season goals and form peaks, morale, promises, talks |
| 0.5.0 | Market | Scouting assignments, shortlists, comparison, competition for riders, money balancing |
| 0.6.0 | Organisation | Staff development, facilities, equipment, sponsor wishes |
| 0.7.0 | Presentation | Stage in fast motion, media, season review, introduction |
