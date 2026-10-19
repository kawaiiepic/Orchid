import 'package:cached_network_image/cached_network_image.dart';
import 'package:orchid/widgets/karaoke_lyrics.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../services/player_service.dart';

class FullPlayerScreen extends StatefulWidget {
  final PlayerService player;

  const FullPlayerScreen({super.key, required this.player});

  @override
  State<StatefulWidget> createState() => _FullPlayerScreen();
}

class _FullPlayerScreen extends State<FullPlayerScreen> {
  bool _showLyrics = false;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:${m.padLeft(2, '0')}:$s';
    return '$m:$s';
  }

  Widget _lyricsPanel() {
    final track = widget.player.current;
    if (track == null) return const SizedBox.shrink();

    final hasSyl = widget.player.lyrics?.hasSyllables == true;

    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('Spicy Lyrics').semiBold(),
                  const SizedBox(width: 8),
                  Text(
                    hasSyl ? 'syllable karaoke' : 'Apple Music sync',
                  ).xSmall().muted(),
                  const Spacer(),
                  GhostButton(
                    onPressed: () {
                      setState(() => _showLyrics = !_showLyrics);
                    },
                    child: Text(_showLyrics ? 'Hide' : 'Show'),
                  ),
                ],
              ),
              if (_showLyrics) ...[
                const SizedBox(height: 12),
                Expanded(
                  child: KaraokeLyrics(
                    player: widget.player.player,
                    lyrics: widget.player.lyrics,
                    loading: widget.player.lyricsLoading,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      child: Builder(
        builder: (context) {
          final track = widget.player.current;
          return Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      variance: ButtonVariance.ghost,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.arrowLeft),
                    ),
                    const Spacer(),
                    Text(
                      widget.player.playingVia ?? 'Now playing',
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.primary,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 40),
                  ],
                ),
              ),

              // Album art
              if (_showLyrics)
                Expanded(child: _lyricsPanel())
              else
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (track?.artworkUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: track!.artworkUrl!,
                              width: 500,
                              height: 500,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Container(
                            width: 500,
                            height: 500,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(track?.title ?? 'No track playing',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(track?.artist ?? 'Unknown artist',
                            style:
                                TextStyle(fontSize: 14, color: scheme.primary)),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),

              // Progress
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    StreamBuilder<Duration>(
                      stream: widget.player.player.positionStream,
                      builder: (context, snapshot) {
                        final pos = snapshot.data ?? Duration.zero;
                        final dur =
                            widget.player.player.duration ?? Duration.zero;
                        return Column(
                          children: [
                            SizedBox(
                                width: double.infinity,
                                child: Slider(
                                    value: SliderValue.single(
                                        pos.inMilliseconds.toDouble()),
                                    max: dur.inMilliseconds.toDouble(),
                                    onChanged: (v) => widget.player.seek(
                                          Duration(
                                              milliseconds: v.value.round()),
                                        ))),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_fmt(pos),
                                    style: TextStyle(color: scheme.primary)),
                                Text(_fmt(dur),
                                    style: TextStyle(color: scheme.primary)),
                              ],
                            )
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              // Controls
              Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Tooltip(
                              tooltip: const TooltipContainer(
                                child: Text('Previous'),
                              ).call,
                              child: IconButton(
                                variance: ButtonVariance.ghost,
                                onPressed: () => widget.player.playPrevious(),
                                icon: const Icon(LucideIcons.skipBack),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              tooltip: TooltipContainer(
                                child: Text(
                                  widget.player.player.playing
                                      ? 'Pause'
                                      : 'Play',
                                ),
                              ).call,
                              child: IconButton(
                                variance: ButtonVariance.ghost,
                                onPressed: widget.player.togglePlayPause,
                                icon: widget.player.player.playing
                                    ? const Icon(LucideIcons.play)
                                    : const Icon(LucideIcons.pause),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              tooltip: const TooltipContainer(
                                child: Text('Next'),
                              ).call,
                              child: IconButton(
                                variance: ButtonVariance.ghost,
                                onPressed: () => widget.player.playNext(),
                                icon: const Icon(LucideIcons.skipForward),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 16,
                    child: Row(
                      children: [
                        IconButton(
                            onPressed: () {
                              setState(() {
                                _showLyrics = !_showLyrics;
                              });
                            },
                            icon: Icon(LucideIcons.music),
                            variance: ButtonVariance.ghost)
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
