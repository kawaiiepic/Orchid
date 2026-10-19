import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/lyrics_service.dart';

class KaraokeLyrics extends StatefulWidget {
  final AudioPlayer player;
  final LyricsResult? lyrics;
  final bool loading;

  const KaraokeLyrics({
    super.key,
    required this.player,
    required this.lyrics,
    this.loading = false,
  });

  @override
  State<KaraokeLyrics> createState() => _KaraokeLyricsState();
}

class _KaraokeLyricsState extends State<KaraokeLyrics> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};

  bool _userScrolling = false;
  bool _follow = true;
  int _lastActive = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  void _onUserScrollStart() {
    _userScrolling = true;
    _follow = false;
  }

  void _onUserScrollEnd() {
    _userScrolling = false;
  }

  void _maybeFollow(int activeIdx, bool playing) {
    if (!playing) {
      _follow = false;
      return;
    }
    if (_userScrolling) return;

    if (!_follow && playing) {
      _follow = true;
    }
    if (!_follow || activeIdx < 0) return;
    if (activeIdx == _lastActive) return;
    _lastActive = activeIdx;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ctx = _keyFor(activeIdx).currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: Text('Loading lyrics…'));
    }
    final result = widget.lyrics;
    if (result == null || !result.hasAny) {
      return const Center(child: Text('No lyrics found.'));
    }

    if (result.lines.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: SingleChildScrollView(child: Text(result.displayText))),
          const SizedBox(height: 8),
          _AttributionBar(result: result),
        ],
      );
    }

    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      initialData: widget.player.position,
      builder: (context, snap) {
        final t = (snap.data ?? Duration.zero).inMilliseconds / 1000.0;
        final playing = widget.player.playing;
        final activeIdx = result.lineIndexAt(t);

        if (activeIdx >= 0 && playing) {
          _maybeFollow(activeIdx, playing);
        } else if (!playing) {
          _follow = false;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollStartNotification && n.dragDetails != null) {
                    _onUserScrollStart();
                  } else if (n is ScrollEndNotification) {
                    _onUserScrollEnd();
                    if (widget.player.playing) {
                      Future.delayed(const Duration(milliseconds: 1200), () {
                        if (mounted &&
                            widget.player.playing &&
                            !_userScrolling) {
                          setState(() => _follow = true);
                        }
                      });
                    }
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  itemCount: result.lines.length,
                  itemBuilder: (context, i) {
                    final line = result.lines[i];
                    final isActive = i == activeIdx;
                    final isPast = activeIdx >= 0 && i < activeIdx;
                    return KeyedSubtree(
                      key: _keyFor(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 4,
                        ),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          opacity: isActive ? 1 : (isPast ? 0.66 : 0.46),
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 340),
                            curve: Curves.easeOutCubic,
                            scale: isActive ? 1.015 : 1,
                            child: _LyricLineView(
                              line: line,
                              t: t,
                              isActiveLine: isActive,
                              isPast: isPast,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            _AttributionBar(result: result),
          ],
        );
      },
    );
  }
}

class _LyricLineView extends StatelessWidget {
  final LyricLine line;
  final double t;
  final bool isActiveLine;
  final bool isPast;

