import 'package:cached_network_image/cached_network_image.dart';
import 'package:orchid/widgets/karaoke_lyrics.dart';
import 'package:orchid/widgets/liquid_artwork_background.dart';
import 'package:orchid/widgets/queue_sheet.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../services/lyrics_service.dart';
import '../services/player_service.dart';

class FullPlayerScreen extends StatefulWidget {
  final PlayerService player;

  const FullPlayerScreen({super.key, required this.player});

  @override
  State<StatefulWidget> createState() => _FullPlayerScreen();
}

class _FullPlayerScreen extends State<FullPlayerScreen> {
  bool _showLyrics = true;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:${m.padLeft(2, '0')}:$s';
    return '$m:$s';
  }

  String? _currentLine(LyricsResult? lyrics, double t) {
    if (lyrics == null || !lyrics.hasAny) return null;
    if (lyrics.lines.isEmpty) {
      final plain = lyrics.displayText.trim();
      if (plain.isEmpty) return null;
      return plain.split('\n').first;
    }
    final i = lyrics.lineIndexAt(t);
    if (i < 0) return null;
    final line = lyrics.lines[i];
    if (line.isInterlude) return '• • •';
    final text = line.text.trim();
    return text.isEmpty ? null : text;
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v < -400 && widget.player.hasNext) {
      widget.player.playNext();
    } else if (v > 400) {
      widget.player.playPrevious();
    }
  }

  Widget _lyricsBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey(widget.player.lyricsGeneration),
        child: KaraokeLyrics(
          player: widget.player.player,
          lyrics: widget.player.lyrics,
          loading: widget.player.lyricsLoading,
        ),
      ),
    );
  }

  Widget _artworkBody(ColorScheme scheme) {
    final track = widget.player.current;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (track?.artworkUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: track!.artworkUrl!,
              width: 280,
              height: 280,
              fit: BoxFit.cover,
            ),
          )
        else
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              color: scheme.muted,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          track?.title ?? 'No track playing',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          track?.artist ?? 'Unknown artist',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: scheme.primary),
        ),
        const SizedBox(height: 16),
        StreamBuilder<Duration>(
          stream: widget.player.player.positionStream,
          initialData: widget.player.player.position,
          builder: (context, snap) {
            final t = (snap.data ?? Duration.zero).inMilliseconds / 1000.0;
            final line = _currentLine(widget.player.lyrics, t);
            if (line == null) {
              if (widget.player.lyricsLoading) {
                return const Text('Loading lyrics…').small().muted();
              }
              return const SizedBox(height: 20);
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                line,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: scheme.foreground.withOpacity(0.92),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        final track = widget.player.current;
        return Scaffold(
          child: LiquidArtworkBackground(
            imageUrl: track?.artworkUrl,
            child: GestureDetector(
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          variance: ButtonVariance.ghost,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(LucideIcons.arrowLeft),
                        ),
                        const Spacer(),
                        Text(
                          widget.player.sourceLabel,
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.primary,
                          ),
                        ),
                        const Spacer(),
                        // Anchor for shadcn drawer overlay.
                        OverlayAnchor(
                          anchor: #orchidQueueDrawer,
                          child: IconButton(
                            variance: ButtonVariance.ghost,
                            onPressed: () =>
                                showQueueSheet(context, widget.player),
                            icon: const Icon(LucideIcons.listMusic),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _showLyrics
                          ? _lyricsBody()
                          : _artworkBody(scheme),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: StreamBuilder<Duration>(
                      stream: widget.player.player.positionStream,
                      initialData: widget.player.player.position,
                      builder: (context, snapshot) {
                        final pos = snapshot.data ?? Duration.zero;
                        final dur =
                            widget.player.player.duration ?? Duration.zero;
                        final maxMs = dur.inMilliseconds.toDouble();
                        final hasDur = maxMs > 0 && maxMs.isFinite;
                        final posMs = hasDur
                            ? pos.inMilliseconds
                                .toDouble()
                                .clamp(0.0, maxMs)
                            : 0.0;

                        return Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Slider(
                                value: SliderValue.single(posMs),
                                min: 0,
                                max: hasDur ? maxMs : 1,
                                onChanged: hasDur
                                    ? (v) => widget.player.seek(
                                          Duration(
                                            milliseconds:
                                                v.value.round().clamp(
                                              0,
                                              maxMs.round(),
                                            ),
                                          ),
                                        )
                                    : null,
                              ),
                            ),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _fmt(pos),
                                  style: TextStyle(color: scheme.primary),
                                ),
                                Text(
                                  _fmt(dur),
                                  style: TextStyle(color: scheme.primary),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            variance: ButtonVariance.ghost,
                            onPressed: () => widget.player.playPrevious(),
                            icon: const Icon(LucideIcons.skipBack),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            variance: ButtonVariance.ghost,
                            onPressed: widget.player.togglePlayPause,
                            icon: Icon(
                              widget.player.player.playing
                                  ? LucideIcons.pause
                                  : LucideIcons.play,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            variance: ButtonVariance.ghost,
                            onPressed: widget.player.hasNext
                                ? () => widget.player.playNext()
                                : null,
                            icon: const Icon(LucideIcons.skipForward),
                          ),
                        ],
                      ),
                      Positioned(
                        right: 12,
                        child: IconButton(
                          variance: ButtonVariance.ghost,
                          onPressed: () {
                            setState(() => _showLyrics = !_showLyrics);
                          },
                          icon: Icon(
                            _showLyrics
                                ? LucideIcons.image
                                : LucideIcons.mic,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Row(
                      children: [
                        Icon(widget.player.volume == 0
                            ? LucideIcons.volumeX
                            : LucideIcons.volume2, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Slider(
                            value: SliderValue.single(widget.player.volume),
                            min: 0,
                            max: 1,
                            onChanged: (value) =>
                                widget.player.setVolume(value.value),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 42,
                          child: Text(
                            '${(widget.player.volume * 100).round()}%',
                            textAlign: TextAlign.end,
                          ).xSmall().muted(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
