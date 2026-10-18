import 'dart:io';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sim/sim.dart';

import 'app_state.dart';

/// Day a contract ends on: contracts run to the end of a year.
///
/// @param year Last year of the contract.
/// @returns The date in the format of the current language.
String contractEnd(int year) =>
    I18n.lang == Lang.de ? '31.12.$year' : '31 Dec $year';

/// Font of headings, buttons and big numbers.
const headFont = 'Barlow Semi Condensed';

/// Text style of a page or panel heading.
///
/// @param size Font size.
/// @returns The style in the heading font.
TextStyle headStyle(double size, {Color? color}) => TextStyle(
  fontFamily: headFont,
  fontSize: size,
  height: 1.1,
  fontWeight: FontWeight.w700,
  color: color ?? TeamColors.text,
);

/// @param tier A race tier.
/// @returns The colour that marks it in lists, chips and the calendar.
Color tierColor(RaceTier tier) => switch (tier) {
  RaceTier.grandTour => const Color(0xFFE86AA6),
  RaceTier.monument => TeamColors.red,
  RaceTier.worldTour => TeamColors.gold,
  RaceTier.proSeries => const Color(0xFF5AD19A),
  RaceTier.class1 => const Color(0xFF6DB3FF),
  RaceTier.championship => const Color(0xFFC9A2FF),
  _ => TeamColors.muted,
};

/// Country codes of the WorldDB that differ from ISO 3166, mapped to the
/// two-letter ISO code. All other codes are ISO three-letter codes already.
const _iso = {
  'DEN': 'DK', 'NED': 'NL', 'SLO': 'SI', 'GER': 'DE', 'SWI': 'CH', //
  'POR': 'PT', 'LAT': 'LV', 'UAE': 'AE', 'KOS': 'XK', 'KUW': 'KW',
  'ROM': 'RO', 'MOL': 'MD', 'SAR': 'ZA', 'SWD': 'SE', 'CRO': 'HR',
  'URU': 'UY', 'OMA': 'OM', 'CHI': 'CN', 'BUL': 'MTN', 'BER': 'BM',
  'GRE': 'GR', 'MAS': 'MY', 'SER': 'RS', 'CRC': 'CR', 'ZIM': 'ZW',
};

/// Flag of a country.
class Flag extends StatelessWidget {
  /// Creates a flag.
  ///
  /// @param code Country code of the WorldDB, e.g. `GER`.
  /// @param width Width in logical pixels; the height follows as 2:3.
  const Flag(this.code, {super.key, this.width = 20});
  final String code;
  final double width;

  // Flag code per country code; null if the package has no such flag.
  static final _known = <String, String?>{};

  @override
  Widget build(BuildContext context) {
    final iso = _known.putIfAbsent(
      code,
      () => FlagCode.fromCountryCode(_iso[code] ?? code),
    );
    final height = width * 2 / 3;
    if (iso == null) return SizedBox(width: width, height: height);
    return Tooltip(
      message: code,
      waitDuration: const Duration(milliseconds: 500),
      child: CountryFlag.fromCountryCode(
        iso,
        theme: ImageTheme(
          width: width,
          height: height,
          shape: const RoundedRectangle(2),
        ),
      ),
    );
  }
}

/// Flag followed by the country code, for table cells.
///
/// @param code Country code of the WorldDB.
/// @returns The cell content.
Widget flagCell(String code) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Flag(code, width: 18),
    const SizedBox(width: 6),
    Flexible(
      child: Text(
        code,
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: const TextStyle(color: TeamColors.muted),
      ),
    ),
  ],
);

/// Logo of a race on a tile in the colour of its tier. Races without a logo
/// show their abbreviation.
class RaceLogo extends StatelessWidget {
  /// Creates a logo tile.
  ///
  /// @param dataDir The data folder of the app.
  /// @param race The race.
  /// @param size Edge length in logical pixels.
  const RaceLogo({
    super.key,
    required this.dataDir,
    required this.race,
    this.size = 30,
  });
  final String dataDir;
  final RaceInfo race;
  final double size;

