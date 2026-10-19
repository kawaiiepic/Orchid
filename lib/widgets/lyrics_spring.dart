import 'dart:math' as math;

/// Analytic damped spring — port of Sweet Lyrics / Spicy `Spring.ts` (Fraktality spr).
class LyricsSpring {
  static const _sleepOffsetSq = (1.0 / 3840.0) * (1.0 / 3840.0);
  static const _sleepVelocitySq = 1e-2 * 1e-2;
  static const _eps = 1e-5;

  double dampingRatio;
  double frequency;
  double goal;
  double position;
  double velocity;

  LyricsSpring(
    double start, {
    required this.frequency,
    required this.dampingRatio,
    double? goal,
  })  : goal = goal ?? start,
        position = start,
        velocity = 0;

  void setGoal(double g, {bool replacePosition = false}) {
    goal = g;
    if (replacePosition) {
      position = g;
      velocity = 0;
    }
  }

  bool get canSleep {
    if (velocity * velocity > _sleepVelocitySq) return false;
    final o = position - goal;
    return o * o <= _sleepOffsetSq;
  }

  double step(double dt) {
    final d = dampingRatio;
    final f = frequency * 2 * math.pi;
    final g = goal;
    var p = position;
    var v = velocity;

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
      final z = c > _eps
          ? j / c
          : (() {
              final a = dt * f;
              return a +
                  ((a * a) * (c * c) * (c * c) / 20 - c * c) * (a * a * a) / 6;
            })();
      final y = f * c > _eps
          ? j / (f * c)
          : (() {
              final b = f * c;
              return dt +
                  ((dt * dt) * (b * b) * (b * b) / 20 - b * b) *
                      (dt * dt * dt) /
                      6;
            })();
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
    position = p;
    velocity = v;
    return p;
  }

  bool _canSleepAfter(double p, double v, double g) {
    if (v * v > _sleepVelocitySq) return false;
    final o = p - g;
    return o * o <= _sleepOffsetSq;
  }
}

/// Scale / yOffset / glow springs for one glyph (Sweet Lyrics frequencies).
class GlyphSprings {
  final LyricsSpring scale;
  final LyricsSpring yOffset;
  final LyricsSpring glow;

  GlyphSprings({
    double scale = 1,
    double yOffset = 0,
    double glow = 0,
  })  : scale = LyricsSpring(scale, frequency: 0.88, dampingRatio: 0.64),
        yOffset = LyricsSpring(yOffset, frequency: 1.45, dampingRatio: 0.4),
        glow = LyricsSpring(glow, frequency: 1.18, dampingRatio: 0.56);

  (double, double, double) step({
    required double scaleGoal,
    required double yGoal,
    required double glowGoal,
    required double dt,
    bool snap = false,
  }) {
    scale.setGoal(scaleGoal, replacePosition: snap);
    yOffset.setGoal(yGoal, replacePosition: snap);
    glow.setGoal(glowGoal, replacePosition: snap);
    return (scale.step(dt), yOffset.step(dt), glow.step(dt));
  }

  bool get isSettled => scale.canSleep && yOffset.canSleep && glow.canSleep;
}
