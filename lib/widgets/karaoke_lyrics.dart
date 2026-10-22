import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/lyrics_appearance.dart';
import '../services/lyrics_service.dart';
import 'lyrics_spring.dart';

class _Spline {
  final List<double> xs;
  final List<double> ys;
  final List<double> ks;
  _Spline(List<(double, double)> points)
      : xs = points.map((p) => p.$1).toList(),
        ys = points.map((p) => p.$2).toList(),
        ks = _derivatives(points.map((p) => p.$1).toList(), points.map((p) => p.$2).toList());
  double at(double x) {
    if (xs.length <= 1) return ys.isEmpty ? 0 : ys.first;
    var i = 1;
    while (i < xs.length - 1 && xs[i] < x) {
      i++;
    }
    final x0 = xs[i - 1], x1 = xs[i];
    final y0 = ys[i - 1], y1 = ys[i];
    final h = x1 - x0;
    if (h == 0) return y0;
    final t = ((x - x0) / h).clamp(0.0, 1.0);
    final a = ks[i - 1] * h - (y1 - y0);
    final b = -ks[i] * h + (y1 - y0);
    return (1 - t) * y0 + t * y1 + t * (1 - t) * (a * (1 - t) + b * t);
  }

  static List<double> _derivatives(List<double> xs, List<double> ys) {
    final n = xs.length;
    if (n <= 1) return List.filled(n, 0);
    final a = List.filled(n, 0.0);
    final b = List.filled(n, 0.0);
    final c = List.filled(n, 0.0);
    final r = List.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      if (i == 0) {
        final h = xs[1] - xs[0];
        b[i] = 2 / h; c[i] = 1 / h; r[i] = 3 * (ys[1] - ys[0]) / (h * h);
      } else if (i == n - 1) {
        final h = xs[i] - xs[i - 1];
        a[i] = 1 / h; b[i] = 2 / h; r[i] = 3 * (ys[i] - ys[i - 1]) / (h * h);
      } else {
        final h0 = xs[i] - xs[i - 1];
        final h1 = xs[i + 1] - xs[i];
        a[i] = 1 / h0; b[i] = 2 * (1 / h0 + 1 / h1); c[i] = 1 / h1;
        r[i] = 3 * ((ys[i] - ys[i - 1]) / (h0 * h0) + (ys[i + 1] - ys[i]) / (h1 * h1));
      }
    }
    for (var i = 1; i < n; i++) {
      final m = a[i] / b[i - 1];
      b[i] -= m * c[i - 1];
      r[i] -= m * r[i - 1];
    }
    final k = List.filled(n, 0.0);
    k[n - 1] = r[n - 1] / b[n - 1];
    for (var i = n - 2; i >= 0; i--) {
      k[i] = (r[i] - c[i] * k[i + 1]) / b[i];
    }
    return k;
  }
}

class _Curves {
  static final scale = _Spline([(0, 0.92), (0.55, 1.18), (1, 1.02)]);
  static final yOffset = _Spline([(0, 1.0 / 100), (0.9, -(1.0 / 50)), (1, 0)]);
  static final glow = _Spline([(0, 0), (0.12, 1), (0.55, 1), (1, 0)]);
  static final letterScale = _Spline([(0, 0.9), (0.55, 1.32), (1, 1.04)]);
  static final letterYOffset = _Spline([(0, 1.0 / 100), (0.9, -(1.0 / 48)), (1, 0)]);
  static final lineGlow = _Spline([(0, 0), (0.5, 1), (1, 0)]);
  static final dotScale = _Spline([(0, 0.75), (0.7, 1.05), (1, 1)]);
  static final dotYOffset = _Spline([(0, 0), (0.9, -0.12), (1, 0)]);
  static final dotGlow = _Spline([(0, 0), (0.6, 1), (1, 1)]);
  static final dotOpacity = _Spline([(0, 0.35), (0.6, 1), (1, 1)]);
  static final simpleYOffset = _Spline([(0, 1.0 / 100), (1, -0.033)]);
  static const notSungOpacity = 0.51;
  static const activeOpacity = 1.0;
  static const sungOpacity = 0.497;
  static const blurMultiplier = 0.35;
  static double get maxBlur => 1.8;
  static const leadLit = 0.85;
  static const leadUnlit = 0.5;
  static const bgLit = 0.6;
  static const bgUnlit = 0.3;
  static const simpleLeadLit = 1.0;
  static const simpleLeadUnlit = 0.3;
  static const fillFade = 0.2;
  static const simpleFillFade = 0.5;
  static const preHiddenDots = 0.5;
  static const emphasizeEndSub = 0.25;
  static const activeLineScale = 1.12;
}

