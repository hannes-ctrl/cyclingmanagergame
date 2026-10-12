import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:sim/sim.dart';

import 'dataset.dart';
import 'finish.dart';

/// Key figures of a race, real or as the mean over simulation runs.
/// Quantities with a wide range are stored as logarithms so that a bunch
/// finish and a solo win are weighted comparably.
class RaceShape {
  RaceShape(this.logFirstGroup, this.logGap10, this.logGapMedian, this.logGap90,
      this.speedKmh, this.breakWin);

  final double logFirstGroup;
  final double logGap10;
  final double logGapMedian;
  final double logGap90;
  final double speedKmh;

  /// Share of runs in which an early breakaway rider wins (real: 0 or 1).
  final double breakWin;

  /// Computes the key figures of one race.
  ///
  /// @param times Riding times in seconds, sorted ascending.
  /// @param raceKm Race distance.
  /// @param breakWin Whether a breakaway rider won.
  /// @param fieldShare Share of the field the first group is scaled to.
  /// @returns The key figures.
  static RaceShape of(List<double> times, double raceKm, bool breakWin,
      {double fieldShare = 1}) {
    final t0 = times.first;
    double gapAt(double share) =>
        log(1 + times[((times.length - 1) * share).round()] - t0);
    // A real field is larger than the part of it found in the database; a
    // big first group is scaled down to the simulated field, a solo win or
    // a duo stays what it is.
    final first = times.where((t) => t - t0 <= 1).length;
    final scaled = first <= 2 ? first : max(3, (first * fieldShare).round());
    return RaceShape(
      log(scaled),
      log(1 + times[min(9, times.length - 1)] - t0),
      gapAt(0.5),
      gapAt(0.9),
      raceKm / (t0 / 3600),
      breakWin ? 1 : 0,
    );
  }

  /// @param all Key figures of several runs.
  /// @returns Their mean.
  static RaceShape mean(List<RaceShape> all) {
    double avg(double Function(RaceShape) f) =>
        all.map(f).reduce((a, b) => a + b) / all.length;
    return RaceShape(
      avg((s) => s.logFirstGroup),
      avg((s) => s.logGap10),
      avg((s) => s.logGapMedian),
      avg((s) => s.logGap90),
      avg((s) => s.speedKmh),
      avg((s) => s.breakWin),
    );
  }
}

/// How far the simulation of one race is from reality.
class CaseScore {
  CaseScore(this.label, this.type, this.real, this.sim, this.rankTerm,
      this.winnerTop3, this.winnerTop10, this.loss,
      {this.finishShares = const [],
      this.wonHow,
      this.shapeTerm = 0,
      this.speedTerm = 0,
      this.realKind});

  /// Parts of [loss], already weighted, for the report.
  final double shapeTerm;
  final double speedTerm;

  /// Size class of the real winner's group, counted over all finishers;
  /// null for time trials.
  final FinishKind? realKind;

  /// Share of the simulation runs that ended solo, as a duo, in a small
  /// group and in a bunch sprint (in the order of [FinishKind.road]).
  final List<double> finishShares;

  /// How the real race was decided according to ProCyclingStats, if known.
  final String? wonHow;

  final String label;
  final String type;
  final RaceShape real;
  final RaceShape sim;

  /// 0 = the real top five are also at the front of the simulation, 1 = at the very back.
  final double rankTerm;

  /// Share of runs in which the real winner finishes in the top 3 and top 10.
  final double winnerTop3;
  final double winnerTop10;
  final double loss;
}

/// Weights of the error terms.
///
/// Only the dynamics of a race count, measured by four figures: the size of
/// the winner's group, the gap of tenth place, the gap of the middle of the
/// field and the average speed. Who wins, and whether he comes from the
/// breakaway, does not enter the error at all: the best riders do not start
/// everywhere, and crashes, injuries and form of the day decide a single
/// real result. Those figures are still printed, for information.
///
/// Two kinds of terms exist. Per race: how far the simulated race is from
/// the real one in the four figures. Per race type: how far the simulated
/// *frequency* of each size class of the winner's group (solo, duo, small
/// group, bunch) is from the real one. The second kind keeps the search
/// from giving up on rare outcomes, which a per-race error alone tolerates.
const _wShape = 0.5;
const _wSpeed = 400.0;

/// Upper limit for shape plus speed error of one race. Stages that were
/// neutralised, shortened or ridden as a parade cannot be matched and must
/// not dominate the search.
const _caseCap = 8.0;

/// Weight of the per-type frequency terms.
const _wFrequency = 60.0;