  // Whether a file exists, per path; checked once.
  static final _exists = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final color = tierColor(RaceTier.of(race.raceClass));
    final path = '$dataDir/logos/${race.id}.png';
    final has = _exists.putIfAbsent(path, () => File(path).existsSync());
    final abbr = race.abbr.isEmpty ? race.name : race.abbr;
    final short = Center(
      child: Text(
        abbr.substring(0, abbr.length < 3 ? abbr.length : 3).toUpperCase(),
        style: TextStyle(
          fontFamily: headFont,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: Color.lerp(TeamColors.ground, color, 0.22),
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(size * 0.16),
      ),
      child: has
          ? Image.file(
              File(path),
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => short,
            )
          : short,
    );
  }
}

/// Rounded chip that can be switched on and off.
class Pill extends StatelessWidget {
  /// Creates a chip.
  ///
  /// @param label Text of the chip.
  /// @param selected Whether it is switched on.
  /// @param onTap Called when the player clicks it.
  /// @param colors Team colours.
  /// @param dot Optional colour of a dot in front of the label.
  const Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
    this.dot,
  });
  final String label;
  final bool selected;

  /// Null disables the chip.
  final VoidCallback? onTap;
  final TeamColors colors;
  final Color? dot;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? TeamColors.text : Colors.transparent,
    shape: StadiumBorder(
      side: BorderSide(color: selected ? TeamColors.text : colors.line),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: selected
                    ? TeamColors.ground
                    : onTap == null
                    ? TeamColors.muted
                    : TeamColors.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Race groups a list can be filtered by; class 2 and under-23 races share
/// one entry.
enum TierGroup {
  grandTour('Grand Tours', [RaceTier.grandTour]),
  monument('Monuments', [RaceTier.monument]),
  worldTour('WorldTour', [RaceTier.worldTour]),
  proSeries('ProSeries', [RaceTier.proSeries]),
  class1('Class 1', [RaceTier.class1]),
  class2('Class 2 and U23', [RaceTier.class2, RaceTier.under23]),
  championship('Championships', [RaceTier.championship]);

  const TierGroup(this._label, this.tiers);
  final String _label;

  /// The label in the current language.
  String get label => tr(_label);
  final List<RaceTier> tiers;

  /// @param tier A race tier.
  /// @returns The group it is filtered under.
  static TierGroup of(RaceTier tier) =>
      values.firstWhere((g) => g.tiers.contains(tier));
}

/// Row of chips to filter races by group; no selection means all groups.
class TierPills extends StatelessWidget {
  /// Creates the row.
  ///
  /// @param selected The groups switched on.
  /// @param onChanged Called with the new selection.
  /// @param colors Team colours.
  const TierPills({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.colors,
  });
  final Set<TierGroup> selected;
  final void Function(Set<TierGroup>) onChanged;
  final TeamColors colors;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      Pill(
        label: tr('All'),
        selected: selected.isEmpty,
        colors: colors,
        onTap: () => onChanged({}),
      ),
      for (final g in TierGroup.values)
        Pill(
          label: g.label,
          selected: selected.contains(g),
          colors: colors,
          dot: tierColor(g.tiers.first),
          onTap: () => onChanged(
            selected.contains(g)
                ? ({...selected}..remove(g))
                : {...selected, g},
          ),
        ),
    ],
  );
}

/// Search field in the style of the app.
class SearchBox extends StatelessWidget {
  /// Creates the field.
  ///
  /// @param hint Placeholder text.
  /// @param onChanged Called with the text on every change.
  /// @param colors Team colours.
  /// @param width Width of the field; null fills the parent.
  const SearchBox({
    super.key,
    required this.hint,
    required this.onChanged,
    required this.colors,
    this.width = 200,
  });
  final String hint;
  final void Function(String) onChanged;
  final TeamColors colors;
  final double? width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 34,
    child: TextField(
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: TeamColors.muted),
        prefixIcon: const Icon(
          LucideIcons.search,
          size: 16,
          color: TeamColors.muted,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
        isDense: true,
        filled: true,
        fillColor: TeamColors.ground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: TeamColors.text),
        ),
      ),
      onChanged: onChanged,
    ),
  );
}

