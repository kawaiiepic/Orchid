// Per-frame state machine for the lyrics.
//
// Ported from Sweet Lyrics for iOS (LyricsAnimator.swift), a port of Spicy
// Lyrics' `LyricsAnimator.ts`: NotSung / Active / Sung states, syllable
// gradients, cubic splines for scale / lift / glow, and springs.
// Sweet Lyrics is AGPL-3.0; this file is a derivative work.
//
// Not reactive on purpose: the lyrics widget's ticker calls [step] once per
// frame and reads [visuals]. [revisions] says which lines actually changed, so
// the widget only rebuilds those.

import 'dart:math' as math;

import 'motion.dart';
import 'prepared_lyrics.dart';

enum ElementState { notSung, active, sung }

ElementState elementStateOf(double time, double start, double end) {
  if (time < start) return ElementState.notSung;
  if (time >= end) return ElementState.sung;
  return ElementState.active;
}

double _progress(double time, double start, double end) {
  if (time <= start) return 0;
  if (time >= end) return 1;
  return (time - start) / (end - start);
}

// ---------------------------------------------------------------------------
// Visual output (what the widgets draw)
// ---------------------------------------------------------------------------

/// Transform + paint of one glyph run (a syllable, a letter or a dot).
class GlyphVisual {
  double scale;

  /// Vertical offset as a fraction of the font size (positive = down).
  double yOffset;

  /// 0..1+ glow strength, mapped to a shadow per element kind.
  double glow;

  /// Left edge of the fill gradient as a fraction of the glyph width
  /// (-0.2 = unlit, 1 = lit).
  double gradient;
  double opacity;

  GlyphVisual({
    this.scale = 1,
    this.yOffset = 0,
    this.glow = 0,
    this.gradient = -0.2,
    this.opacity = 1,
  });
}

class SyllableVisual {
  final GlyphVisual glyph;

  /// Per-letter visuals for emphasised syllables, empty otherwise.
  final List<GlyphVisual> letters;

  SyllableVisual(this.glyph, this.letters);
}

class LineVisual {
  ElementState state = ElementState.notSung;
  double opacity = 0.51;
  double blur = 0;

  /// Whole-line scale (line-synced lines grow to 1.05 while active).
  double scale = 1;

  /// Syllable-synced lines: `[word][syllable]`.
  List<List<SyllableVisual>> lead = const [];
  List<List<SyllableVisual>> background = const [];

  /// Line-synced lines.
  final GlyphVisual line = GlyphVisual();

  /// Interlude dots. An interlude row only takes up space while active
  /// (`presence` 0/1); its dot group pops in and out with `dotGroupScale`.
  List<GlyphVisual> dots = const [];
  double presence = 1;
  double dotGroupScale = 0;
}

// ---------------------------------------------------------------------------
// Curves (values from Spicy Lyrics' LyricsAnimator.ts)
// ---------------------------------------------------------------------------

class LyricCurves {
  LyricCurves._();

  static final scale = CubicSpline([
    [0, 0.95],
    [0.7, 1.0505],
    [1, 1]
  ]);
  static final yOffset = CubicSpline([
    [0, 1.0 / 100],
    [0.9, -(1.0 / 60)],
    [1, 0]
  ]);
  static final glow = CubicSpline([
    [0, 0],
    [0.15, 1],
    [0.6, 1],
    [1, 0]
  ]);
  static final letterScale = CubicSpline([
    [0, 0.95],
    [0.7, 1.175],
    [1, 1]
  ]);
  static final letterYOffset = CubicSpline([
    [0, 1.0 / 100],
    [0.9, -(1.0 / 56)],
    [1, 0]
  ]);
  static final lineGlow = CubicSpline([
    [0, 0],
    [0.5, 1],
    [1, 0]
  ]);

