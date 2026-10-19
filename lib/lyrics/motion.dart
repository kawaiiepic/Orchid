// Motion primitives for the lyrics renderer.
//
// Ported from Sweet Lyrics for iOS (Spring.swift, Easing.swift), which in turn
// ports Spicy Lyrics' `modules/Spring.ts` (itself a port of
// https://github.com/Fraktality/spr, MIT, Copyright (c) Fraktality).
//
// Sweet Lyrics is AGPL-3.0; this file is a derivative work.

import 'dart:math' as math;

double clampD(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

/// d3-ease `easeSinOut`.
double easeSinOut(double t) => math.sin(t * math.pi / 2);

// ---------------------------------------------------------------------------
// CSS timing functions
// ---------------------------------------------------------------------------

/// A CSS timing function, so the stylesheet transitions of Spicy Lyrics can be
/// replayed exactly.
abstract class Easing {
  const Easing();

  double value(double t);

  /// CSS `ease`.
  static const Easing ease = CubicBezierEasing(0.25, 0.1, 0.25, 1);
}

class CubicBezierEasing extends Easing {
  final double x1, y1, x2, y2;

  const CubicBezierEasing(this.x1, this.y1, this.x2, this.y2);

  @override
  double value(double t) {
    final x = clampD(t, 0, 1);
    final cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
    final cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
    double sampleX(double s) => ((ax * s + bx) * s + cx) * s;
    double sampleY(double s) => ((ay * s + by) * s + cy) * s;
    double slopeX(double s) => (3 * ax * s + 2 * bx) * s + cx;

    // Newton's method on x(s) = x ...
    var s = x;
    for (var i = 0; i < 8; i++) {
      final err = sampleX(s) - x;
      if (err.abs() < 1e-6) return sampleY(s);
      final d = slopeX(s);
      if (d.abs() < 1e-6) break;
      s -= err / d;
    }
    // ... with a bisection fallback.
    var low = 0.0, high = 1.0;
    s = x;
    for (var i = 0; i < 30; i++) {
      final v = sampleX(s);
      if ((v - x).abs() < 1e-6) break;
      if (v < x) {
        low = s;
      } else {
        high = s;
      }
      s = (low + high) / 2;
    }
    return sampleY(s);
  }
}

/// CSS `linear(...)`: `(progress, value)` points, interpolated piecewise.
class LinearPointsEasing extends Easing {
  final List<List<double>> points;

  const LinearPointsEasing(this.points);

  @override
  double value(double t) {
    final x = clampD(t, 0, 1);
    if (points.isEmpty) return x;
    var prev = points.first;
    if (x <= prev[0]) return prev[1];
    for (var i = 1; i < points.length; i++) {
      final p = points[i];
      if (x <= p[0]) {
        final span = p[0] - prev[0];
        return span > 0
            ? prev[1] + (p[1] - prev[1]) * (x - prev[0]) / span
            : p[1];
      }
      prev = p;
    }
    return prev[1];
  }
}

/// A CSS-style transition of one number: retargeting starts a new transition
/// from the current value.
class CssTransition {
  double value;
  double _from;
  double _to;
  double _startedAt = 0;
  final double duration;
  final Easing easing;

  CssTransition(double start, {required this.duration, required this.easing})
      : value = start,
        _from = start,
        _to = start;

  bool get isSettled => value == _to;

  /// Moves toward [target] at media time [now]; returns the current value.
  double update(double target, double now, {bool snap = false}) {
    if (snap) {
      value = target;
      _from = target;
      _to = target;
      return value;
    }
    if (target != _to) {
      _from = value;
      _to = target;
      _startedAt = now;
    }
    if (value != _to) {
      final progress = duration > 0 ? (now - _startedAt) / duration : 1.0;
      value = progress >= 1 ? _to : _from + (_to - _from) * easing.value(progress);
    }
    return value;
  }
}

// ---------------------------------------------------------------------------
// Spring
// ---------------------------------------------------------------------------

/// Analytic damped spring (solved exactly for any step size).
class Spring {
  static const double _sleepOffsetSqLimit = (1.0 / 3840.0) * (1.0 / 3840.0);
  static const double _sleepVelocitySqLimit = 1e-2 * 1e-2;
  static const double _eps = 1e-5;

  double dampingRatio;
  double frequency;
  double _goal;
  double _position;
  double _velocity = 0;

  Spring(double start,
      {required this.frequency, required double damping, double? goal})
      : dampingRatio = damping,
        _goal = goal ?? start,
        _position = start;

  double get goal => _goal;
  double get position => _position;
  double get velocity => _velocity;

  void setGoal(double goal, {bool replacePosition = false}) {
    _goal = goal;
    if (replacePosition) {
      _position = goal;
      _velocity = 0;
    }
  }

  bool get canSleep {
    if (_velocity * _velocity > _sleepVelocitySqLimit) return false;
    final offset = _position - _goal;
    return offset * offset <= _sleepOffsetSqLimit;
  }

  double step(double dt) {
    final d = dampingRatio;
    final f = frequency * 2 * math.pi;
    final g = _goal;
    var p = _position;
    var v = _velocity;

    if (d == 1) {
      final q = math.exp(-f * dt);
      final w = dt * q;
      final c0 = q + w * f;
      final c2 = q - w * f;
      final c3 = w * f * f;
      final o = p - g;
      p = o * c0 + v * w + g;
      v = v * c2 - o * c3;
    } else if (d < 1) {
      final q = math.exp(-d * f * dt);
      final c = math.sqrt(1 - d * d);
      final i = math.cos(dt * f * c);
      final j = math.sin(dt * f * c);

      double z;
      if (c > _eps) {
        z = j / c;
      } else {
        final a = dt * f;
        z = a + ((a * a) * (c * c) * (c * c) / 20 - c * c) * (a * a * a) / 6;
      }

      double y;
      if (f * c > _eps) {
        y = j / (f * c);
      } else {
        final b = f * c;
        y = dt + ((dt * dt) * (b * b) * (b * b) / 20 - b * b) * (dt * dt * dt) / 6;
      }

      final o = p - g;
      p = (o * (i + z * d) + v * y) * q + g;
      v = (v * (i - z * d) - o * (z * f)) * q;
    } else {
      final c = math.sqrt(d * d - 1);
      final r1 = -f * (d + c);
      final r2 = -f * (d - c);
      final ec1 = math.exp(r1 * dt);
      final ec2 = math.exp(r2 * dt);
      final o = p - g;
      final co2 = (v - o * r1) / (2 * f * c);
      final co1 = ec1 * (o - co2);
      p = co1 + co2 * ec2 + g;
      v = co1 * r1 + co2 * ec2 * r2;
    }

    if (_canSleepAfter(p, v, g)) {
      p = g;
      v = 0;
    }
    _position = p;
    _velocity = v;
    return p;
  }

  static bool _canSleepAfter(double p, double v, double g) {
    if (v * v > _sleepVelocitySqLimit) return false;
    final o = p - g;
    return o * o <= _sleepOffsetSqLimit;
  }
}

// ---------------------------------------------------------------------------
// Cubic spline
// ---------------------------------------------------------------------------

/// Natural cubic spline through a handful of control points, matching the
/// `cubic-spline` npm package Spicy Lyrics uses for its animation curves.
class CubicSpline {
  final List<double> _xs;
  final List<double> _ys;
  final List<double> _ks;

  CubicSpline(List<List<double>> points)
      : _xs = points.map((p) => p[0]).toList(growable: false),
        _ys = points.map((p) => p[1]).toList(growable: false),
        _ks = _derivatives(
          points.map((p) => p[0]).toList(growable: false),
          points.map((p) => p[1]).toList(growable: false),
        );

  double at(double x) {
    if (_xs.length < 2) return _ys.isEmpty ? 0 : _ys.first;
    var i = 1;
    while (i < _xs.length - 1 && _xs[i] < x) {
      i++;
    }
    final x0 = _xs[i - 1], x1 = _xs[i];
    final y0 = _ys[i - 1], y1 = _ys[i];
    final h = x1 - x0;
    final t = (x - x0) / h;
    final a = _ks[i - 1] * h - (y1 - y0);
    final b = -_ks[i] * h + (y1 - y0);
    return (1 - t) * y0 + t * y1 + t * (1 - t) * (a * (1 - t) + b * t);
  }

  /// Solves the tridiagonal system for the knot derivatives of a natural spline.
  static List<double> _derivatives(List<double> xs, List<double> ys) {
    final n = xs.length;
    if (n < 2) return List<double>.filled(n, 0);
    final a = List<double>.filled(n, 0);
    final b = List<double>.filled(n, 0);
    final c = List<double>.filled(n, 0);
    final r = List<double>.filled(n, 0);

    for (var i = 0; i < n; i++) {
      if (i == 0) {
        final h = xs[1] - xs[0];
        b[i] = 2 / h;
        c[i] = 1 / h;
        r[i] = 3 * (ys[1] - ys[0]) / (h * h);
      } else if (i == n - 1) {
        final h = xs[i] - xs[i - 1];
        a[i] = 1 / h;
        b[i] = 2 / h;
        r[i] = 3 * (ys[i] - ys[i - 1]) / (h * h);
      } else {
        final h0 = xs[i] - xs[i - 1];
        final h1 = xs[i + 1] - xs[i];
        a[i] = 1 / h0;
        b[i] = 2 * (1 / h0 + 1 / h1);
        c[i] = 1 / h1;
        r[i] = 3 *
            ((ys[i] - ys[i - 1]) / (h0 * h0) +
                (ys[i + 1] - ys[i]) / (h1 * h1));
      }
    }

    // Thomas algorithm.
    for (var i = 1; i < n; i++) {
      final m = a[i] / b[i - 1];
      b[i] -= m * c[i - 1];
      r[i] -= m * r[i - 1];
    }
    final k = List<double>.filled(n, 0);
    k[n - 1] = r[n - 1] / b[n - 1];
    for (var i = n - 2; i >= 0; i--) {
      k[i] = (r[i] - c[i] * k[i + 1]) / b[i];
    }
    return k;
  }
}
