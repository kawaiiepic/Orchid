import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show
        Curves,
        FontWeight,
        TextStyle,
        TextAlign,
        TextSpan,
        TextDecoration,
        Scrollable;
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
      return const Center(child: Text('Loading lyrics…').muted());
    }
    final result = widget.lyrics;
    if (result == null || !result.hasAny) {
      return const Center(child: Text('No lyrics found.').muted());
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
                        child: _LyricLineView(
                          line: line,
                          t: t,
                          isActiveLine: isActive,
                          isPast: isPast,
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
  final bool isActive;
  final bool isPast;
  final bool isActiveLine;
  final bool compact;

  const _SyllableChip({
    required this.syllable,
    required this.isActive,
    required this.isPast,
    required this.isActiveLine,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    late final Color color;
    late final FontWeight weight;
    late final double size;

    if (compact) {
      size = 12;
      weight = isActive ? FontWeight.w600 : FontWeight.w400;
      color = isActive
          ? scheme.primary
          : scheme.mutedForeground.withOpacity(isPast ? 0.7 : 0.45);
    } else if (isActive) {
      size = isActiveLine ? 22 : 16;
      weight = FontWeight.w700;
      color = scheme.primary;
    } else if (isPast) {
      size = isActiveLine ? 18 : 14;
      weight = FontWeight.w500;
      color = scheme.mutedForeground;
    } else {
      size = isActiveLine ? 18 : 14;
      weight = FontWeight.w400;
      color = isActiveLine
          ? scheme.foreground.withOpacity(0.4)
          : scheme.mutedForeground.withOpacity(0.45);
    }

    final needsSpace = !syllable.isPartOfWord;

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 70),
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.25,
      ),
      child: Text(needsSpace ? '${syllable.text} ' : syllable.text),
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
