import 'package:flutter/material.dart';
import 'package:game/game.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';
import 'rider_dialog.dart';

/// The views of the squad table.
enum _View { attributes, shape, contracts, season }

/// Squad with four views: rider attributes, form and training, contracts,
/// and the season so far. A click on a rider opens his profile.
class SquadScreen extends StatefulWidget {
  const SquadScreen({super.key, required this.state, this.view});
  final AppState state;

  /// Name of the view to open: `attributes`, `shape`, `contracts` or
  /// `season`; the attributes without it.
  final String? view;

  @override
  State<SquadScreen> createState() => _SquadScreenState();
}

/// State of the screen: the selected view and the rider type filter.
class _SquadScreenState extends State<SquadScreen> {
  late var _view = _View.values
      .where((v) => v.name == widget.view)
      .firstWhere((_) => true, orElse: () => _View.attributes);
  String? _type;
  var _search = '';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final c = state.colors;
    final career = state.career;
    final eco = career.economy;
    final year = career.year;
    final squad = state.squad;
    final types = {for (final r in squad) riderType(r)}.toList()..sort();
    final rows = [
      for (final r in squad)
        if ((_type == null || riderType(r) == _type) &&
            (_search.isEmpty ||
                r.name.toLowerCase().contains(_search.toLowerCase()) ||
                r.country.toLowerCase() == _search.toLowerCase()))
          r,
    ];

    Col<SimRider> attribute(String title, double Function(Attributes) pick) =>
        Col(
          title,
          44,
          (r, _) {
            final v = pick(r.attributes);
            return cellText(
              v.round().toString(),
              color: attributeColor(v),
              bold: v >= 72,
            );
          },
          numeric: true,
          sortKey: (r) => pick(r.attributes),
        );