/// One line of a filter column: a checkbox or radio mark, a label and an
/// optional count.
class FilterOption extends StatelessWidget {
  /// Creates the line.
  ///
  /// @param label Text of the option.
  /// @param selected Whether it is ticked.
  /// @param onTap Called when the player clicks it.
  /// @param radio Draws a radio mark instead of a checkbox.
  /// @param count Optional number shown at the right.
  /// @param dot Optional colour of a dot in front of the label.
  const FilterOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.radio = false,
    this.count,
    this.dot,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool radio;
  final int? count;
  final Color? dot;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(3),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Row(
        children: [
          Icon(
            radio
                ? (selected ? LucideIcons.circleDot : LucideIcons.circle)
                : (selected ? LucideIcons.squareCheck : LucideIcons.square),
            size: 16,
            color: selected ? TeamColors.text : TeamColors.muted,
          ),
          const SizedBox(width: 8),
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? TeamColors.text : TeamColors.muted,
              ),
            ),
          ),
          if (count != null)
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                color: TeamColors.muted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    ),
  );
}

/// Heading of a group in a filter column.
class FilterHead extends StatelessWidget {
  const FilterHead(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
        color: TeamColors.muted,
      ),
    ),
  );
}

/// The season as a ribbon of twelve months with one bar per race, coloured
/// by tier. A click on a month selects it.
class SeasonTimeline extends StatelessWidget {
  /// Creates the timeline.
  ///
  /// @param year The season.
  /// @param races The races to draw, usually the team's own.
  /// @param colors Team colours.
  /// @param month The selected month, 1 to 12.
  /// @param today The current day of the career.
  /// @param onMonth Called with the month the player clicked.
  const SeasonTimeline({
    super.key,
    required this.year,
    required this.races,
    required this.colors,
    required this.month,
    required this.today,
    required this.onMonth,
  });
  final int year;
  final List<RaceEntry> races;
  final TeamColors colors;
  final int month;
  final DateTime today;
  final void Function(int) onMonth;

