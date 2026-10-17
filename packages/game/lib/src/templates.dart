import 'package:sim/sim.dart';

import 'career.dart';
import 'points.dart';

/// A programme template: a set of races assigned to a rider with one
/// click. The built-in ones follow rules over the calendar of the season,
/// so that they hold in every year; the player's own ones name the races.
class ProgramTemplate {
  ProgramTemplate._(this._name, this._rule, this.races);

  /// A template of the player's: the races he chose for one rider.
  ///
  /// @param name The name he gave it.
  /// @param races Ids of the races.
  ProgramTemplate.own(String name, List<int> races) : this._(name, null, races);

  final String _name;
  final bool Function(Career c, RaceEntry race)? _rule;

  /// Race ids of an own template; empty for a built-in one.
  final List<int> races;

  /// Whether the template comes with the game.
  bool get builtIn => _rule != null;

  /// The name, translated for the built-in templates.
  String get name => builtIn ? tr(_name) : _name;

  /// The name as stored: the English key of a built-in template.
  String get key => _name;

  /// @param c The career.
  /// @param race A race of the calendar.
  /// @returns Whether the template includes it.
  bool includes(Career c, RaceEntry race) =>
      _rule?.call(c, race) ?? races.contains(race.info.id);

  static List<SimRoute> _routes(Career c, RaceEntry race) =>
      [for (final s in race.stages) c.world.route(s.id)];

  static bool _oneDay(RaceEntry r) => !r.isStageRace;
  static bool _big(RaceEntry r) => r.tier.factor >= 2;
  static bool _wt(RaceEntry r) => r.tier.factor >= 5;
  static bool _months(RaceEntry r, int from, int to) =>
      r.start.month >= from && r.start.month <= to;

  /// The templates that come with the game.
  static final builtIns = [
    ProgramTemplate._(
        'Cobbled classics',
        (c, r) =>
            _oneDay(r) &&
            _months(r, 2, 4) &&
            _routes(c, r).any((s) => s.sectorRace || s.sectorLoad >= 8),
        const []),
    ProgramTemplate._(
        'Ardennes classics',
        (c, r) =>
            _oneDay(r) &&
            _big(r) &&
            _months(r, 4, 4) &&
            _routes(c, r).every((s) => !s.sectorRace && !s.sprintStage),
        const []),
    ProgramTemplate._(
        'Giro programme',
        (c, r) =>
            grandTourOf(r.info) == GrandTour.giro ||
            (r.isStageRace && _big(r) && _months(r, 4, 4)),
        const []),
    ProgramTemplate._(
        'Tour helper',
        (c, r) =>
            grandTourOf(r.info) == GrandTour.tour ||
            (r.isStageRace && _wt(r) && _months(r, 6, 6)),
        const []),
    ProgramTemplate._(
        'Vuelta programme',
        (c, r) =>
            grandTourOf(r.info) == GrandTour.vuelta ||
            (r.isStageRace &&
                _big(r) &&
                (r.start.month == 7 && r.start.day >= 20 ||
                    r.start.month == 8 && r.start.day <= 12)),
        const []),
    ProgramTemplate._('Sprinter\'s spring', (c, r) {
      if (!_months(r, 1, 4) || r.tier == RaceTier.grandTour) return false;
      final routes = _routes(c, r);
      final sprints = routes.where((s) => s.sprintStage).length;
      return _big(r) && sprints * 2 >= routes.length;
    }, const []),
    ProgramTemplate._(
        'Autumn classics',
        (c, r) =>
            _oneDay(r) &&
            _big(r) &&
            _months(r, 9, 10) &&
            _routes(c, r).every((s) => !s.sprintStage),
        const []),
  ];
}
