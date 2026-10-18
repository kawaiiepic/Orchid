import 'package:flutter/material.dart' show Colors, FontWeight, TextStyle, TextAlign;
import 'package:just_audio/just_audio.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../services/lyrics_service.dart';

/// Karaoke view driven by [player.positionStream] and structured [LyricsResult].
///
/// - Syllable mode: highlights the active lead syllable; background vocals muted
/// - Line mode: highlights the active line when no syllable data
/// - Plain fallback: static text when nothing is timed
class KaraokeLyrics extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (loading) {
      return const Text('Loading lyrics…').muted();
    }
    final result = lyrics;
    if (result == null || !result.hasAny) {
      return const Text('No lyrics found.').muted();
    }

    if (!result.hasSyllables && result.lines.isEmpty) {
      return Text(result.displayText);
    }

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final t = (snapshot.data ?? Duration.zero).inMilliseconds / 1000.0;
        return _KaraokeBody(lyrics: result, t: t);
      },
    );
  }
}

class _KaraokeBody extends StatelessWidget {
  final LyricsResult lyrics;
  final double t;

  const _KaraokeBody({required this.lyrics, required this.t});

  @override
  Widget build(BuildContext context) {
    final lines = lyrics.lines;
    if (lines.isEmpty) {
      return Text(lyrics.displayText);
    }

    final activeIdx = lyrics.lineIndexAt(t);
    // Window: a few lines around the active one so it stays readable
    const window = 2;
    final start = activeIdx < 0
        ? 0
        : (activeIdx - window).clamp(0, lines.length - 1);
    final end = activeIdx < 0
        ? (window * 2 + 1).clamp(0, lines.length)
        : (activeIdx + window + 1).clamp(0, lines.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = start; i < end; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _LyricLineView(
              line: lines[i],
              t: t,
              isActiveLine: i == activeIdx,
              isPast: activeIdx >= 0 && i < activeIdx,
            ),
          ),
      ],
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
    final activeSyl = isActiveLine ? line.activeLeadIndex(t) : -1;

    if (!line.hasSyllables) {
      final color = isActiveLine
          ? scheme.foreground
          : isPast
              ? scheme.mutedForeground
              : scheme.mutedForeground;
      return Text(
        line.text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: isActiveLine ? 20 : 15,
          fontWeight: isActiveLine ? FontWeight.w600 : FontWeight.w400,
          color: color,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Lead syllables
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < line.lead.length; i++)
              _SyllableChip(
                syllable: line.lead[i],
                isActive: i == activeSyl,
                isPast: isPast || (isActiveLine && activeSyl >= 0 && i < activeSyl),
                isFuture: !isPast && !(isActiveLine && activeSyl >= 0 && i <= activeSyl),
                isActiveLine: isActiveLine,
                compact: false,
              ),
          ],
        ),
        // Background vocals (smaller, muted)
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
                  isFuture: t < s.start,
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
  final bool isFuture;
  final bool isActiveLine;
  final bool compact;

  const _SyllableChip({
    required this.syllable,
    required this.isActive,
    required this.isPast,
    required this.isFuture,
    required this.isActiveLine,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Color color;
    FontWeight weight;
    double size;

    if (compact) {
      size = 12;
      weight = FontWeight.w400;
      if (isActive) {
        color = scheme.primary;
        weight = FontWeight.w600;
      } else if (isPast) {
        color = scheme.mutedForeground;
      } else {
        color = scheme.mutedForeground.withValues(alpha: 0.55);
      }
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
          ? scheme.foreground.withValues(alpha: 0.45)
          : scheme.mutedForeground.withValues(alpha: 0.5);
    }

    // Space after syllable unless it's a mid-word fragment
    final needsSpace = !syllable.isPartOfWord;

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 80),
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.25,
      ),
      child: Text(
        needsSpace ? '${syllable.text} ' : syllable.text,
      ),
    );
  }
}