  const _LyricLineView({
    required this.line,
    required this.t,
    required this.isActiveLine,
    required this.isPast,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!line.hasSyllables) {
      final color =
          isActiveLine ? scheme.foreground : scheme.mutedForeground;
      return Text(
        line.text,
        textAlign:
            line.oppositeAligned ? TextAlign.right : TextAlign.center,
        style: TextStyle(
          fontSize: isActiveLine ? 20 : 15,
          fontWeight: isActiveLine ? FontWeight.w600 : FontWeight.w400,
          color: color,
        ),
      );
    }

    final activeSyl = isActiveLine ? line.activeLeadIndex(t) : -1;

    return Column(
      crossAxisAlignment: line.oppositeAligned
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.center,
      children: [
        Wrap(
          alignment: line.oppositeAligned
              ? WrapAlignment.end
              : WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < line.lead.length; i++)
              _SyllableChip(
                syllable: line.lead[i],
                t: t,
                isActive: i == activeSyl,
                isPast: isPast ||
                    (isActiveLine && activeSyl >= 0 && i < activeSyl),
                isActiveLine: isActiveLine,
                compact: false,
              ),
          ],
        ),
        if (line.background.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (final s in line.background)
                _SyllableChip(
                  syllable: s,
                  t: t,
                  isActive: s.activeAt(t),
                  isPast: t >= s.end,
                  isActiveLine: isActiveLine,
                  compact: true,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SyllableChip extends StatelessWidget {
  final LyricSyllable syllable;
  final double t;
  final bool isActive;
  final bool isPast;
  final bool isActiveLine;
  final bool compact;

  const _SyllableChip({
    required this.syllable,
    required this.t,
    required this.isActive,
    required this.isPast,
    required this.isActiveLine,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = (syllable.end - syllable.start).clamp(0.001, 60.0);
    final progress = ((t - syllable.start) / duration).clamp(0.0, 1.0);

    // Sweet Lyrics keeps typography consistent and animates the glyph itself.
    // Past syllables are fully lit, future syllables are dim, and the active
    // syllable uses a left-to-right fill that follows playback continuously.
    final fillPosition = isPast ? 1.0 : (isActive ? progress : -0.2);
    final fadeEnd = fillPosition + 0.2;
    final begin = Alignment((fillPosition * 2) - 1, 0);
    final finish = Alignment((fadeEnd * 2) - 1, 0);

    final glow = isActive
        ? (progress < 0.15
            ? progress / 0.15
            : progress < 0.6
                ? 1.0
                : (1.0 - progress) / 0.4)
        : 0.0;
    final scale = isActive
        ? (progress < 0.7
            ? 0.95 + (progress / 0.7) * 0.1005
            : 1.0505 - ((progress - 0.7) / 0.3) * 0.0505)
        : 1.0;
    final y = isActive
        ? (progress < 0.9
            ? 0.01 + (progress / 0.9) * (-0.0267)
            : -0.0167 + ((progress - 0.9) / 0.1) * 0.0167)
        : 0.0;
    final needsSpace = !syllable.isPartOfWord;
    final fontSize = compact ? 16.0 : 22.0;
    final alphaLit = compact ? 0.6 : 0.85;
    final alphaUnlit = compact ? 0.3 : 0.5;

    return Transform.translate(
      offset: Offset(0, -y * fontSize),
      child: Transform.scale(
        scale: compact ? 1 : scale,
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: begin,
            end: finish,
            colors: [
              scheme.foreground.withOpacity(alphaLit),
              scheme.foreground.withOpacity(alphaUnlit),
            ],
          ).createShader(bounds),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: compact ? FontWeight.w600 : FontWeight.w700,
              color: scheme.foreground,
              height: 1.25,
              shadows: !compact && isActive && glow > 0.004
                  ? [
                      Shadow(
                        color: scheme.foreground.withOpacity(glow * 0.35),
                        blurRadius: 3 + glow,
                      ),
                    ]
                  : const [],
            ),
            child: Text(needsSpace ? '${syllable.text} ' : syllable.text),
          ),
        ),
      ),
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
    final parts = <InlineSpan>[];

    parts.add(TextSpan(
      text: result.providerLabel,
      style: TextStyle(fontSize: 11, color: scheme.mutedForeground),
    ));

    if (result.isCommunity) {
      if (result.uploader != null) {
        parts.add(TextSpan(
          text: ' · uploaded by ',
          style: TextStyle(fontSize: 11, color: scheme.mutedForeground),
        ));
        parts.add(TextSpan(
          text: result.uploader!.username,
          style: TextStyle(
            fontSize: 11,
            color: scheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _open(result.uploader!.url),
        ));
      }
      if (result.maker != null) {
        parts.add(TextSpan(
          text: ' · made by ',
          style: TextStyle(fontSize: 11, color: scheme.mutedForeground),
        ));
        parts.add(TextSpan(
          text: result.maker!.username,
          style: TextStyle(
            fontSize: 11,
            color: scheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _open(result.maker!.url),
        ));
      }
    }

    if (result.sourceVia != null) {
      parts.add(TextSpan(
        text: ' · via ${result.sourceVia}',
        style: TextStyle(fontSize: 11, color: scheme.mutedForeground),
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text.rich(
        TextSpan(children: parts),
        textAlign: TextAlign.center,
      ),
    );
  }
}
