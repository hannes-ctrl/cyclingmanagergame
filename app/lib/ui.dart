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
  'URU': 'UY', 'OMA': 'OM', 'CHI': 'CN', 'BUL': 'BG', 'BER': 'BM',
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
  monument('Monumente', [RaceTier.monument]),
  worldTour('WorldTour', [RaceTier.worldTour]),
  proSeries('ProSeries', [RaceTier.proSeries]),
  class1('Klasse 1', [RaceTier.class1]),
  class2('Klasse 2 und U23', [RaceTier.class2, RaceTier.under23]),
  championship('Meisterschaften', [RaceTier.championship]);

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
        label: tr('Alle'),
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
    'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', //
    'Nov', 'Dez',
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
  'Persönlichkeit': 'Die Person in einem Wort, aus Professionalität, Ehrgeiz, Treue und Konstanz. Grün ist ein gutes Zeichen (etwa Musterprofi, Professionell, Loyal), rot eine Warnung (etwa Söldner, Nachlässig, Launisch); die meisten Fahrer sind ausgeglichen. Sie steht fest, sobald die Karriere beginnt.',
  'Stellung im Team': 'Was ein Fahrer in seinem Team erwarten darf: Star und Kapitän wollen in wichtigen Rennen auf eigene Rechnung fahren, Edelhelfer, Helfer und Talente nicht. Sie folgt aus Stärke und Alter; bei deinen Fahrern änderst du sie. Eine Aufwertung hebt die Moral, eine Rückstufung drückt sie, ebenso ein Star, der Helferdienste leisten muss.',
  'Moral': 'Wie zufrieden ein Fahrer ist, in jedem Team. Siege, Podien, gehaltene Versprechen und eine Rolle über seiner Stellung heben sie; gebrochene Versprechen, eine Rückstufung und zu wenige Renntage drücken sie. Wer verletzt oder krank ist, nimmt ein verpasstes Rennen nicht übel. Sie verschiebt seine Form um bis zu knapp ein Prozent in jede Richtung und seine Gehaltsforderung.',
  'Saisonziele': 'Bis zu drei Rennen, auf die ein Fahrer seine Saison ausrichtet. Dort startet er sicher und ist gut ein Prozent stärker, in den übrigen Rennen eine Spur schwächer. Der Sportliche Leiter setzt sie aus dem Saisonplan; mit der Zielscheibe änderst du sie.',
  'Versprechen': 'Eine Zusage: ein Startplatz oder eine Kapitänsrolle in einem Rennen, oder im Vertragsgespräch für die ganze erste Saison (Start bei einer Grand Tour, Kapitän in einem WorldTour-Rennen). Gehalten hebt sie die Moral, gebrochen fällt die Moral tief. Fällt der Fahrer verletzt oder krank aus, entfällt sie ohne Folgen.',
  'Professionalität': 'Wie ernst ein Fahrer Training und Erholung nimmt. Hohe Professionalität lässt ihn bis zu zehn Prozent schneller reifen, niedrige entsprechend langsamer.',
  'Ehrgeiz': 'Wie sehr ein Fahrer Ergebnisse und eine eigene Rolle will. Ehrgeizige Fahrer reagieren stärker auf alles, was ihre Moral bewegt, und beschweren sich über zu wenige Renntage.',
  'Treue': 'Wie sehr ein Fahrer an seinem Team hängt. Treue Fahrer verlangen weniger, um zu verlängern.',
  'Konstanz': 'Wie wenig die Form eines Fahrers von Rennen zu Rennen schwankt.',
  'Form': 'Leistungsfaktor am Start eines Rennens. 0 % ist der Stand bei normalem Training ohne Rennen. Renntage in den Beinen und Erholung heben ihn bis etwa +4 %, Erschöpfung drückt ihn bis etwa −3 %.',
  'Fitness': 'Langfristige Trainings- und Rennbelastung der letzten rund sechs Wochen. Mehr Fitness bedeutet bessere Form, sobald die Ermüdung abgeklungen ist.',
  'Ermüdung': 'Belastung der letzten Woche. Sie steigt mit Rennen und hartem Training schnell und fällt in wenigen Ruhetagen wieder.',
  'Frische': 'Fitness minus Ermüdung. Unter −20 ist ein Fahrer müde, unter −40 würde ein Sportlicher Leiter ihn nicht aufstellen.',
  'Stärke': 'Gesamtwert aus den besten Fähigkeiten des Fahrers. Bestimmt Marktwert und Gehaltsforderung.',
  'Potenzial': 'Wie stark sich der Fahrer bis etwa 27 noch verbessern kann, von 1 bis 6. Ab 4,5 lohnt sich Geduld.',
  'Pot': 'Potenzial von 1 bis 6: wie stark sich der Fahrer noch verbessert.',
  'Eignung': 'Wie gut die Fähigkeiten des Fahrers zu den Strecken dieses Rennens passen, gemittelt über seine drei besten Etappen.',
  'Renntage': 'Renntage in dieser Saison. Ab 80 schont ein Sportlicher Leiter den Fahrer.',
  'Belastung': 'Trainingsumfang: schonend erholt, hart baut schneller Fitness auf und macht müde.',
  'Schwerpunkt': 'Im Training: Diese Fähigkeiten entwickeln sich schneller, die übrigen langsamer. Bei Sportlichen Leitern: die Rennart, die er am besten führt.',
  'Marktwert': 'Jahresgehalt, das der Fahrer auf dem Markt erzielen würde.',
  'Aussicht für zwölf Monate': 'Erwartete Veränderung je Fähigkeit in einem Jahr bei normalem Training und durchschnittlichem Trainer. Ab 32 geht es abwärts.',
  'Können': 'Hauptwert der Person von 1 bis 20. Beim Sportlichen Leiter die Taktik, beim Trainer die Entwicklung der Fahrer, beim Arzt die Dauer von Ausfällen, beim Scout die Genauigkeit der Berichte.',
  'Rennlesen': 'Wie gut der Sportliche Leiter auf Angriffe reagiert und Fahrer in die Gruppe des Tages bringt, von 1 bis 20.',
  'Motivation': 'Wie sehr der Sportliche Leiter die Form seiner Fahrer am Renntag hebt, von 1 bis 20.',
  'Flach': 'Tempo auf flachen Strecken und im Wind.',
  'Berg': 'Lange Anstiege über mehrere Kilometer.',
  'Mittelgebirge': 'Mittlere Anstiege und welliges Gelände.',
  'Hügel': 'Kurze, steile Anstiege.',
  'Zeitfahren': 'Einzelzeitfahren über längere Distanzen.',
  'Prolog': 'Kurze Zeitfahren unter acht Kilometern.',
  'Kopfsteinpflaster': 'Pflastersektoren und schlechte Straßen.',
  'Sprint': 'Endgeschwindigkeit im Sprint.',
  'Antritt': 'Beschleunigung: Angriffe und der Beginn des Sprints.',
  'Abfahrt': 'Tempo und Sicherheit bergab.',
  'Ausreißer': 'Chance, in die Gruppe des Tages zu kommen, und Arbeit darin.',
  'Ausdauer': 'Wie langsam die Kraft über einen langen Renntag nachlässt.',
  'Widerstand': 'Wie lange der Fahrer über seiner Schwelle fahren kann.',
  'Regeneration': 'Erholung von Etappe zu Etappe in Rundfahrten.',
  'FL': 'Flach: Tempo auf flachen Strecken und im Wind.',
  'BG': 'Berg: lange Anstiege.',
  'MB': 'Mittelgebirge: mittlere Anstiege und welliges Gelände.',
  'HÜ': 'Hügel: kurze, steile Anstiege.',
  'ZF': 'Zeitfahren.',
  'PR': 'Prolog: kurze Zeitfahren.',
  'KO': 'Kopfsteinpflaster.',
  'SP': 'Sprint.',
  'ANT': 'Antritt: Beschleunigung.',
  'ABF': 'Abfahrt.',
  'AUS': 'Ausreißer: Chance auf die Gruppe des Tages.',
  'AD': 'Ausdauer über einen langen Renntag.',
  'WID': 'Widerstand: Zeit über der Schwelle.',
  'REG': 'Regeneration zwischen Etappen.',
};

/// Wraps a widget in a tooltip with the explanation of a figure, shown
/// after hovering for a moment. Labels without an explanation stay as
/// they are.
///
/// @param label Label or column heading of the figure.
/// @param child The widget to explain.
/// @returns The widget, with a tooltip if the label is known.
Widget withHelp(String label, Widget child) {
  // The label arrives translated; the table is keyed by the German one.
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
