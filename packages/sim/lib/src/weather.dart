import 'dart:math';

import 'i18n.dart';
import 'model.dart';

/// Countries with hot summers: their riders cope better with heat and
/// worse with cold.
const _hot = {
  'ESP',
  'ITA',
  'POR',
  'FRA',
  'COL',
  'ECU',
  'VEN',
  'MEX',
  'ARG',
  'CHI',
  'AUS',
  'RSA',
  'ERI',
  'ETH',
  'RWA',
  'UAE',
  'ISR',
  'KAZ',
  'GRE',
  'CRO',
  'SLO',
  'BRA',
  'CRC',
  'ALG',
  'MAR',
  'TUR',
  'UZB',
};

/// Countries with cool summers: their riders cope better with cold and
/// worse with heat.
const _cool = {
  'NOR',
  'DEN',
  'SWE',
  'FIN',
  'NED',
  'BEL',
  'GBR',
  'IRL',
  'EST',
  'LAT',
  'LTU',
  'CAN',
  'POL',
  'GER',
  'LUX',
  'CZE',
  'AUT',
  'SUI',
  'NZL',
  'ISL',
};

/// The extra energy a rider spends in heat or cold. From 27 °C every degree
/// costs two per cent, below 6 °C four per cent in all; how much of it a
/// rider pays depends on his build and where he comes from. A heavy rider
/// sheds heat badly and keeps warm well, a light one the other way round,
/// and riders of hot countries are used to the heat, those of the north to
/// the cold.
///
/// @param temperatureC Air temperature.
/// @param r The rider.
/// @returns A factor on his energy use, 1 in mild weather.
double climateCost(double temperatureC, SimRider r) {
  if (temperatureC > 27) return 1 + 0.02 * (temperatureC - 27) * heatFactor(r);
  if (temperatureC < 6) return 1 + 0.04 * coldFactor(r);
  return 1;
}

/// How much of the extra energy in the heat a rider pays: 1 for the
/// average, less for a light rider of a hot country.
///
/// @param r The rider.
/// @returns 0.45 to 1.9.
double heatFactor(SimRider r) {
  final build = (1 + 0.03 * (r.massKg - 68)).clamp(0.6, 1.6);
  final home = _hot.contains(r.country)
      ? 0.75
      : _cool.contains(r.country)
          ? 1.2
          : 1.0;
  return build * home;
}

/// How much of the extra energy in the cold a rider pays: 1 for the
/// average, less for a heavy rider of the north.
///
/// @param r The rider.
/// @returns 0.38 to 1.95.
double coldFactor(SimRider r) {
  final build = (1 - 0.02 * (r.massKg - 68)).clamp(0.5, 1.5);
  final home = _cool.contains(r.country)
      ? 0.75
      : _hot.contains(r.country)
          ? 1.3
          : 1.0;
  return build * home;
}

/// Weather of a race day.
///
/// The stage files carry no compass headings, so the wind is described
/// relative to the direction the route sets off in, and the sim lets the
/// road turn as it goes (see [windAlong]).
class Weather {
  const Weather({
    this.temperatureC = 18,
    this.rain = false,
    this.windMs = 0,
    this.windFrom = 0,
  });

  /// Air temperature in °C.
  final double temperatureC;

  /// Whether the roads are wet.
  final bool rain;

  /// Wind speed at a height of 10 m in m/s.
  final double windMs;

  /// Direction the wind blows from, in radians, relative to the direction
  /// of the first kilometres of the route (0 = straight into the riders' faces).
  final double windFrom;

  /// A dry, still day: what the simulation assumed before it knew weather.
  static const calm = Weather();

  // Mean temperature, chance of rain and mean wind per month for central
  // and western Europe, where most of the calendar takes place.
  static const _temperature = [5.0, 6, 10, 14, 18, 22, 25, 24, 20, 15, 9, 6];
  static const _rain = [.35, .35, .3, .3, .25, .2, .15, .15, .2, .3, .35, .35];
  static const _wind = [6.0, 6, 6, 5, 4.5, 4, 3.5, 3.5, 4, 5, 6, 6];

  static const _south = {'AUS', 'NZL', 'ARG', 'RSA', 'CHI', 'CHL', 'URU'};
  static const _desert = {'UAE', 'OMA', 'SAU', 'KSA', 'QAT', 'BRN'};
  static const _north = {'BEL', 'NED', 'DEN', 'NOR', 'GBR', 'IRL', 'SWE'};
  static const _med = {'ESP', 'POR', 'ITA', 'CRO', 'GRE', 'TUR', 'SLO'};

  /// Draws the weather of a day.
  ///
  /// @param r Random source.
  /// @param month Month of the race, 1 to 12.
  /// @param country Country code of the race, e.g. `BEL`; empty if unknown.
  /// @returns The weather.
  static Weather draw(Random r, int month, [String country = '']) {
    var m = (month - 1) % 12;
    if (_south.contains(country)) m = (m + 6) % 12;
    var temperature = _temperature[m];
    var rainChance = _rain[m];
    var wind = _wind[m];
    if (_desert.contains(country)) {
      temperature += 10;
      rainChance = 0.03;
      wind += 1;
    } else if (_north.contains(country)) {
      temperature -= 2;
      rainChance += 0.1;
      wind += 1.5;
    } else if (_med.contains(country)) {
      temperature += 3;
      rainChance -= 0.08;
    }
    final u = max(r.nextDouble(), 1e-12);
    final gauss = sqrt(-2 * log(u)) * cos(2 * pi * r.nextDouble());
    final rain = r.nextDouble() < rainChance;
    // Mostly moderate, now and then a stormy day.
    var speed = wind * (0.4 + 1.1 * r.nextDouble());
    if (r.nextDouble() < 0.12) speed += wind * 0.9;
    return Weather(
      temperatureC: temperature + 3.5 * gauss - (rain ? 3 : 0),
      rain: rain,
      windMs: speed,
      windFrom: 2 * pi * r.nextDouble(),
    );
  }

