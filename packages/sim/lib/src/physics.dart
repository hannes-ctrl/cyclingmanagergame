import 'dart:math';

import 'model.dart';
import 'tuning.dart';

// The attributes describe a rider of reference build. A rider's own weight
// and height turn that into watts (see [bodyScale]), so a light climber and
// a heavy rouleur with the same attribute climb, or ride on the flat, at the
// same speed, while descents and rolling terrain feel their real build.
const riderMassKg = 70.0;
const bikeMassKg = 8.0;
const systemMassKg = riderMassKg + bikeMassKg;
const _gravity = 9.81;

/// Air density at sea level and 15 to 20 °C (kg/m³).
const seaLevelAirDensity = 1.2;

/// Drag area of a rider of reference build alone in the wind (m²).
const soloCda = 0.28;
const timeTrialCda = 0.21;
const _asphaltCrr = 0.004;

/// Rolling resistance coefficient of a segment.
///
/// @param s The segment; cobbles and unpaved surface add resistance.
/// @param wet Whether the road is wet, which makes cobbles worse.
/// @returns The coefficient (dimensionless).
double rollingResistance(Segment s, {bool wet = false}) =>
    _asphaltCrr +
    0.002 * (s.cobble + (wet && s.cobble > 0 ? 1 : 0)) +
    0.0012 * s.unpaved;

/// Air density at an altitude.
///
/// @param altitudeM Altitude in metres.
/// @returns Density in kg/m³.
double airDensity(double altitudeM) =>
    seaLevelAirDensity * exp(-max(0.0, altitudeM) / 8400);

/// Share of his sea-level power an acclimatised rider keeps at altitude
/// (after Bassett et al. 1999, counted from 500 m).
///
/// @param altitudeM Altitude in metres.
/// @returns A factor between 0.7 and 1.
double altitudePower(double altitudeM) {
  final x = max(0.0, altitudeM - 500) / 1000;
  return ((99.921 - 1.8991 * x - 1.122 * x * x) / 99.921).clamp(0.7, 1.0);
}

/// Frontal size of a rider relative to the reference build, from his body
/// surface (Du Bois).
///
/// @param r The rider.
/// @returns Factor on the drag area.
double cdaScale(SimRider r) =>
    pow(r.massKg / riderMassKg, 0.425).toDouble() *
    pow(r.heightM / 1.8, 0.725).toDouble();

/// Factor that turns the power of a reference rider into this rider's watts
/// on a given gradient: uphill it keeps his watts per kilogram (of rider and
/// bike), on the flat his watts per drag area.
///
/// @param r The rider.
/// @param grade Gradient as a fraction.
/// @returns Factor on [thresholdPower].
double bodyScale(SimRider r, double grade) {
  final w = (grade / 0.05).clamp(0.0, 1.0);
  return w * (r.massKg + bikeMassKg) / systemMassKg + (1 - w) * cdaScale(r);
}

/// Power needed to ride at a given speed.
///
/// @param v Speed in m/s.
/// @param grade Gradient as a fraction.
/// @param cda Drag area in m².
/// @param crr Rolling resistance coefficient.
/// @param mass Mass of rider and bike in kg.
/// @param rho Air density in kg/m³.
/// @param headwind Wind against the direction of travel in m/s.
/// @returns Power in watts.
double powerFor(double v, double grade, double cda, double crr,
    {double mass = systemMassKg,
    double rho = seaLevelAirDensity,
    double headwind = 0}) {
  final slope = grade / sqrt(1 + grade * grade);
  final air = v + headwind;
  return mass * _gravity * (slope + crr) * v +
      0.5 * rho * cda * air * air.abs() * v;
}