/// Simulates one race several times and compares it with the real result.
///
/// @param c The real race.
/// @param tuning Tuning values to test.
/// @param runs Number of simulation runs.
/// @param seed Base seed.
/// @returns The score of this race.
CaseScore scoreCase(CalibrationCase c, SimTuning tuning, int runs, int seed) {
  // The real race is measured on all finishers; its first group is scaled
  // to the part of the field that the simulation has.
  final all = c.allTimes.isEmpty ? c.realTimes : c.allTimes;
  final real = RaceShape.of(all, c.route.raceKm, c.winnerFromBreak,
      fieldShare: c.riders.length / all.length);
  final realGroup = all.where((t) => t - all.first <= 1).length;
  final top5 = c.realOrder.take(5).toSet();
  final winner = c.realOrder.first;
  final shapes = <RaceShape>[];
  var rankSum = 0.0, top3 = 0, top10 = 0;
  final finishes = List.filled(FinishKind.road.length, 0);
  for (var r = 0; r < runs; r++) {
    // The seed depends on the race and the run, not on the tuning values, so
    // every setting sees the same random numbers.
    final result = simulateStage(c.route, c.riders,
        seed: seed + 7919 * r + c.label.hashCode % 100000,
        tuning: tuning,
        gcGaps: c.gcGaps);
    shapes.add(RaceShape.of([for (final p in result.placings) p.timeS],
        c.route.raceKm, result.breakSurvived));
    final firstGroup = result.placings
        .where((p) => p.group == result.placings.first.group)
        .length;
    finishes[FinishKind.road.indexOf(FinishKind.ofGroup(firstGroup))]++;
    for (var i = 0; i < result.placings.length; i++) {
      final id = result.placings[i].rider.id;
      if (top5.contains(id)) rankSum += log(i + 1);
      if (id == winner) {
        if (i < 3) top3++;
        if (i < 10) top10++;
      }
    }
  }
  final sim = RaceShape.mean(shapes);
  final rankTerm = rankSum / (runs * top5.length) / log(c.riders.length);

  /// @param x A number.
  /// @returns Its square.
  double sq(double x) => x * x;
  final road = c.route.kind == StageKind.road;
  final shapeTerm = _wShape *
      ((road ? sq(sim.logFirstGroup - real.logFirstGroup) : 0) +
          sq(sim.logGap10 - real.logGap10) +
          sq(sim.logGapMedian - real.logGapMedian));
  final speedTerm = _wSpeed * sq(sim.speedKmh / real.speedKmh - 1);
  final shares = [for (final n in finishes) n / runs];
  final capped = min(_caseCap, shapeTerm + speedTerm);
  final loss = capped;
  return CaseScore(
      c.label, c.type, real, sim, rankTerm, top3 / runs, top10 / runs, loss,
      finishShares: shares,
      wonHow: c.wonHow,
      realKind: road ? FinishKind.ofGroup(realGroup) : null,
      shapeTerm: shapeTerm,
      speedTerm: speedTerm);
}

/// Scores of all races for one tuning set.
class Evaluation {
  Evaluation(this.scores);
  final List<CaseScore> scores;

  /// Mean error of the single races.
  double get caseLoss =>
      scores.map((s) => s.loss).reduce((a, b) => a + b) / scores.length;

  /// Error of the frequencies per race type: how often the winner's group
  /// falls into each size class, simulation against reality.
  /// Types with fewer than four races are left out as too noisy.
  double get frequencyLoss {
    final byType = <String, List<CaseScore>>{};
    for (final s in scores) {
      if (s.type != 'Zeitfahren') byType.putIfAbsent(s.type, () => []).add(s);
    }
    double sq(double x) => x * x;
    double mean(Iterable<double> x) => x.reduce((a, b) => a + b) / x.length;
    var sum = 0.0, weight = 0;
    for (final list in byType.values) {
      if (list.length < 4) continue;
      var term = 0.0;
      final known = [
        for (final s in list)
          if (s.realKind != null && s.finishShares.isNotEmpty) s,
      ];
      if (known.length >= 4) {
        for (var k = 0; k < FinishKind.road.length; k++) {
          term += sq(mean(known.map((s) => s.finishShares[k])) -
              known.where((s) => s.realKind == FinishKind.road[k]).length /
                  known.length);
        }
      }
      sum += term * list.length;
      weight += list.length;
    }
    return weight == 0 ? 0 : _wFrequency * sum / weight;
  }

  /// Total error; lower is better.
  double get loss => caseLoss + frequencyLoss;
}

/// Scores a tuning set over all races, spread across several cores.
///
/// @param cases The real races.
/// @param tuning Tuning values by name.
/// @param runs Simulation runs per race.
/// @param seed Base seed.
/// @param workers Number of isolates; defaults to all cores but one.
/// @returns The evaluation.
Future<Evaluation> evaluate(
  List<CalibrationCase> cases,
  Map<String, double> tuning, {
  required int runs,
  required int seed,
  int? workers,
}) async {
  final n =
      min(workers ?? max(1, Platform.numberOfProcessors - 1), cases.length);
  // Deal out in turn so that long and short races are spread evenly.
  final chunks = List.generate(n, (_) => <CalibrationCase>[]);
  for (var i = 0; i < cases.length; i++) {
    chunks[i % n].add(cases[i]);
  }
  final parts = await Future.wait([
    for (final chunk in chunks)
      Isolate.run(() {
        final t = SimTuning(tuning);
        return [for (final c in chunk) scoreCase(c, t, runs, seed)];
      }),
  ]);
  return Evaluation([for (final p in parts) ...p]);
}