  static final dotScale = CubicSpline([
    [0, 0.75],
    [0.7, 1.05],
    [1, 1]
  ]);
  static final dotYOffset = CubicSpline([
    [0, 0],
    [0.9, -0.12],
    [1, 0]
  ]);
  static final dotGlow = CubicSpline([
    [0, 0],
    [0.6, 1],
    [1, 1]
  ]);
  static final dotOpacity = CubicSpline([
    [0, 0.35],
    [0.6, 1],
    [1, 1]
  ]);

  static final sungLetterGlow = glow.at(0.2);

  // Simple Lyrics Mode: words only drift up, letters get milder curves, dots
  // only fade.
  static final simpleYOffset = CubicSpline([
    [0, 1.0 / 100],
    [1, -0.033]
  ]);
  static final simpleLetterScale = CubicSpline([
    [0, 0.95],
    [0.7, 1.07],
    [1, 1]
  ]);
  static final simpleLetterYOffset = CubicSpline([
    [0, 1.0 / 100],
    [0.9, -(1.0 / 62)],
    [1, 0]
  ]);
  static final simpleDotOpacity = CubicSpline([
    [0, 0.27],
    [0.6, 1],
    [1, 1]
  ]);

  /// `Animate()` runs Simple Lyrics Mode 33.5 ms behind.
  static const simplePositionOffset = -0.0335;
  static const simpleLongerThan = 1.5;
  static const simpleLonger = _Strength(glow: 0.4, yOffset: 0.45, scale: 1.103);
  static const simpleShorter =
      _Strength(glow: 0.285, yOffset: 0.1, scale: 1.09);

  // Spring tuning.
  static const yOffsetFrequency = 1.45, yOffsetDamping = 0.4;
  static const scaleFrequency = 0.88, scaleDamping = 0.64;
  static const glowFrequency = 1.18, glowDamping = 0.56;

  // Line states (Mixed.css).
  static const notSungOpacity = 0.51;
  static const activeOpacity = 1.0;
  static const sungOpacity = 0.497;

  /// A line overlapped by the active one, when line blur is on.
  static const sungAfterActiveOpacity = 0.45;
  static const blurMultiplier = 1.25;
  static const maxBlur = blurMultiplier * 5 + blurMultiplier * 0.465;

  // CSS transitions (Mixed.css).
  static const lineOpacityDuration = 0.2;
  static const lineOpacityEasing = CubicBezierEasing(0.61, 1, 0.88, 1);
  static const lineSyncedDuration = 0.2;
  static const lineSyncedEasing = CubicBezierEasing(0.37, 0, 0.63, 1);
  static const activeLineSyncedScale = 1.05;
  static const interludeOpacityDuration = 0.14;
  static const dotsInDuration = 0.3;
  static const dotsOutDuration = 0.4;

  /// `.musical-line:is(.pre-hidden, :not(.Active)) .dotGroup`: a small
  /// wind-up, then gone.
  static const dotsOutEasing = LinearPointsEasing([
    [0, 0],
    [0.094, -0.006],
    [0.18, -0.029],
    [0.433, -0.157],
    [0.514, -0.185],
    [0.559, -0.189],
    [0.60, -0.182],
    [0.639, -0.163],
    [0.676, -0.133],
    [0.723, -0.074],
    [0.767, 0.006],
    [0.85, 0.238],
    [0.927, 0.566],
    [1, 1],
  ]);

  /// The dots start hiding this long before the interlude ends.
  static const preHiddenDots = 0.5;
}

class _Strength {
  final double glow, yOffset, scale;
  const _Strength({
    required this.glow,
    required this.yOffset,
    required this.scale,
  });
}

// ---------------------------------------------------------------------------
// Spring bundles
// ---------------------------------------------------------------------------

class _GlyphSprings {
  final Spring scale;
  final Spring yOffset;
  final Spring glow;

