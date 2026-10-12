import 'dart:math';

import 'model.dart';
import 'tuning.dart';

// All riders are computed with the same mass; differences between light and
// heavy riders are already contained in the mountain and flat attributes.
const riderMassKg = 70.0;
const systemMassKg = 78.0;
const _gravity = 9.81;
const _airDensity = 1.2;

/// Drag area of a rider alone in the wind (m²).
const soloCda = 0.32;
const timeTrialCda = 0.24;
const _asphaltCrr = 0.004;

/// Rolling resistance coefficient of a segment.
///
/// @param s The segment; cobbles and unpaved surface add resistance.
/// @returns The coefficient (dimensionless).
double rollingResistance(Segment s) =>
    _asphaltCrr + 0.002 * s.cobble + 0.0012 * s.unpaved;

/// Power needed to ride at a given speed.
///
/// @param v Speed in m/s.
/// @param grade Gradient as a fraction.
/// @param cda Drag area in m².
/// @param crr Rolling resistance coefficient.
/// @returns Power in watts.
double powerFor(double v, double grade, double cda, double crr) {
  final slope = grade / sqrt(1 + grade * grade);
  return systemMassKg * _gravity * (slope + crr) * v +
      0.5 * _airDensity * cda * v * v * v;
}

/// Speed reached with a given power; the inverse of [powerFor].
///
/// @param power Power in watts.
/// @param grade Gradient as a fraction.
/// @param cda Drag area in m².
/// @param crr Rolling resistance coefficient.
/// @returns Speed in m/s.
double speedFor(double power, double grade, double cda, double crr) {
  final slope = grade / sqrt(1 + grade * grade);
  final a = systemMassKg * _gravity * (slope + crr);
  // Downhill the power curve has a minimum; we want the solution to its right.
  var lo = a < 0 ? sqrt(-a / (1.5 * _airDensity * cda)) : 0.0;
  var hi = 40.0;
  for (var i = 0; i < 40; i++) {
    final mid = (lo + hi) / 2;
    if (powerFor(mid, grade, cda, crr) < power) {
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

/// Threshold power for an attribute value.
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

/// Top speed on a descent; steeper descents are more technical.
///
/// @param grade Gradient as a fraction (negative downhill).
/// @param downhill The rider's downhill attribute.
/// @returns Speed limit in m/s.
double descentCap(double grade, double downhill) {
  if (grade > -0.03) return 40;
  final kmh = 62 + (downhill - 70) * 0.6 + (grade < -0.07 ? -6 : 0);
  return kmh / 3.6;
}
