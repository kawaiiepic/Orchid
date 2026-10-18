import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' show Slider, SliderTheme, SliderThemeData, RoundSliderThumbShape, RoundSliderOverlayShape;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../services/player_service.dart';
import '../widgets/karaoke_lyrics.dart';

class FullPlayerScreen extends StatelessWidget {
  final PlayerService player;

  const FullPlayerScreen({super.key, required this.player});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:${m.padLeft(2, '0')}:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.current;
        final scheme = Theme.of(context).colorScheme;

        return Scaffold(
          child: SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton.ghost(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.chevronDown),
                      ),
                      const Spacer(),
                      Text(
                        player.playingVia ?? 'Now playing',
                      ).small().muted(),
                      const Spacer(),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),

                // Artwork
                if (track?.artworkUrl != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: track!.artworkUrl!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 12),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Text(track?.title ?? '—').large().semiBold(),
                      const SizedBox(height: 4),
                      Text(track?.artist ?? '').muted(),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Lyrics (takes remaining space)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: KaraokeLyrics(
                      player: player.player,
                      lyrics: player.lyrics,
                      loading: player.lyricsLoading,
                    ),
                  ),
                ),

                // Progress
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: StreamBuilder<Duration>(
                    stream: player.player.positionStream,
                    builder: (context, posSnap) {
                      return StreamBuilder<Duration?>(
                        stream: player.player.durationStream,
                        builder: (context, durSnap) {
                          final pos = posSnap.data ?? Duration.zero;
                          final dur = durSnap.data ?? Duration.zero;
                          final max = dur.inMilliseconds.toDouble().clamp(1, double.infinity);
                          final value = pos.inMilliseconds.toDouble().clamp(0, max);

                          return Column(
                            children: [
                              SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                  activeTrackColor: scheme.primary,
                                  inactiveTrackColor: scheme.muted,
                                  thumbColor: scheme.primary,
                                ),
                                child: Slider(
                                  value: value,
                                  max: max,
                                  onChanged: (v) {
                                    player.seek(Duration(milliseconds: v.round()));
                                  },
                                ),
                              ),
                              Row(
                                children: [
                                  Text(_fmt(pos)).xSmall().muted(),
                                  const Spacer(),
                                  Text(_fmt(dur)).xSmall().muted(),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),

                // Transport
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.ghost(
                        onPressed: track == null
                            ? null
                            : () => player.playPrevious(),
                        icon: const Icon(LucideIcons.skipBack),
                      ),
                      const SizedBox(width: 12),
                      IconButton.ghost(
                        onPressed: track == null
                            ? null
                            : () => player.togglePlayPause(),
                        icon: Icon(
                          player.player.playing
                              ? LucideIcons.pause
                              : LucideIcons.play,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.ghost(
                        onPressed: player.hasNext
                            ? () => player.playNext()
                            : null,
                        icon: const Icon(LucideIcons.skipForward),
                      ),
                    ],
                  ),
                ),

                // Volume
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.volume1, size: 16),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                            activeTrackColor: scheme.mutedForeground,
                            inactiveTrackColor: scheme.muted,
                            thumbColor: scheme.foreground,
                          ),
                          child: Slider(
                            value: player.volume,
                            onChanged: (v) => player.setVolume(v),
                          ),
                        ),
                      ),
                      const Icon(LucideIcons.volume2, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