  /// @returns A short description for reports, e.g. "24 °C, Regen, Wind 30 km/h".
  String describe() {
    final parts = [
      tr('{0} °C', [temperatureC.round()]),
      if (rain) tr('rain'),
      windMs < 2
          ? tr('hardly any wind')
          : tr('wind {0} km/h', [(windMs * 3.6).round()]),
    ];
    return parts.join(', ');
  }

  /// @returns The weather as a compact list.
  List<num> toJson() => [temperatureC, rain ? 1 : 0, windMs, windFrom];

  /// @param j A list written by [toJson].
  /// @returns The weather.
  static Weather fromJson(List<dynamic> j) => Weather(
        temperatureC: (j[0] as num).toDouble(),
        rain: j[1] == 1,
        windMs: (j[2] as num).toDouble(),
        windFrom: (j[3] as num).toDouble(),
      );
}

/// Wind felt by the riders on each segment of a route.
class WindField {
  WindField(this.head, this.cross);

  /// Component against the direction of travel in m/s; negative is tailwind.
  final List<double> head;

  /// Component across the road in m/s, always positive.
  final List<double> cross;

  /// No wind anywhere.
  static WindField still(int segments) =>
      WindField(List.filled(segments, 0), List.filled(segments, 0));
}

/// Lays the wind of the day over a route. The road changes direction every
/// few kilometres, and towns, trees and valleys shelter it in places.
///
/// @param route The stage.
/// @param w Weather of the day.
/// @param r Random source.
/// @returns Head- and crosswind per segment.
/// Which segments of a route lie open to the wind: flat roads low in the
/// plain, without mountains close by, in blocks of five kilometres. Climbs,
/// descents, valleys and high mountains are sheltered. Of the open blocks
/// about half are exposed (fields, coast, dykes), the rest run between
/// houses, hedges and woods; which ones is fixed per route, so that the
/// same roads are open every year and the profile can show them.
///
/// @param route The stage.
/// @returns Per segment whether it is open.
List<bool> exposedSegments(SimRoute route) =>
    _exposed[route] ??= _exposedSegments(route);

final _exposed = Expando<List<bool>>();

List<bool> _exposedSegments(SimRoute route) {
  final segs = route.segments;
  final out = List.filled(segs.length, false);
  if (route.kind != StageKind.road || segs.isEmpty) return out;
  final hash =
      route.name.codeUnits.fold(17, (h, c) => (h * 31 + c) & 0x7fffffff);
  var i = 0;
  while (i < segs.length) {
    final block = (segs[i].km / 5).floor();
    var j = i;
    var alt = 0.0, steep = 0.0, n = 0;
    while (j < segs.length && (segs[j].km / 5).floor() == block) {
      alt += segs[j].altitudeM;
      steep += segs[j].grade.abs();
      n++;
      j++;
    }
    alt /= n;
    steep /= n;
    // The relief within ten kilometres: a valley floor has mountains
    // around it.
    var lo = double.infinity, hi = -double.infinity;
    for (final s in segs) {
      if ((s.km - segs[i].km).abs() > 10) continue;
      lo = min(lo, s.altitudeM);
      hi = max(hi, s.altitudeM);
    }
    final flatLand = alt < 800 && steep < 0.012 && hi - lo < 250;
    final luck = Random(hash + block * 7919).nextDouble();
    if (flatLand && luck < 0.5) {
      for (var k = i; k < j; k++) {
        out[k] = segs[k].climbKm == 0 && segs[k].grade.abs() < 0.02;
      }
    }
    i = j;
  }
  return out;
}

WindField windAlong(SimRoute route, Weather w, Random r) {
  final n = route.segments.length;
  if (w.windMs < 0.5) return WindField.still(n);
  final head = List<double>.filled(n, 0), cross = List<double>.filled(n, 0);
  final open = exposedSegments(route);
  var heading = 0.0;
  var blockEnd = -1.0;
  for (var i = 0; i < n; i++) {
    final s = route.segments[i];
    if (s.km >= blockEnd) {
      blockEnd = s.km + 5;
      final u = max(r.nextDouble(), 1e-12);
      heading += 0.7 * sqrt(-2 * log(u)) * cos(2 * pi * r.nextDouble());
      // Drawn as before, so that the random numbers stay in step.
      r.nextDouble();
    }
    final exposure = open[i] ? 1.0 : 0.35;
    // Climbs wind through valleys and woods; at rider height the wind is
    // weaker than at 10 m.
    final shelter = s.climbKm > 0 || s.grade < -0.03 ? 0.5 : 1.0;
    final speed = 0.6 * w.windMs * exposure * shelter;
    final relative = w.windFrom - heading;
    head[i] = speed * cos(relative);
    cross[i] = (speed * sin(relative)).abs();
  }
  return WindField(head, cross);
}