  _GlyphSprings({
    required double scale,
    required double yOffset,
    required double glow,
    double scaleFrequency = LyricCurves.scaleFrequency,
    double scaleDamping = LyricCurves.scaleDamping,
    double yFrequency = LyricCurves.yOffsetFrequency,
    double yDamping = LyricCurves.yOffsetDamping,
    double glowFrequency = LyricCurves.glowFrequency,
    double glowDamping = LyricCurves.glowDamping,
  })  : scale =
            Spring(scale, frequency: scaleFrequency, damping: scaleDamping),
        yOffset = Spring(yOffset, frequency: yFrequency, damping: yDamping),
        glow = Spring(glow, frequency: glowFrequency, damping: glowDamping);

  /// Steps all three toward the targets; returns (scale, yOffset, glow).
  List<double> step(double s, double y, double g, double dt) {
    scale.setGoal(s);
    yOffset.setGoal(y);
    glow.setGoal(g);
    return [scale.step(dt), yOffset.step(dt), glow.step(dt)];
  }

  void snapTo(double s, double y, double g) {
    scale.setGoal(s, replacePosition: true);
    yOffset.setGoal(y, replacePosition: true);
    glow.setGoal(g, replacePosition: true);
  }

  bool get isSettled => scale.canSleep && yOffset.canSleep && glow.canSleep;
}

class _SyllableSprings {
  final _GlyphSprings glyph;
  final List<_GlyphSprings> letters;
  _SyllableSprings(this.glyph, this.letters);
}

class _DotSprings {
  final _GlyphSprings glyph;
  final Spring opacity;
  _DotSprings(this.glyph, this.opacity);
}

/// Scale that eases in with one curve and out with another (the interlude's
/// dot group).
class _InOutTween {
  CssTransition _tween = CssTransition(0,
      duration: LyricCurves.dotsOutDuration,
      easing: LyricCurves.dotsOutEasing);
  bool _showing = false;

  double update({required bool show, required double now, required bool snap}) {
    if (show != _showing) {
      _showing = show;
      _tween = CssTransition(
        _tween.value,
        duration:
            show ? LyricCurves.dotsInDuration : LyricCurves.dotsOutDuration,
        easing: show ? Easing.ease : LyricCurves.dotsOutEasing,
      );
    }
    return _tween.update(show ? 1 : 0, now, snap: snap);
  }

  bool get isSettled => _tween.isSettled;
}

class _LineSprings {
  final CssTransition opacity;
  final CssTransition scale;
  final Spring glow;
  final _InOutTween dotGroup = _InOutTween();
  final List<List<_SyllableSprings>> lead;
  final List<List<_SyllableSprings>> background;
  final List<_DotSprings> dots;

  /// False once a line is off-stage and every spring has come to rest: it is
  /// skipped until its state changes again. Most of a song is asleep at any
  /// moment.
  bool awake = true;
  ElementState? lastState;

  _LineSprings({
    required this.opacity,
    required this.scale,
    required this.glow,
    required this.lead,
    required this.background,
    required this.dots,
  });
}

// ---------------------------------------------------------------------------
// Animator
// ---------------------------------------------------------------------------

class LyricsAnimator {
  final PreparedLyrics lyrics;

  /// Simple Lyrics Mode.
  final bool simple;

  final List<LineVisual> visuals;

  /// Bumped for a line whenever its visual changed this frame.
  final List<int> revisions;

  /// The line the view should keep in focus (scroll target and blur origin).
  int focusIndex = 0;

  /// The last step jumped to the clock instead of animating (a seek, a
  /// resume).
  bool snapped = true;

  final List<_LineSprings> _springs;
  double? _lastFrame;
  double? _lastPosition;

  LyricsAnimator(this.lyrics, {this.simple = false})
      : _springs = lyrics.lines.map(_makeSprings).toList(growable: false),
        visuals = lyrics.lines.map(_makeVisual).toList(growable: false),
        revisions = List<int>.filled(lyrics.lines.length, 0);

