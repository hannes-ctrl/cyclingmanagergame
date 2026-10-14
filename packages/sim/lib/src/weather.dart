import 'dart:math';

import 'i18n.dart';
import 'model.dart';

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
WindField windAlong(SimRoute route, Weather w, Random r) {
  final n = route.segments.length;
  if (w.windMs < 0.5) return WindField.still(n);
  final head = List<double>.filled(n, 0), cross = List<double>.filled(n, 0);
  var heading = 0.0;
  var exposure = 1.0;
  var blockEnd = -1.0;
  for (var i = 0; i < n; i++) {
    final s = route.segments[i];
    if (s.km >= blockEnd) {
      blockEnd = s.km + 5;
      final u = max(r.nextDouble(), 1e-12);
      heading += 0.7 * sqrt(-2 * log(u)) * cos(2 * pi * r.nextDouble());
      exposure = r.nextDouble() < 0.45 ? 1.0 : 0.35;
    }
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