double _progress(double t, double start, double end) {
  if (t <= start) return 0;
  if (t >= end) return 1;
  final d = end - start;
  if (d <= 0) return 1;
  return ((t - start) / d).clamp(0.0, 1.0);
}

enum _SylState { notSung, active, sung }

_SylState _state(double t, double start, double end) {
  if (t < start) return _SylState.notSung;
  if (t >= end) return _SylState.sung;
  return _SylState.active;
}

class KaraokeLyrics extends StatefulWidget {
  final AudioPlayer player;
  final LyricsResult? lyrics;
  final bool loading;
  const KaraokeLyrics({super.key, required this.player, required this.lyrics, this.loading = false});
  @override
  State<KaraokeLyrics> createState() => _KaraokeLyricsState();
}

class _KaraokeLyricsState extends State<KaraokeLyrics> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  final _appearance = LyricsAppearance.instance;
  bool _userScrolling = false;
  int _lastActive = -1;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _lastDt = 1 / 60;
  double _pinchScale = 1.0;
  double _basePinch = 1.0;
  double _frameTime = 1 / 60;
  double _presentationLead = 0;
  String? _copyHint;

  @override
  void initState() {
    super.initState();
    _appearance.load();
    _appearance.addListener(_onAppearance);
    _ticker = createTicker(_onTick)..start();
  }

  void _onAppearance() { if (mounted) setState(() {}); }

  void _onTick(Duration elapsed) {
    final rawDt = _lastTick == Duration.zero ? 1 / 60 : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final dt = rawDt.clamp(0.0, 0.25);
    _lastDt = dt;
    const expected = 1 / 60;
    if (dt > 0.006 && dt < 0.4) {
      _frameTime += (dt - _frameTime) * (dt > _frameTime ? 0.3 : 0.08);
      _presentationLead = (1.5 * (_frameTime - expected * 1.1)).clamp(0.0, 0.15);
    }
    if (mounted && (widget.player.playing || dt < 0.2)) setState(() {});
  }

  @override
  void dispose() {
    _appearance.removeListener(_onAppearance);
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  void _maybeFollow(int activeIdx, bool playing) {
    if (!playing || _userScrolling) return;
    if (activeIdx < 0 || activeIdx == _lastActive) return;
    _lastActive = activeIdx;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ctx = _keyFor(activeIdx).currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic, alignment: 0.35);
    });
  }

  Future<void> _seekTo(double seconds) async {
    await widget.player.seek(Duration(milliseconds: (seconds * 1000).round()));
  }

  Future<void> _copyLine(String text) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    setState(() => _copyHint = 'Copied');
    Future.delayed(const Duration(seconds: 1), () { if (mounted) setState(() => _copyHint = null); });
  }

  Future<void> _shareOrCopyLine(String text) async {
    if (text.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    try {
      await Share.share(text.trim());
      if (mounted) setState(() => _copyHint = 'Shared');
    } catch (_) {
      await _copyLine(text);
      return;
    }
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _copyHint = null);
    });
  }

  Widget _maybeBlur(double blur, Widget child) {
    if (blur <= 0.05) return child;
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: blur * 0.35, sigmaY: blur * 0.35),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const Center(child: Text('Loading lyrics…'));
    final result = widget.lyrics;
    if (result == null || !result.hasAny) return const Center(child: Text('No lyrics found.'));
    if (result.lines.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: SingleChildScrollView(child: Text(result.displayText))),
        const SizedBox(height: 8),
        _AttributionBar(result: result),
      ]);
    }

    final a = _appearance;
    final hasDuets = result.lines.any((l) => l.oppositeAligned);
    final mediaT = widget.player.position.inMilliseconds / 1000.0;
    final t = mediaT + _presentationLead;
    final playing = widget.player.playing;
    final focusIdx = result.lineIndexAt(t);
    final fontSize = a.fontSize * _pinchScale;
    if (focusIdx >= 0 && playing) _maybeFollow(focusIdx, playing);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_copyHint != null)
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(_copyHint!).xSmall().muted().center()),
      Expanded(
        child: GestureDetector(
          onScaleStart: (_) => _basePinch = _pinchScale,
          onScaleUpdate: (d) {
            if (d.pointerCount >= 2) setState(() => _pinchScale = (_basePinch * d.scale).clamp(0.7, 2.2));
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _userScrolling = true;
              } else if (n is ScrollEndNotification) _userScrolling = false;
              return false;
            },
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 28),
              addAutomaticKeepAlives: true,
              itemCount: result.lines.length,
              itemBuilder: (context, i) {
                final line = result.lines[i];
                final isFocus = i == focusIdx;
                final distance = focusIdx < 0 ? 0 : (i - focusIdx).abs();
                final lineState = _state(t, line.start, line.end);
                final effectiveState = isFocus && lineState == _SylState.sung
                    ? (focusIdx < result.lines.length - 1 && t < result.lines[focusIdx + 1].start
                        ? _SylState.active
                        : lineState)
                    : (isFocus && lineState == _SylState.notSung && t >= line.start
                        ? _SylState.active
                        : lineState);

                if (line.isInterlude) {
                  final active = line.activeAt(t);
                  final preHidden = t > line.end - _Curves.preHiddenDots;
                  return KeyedSubtree(
                    key: _keyFor(i),
                    child: IgnorePointer(
                      ignoring: !active,
                      child: Opacity(
                        opacity: (active || distance <= 1) ? 1 : 0,
                        child: _InterludeDots(
                          dots: line.interludeDots, t: t, active: active && !preHidden,
                          dt: _lastDt, simple: a.simpleMode, glowScale: a.glowScale,
                        ),
                      ),
                    ),
                  );
                }

                double opacity;
                switch (effectiveState) {
                  case _SylState.notSung: opacity = _Curves.notSungOpacity;
                  case _SylState.active: opacity = _Curves.activeOpacity;
                  case _SylState.sung: opacity = _Curves.sungOpacity;
                }
                opacity = (1 - (1 - opacity) * (2 - a.inactiveBrightness)).clamp(0.05, 1.0);

                final blur = (a.blurEnabled && !isFocus && distance > 1)
                    ? math.min(_Curves.blurMultiplier * (distance - 1), _Curves.maxBlur) * a.blurScale
                    : 0.0;

                final cqw = fontSize * 0.18;
                EdgeInsets insets;
                if (a.centered) {
                  insets = EdgeInsets.symmetric(horizontal: cqw * 5);
                } else if (hasDuets) {
                  insets = line.oppositeAligned
                      ? EdgeInsets.only(left: cqw * 15)
                      : EdgeInsets.only(right: cqw * 15);
                } else {
                  insets = EdgeInsets.only(right: cqw * 5);
                }

                return KeyedSubtree(
                  key: _keyFor(i),
                  child: RepaintBoundary(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6 * a.lineSpacingScale).add(insets),
                      child: GestureDetector(
                        onTap: () => _seekTo(line.start),
                        onLongPress: () => _shareOrCopyLine(line.text),
                        child: Opacity(
                          opacity: opacity,
                          child: _maybeBlur(
                            blur,
                            _LyricLineView(
                              line: line, t: t, dt: _lastDt,
                              isActiveLine: isFocus && effectiveState == _SylState.active,
                              isPast: effectiveState == _SylState.sung || (focusIdx >= 0 && i < focusIdx),
                              fontSize: fontSize, appearance: a,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      _AttributionBar(result: result),
    ]);
  }
}

class _InterludeDots extends StatefulWidget {
  final List<LyricSyllable> dots;
  final double t;
  final bool active;
  final double dt;
  final bool simple;
  final double glowScale;
  const _InterludeDots({required this.dots, required this.t, required this.active, required this.dt, required this.simple, required this.glowScale});
  @override
  State<_InterludeDots> createState() => _InterludeDotsState();
}

class _InterludeDotsState extends State<_InterludeDots> {
  final _springs = <GlyphSprings>[];
  double _groupScale = 0;
  @override
  Widget build(BuildContext context) {
    while (_springs.length < widget.dots.length) {
      _springs.add(GlyphSprings());
    }
    final targetGroup = widget.active ? 1.0 : 0.0;
    _groupScale += (targetGroup - _groupScale) * (1 - math.exp(-widget.dt / (widget.active ? 0.3 : 0.4)));
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: _groupScale.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.85 + 0.15 * _groupScale,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.dots.length; i++)
                Builder(builder: (_) {
                  final d = widget.dots[i];
                  final st = _state(widget.t, d.start, d.end);
                  final p = switch (st) {
                    _SylState.notSung => 0.0,
                    _SylState.sung => 1.0,
                    _SylState.active => _progress(widget.t, d.start, d.end),
                  };
                  final (sc, y, gl) = widget.simple
                      ? (1.0, 0.0, 0.0)
                      : _springs[i].step(scaleGoal: _Curves.dotScale.at(p), yGoal: _Curves.dotYOffset.at(p), glowGoal: _Curves.dotGlow.at(p), dt: widget.dt);
                  final op = _Curves.dotOpacity.at(p);
                  return Transform.translate(
                    offset: Offset(0, -y * 22),
                    child: Transform.scale(
                      scale: sc,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('•', style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700,
                          color: scheme.foreground.withValues(alpha: op),
                          shadows: gl * widget.glowScale > 0.05
                              ? [Shadow(color: scheme.foreground.withValues(alpha: gl * 0.9 * widget.glowScale), blurRadius: (4 + 6 * gl) / 2)]
                              : null,
                        )),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

enum _GlowKind { syllable, letter, line }

class _LyricLineView extends StatelessWidget {
  final LyricLine line;
  final double t;
  final double dt;
  final bool isActiveLine;
  final bool isPast;
  final double fontSize;
  final LyricsAppearance appearance;
  const _LyricLineView({required this.line, required this.t, required this.dt, required this.isActiveLine, required this.isPast, required this.fontSize, required this.appearance});

  @override
  Widget build(BuildContext context) {
    final centered = appearance.centered;
    final align = centered ? CrossAxisAlignment.center : (line.oppositeAligned ? CrossAxisAlignment.end : CrossAxisAlignment.start);
    final wrapAlign = centered ? WrapAlignment.center : (line.oppositeAligned ? WrapAlignment.end : WrapAlignment.start);

    Widget body;
    if (!line.hasSyllables) {
      final p = isPast ? 1.0 : (isActiveLine ? _progress(t, line.start, line.end) : 0.0);
      final gradient = isPast ? 1.0 : (isActiveLine ? p : -0.2);
      final glow = appearance.simpleMode ? 0.0 : (isActiveLine ? _Curves.lineGlow.at(p) : 0.0) * appearance.glowScale;
      final scale = isActiveLine ? _Curves.activeLineScale : 1.0;
      body = AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: centered ? Alignment.center : (line.oppositeAligned ? Alignment.centerRight : Alignment.centerLeft),
        child: _FilledText(
          text: line.text, fontSize: fontSize, fontWeight: appearance.weight, gradient: gradient,
          lit: appearance.simpleMode ? _Curves.simpleLeadLit : _Curves.leadLit,
          unlit: appearance.simpleMode ? _Curves.simpleLeadUnlit : _Curves.leadUnlit,
          fade: appearance.simpleMode ? _Curves.simpleFillFade : _Curves.fillFade,
          glow: glow, glowKind: _GlowKind.line,
          textAlign: centered ? TextAlign.center : (line.oppositeAligned ? TextAlign.right : TextAlign.left),
        ),
      );
    } else {
      final activeSyl = isActiveLine ? line.activeLeadIndex(t) : -1;
      body = Column(crossAxisAlignment: align, children: [
        Wrap(alignment: wrapAlign, crossAxisAlignment: WrapCrossAlignment.center, spacing: fontSize * 0.6 * 0.32, children: [
          for (var i = 0; i < line.lead.length; i++)
            _SyllableGlyph(
              key: ValueKey('L${line.start}_$i'),
              syllable: line.lead[i], t: t, dt: dt,
              forceActive: i == activeSyl && isActiveLine,
              forcePast: isPast || (isActiveLine && activeSyl >= 0 && i < activeSyl),
              compact: false,
              nextStart: i + 1 < line.lead.length ? line.lead[i + 1].start : null,
              fontSize: fontSize, appearance: appearance,
            ),
        ]),
        if (line.background.isNotEmpty) ...[
          const SizedBox(height: 2),
          Wrap(alignment: wrapAlign, spacing: fontSize * 0.45 * 0.32, children: [
            for (var i = 0; i < line.background.length; i++)
              _SyllableGlyph(
                key: ValueKey('B${line.start}_$i'),
                syllable: line.background[i], t: t, dt: dt,
                forceActive: line.background[i].timedAt(t),
                forcePast: t >= line.background[i].end,
                compact: true,
                nextStart: i + 1 < line.background.length ? line.background[i + 1].start : null,
                fontSize: fontSize * 0.75, appearance: appearance,
              ),
          ]),
        ],
      ]);
    }

    final translation = appearance.showTranslations ? line.translatedText : null;
    return Column(crossAxisAlignment: align, children: [
      body,
      if (translation != null && translation.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(translation,
            textAlign: centered ? TextAlign.center : (line.oppositeAligned ? TextAlign.right : TextAlign.left),
            style: TextStyle(fontSize: fontSize * 0.55 * appearance.translationScale, fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.foreground.withValues(alpha: 0.55)),
          ),
        ),
    ]);
  }
}

class _SyllableGlyph extends StatefulWidget {
  final LyricSyllable syllable;
  final double t;
  final double dt;
  final bool forceActive;
  final bool forcePast;
  final bool compact;
  final double? nextStart;
  final double fontSize;
  final LyricsAppearance appearance;
  const _SyllableGlyph({super.key, required this.syllable, required this.t, required this.dt, required this.forceActive, required this.forcePast, required this.compact, this.nextStart, required this.fontSize, required this.appearance});
  @override
  State<_SyllableGlyph> createState() => _SyllableGlyphState();
}

class _SyllableGlyphState extends State<_SyllableGlyph> {
  final _springs = GlyphSprings();
  @override
  Widget build(BuildContext context) {
    final syllable = widget.syllable;
    final t = widget.t;
    final simple = widget.appearance.simpleMode;
    final effectiveEnd = widget.nextStart != null ? math.max(syllable.end, widget.nextStart!) : syllable.end;
    final st = widget.forcePast ? _SylState.sung : (widget.forceActive ? _SylState.active : _state(t, syllable.start, effectiveEnd));
    final p = switch (st) {
      _SylState.notSung => 0.0,
      _SylState.sung => 1.0,
      _SylState.active => _progress(t, syllable.start, syllable.end),
    };
    final unlitEdge = simple ? -0.5 : -0.2;
    final gradient = switch (st) {
      _SylState.notSung => unlitEdge,
      _SylState.sung => 1.0,
      _SylState.active => unlitEdge + 1.2 * p,
    };
    double scaleGoal, yGoal, glowGoal;
    if (simple) {
      scaleGoal = 1; yGoal = st == _SylState.notSung ? 0 : _Curves.simpleYOffset.at(p); glowGoal = 0;
    } else {
      scaleGoal = st == _SylState.notSung ? 1.0 : _Curves.scale.at(p);
      yGoal = st == _SylState.notSung ? 0.0 : _Curves.yOffset.at(p);
      glowGoal = st == _SylState.notSung ? 0.0 : _Curves.glow.at(p);
    }
    final (scale, y, glowRaw) = _springs.step(scaleGoal: scaleGoal, yGoal: yGoal, glowGoal: glowGoal, dt: widget.dt);
    final glow = glowRaw * widget.appearance.glowScale;
    final fontSize = widget.fontSize;
    final lit = widget.compact ? _Curves.bgLit : (simple ? _Curves.simpleLeadLit : _Curves.leadLit);
    final unlit = widget.compact ? _Curves.bgUnlit : (simple ? _Curves.simpleLeadUnlit : _Curves.leadUnlit);
    final fade = simple ? _Curves.simpleFillFade : _Curves.fillFade;
    final emphasize = !widget.compact && !simple && (syllable.end - syllable.start) >= 1.0 && syllable.text.runes.length > 1 && st == _SylState.active;
    final displayText = widget.appearance.showTransliteration && syllable.transliteratedText != null && syllable.transliteratedText!.isNotEmpty
        ? syllable.transliteratedText! : syllable.text;
    final display = !syllable.isPartOfWord ? '$displayText ' : displayText;
    if (emphasize) {
      final emphEnd = math.max(syllable.start + 0.05, syllable.end - _Curves.emphasizeEndSub);
      return _EmphasizedWord(text: display, t: t, start: syllable.start, end: emphEnd, fontSize: fontSize, lit: lit, unlit: unlit, glowScale: widget.appearance.glowScale, weight: widget.appearance.weight);
    }
    return Transform.translate(
      offset: Offset(0, -y * fontSize),
      child: Transform.scale(
        scale: scale, filterQuality: FilterQuality.medium,
        child: _FilledText(text: display, fontSize: fontSize, fontWeight: widget.compact ? FontWeight.w600 : widget.appearance.weight, gradient: gradient, lit: lit, unlit: unlit, fade: fade, glow: glow, glowKind: _GlowKind.syllable),
      ),
    );
  }
}

class _EmphasizedWord extends StatelessWidget {
  final String text; final double t; final double start; final double end; final double fontSize; final double lit; final double unlit; final double glowScale; final FontWeight weight;
  const _EmphasizedWord({required this.text, required this.t, required this.start, required this.end, required this.fontSize, required this.lit, required this.unlit, required this.glowScale, required this.weight});
  @override
  Widget build(BuildContext context) {
    final chars = text.characters.toList();
    if (chars.isEmpty) return const SizedBox.shrink();
    final dur = (end - start).clamp(0.001, 60.0);
    final letterDur = dur / chars.length;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < chars.length; i++)
        Builder(builder: (context) {
          final ls = start + i * letterDur;
          final le = ls + letterDur;
          final st = _state(t, ls, le);
          var activeLetter = -1;
          var activeP = 0.0;
          for (var j = 0; j < chars.length; j++) {
            final a = start + j * letterDur;
            final b = a + letterDur;
            if (t >= a && t < b) { activeLetter = j; activeP = _progress(t, a, b); break; }
          }
          final restScale = _Curves.letterScale.at(0);
          final restY = _Curves.letterYOffset.at(0);
          final restGlow = _Curves.glow.at(0);
          double targetScale = restScale, targetY = restY, targetGlow = restGlow, gradient;
          if (t < start) {
            gradient = -0.2;
          } else if (t >= end) {
            targetScale = _Curves.letterScale.at(1); targetY = _Curves.letterYOffset.at(1); targetGlow = _Curves.glow.at(1); gradient = 1;
          } else if (activeLetter >= 0) {
            final baseScale = _Curves.letterScale.at(activeP);
            final baseY = _Curves.letterYOffset.at(activeP);
            final baseGlow = _Curves.glow.at(activeP);
            final d = (i - activeLetter).abs().toDouble();
            final falloff = math.max(0.0, 1 / (1 + math.pow(d, 2.8)));
            final glowFalloff = math.max(0.0, 1 / (1 + d * 0.9));
            targetScale = restScale + (baseScale - restScale) * falloff;
            targetY = restY + (baseY - restY) * falloff;
            targetGlow = restGlow + (baseGlow - restGlow) * glowFalloff;
            if (st == _SylState.active && i == activeLetter) {
              gradient = -0.2 + 1.2 * math.sin(activeP * math.pi / 2);
            } else if (st == _SylState.sung) gradient = 1;
            else gradient = -0.2;
          } else {
            gradient = st == _SylState.sung ? 1.0 : -0.2;
          }
          return Transform.translate(
            offset: Offset(0, -targetY * fontSize),
            child: Transform.scale(
              scale: targetScale, filterQuality: FilterQuality.medium,
              child: _FilledText(text: chars[i], fontSize: fontSize, fontWeight: weight, gradient: gradient, lit: lit, unlit: unlit, fade: _Curves.fillFade, glow: targetGlow * glowScale, glowKind: _GlowKind.letter),
            ),
          );
        }),
    ]);
  }
}

class _FilledText extends StatelessWidget {
  final String text; final double fontSize; final FontWeight fontWeight; final double gradient; final double lit; final double unlit; final double fade; final double glow; final _GlowKind glowKind; final TextAlign textAlign;
  const _FilledText({required this.text, required this.fontSize, required this.fontWeight, required this.gradient, required this.lit, required this.unlit, required this.fade, required this.glow, required this.glowKind, this.textAlign = TextAlign.left});
  double _glowRadius() => switch (glowKind) { _GlowKind.syllable => (4 + 2 * glow) / 2, _GlowKind.letter => (4 + 12 * glow) / 2, _GlowKind.line => (4 + 8 * glow) / 2 };
  double _glowOpacity() {
    final v = switch (glowKind) { _GlowKind.syllable => glow * 0.35, _GlowKind.letter => glow * 1.85, _GlowKind.line => glow * 0.5 };
    return v.clamp(0.0, 1.0);
  }
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fillPos = gradient.clamp(-0.5, 1.2);
    final begin = Alignment(fillPos * 2 - 1, 0);
    final end = Alignment((fillPos + fade) * 2 - 1, 0);
    final gOpacity = _glowOpacity();
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(begin: begin, end: end, colors: [scheme.foreground.withValues(alpha: lit), scheme.foreground.withValues(alpha: unlit)]).createShader(bounds),
      child: Text(text, textAlign: textAlign, style: TextStyle(
        fontSize: fontSize, fontWeight: fontWeight, color: scheme.foreground, height: 1.25,
        shadows: gOpacity > 0.004 ? [Shadow(color: scheme.foreground.withValues(alpha: gOpacity), blurRadius: _glowRadius())] : const [],
      )),
    );
  }
}