/// Speed reached with a given power; the inverse of [powerFor].
///
/// @param power Power in watts.
/// @param grade Gradient as a fraction.
/// @param cda Drag area in m².
/// @param crr Rolling resistance coefficient.
/// @param mass Mass of rider and bike in kg.
/// @param rho Air density in kg/m³.
/// @param headwind Wind against the direction of travel in m/s.
/// @returns Speed in m/s.
double speedFor(double power, double grade, double cda, double crr,
    {double mass = systemMassKg,
    double rho = seaLevelAirDensity,
    double headwind = 0}) {
  double p(double v) =>
      powerFor(v, grade, cda, crr, mass: mass, rho: rho, headwind: headwind);
  // Downhill or with a tailwind the power curve can have a minimum; we want
  // the solution to its right.
  var lo = 0.0, hi = 40.0;
  final slope = grade / sqrt(1 + grade * grade);
  if (headwind == 0 && slope + crr < 0) {
    lo = sqrt(-mass * _gravity * (slope + crr) / (1.5 * rho * cda));
  } else if (headwind < 0 || slope + crr < 0) {
    // Find where the curve starts to rise.
    var a = 0.0, b = 40.0;
    for (var i = 0; i < 40; i++) {
      final m = (a + b) / 2;
      if (p(m + 0.01) < p(m)) {
        a = m;
      } else {
        b = m;
      }
    }
    lo = a;
  }
  for (var i = 0; i < 40; i++) {
    final mid = (lo + hi) / 2;
    if (p(mid) < power) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return max(lo, 1.5);
}

/// Which rider attribute counts on a segment.
///
/// @param s The segment.
/// @param a The rider's attributes.
/// @param timeTrial Whether the stage is a time trial.
/// @returns The attribute value blended for gradient and surface.
double effectiveAttribute(Segment s, Attributes a, {bool timeTrial = false}) {
  final level = timeTrial ? a.timeTrial : a.flat;
  final climb = s.climbKm >= 8
      ? a.mountain
      : s.climbKm >= 3
          ? a.mediumMountain
          : a.hill;
  double base;
  if (s.grade < -0.03) {
    base = 0.5 * level + 0.5 * a.downhill;
  } else {
    // The steeper, the less drag matters and the more the mountain attribute.
    final w = (s.grade / 0.05).clamp(0.0, 1.0);
    base = w * climb + (1 - w) * level;
  }
  if (s.cobble > 0) {
    final c = 0.35 + 0.1 * s.cobble;
    base = (1 - c) * base + c * a.cobble;
  } else if (s.unpaved > 0) {
    final c = 0.2 + 0.05 * s.unpaved;
    base = (1 - c) * base + c * a.cobble;
  }
  return base;
}

/// Threshold power of a rider of reference build for an attribute value.
///
/// @param attribute Attribute on the PCM scale.
/// @param t Tuning values.
/// @returns Power in watts.
double thresholdPower(double attribute, SimTuning t) =>
    riderMassKg * t.thresholdWkg * (1 + t.gainPerPoint * (attribute - 70));

/// Share of the drag a rider still feels in the slipstream.
///
/// @param groupSize Number of riders in the group.
/// @param t Tuning values.
/// @returns A factor between 0 and 1; 1 means no shelter.
double draftFactor(int groupSize, SimTuning t) {
  if (groupSize <= 1) return 1;
  if (groupSize <= 4) return t.draftSmall;
  if (groupSize <= 15) return t.draftMedium;
  if (groupSize <= 60) return t.draftLarge;
  return t.draftPeloton;
}

/// Top speed on a descent; steeper descents are more technical. Heavier
/// riders roll faster, wet roads cost a lot.
///
/// @param grade Gradient as a fraction (negative downhill).
/// @param downhill The rider's downhill attribute.
/// @param massKg The rider's weight.
/// @param wet Whether the road is wet.
/// @returns Speed limit in m/s.
double descentCap(double grade, double downhill,
    {double massKg = riderMassKg, bool wet = false}) {
  if (grade > -0.03) return 40;
  final kmh = 62 +
      (downhill - 70) * (wet ? 0.8 : 0.6) +
      (grade < -0.07 ? -6 : 0) +
      (massKg - riderMassKg) * 0.15 -
      (wet ? 9 : 0);
  return kmh / 3.6;
}