  /// The next step jumps straight to the clock.
  void snapNext() => _lastPosition = null;

  /// Advances every spring to [position] (seconds). [now] is any monotonic
  /// clock in seconds.
  void step({
    required double position,
    required double now,
    required bool blurEnabled,
  }) {
    var dt = _lastFrame == null ? 1.0 / 60 : now - _lastFrame!;
    if (dt <= 0) return;
    final pos = position + (simple ? LyricCurves.simplePositionOffset : 0);

    // No frames for a while (the app was hidden, the device stalled): whatever
    // the springs were doing is stale, so snap like after a seek.
    final resumed = dt > 0.4;
    // The springs are solved exactly for any step, so a slow frame takes its
    // whole length.
    dt = math.min(dt, 0.25);
    // A seek: snap everything instead of animating across the whole song.
    final jumped = resumed ||
        _lastPosition == null ||
        (pos - _lastPosition!).abs() > 1.5;
    _lastFrame = now;
    _lastPosition = pos;
    snapped = jumped;

    if (lyrics.kind == PreparedKind.staticText) {
      if (!jumped) return;
      for (var i = 0; i < visuals.length; i++) {
        visuals[i]
          ..state = ElementState.active
          ..opacity = 1
          ..blur = 0;
        visuals[i].line.gradient = 1;
        revisions[i]++;
      }
      return;
    }

    focusIndex = focus(lyrics.lines, pos);
    var previousActive = false;

    for (var index = 0; index < lyrics.lines.length; index++) {
      final line = lyrics.lines[index];
      final ls = _springs[index];
      final visual = visuals[index];
      final state = elementStateOf(pos, line.start, line.end);
      if (ls.lastState != state || jumped) ls.awake = true;
      ls.lastState = state;

      final wasAwake = ls.awake;
      final prevOpacity = visual.opacity;
      final prevBlur = visual.blur;
      final prevScale = visual.scale;
      final prevPresence = visual.presence;
      final prevDotGroup = visual.dotGroupScale;
      final prevState = visual.state;

      // Line level: opacity (a CSS transition) and the distance blur.
      double targetOpacity;
      switch (state) {
        case ElementState.notSung:
          targetOpacity = LyricCurves.notSungOpacity;
        case ElementState.active:
          targetOpacity = LyricCurves.activeOpacity;
        case ElementState.sung:
          targetOpacity = LyricCurves.sungOpacity;
      }
      if (state == ElementState.sung &&
          previousActive &&
          blurEnabled &&
          !line.isInterlude) {
        targetOpacity = LyricCurves.sungAfterActiveOpacity;
      }
      if (!line.isInterlude) previousActive = state == ElementState.active;

      final distance = (index - focusIndex).abs();
      final blur = (!blurEnabled || state == ElementState.active || distance == 0)
          ? 0.0
          : math.min(LyricCurves.blurMultiplier * distance, LyricCurves.maxBlur);

      visual
        ..state = state
        ..blur = blur;

      switch (line.kind) {
        case PreparedKind.syllable:
          visual.opacity = ls.opacity.update(targetOpacity, now, snap: jumped);
          if (ls.awake) {
            final settledLead = _stepWords(line.lead, ls.lead, visual.lead,
                time: pos, dt: dt, snap: jumped);
            final settledBg = _stepWords(
                line.background, ls.background, visual.background,
                time: pos, dt: dt, snap: jumped);
            if (state != ElementState.active && settledLead && settledBg) {
              ls.awake = false;
            }
          }

        case PreparedKind.line:
          visual.opacity = ls.opacity.update(targetOpacity, now, snap: jumped);
          visual.scale = ls.scale.update(
              state == ElementState.active
                  ? LyricCurves.activeLineSyncedScale
                  : 1,
              now,
              snap: jumped);
          if (ls.awake) {
            final p = _progress(pos, line.start, line.end);
            double targetGlow;
            switch (state) {
              case ElementState.active:
                targetGlow = LyricCurves.lineGlow.at(p);
                visual.line.gradient = p;
              case ElementState.notSung:
                targetGlow = LyricCurves.lineGlow.at(0);
                visual.line.gradient = -0.2;
              case ElementState.sung:
                targetGlow = LyricCurves.lineGlow.at(1);
                visual.line.gradient = 1;
            }
            ls.glow.setGoal(simple ? 0 : targetGlow, replacePosition: jumped);
            visual.line.glow = ls.glow.step(dt);
            if (state != ElementState.active && ls.glow.canSleep) {
              ls.awake = false;
            }
          }

        case PreparedKind.interlude:
          // Only takes up space while active; fades in and out over 0.14 s.
          visual.presence = state == ElementState.active ? 1 : 0;
          visual.opacity = ls.opacity
              .update(state == ElementState.active ? 1 : 0, now, snap: jumped);
          final preHidden = pos > line.end - LyricCurves.preHiddenDots;
          visual.dotGroupScale = ls.dotGroup.update(
              show: state == ElementState.active && !preHidden,
              now: now,
              snap: jumped);
          if (ls.awake) {
            var settled = ls.dotGroup.isSettled;
            for (var k = 0; k < line.dots.length; k++) {
              final dot = line.dots[k];
              double p;
              switch (elementStateOf(pos, dot.start, dot.end)) {
                case ElementState.notSung:
                  p = 0;
                case ElementState.active:
                  p = _progress(pos, dot.start, dot.end);
                case ElementState.sung:
                  p = 1;
              }
              final s = ls.dots[k];
              if (simple) {
                // Simple mode: the dots only fade in.
                s.opacity.setGoal(LyricCurves.simpleDotOpacity.at(p),
                    replacePosition: jumped);
                final opacity = s.opacity.step(dt);
                settled = settled && s.opacity.canSleep;
                visual.dots[k]
                  ..scale = 1
                  ..yOffset = 0
                  ..glow = 0
                  ..gradient = 1
                  ..opacity = opacity;
                continue;
              }
              if (jumped) {
                s.glyph.snapTo(LyricCurves.dotScale.at(p),
                    LyricCurves.dotYOffset.at(p), LyricCurves.dotGlow.at(p));
                s.opacity.setGoal(LyricCurves.dotOpacity.at(p),
                    replacePosition: true);
              }
              final r = s.glyph.step(LyricCurves.dotScale.at(p),
                  LyricCurves.dotYOffset.at(p), LyricCurves.dotGlow.at(p), dt);
              s.opacity.setGoal(LyricCurves.dotOpacity.at(p));
              final opacity = s.opacity.step(dt);
              settled = settled && s.glyph.isSettled && s.opacity.canSleep;
              visual.dots[k]
                ..scale = r[0]
                ..yOffset = r[1]
                ..glow = r[2]
                ..gradient = 1
                ..opacity = opacity;
            }
            if (state != ElementState.active && settled) ls.awake = false;
          }

        case PreparedKind.staticText:
          break;
      }

      if (wasAwake ||
          visual.opacity != prevOpacity ||
          visual.blur != prevBlur ||
          visual.scale != prevScale ||
          visual.presence != prevPresence ||
          visual.dotGroupScale != prevDotGroup ||
          visual.state != prevState) {
        revisions[index]++;
      }
    }
  }