class _AttributionBar extends StatelessWidget {
  final LyricsResult result;
  const _AttributionBar({required this.result});
  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = <InlineSpan>[TextSpan(text: result.providerLabel, style: TextStyle(fontSize: 11, color: scheme.mutedForeground))];
    if (result.isCommunity) {
      if (result.uploader != null) {
        parts.add(TextSpan(text: ' · uploaded by ', style: TextStyle(fontSize: 11, color: scheme.mutedForeground)));
        parts.add(TextSpan(text: result.uploader!.username, style: TextStyle(fontSize: 11, color: scheme.primary, decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = () => _open(result.uploader!.url)));
      }
      if (result.maker != null) {
        parts.add(TextSpan(text: ' · made by ', style: TextStyle(fontSize: 11, color: scheme.mutedForeground)));
        parts.add(TextSpan(text: result.maker!.username, style: TextStyle(fontSize: 11, color: scheme.primary, decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = () => _open(result.maker!.url)));
      }
    }
    if (result.sourceVia != null) {
      parts.add(TextSpan(text: ' · via ${result.sourceVia}', style: TextStyle(fontSize: 11, color: scheme.mutedForeground)));
    }
    return Padding(padding: const EdgeInsets.only(top: 4, bottom: 4), child: Text.rich(TextSpan(children: parts), textAlign: TextAlign.center));
  }
}