/// Searches for better tuning values until the budget has run out.
///
/// Method: starting from the best known setting, a few randomly chosen
/// parameters are changed. If the result is better it is kept and the step
/// size grows, otherwise it shrinks. Every [reseedEvery] attempts the random
/// numbers change so that the search does not adapt to one particular draw.
///
/// @param cases The real races.
/// @param budget Time to search for.
/// @param runs Simulation runs per race.
/// @param start Setting to start from.
/// @param seed Base seed.
/// @param reseedEvery Attempts between two changes of the random numbers.
/// @param onImprove Called with every better setting found.
/// @param log Receives progress lines.
/// @param validation Races held back from the search; their error is logged
///   with every improvement.
/// @returns The best setting found.
Future<Map<String, double>> optimize(
  List<CalibrationCase> cases, {
  required Map<String, double> start,
  required Duration budget,
  required int runs,
  required int seed,
  int reseedEvery = 25,
  void Function(Map<String, double> best, double loss, int evaluations)?
      onImprove,
  void Function(String line)? log,
  List<CalibrationCase> validation = const [],
}) async {
  final rng = Random(seed);
  final params = SimTuning.params;

  /// @returns A standard normal sample.
  double gauss() =>
      sqrt(-2 * log_(max(rng.nextDouble(), 1e-12))) *
      cos(2 * pi * rng.nextDouble());

  // Parameters added since the start values were stored take their default.
  var best = {for (final p in params) p.name: start[p.name] ?? p.standard};
  var evalSeed = seed;
  var bestLoss = (await evaluate(cases, best, runs: runs, seed: evalSeed)).loss;
  // A candidate must also win on a second set of random numbers. Without
  // this check the search collects settings that merely suit one draw.
  var confirmSeed = seed + 1;
  var bestConfirm =
      (await evaluate(cases, best, runs: runs, seed: confirmSeed)).loss;
  var sigma = 0.08;
  var evaluations = 2, accepted = 0, rejected = 0, lastReseed = 0;
  final watch = Stopwatch()..start();
  log?.call('Start: Fehler ${bestLoss.toStringAsFixed(4)}');

  while (watch.elapsed < budget) {
    if (evaluations - lastReseed >= reseedEvery) {
      lastReseed = evaluations;
      evalSeed = rng.nextInt(1 << 30);
      bestLoss = (await evaluate(cases, best, runs: runs, seed: evalSeed)).loss;
      confirmSeed = rng.nextInt(1 << 30);
      bestConfirm =
          (await evaluate(cases, best, runs: runs, seed: confirmSeed)).loss;
      evaluations += 2;
      log?.call('Neue Zufallszahlen: Fehler der besten Einstellung '
          '${bestLoss.toStringAsFixed(4)}');
    }
    final candidate = Map.of(best);
    final changed = <String>[];
    while (changed.isEmpty) {
      for (final p in params) {
        if (rng.nextDouble() > 0.2) continue;
        final span = p.max - p.min;
        candidate[p.name] =
            (best[p.name]! + sigma * span * gauss()).clamp(p.min, p.max);
        changed.add(p.name);
      }
    }
    final loss =
        (await evaluate(cases, candidate, runs: runs, seed: evalSeed)).loss;
    evaluations++;
    var confirmed = double.infinity;
    if (loss < bestLoss - 1e-4) {
      confirmed =
          (await evaluate(cases, candidate, runs: runs, seed: confirmSeed))
              .loss;
      evaluations++;
      if (confirmed >= bestConfirm) rejected++;
    }
    if (confirmed < bestConfirm) {
      best = candidate;
      bestLoss = loss;
      bestConfirm = confirmed;
      accepted++;
      sigma = min(0.25, sigma * 1.3);
      onImprove?.call(best, bestLoss, evaluations);
      // The held-back races show whether the gain is real or fitted noise.
      final check = validation.isEmpty
          ? ''
          : ', Kontrolle ${(await evaluate(validation, best, runs: runs, seed: 4711)).loss.toStringAsFixed(4)}';
      log?.call('${_hm(watch.elapsed)}  Versuch $evaluations: besser, Fehler '
          '${bestLoss.toStringAsFixed(4)}$check  (${changed.join(', ')})');
    } else {
      sigma = max(0.01, sigma * 0.96);
    }
  }
  log?.call('Ende nach ${_hm(watch.elapsed)}: $evaluations Versuche, '
      '$accepted Verbesserungen, $rejected nicht bestätigt, Fehler ${bestLoss.toStringAsFixed(4)}');
  return best;
}

/// @param x A positive number.
/// @returns Its natural logarithm (named to avoid the clash with the `log`
///   parameter above).
double log_(double x) => log(x);

String _hm(Duration d) =>
    '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