  /// Lines starting this close together are sung together (a duet); the first
  /// one keeps focus.
  static const double _duetWindow = 0.6;

  /// The last line that has started (so the view stays on a line through
  /// short gaps).
  static int focus(List<PreparedLine> lines, double time) {
    if (lines.isEmpty) return 0;
    var low = 0, high = lines.length - 1, found = 0;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].start <= time) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    // Background rows never hold focus: they belong to their lead line.
    if (lines[found].isBackground && lines[found].leadId != null) {
      found = lines[found].leadId!;
    }
    // Prefer the first of several lines that start together (duets). Only
    // lines that start together count: a long earlier line that merely
    // overlaps must not hold focus while the next line is being sung.
    var index = found;
    while (index > 0) {
      final previous = lines[index - 1];
      if (previous.isInterlude ||
          previous.isBackground ||
          lines[index].start - previous.start > _duetWindow ||
          elementStateOf(time, previous.start, previous.end) !=
              ElementState.active) {
        break;
      }
      index -= 1;
    }
    return index;
  }

  /// Steps every syllable of a word list; returns whether all of their
  /// springs are at rest.
  bool _stepWords(
    List<PreparedWord> words,
    List<List<_SyllableSprings>> springs,
    List<List<SyllableVisual>> out, {
    required double time,
    required double dt,
    required bool snap,
  }) {
    var settled = true;
    for (var w = 0; w < words.length; w++) {
      for (var s = 0; s < words[w].syllables.length; s++) {
        final syllable = words[w].syllables[s];
        final store = springs[w][s];
        final visual = out[w][s];
        final letters = syllable.letters;
        if (letters != null && letters.isNotEmpty) {
          // A letter group lives on the emphasised range (`Emphasize` ends it
          // 250 ms early), and the whole word rides the word springs while its
          // letters ripple on top.
          final start = letters.first.start;
          final end = letters.last.end;
          _stepSyllable(start, end, store, visual,
              time: time, dt: dt, snap: snap);
          _stepLetters(start, end, letters, store, visual,
              time: time, dt: dt, snap: snap);
        } else {
          _stepSyllable(syllable.start, syllable.end, store, visual,
              time: time, dt: dt, snap: snap);
        }
        settled =
            settled && store.glyph.isSettled && store.letters.every((l) => l.isSettled);
      }
    }
    return settled;
  }

  void _stepSyllable(
    double start,
    double end,
    _SyllableSprings store,
    SyllableVisual visual, {
    required double time,
    required double dt,
    required bool snap,
  }) {
    final state = elementStateOf(time, start, end);
    if (simple) {
      // No scale or glow: the word drifts up while a wider, softer fill
      // passes over it.
      double p;
      switch (state) {
        case ElementState.notSung:
          p = 0;
          visual.glyph.gradient = -0.5;
        case ElementState.active:
          p = _progress(time, start, end);
          visual.glyph.gradient = -0.5 + 1.2 * p;
        case ElementState.sung:
          p = 1;
          visual.glyph.gradient = 1;
      }
      store.glyph.yOffset
          .setGoal(LyricCurves.simpleYOffset.at(p), replacePosition: snap);
      visual.glyph
        ..yOffset = store.glyph.yOffset.step(dt)
        ..scale = 1
        ..glow = 0;
      return;
    }
    double p;
    switch (state) {
      case ElementState.notSung:
        p = 0;
        visual.glyph.gradient = -0.2;
      case ElementState.active:
        p = _progress(time, start, end);
        visual.glyph.gradient = -0.2 + 1.2 * p;
      case ElementState.sung:
        p = 1;
        visual.glyph.gradient = 1;
    }
    final ts = LyricCurves.scale.at(p);
    final ty = LyricCurves.yOffset.at(p);
    final tg = LyricCurves.glow.at(p);
    if (snap) store.glyph.snapTo(ts, ty, tg);
    final r = store.glyph.step(ts, ty, tg, dt);
    visual.glyph
      ..scale = r[0]
      ..yOffset = r[1]
      ..glow = r[2];
  }

  void _stepLetters(
    double start,
    double end,
    List<PreparedLetter> letters,
    _SyllableSprings store,
    SyllableVisual visual, {
    required double time,
    required double dt,
    required bool snap,
  }) {
    final wordState = elementStateOf(time, start, end);

    var activeLetter = -1;
    var activeProgress = 0.0;
    if (wordState == ElementState.active) {
      for (var i = 0; i < letters.length; i++) {
        if (elementStateOf(time, letters[i].start, letters[i].end) ==
            ElementState.active) {
          activeLetter = i;
          activeProgress = _progress(time, letters[i].start, letters[i].end);
          break;
        }
      }
    }

    final scaleCurve =
        simple ? LyricCurves.simpleLetterScale : LyricCurves.letterScale;
    final yCurve =
        simple ? LyricCurves.simpleLetterYOffset : LyricCurves.letterYOffset;
    final strength = end - start > LyricCurves.simpleLongerThan
        ? LyricCurves.simpleLonger
        : LyricCurves.simpleShorter;
    // Simple mode scales the letter curves and drives them by the whole
    // word's progress.
    final wordProgress = _progress(time, start, end);
    final restScale = scaleCurve.at(0);
    final restY = yCurve.at(0);
    final restGlow = LyricCurves.glow.at(0);
    final unlit = simple ? -0.5 : -0.2;

    for (var k = 0; k < letters.length; k++) {
      final letter = letters[k];
      final letterState = elementStateOf(time, letter.start, letter.end);
      var targetScale = restScale, targetY = restY, targetGlow = restGlow;
      double gradient;

      switch (wordState) {
        case ElementState.notSung:
          gradient = unlit;
        case ElementState.sung:
          targetScale = scaleCurve.at(1);
          targetY = yCurve.at(1);
          targetGlow = LyricCurves.glow.at(1);
          gradient = 1;
        case ElementState.active:
          if (activeLetter >= 0) {
            // Proximity falloff around the letter being sung.
            final count = simple ? wordProgress : activeProgress;
            final baseScale =
                scaleCurve.at(count) * (simple ? strength.scale : 1);
            final baseY = yCurve.at(count) * (simple ? strength.yOffset : 1);
            final baseGlow =
                LyricCurves.glow.at(count) * (simple ? strength.glow : 1);
            final d = (k - activeLetter).abs().toDouble();
            final falloff = math.max(0.0, 1 / (1 + math.pow(d, 2.8)));
            final glowFalloff = math.max(0.0, 1 / (1 + d * 0.9));
            targetScale = restScale + (baseScale - restScale) * falloff;
            targetY = restY + (baseY - restY) * falloff;
            targetGlow = restGlow + (baseGlow - restGlow) * glowFalloff;
          }
          switch (letterState) {
            case ElementState.notSung:
              if (!simple) {
                targetScale = restScale;
                targetY = restY;
                targetGlow = restGlow;
              }
              gradient = unlit;
            case ElementState.sung:
              if (activeLetter == -1) {
                targetGlow = LyricCurves.sungLetterGlow;
              }
              gradient = 1;
            case ElementState.active:
              gradient = k == activeLetter
                  ? unlit + 1.2 * easeSinOut(activeProgress)
                  : unlit;
          }
      }

      final springs = store.letters[k];
      if (snap) springs.snapTo(targetScale, targetY, targetGlow);
      final r = springs.step(targetScale, targetY, targetGlow, dt);
      visual.letters[k]
        ..scale = r[0]
        ..yOffset = r[1] * 2
        ..glow = r[2]
        ..gradient = gradient
        ..opacity = 1;
    }
  }

  // -------------------------------------------------------------------------
  // Construction
  // -------------------------------------------------------------------------

  static _LineSprings _makeSprings(PreparedLine line) {
    List<List<_SyllableSprings>> syllableSprings(List<PreparedWord> words) {
      return [
        for (final word in words)
          [
            for (final syllable in word.syllables)
              _SyllableSprings(
                _GlyphSprings(
                  scale: LyricCurves.scale.at(0),
                  yOffset: LyricCurves.yOffset.at(0),
                  glow: LyricCurves.glow.at(0),
                ),
                [
                  for (final _ in syllable.letters ?? const <PreparedLetter>[])
                    _GlyphSprings(
                      scale: LyricCurves.letterScale.at(0),
                      yOffset: LyricCurves.letterYOffset.at(0),
                      glow: LyricCurves.glow.at(0),
                    ),
                ],
              ),
          ],
      ];
    }

    var lead = <List<_SyllableSprings>>[];
    var background = <List<_SyllableSprings>>[];
    var dots = <_DotSprings>[];
    switch (line.kind) {
      case PreparedKind.syllable:
        lead = syllableSprings(line.lead);
        background = syllableSprings(line.background);
      case PreparedKind.interlude:
        dots = [
          for (final _ in line.dots)
            _DotSprings(
              _GlyphSprings(
                scale: LyricCurves.dotScale.at(0),
                yOffset: LyricCurves.dotYOffset.at(0),
                glow: LyricCurves.dotGlow.at(0),
                scaleFrequency: 0.7,
                scaleDamping: 0.6,
                yFrequency: 1.25,
                yDamping: 0.4,
                glowFrequency: 1,
                glowDamping: 0.5,
              ),
              Spring(LyricCurves.dotOpacity.at(0), frequency: 1, damping: 0.5),
            ),
        ];
      case PreparedKind.line:
      case PreparedKind.staticText:
        break;
    }

    final CssTransition opacity;
    switch (line.kind) {
      case PreparedKind.interlude:
        opacity = CssTransition(0,
            duration: LyricCurves.interludeOpacityDuration,
            easing: Easing.ease);
      case PreparedKind.line:
        opacity = CssTransition(LyricCurves.notSungOpacity,
            duration: LyricCurves.lineSyncedDuration,
            easing: LyricCurves.lineSyncedEasing);
      case PreparedKind.syllable:
      case PreparedKind.staticText:
        opacity = CssTransition(LyricCurves.notSungOpacity,
            duration: LyricCurves.lineOpacityDuration,
            easing: LyricCurves.lineOpacityEasing);
    }

    return _LineSprings(
      opacity: opacity,
      scale: CssTransition(1,
          duration: LyricCurves.lineSyncedDuration,
          easing: LyricCurves.lineSyncedEasing),
      glow: Spring(0, frequency: 1, damping: 0.5),
      lead: lead,
      background: background,
      dots: dots,
    );
  }

  static LineVisual _makeVisual(PreparedLine line) {
    List<List<SyllableVisual>> syllableVisuals(List<PreparedWord> words) {
      return [
        for (final word in words)
          [
            for (final syllable in word.syllables)
              SyllableVisual(
                GlyphVisual(
                  scale: LyricCurves.scale.at(0),
                  yOffset: LyricCurves.yOffset.at(0),
                  glow: 0,
                  gradient: -0.2,
                ),
                [
                  for (final _ in syllable.letters ?? const <PreparedLetter>[])
                    GlyphVisual(
                      scale: LyricCurves.letterScale.at(0),
                      yOffset: LyricCurves.letterYOffset.at(0) * 2,
                      glow: 0,
                      gradient: -0.2,
                    ),
                ],
              ),
          ],
      ];
    }

    final visual = LineVisual();
    switch (line.kind) {
      case PreparedKind.syllable:
        visual.lead = syllableVisuals(line.lead);
        visual.background = syllableVisuals(line.background);
      case PreparedKind.interlude:
        visual.dots = [
          for (final _ in line.dots)
            GlyphVisual(
              scale: LyricCurves.dotScale.at(0),
              yOffset: 0,
              glow: 0,
              gradient: 1,
              opacity: LyricCurves.dotOpacity.at(0),
            ),
        ];
        visual.presence = 0;
        visual.opacity = 0;
      case PreparedKind.staticText:
        visual.opacity = 1;
        visual.line.gradient = 1;
      case PreparedKind.line:
        break;
    }
    return visual;
  }
}