  static const _names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', //
    'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 62,
    child: LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final first = DateTime.utc(year, 1, 1);
        final days = DateTime.utc(year + 1, 1, 1).difference(first).inDays;
        double x(DateTime d) => w * d.difference(first).inDays / days;
        // Bars that overlap in time go to the next of three lanes.
        final sorted = [...races]..sort((a, b) => a.start.compareTo(b.start));
        final laneEnd = [first, first, first];
        final bars = <Widget>[];
        for (final r in sorted) {
          var lane = laneEnd.indexWhere((e) => !e.isAfter(r.start));
          if (lane < 0) lane = 2;
          laneEnd[lane] = r.end.add(const Duration(days: 2));
          final left = x(r.start);
          final width = (x(r.end.add(const Duration(days: 1))) - left).clamp(
            5.0,
            w,
          );
          bars.add(
            Positioned(
              left: left,
              top: 24.0 + lane * 12,
              width: width,
              height: 9,
              child: Tooltip(
                message: r.info.name,
                child: Container(
                  decoration: BoxDecoration(
                    color: tierColor(r.tier),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          );
        }
        return Stack(
          children: [
            Row(
              children: [
                for (var m = 1; m <= 12; m++)
                  Expanded(
                    flex: DateTime.utc(year, m + 1, 0).day,
                    child: InkWell(
                      onTap: () => onMonth(m),
                      child: Container(
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(left: 6, top: 3),
                        decoration: BoxDecoration(
                          color: m == month ? colors.panel2 : null,
                          border: Border(
                            left: BorderSide(color: colors.line),
                            top: BorderSide(
                              color: m == month
                                  ? TeamColors.text
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          tr(_names[m - 1]),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: m == month
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: m == month
                                ? TeamColors.text
                                : TeamColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            ...bars,
            if (today.year == year)
              Positioned(
                left: x(today),
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(width: 2, color: TeamColors.text),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Explanations of the figures the game shows, by the label or column
/// heading they appear under.
const statHelp = <String, String>{
  'Normalised power': 'The power a rider could have held evenly for the same strain: hard efforts weigh more than easy riding. Divided by the threshold it gives the intensity (IF); above 0.85 a stage was very hard.',
  'VAM': 'Metres climbed per hour on a climb. Around 1,700 is what the best manage on a long climb at the end of a hard stage.',
  'Team style': 'How a team\'s sports directors race and plan: sprint, general classification, classics, youth, experience or all-round. It follows from the squad and is worked out again every season; for your team you can set it under Delegation.',
  'Tyres': 'Narrow tyres roll best on smooth roads and puncture more on bad ones; wide tyres roll better and puncture less on cobbles and gravel and are a little slower on tarmac. The sports director chooses them per stage; in the race preparation you can fix them for the race.',
  'Mechanics': 'They prepare the bikes and change wheels in the race: good mechanics lose less time at a puncture or a crash and prevent some defects. One for about eight riders.',
  'Physiotherapists': 'Soigneurs and physiotherapists: in stage races good ones let the riders win back more of their fatigue overnight and on rest days. One for about ten riders.',
  'Personality': 'The person in a word, from professionalism, ambition, loyalty, consistency and adaptability. Green is a good sign (such as model professional, professional, loyal), red a warning (such as mercenary, slack, temperamental); most riders are balanced. It comes from what the WorldDB knows of a rider (loyalty to his contracts, years as a professional, wins) and is the same in every career.',
  'Heat and cold': 'How much a rider suffers on a hot or a cold day: a heavy rider sheds heat badly and keeps warm well, a light one the other way round, and riders of hot countries are used to the heat, those of the north to the cold. From 27 °C every degree costs energy, below 6 °C the cold does; the race preparation warns of riders who cope badly.',
  'Team ranking': 'The points of all the team\'s riders this season, by the UCI scale. The place decides what sponsors offer and is one of the board\'s goals.',
  'Three-year ranking': 'The points of a team\'s 20 best riders over three seasons. At the end of the third, the best teams get the WorldTour licences; the two best ProTeams are invited to every WorldTour race.',
  'Balance': 'Money in the account. It grows with sponsor and prize money and shrinks with wages and running costs, month by month. Savings raise what you may pay your riders.',
  'Board confidence': 'How content the board is, 0 to 100. Every season goal met raises it, every one missed lowers it more; it decides what sponsors offer, and with the job market switched on a low value can cost you the job.',
  'Reputation': 'Your standing as a manager, 0 to 100. It rises when your team finishes above what its strength promised and meets its goals, falls otherwise, and drifts towards the level of the team you run. Other teams make offers when your reputation reaches them.',
  'Job market': 'Switched on under Delegation (off at the start): on 1 November the board judges the season; after a bad one it warns you, after a second one it dismisses you at the end of the year. Other teams offer you jobs in the inbox; an accepted offer hands you their riders, staff, money and sponsors at the turn of the year.',
  'Marketing department': 'The sixth facility: every level above three raises what the sponsors pay by three per cent, measured against the level the team started with, on new contracts and offers.',
  'Standing in the team': 'What a rider may expect in his team: a star and a leader want to ride for themselves in important races; key domestiques, domestiques and prospects do not. It follows from strength and age; for your riders you can change it. Moving a rider up lifts his morale, moving him down lowers it, and so does a star who has to work for others.',
  'Morale': 'How content a rider is, in every team. Wins, podiums, kept promises and a role above his standing raise it; broken promises, being moved down and too few race days lower it. A rider who is injured or ill does not resent a race he misses. It shifts his form by up to just under one per cent either way, and the wage he asks.',
  'Season goals': 'Up to three races a rider builds his season around. He is sure to start there and is a good one per cent stronger, a touch weaker in the other races. The sports director sets them from the season plan; the target changes them.',
  'Promise': 'A commitment: a start or a leading role in one race, or, in contract talks, for the whole first season (a start in a Grand Tour, leader in a WorldTour race). Kept, it lifts morale; broken, morale falls far. If the rider is out injured or ill, it lapses without consequences.',
  'Professionalism': 'How seriously a rider takes training and recovery. High professionalism lets him develop up to ten per cent faster, low professionalism correspondingly slower.',
  'Ambition': 'How much a rider wants results and a role of his own. Ambitious riders react more strongly to everything that moves their morale, and complain about too few race days.',
  'Loyalty':
      'How attached a rider is to his team. Loyal riders ask less to renew.',
  'Consistency': 'How little a rider\'s form varies from race to race.',
  'Form': 'Power factor at the start of a race. 0 % is the level with normal training and no racing. Race days in the legs plus recovery raise it to about +4 %, exhaustion pushes it down to about −3 %.',
  'Fitness': 'Long-term training and racing load of roughly the last six weeks. More fitness means better form once the fatigue has faded.',
  'Fatigue': 'Load of the last week. It rises quickly with racing and hard training and falls again within a few rest days.',
  'Freshness': 'Fitness minus fatigue. Below −20 a rider is tired; below −40 a sports director would not select him.',
  'Strength': 'Overall value from the rider\'s best attributes. Decides market value and wage demand.',
  'Potential': 'How much the rider can still improve until about 27, from 1 to 6. From 4.5 patience pays off.',
  'Pot': 'Potential from 1 to 6: how much the rider will still improve.',
  'Fit': 'How well the rider\'s attributes suit the routes of this race, averaged over his three best stages.',
  'Race days':
      'Race days this season. From 80 on a sports director rests the rider.',
  'Training load': 'Training volume: easy lets the rider recover, hard builds fitness faster and tires him.',
  'Focus': 'In training: these attributes develop faster, the others more slowly. For sports directors: the kind of race he directs best.',
  'Market value': 'Yearly wage the rider would get on the market.',
  'Outlook for twelve months': 'Expected change per attribute in a year with normal training and an average coach. From 32 it goes downhill.',
  'Skill': 'The person\'s main value from 1 to 20. For a sports director the tactics, for a coach the development of the riders, for a doctor the length of lay-offs, for a scout the accuracy of the reports.',
  'Race reading': 'How well the sports director reacts to attacks and gets riders into the break of the day, from 1 to 20.',
  'Motivation': 'How much the sports director lifts his riders\' form on race day, from 1 to 20.',
  'Flat': 'Pace on flat roads and in the wind.',
  'Mountain': 'Long climbs over several kilometres.',
  'Medium mountain': 'Mid-length climbs and rolling terrain.',
  'Hill': 'Short, steep climbs.',
  'Time trial': 'Individual time trials over longer distances.',
  'Prologue': 'Short time trials of less than eight kilometres.',
  'Cobbles': 'Cobbled sectors and bad roads.',
  'Sprint': 'Top speed in the sprint.',
  'Acceleration': 'Acceleration: attacks and the start of the sprint.',
  'Downhill': 'Speed and safety downhill.',
  'Breakaway': 'Chance of making the break of the day, and work rate in it.',
  'Stamina': 'How slowly his power fades over a long day of racing.',
  'Resistance': 'How long the rider can ride above his threshold.',
  'Recovery': 'Recovery from stage to stage in stage races.',
  'FL': 'Flat: pace on flat roads and in the wind.',
  'MTN': 'Mountain: long climbs.',
  'MED': 'Medium mountain: mid-length climbs and rolling terrain.',
  'HIL': 'Hill: short, steep climbs.',
  'TT': 'Time trial.',
  'PRL': 'Prologue: short time trials.',
  'COB': 'Cobbles.',
  'SPR': 'Sprint.',
  'ACC': 'Acceleration.',
  'DH': 'Downhill.',
  'BRK': 'Breakaway: chance of making the break of the day.',
  'STA': 'Stamina over a long day of racing.',
  'RES': 'Resistance: time above threshold.',
  'REC': 'Recovery between stages.',
  'Adaptability': 'How quickly a rider settles in a new team. Until he has, his form is up to 0.8 per cent lower: an adaptable rider needs a few weeks, an inflexible one up to four months.',
  'Height': 'Taller riders catch more wind: their air resistance grows with their height, which costs time on the flat and in time trials.',
  'Weight': 'Every kilogram has to be carried uphill: at the same power a light rider climbs faster, on the flat weight matters little. Heavy riders also suffer more in the heat.',
  'Pot.': 'Potential from 1 to 6: how much the rider will still improve.',
  'Days in the break': 'Days a rider spent in the break of the day this season. They have their own ranking.',
  'Most combative': 'Combativity awards this season: on every stage the rider of the break who stayed out in front the longest.',
  'Licence': 'WorldTeam, ProTeam or Continental. It decides which races a team may and must ride and how many riders it may sign (WorldTeam 27–30, ProTeam 20–30, Continental 16–30). The WorldTour licences are given every three years by the three-year ranking.',
  'Points': 'UCI points by the official scale. They decide the team ranking of the season, and with it what sponsors offer, and over three seasons the licences.',
  'Type': 'What kind of rider he is, read from his best attributes. It only describes him; in a race the attributes themselves count.',
  'Wage in the pro team': 'The wage his strength would fetch on the market: what a contract with your pro team would cost.',
  'Stage': 'How far the scouts have got: a first impression gives rough ranges, a detailed report narrower ones, and after the test at the base every value is known.',
  'Class': 'The category of the race: WorldTour, ProSeries, class 1 or class 2. It decides how many UCI points there are and which teams may start.',
  'Stagiaire': 'From 1 August riders of the development team may start for the pro team, except in WorldTour races and championships. They stay in the development team.',
  'Fitness / fatigue': 'Fitness is the training and racing load of roughly the last six weeks, fatigue that of the last week; fitness minus fatigue is the freshness. Both feed the form.',
  'Market wage': 'The yearly wage a rider of his strength would get on the market. His demands start from it.',
  'Mentor': 'An experienced rider of 28 or more who looks after a young one of 23 at most in the same team or its development team. The young rider takes on some of his professionalism. A mentor looks after two at most.',
  'Mentor of': 'The young riders he looks after. They take on some of his professionalism.',
  'Scouting knowledge': 'How well your scouts know the rider. Unknown values show as ranges that narrow with every report, until the test at the base reveals them all.',
  'Wage budget': 'What the team may pay its riders per year. It follows from the budget and grows with the savings.',
  'Still free': 'What is left of the wage budget for new contracts after the wages already agreed.',
  'Standing': 'What a rider may expect in his team: a star and a leader want to ride for themselves in important races; key domestiques, domestiques and prospects do not. It follows from strength and age; for your riders you can change it. Moving a rider up lifts his morale, moving him down lowers it, and so does a star who has to work for others.',
  'Status': 'Whether the rider is available, out injured or ill, at a training camp or racing.',
  'Situation': 'What the ranking means for the licences at the end of the three years: who keeps a WorldTour licence, who goes up and who goes down.',
  'Overall':
      'The points of the seasons of the current three-year cycle added up.',
  'Other offer': 'Another team wants to lure this person away. Match the offer, or he leaves at the turn of the year.',
  'Operations': 'Running costs of the month beside the riders\' wages: staff, facilities, travel, material and service, less what the suppliers pay, plus one-off costs such as camps.',
  'Win': 'How often he won in the trial runs of this race.',
  'Top 3': 'How often he finished on the podium in the trial runs.',
  'Ø': 'His average place in the trial runs.',
  'Next season': 'His contract for next season: renewed, signed with another team, or still open.',
  'Entry': 'Whether the team starts: invited or obliged by its licence, or as a wildcard with the chance the organiser picks it.',
  'Clauses': 'Agreed in the contract: a bonus per win, a release clause for which another team may buy him out, or a guaranteed role.',
  'Wait': 'The team rides along and saves its strength for the finale.',
  'Control the pace':
      'The team controls the field and catches the break of the day in time.',
  'Make the race hard': 'The team sets a hard pace on the climbs before the finale, so that weaker riders are dropped.',
  'Split in the crosswind': 'Where the wind allows it on open roads the team rides in the gutter to split the field; elsewhere it controls the race.',
  'Ignore': 'Nobody of the team goes into the break of the day.',
  'Join': 'The team puts a rider into the break of the day.',
  'Chase down': 'The team does not let the break go and rides behind it.',
  'Board goals': 'What the board expects this season. At the turn of the year each goal met raises its confidence by seven points times its weight, each one missed lowers it by nine times its weight.',
};

/// Explanations that only make sense where they are shown, or repeat
/// another entry; the glossary leaves them out.
const helpInPlaceOnly = {
  'Win',
  'Top 3',
  'Ø',
  'Wait',
  'Control the pace',
  'Make the race hard',
  'Split in the crosswind',
  'Ignore',
  'Join',
  'Chase down',
  'Pot.',
  'Standing',
  'Mentor of',
  'Status',
  'Situation',
  'Overall',
  'Entry',
  'Next season',
  'Other offer',
  'Stage',
  'Fitness / fatigue',
};

/// Wraps a widget in a tooltip with the explanation of a figure, shown
/// after hovering for a moment. Labels without an explanation stay as
/// they are.
///
/// @param label Label or column heading of the figure.
/// @param child The widget to explain.
/// @returns The widget, with a tooltip if the label is known.
Widget withHelp(String label, Widget child) {
  // The label arrives translated; the table is keyed by the English one.
  final text = statHelp.entries
      .where((e) => e.key == label || tr(e.key) == label)
      .map((e) => tr(e.value))
      .firstOrNull;
  if (text == null) return child;
  return Tooltip(
    message: text,
    waitDuration: const Duration(milliseconds: 700),
    constraints: const BoxConstraints(maxWidth: 320),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    textStyle: const TextStyle(fontSize: 13, color: TeamColors.ground),
    child: child,
  );
}

/// The form as a step instead of a percentage: from poor to peak.
///
/// @param form Form factor, about 0.97 to 1.04.
/// @returns The step in the current language.
String formStep(double form) => form >= 1.02
    ? tr('peak')
    : form >= 1.005
    ? tr('very good')
    : form >= 0.99
    ? tr('good')
    : form >= 0.975
    ? tr('average')
    : form >= 0.96
    ? tr('below par')
    : tr('poor');

/// Colours of a race's leader's jerseys: the three Grand Tours their own,
/// every other race yellow, green, polka dots and white.
///
/// @param tour Which Grand Tour the race is, or null.
/// @returns General, points, mountains and youth.
({Color general, Color points, Color mountains, Color youth}) jerseyColors(
  GrandTour? tour,
) => switch (tour) {
  GrandTour.giro => (
    general: const Color(0xFFF2A0C0),
    points: const Color(0xFFB0307A),
    mountains: const Color(0xFF2F6FD0),
    youth: Colors.white,
  ),
  GrandTour.vuelta => (
    general: const Color(0xFFD82030),
    points: const Color(0xFF2FA866),
    mountains: const Color(0xFF3A6FD0),
    youth: Colors.white,
  ),
  _ => (
    general: const Color(0xFFF5D020),
    points: const Color(0xFF2FA866),
    mountains: const Color(0xFFE2333A),
    youth: Colors.white,
  ),
};