    // Name with a marker for riders who cannot race and for champions.
    final name = Col<SimRider>(tr('Fahrer'), 220, (r, _) {
      final injured = career.isInjured(r.id, career.today);
      final champion = career.titlesHeld(r.id).isNotEmpty;
      return Row(
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: injured
                  ? TeamColors.red
                  : career.camps.campOf(r.id, career.today) != null
                  ? TeamColors.gold
                  : career.isBusy(r.id, career.today)
                  ? TeamColors.green
                  : Colors.transparent,
            ),
          ),
          Flexible(child: cellText(career.fullName(r.id))),
          if (champion)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(
                Icons.military_tech_outlined,
                size: 15,
                color: TeamColors.gold,
              ),
            ),
        ],
      );
    }, sortKey: (r) => career.fullName(r.id));
    final age = Col<SimRider>(
      tr('Alter'),
      52,
      (r, _) => cellText('${year - r.born ~/ 10000}'),
      numeric: true,
      sortKey: (r) => -r.born,
    );
    final type = Col<SimRider>(
      tr('Typ'),
      104,
      (r, _) => cellText(tr(riderType(r)), color: TeamColors.muted),
      sortKey: riderType,
    );

    Col<SimRider> number(
      String title,
      double width,
      double Function(SimRider) of, {
      Color Function(double)? color,
      String Function(double)? text,
      String Function(SimRider)? suffix,
    }) => Col(
      title,
      width,
      (r, _) {
        final v = of(r);
        return cellText(
          (text?.call(v) ?? v.round().toString()) + (suffix?.call(r) ?? ''),
          color: color?.call(v),
        );
      },
      numeric: true,
      sortKey: of,
    );
    RiderShape shape(SimRider r) => career.shapeOf(r.id);

    /// Race days the rider is still pencilled in for.
    double plannedDays(SimRider r) {
      var days = 0;
      for (final race in career.ownRaces) {
        if (career.progress.containsKey(race.info.id)) continue;
        if (career.program[race.info.id]?.contains(r.id) ?? false) {
          days += race.stages.length;
        }
      }
      return days.toDouble();
    }

    final columns = switch (_view) {
      _View.attributes => [
        name,
        Col<SimRider>(
          'Nat',
          70,
          (r, _) => flagCell(r.country),
          sortKey: (r) => r.country,
        ),
        age,
        type,
        number(tr('Stärke'), 64, Economy.rating, color: attributeColor),
        Col<SimRider>(
          'Pot',
          44,
          (r, _) => cellText(
            r.potential.toStringAsFixed(1),
            color: r.potential >= 5.5 ? TeamColors.gold : TeamColors.text,
          ),
          numeric: true,
          sortKey: (r) => r.potential,
        ),
        attribute('FL', (a) => a.flat),
        attribute(tr('BG'), (a) => a.mountain),
        attribute(tr('MB'), (a) => a.mediumMountain),
        attribute(tr('HÜ'), (a) => a.hill),
        attribute(tr('ZF'), (a) => a.timeTrial),
        attribute(tr('PR'), (a) => a.prologue),
        attribute(tr('KO'), (a) => a.cobble),
        attribute(tr('SP'), (a) => a.sprint),
        attribute(tr('ANT'), (a) => a.acceleration),
        attribute(tr('ABF'), (a) => a.downhill),
        attribute(tr('AUS'), (a) => a.breakaway),
        attribute(tr('AD'), (a) => a.endurance),
        attribute(tr('WID'), (a) => a.resistance),
        attribute(tr('REG'), (a) => a.recovery),
      ],
      _View.shape => [
        name,
        age,
        number(
          'Form',
          86,
          (r) => shape(r).form,
          text: (v) => '${((v - 1) * 100).toStringAsFixed(1)} %',
          // Where the form is heading since the last weekly record.
          suffix: (r) => widget.state.formTrend(r.id),
          color: (v) => v >= 1.005
              ? TeamColors.gold
              : v >= 0.99
              ? TeamColors.green
              : v < 0.97
              ? TeamColors.red
              : TeamColors.text,
        ),
        number('Fitness', 70, (r) => shape(r).fitness),
        number(tr('Ermüdung'), 96, (r) => shape(r).fatigue),
        number(
          tr('Frische'),
          70,
          (r) => shape(r).freshness,
          text: (v) => '${v >= 0 ? '+' : ''}${v.round()}',
          color: (v) => v < -30
              ? TeamColors.red
              : v > 5
              ? TeamColors.green
              : TeamColors.text,
        ),
        number(tr('Renntage'), 84, (r) => shape(r).raceDays.toDouble()),
        Col<SimRider>('Status', 150, (r, _) {
          final until = shape(r).injuredUntil;
          if (until != null && until.isAfter(career.today)) {
            return cellText(
              tr('fällt aus bis {0}.{1}.', [
                until.day.toString().padLeft(2, '0'),
                until.month.toString().padLeft(2, '0'),
              ]),
              color: TeamColors.red,
            );
          }
          if (career.camps.campOf(r.id, career.today) != null) {
            return cellText(tr('Trainingslager'), color: TeamColors.gold);
          }
          return career.isBusy(r.id, career.today)
              ? cellText(tr('im Rennen'), color: TeamColors.green)
              : cellText('Training', color: TeamColors.muted);
        }),
        Col<SimRider>(tr('Schwerpunkt'), 130, (r, _) {
          return DropdownButton<TrainingFocus>(
            value: shape(r).focus,
            isDense: true,
            underline: const SizedBox(),
            dropdownColor: c.panel2,
            style: const TextStyle(
              fontFamily: 'Barlow',
              fontSize: 13,
              color: TeamColors.text,
            ),
            onChanged: (v) => state.setFocus(r.id, v!),
            items: [
              for (final f in TrainingFocus.values)
                DropdownMenuItem(value: f, child: Text(f.label)),
            ],
          );
        }),
        Col<SimRider>(tr('Belastung'), 250, (r, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final load in TrainingLoad.values)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => state.setLoad(r.id, load),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: shape(r).load == load ? TeamColors.text : null,
                        border: Border.all(color: c.line),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        load.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: shape(r).load == load
                              ? TeamColors.ground
                              : TeamColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
      _View.contracts => [
        name,
        age,
        type,
        number(tr('Stärke'), 64, Economy.rating, color: attributeColor),
        number(
          tr('Gehalt'),
          90,
          (r) => (eco.contracts[r.id]?.wage ?? 0).toDouble(),
          text: (v) => euro(v),
        ),
        number(
          tr('Marktwert'),
          96,
          (r) => eco.marketWage(r).toDouble(),
          text: (v) => euro(v),
        ),
        number(
          tr('Vertrag bis'),
          100,
          (r) => (eco.contracts[r.id]?.endYear ?? 0).toDouble(),
          color: (v) => v <= year ? TeamColors.gold : TeamColors.text,
        ),
        Col<SimRider>(tr('Nächste Saison'), 240, (r, _) {
          final k = eco.contracts[r.id];
          if (k == null) return const SizedBox();
          if (k.nextTeam == r.teamId) {
            return cellText(
              tr('verlängert bis {0} · {1}', [k.nextEnd, euro(k.nextWage)]),
              color: TeamColors.green,
            );
          }
          if (k.nextTeam != null) {
            return cellText(
              tr('wechselt zu {0}', [career.teams[k.nextTeam]?.name ?? '?']),
              color: TeamColors.red,
            );
          }
          return k.endYear <= year
              ? cellText(tr('Vertrag läuft aus'), color: TeamColors.gold)
              : cellText(tr('unter Vertrag'), color: TeamColors.muted);
        }),
      ],
      _View.season => [
        name,
        age,
        type,
        number(
          tr('Punkte'),
          76,
          (r) => career.riderPoints[r.id] ?? 0,
          color: (v) => v > 0 ? TeamColors.text : TeamColors.muted,
        ),
        number(
          tr('Siege'),
          64,
          (r) => career.winsOf(r.id, year).toDouble(),
          color: (v) => v > 0 ? TeamColors.gold : TeamColors.muted,
        ),
        number(tr('Renntage'), 84, (r) => shape(r).raceDays.toDouble()),
        number(
          tr('Geplant'),
          80,
          plannedDays,
          color: (v) => v > 0 ? TeamColors.text : TeamColors.muted,
        ),
        number(
          'Form',
          86,
          (r) => shape(r).form,
          text: (v) => '${((v - 1) * 100).toStringAsFixed(1)} %',
          // Where the form is heading since the last weekly record.
          suffix: (r) => widget.state.formTrend(r.id),
        ),
        Col<SimRider>(tr('Letzter Erfolg'), 330, (r, _) {
          final last = career.palmares[r.id]?.lastOrNull;
          return cellText(
            last == null ? '–' : '${last[0]} · ${last[1]} · ${last[2]}',
            color: last == null ? TeamColors.muted : TeamColors.text,
          );
        }),
      ],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TabStrip<_View>(
          colors: c,
          tabs: {
            _View.attributes: tr('Werte'),
            _View.shape: tr('Form und Training'),
            _View.contracts: tr('Verträge'),
            _View.season: tr('Saison'),
          },
          value: _view,
          onChanged: (v) => setState(() => _view = v),
          trailing: Text(
            tr('{0} Fahrer · Gehälter {1} € · Ø {2} Jahre', [
              squad.length,
              euro(eco.wageBill(state.team.id)),
              (squad.fold(0, (sum, r) => sum + year - r.born ~/ 10000) /
                      (squad.isEmpty ? 1 : squad.length))
                  .toStringAsFixed(1),
            ]),
            style: const TextStyle(color: TeamColors.muted),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in [null, ...types])
                            Pill(
                              label: t == null ? tr('Alle') : tr(t),
                              selected: _type == t,
                              colors: c,
                              onTap: () => setState(() => _type = t),
                            ),
                        ],
                      ),
                    ),
                    SearchBox(
                      hint: tr('Fahrer oder Land'),
                      colors: c,
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: DenseTable<SimRider>(
                    // A new key per team and view so that the sort order does not carry over.
                    key: ValueKey('${state.team.id}-$_view'),
                    colors: c,
                    rows: rows,
                    columns: columns,
                    onTap: (r) => showRiderDialog(context, state, r.id),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (_view) {
                    _View.attributes => tr(
                      'FL Flach · BG Berg · MB Mittelgebirge · HÜ Hügel · ZF Zeitfahren · PR Prolog · KO Kopfsteinpflaster · SP Sprint · ANT Antritt · ABF Abfahrt · AUS Ausreißer · AD Ausdauer · WID Widerstand · REG Regeneration · Klick auf einen Fahrer öffnet sein Profil',
                    ),
                    _View.shape => tr(
                      'Fitness folgt der Belastung der letzten sechs Wochen, Ermüdung der letzten Woche. Frische ist die Differenz. Form ist der Aufschlag auf die Leistung am Start eines Rennens.',
                    ),
                    _View.contracts => tr(
                      'Gespräche über neue Verträge sind ab dem 1. August unter Transfers möglich. Der Marktwert ist das Gehalt, das ein Fahrer dieser Stärke üblicherweise bekommt.',
                    ),
                    _View.season => tr(
                      'Punkte zählen für die Rangliste, Siege sind Rennen, Etappen und Gesamtwertungen. Geplant sind die Renntage aus dem Rennplaner.',
                    ),
                  },
                  style: const TextStyle(fontSize: 12, color: TeamColors.muted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
