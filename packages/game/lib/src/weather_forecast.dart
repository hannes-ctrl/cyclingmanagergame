import 'dart:math';

import 'package:sim/sim.dart';

/// What the team's weather service expects for a stage. The weather of a
/// stage is fixed by its seed long before the start; the forecast blurs it,
/// the more the further ahead the day is, and can be wrong about rain.
class WeatherForecast {
  WeatherForecast(this.temperatureC, this.temperatureSpread, this.rainChance,
      this.windKmh, this.windSpread, this.crosswindDistance, this.daysAhead);

  /// Expected temperature.
  final double temperatureC;

  /// Half the width of the expected range in °C.
  final double temperatureSpread;

  /// Chance of rain in per cent.
  final int rainChance;

  /// Expected wind speed.
  final double windKmh;

  /// Half the width of the expected range in km/h.
  final double windSpread;

  /// Kilometres of open road where the crosswind may split the field.
  final double crosswindDistance;

  /// Days until the stage; 0 on the day.
  final int daysAhead;

  /// Whether the service warns of echelons.
  bool get echelonRisk => crosswindDistance >= 8;

  /// The forecast as a line of text.
  String describe() {
    final low = (temperatureC - temperatureSpread).round();
    final high = (temperatureC + temperatureSpread).round();
    final windLow = max(0, (windKmh - windSpread).round());
    final windHigh = (windKmh + windSpread).round();
    return [
      low == high ? tr('{0} °C', [low]) : tr('{0} to {1} °C', [low, high]),
      tr('chance of rain {0} %', [rainChance]),
      windHigh < 8
          ? tr('hardly any wind')
          : tr('wind {0} to {1} km/h', [windLow, windHigh]),
      if (crosswindDistance >= 3)
        tr('crosswind on about {0} km', [(crosswindDistance / 5).round() * 5]),
    ].join(', ');
  }

  /// Forecasts a stage.
  ///
  /// @param truth The weather the stage will have.
  /// @param route The stage.
  /// @param stageSeed Seed of the stage, which also fixes the wind along
  ///   the route.
  /// @param daysAhead Days until the stage.
  /// @returns The forecast; the same for the same day.
  static WeatherForecast of(
      Weather truth, SimRoute route, int stageSeed, int daysAhead) {
    final d = max(0, daysAhead);
    final r = Random(stageSeed * 13 + d * 7919 + 1);
    double gauss() {
      final u = max(r.nextDouble(), 1e-12);
      return sqrt(-2 * log(u)) * cos(2 * pi * r.nextDouble());
    }

    final spreadC = 1 + 0.4 * min(d, 10);
    final temperature = truth.temperatureC + (0.6 + 0.4 * min(d, 10)) * gauss();
    final noise = 10 * gauss();
    final rain = truth.rain
        ? (88 - 5 * min(d, 8) + noise).clamp(35, 97)
        : (6 + 4 * min(d, 8) + noise).clamp(2, 50);
    final windSpread = 4 + 1.2 * min(d, 10);
    final wind =
        max(0.0, truth.windMs * 3.6 + (2 + 1.0 * min(d, 10)) * gauss());
    final cross = route.kind == StageKind.road
        ? crosswindKm(
            route, windAlong(route, truth, Random(stageSeed * 17 + 3)))
        : 0.0;
    final crossGuess = max(0.0, cross * (1 + 0.12 * min(d, 8) * gauss()));
    return WeatherForecast(temperature, spreadC, (rain / 5).round() * 5, wind,
        windSpread, crossGuess, d);
  }

  /// The weather the forecast stands for, for the sports director's choice
  /// of tyres: rain if it is more likely than not.
  Weather get expected => Weather(
        temperatureC: temperatureC,
        rain: rainChance >= 50,
        windMs: windKmh / 3.6,
      );
}
