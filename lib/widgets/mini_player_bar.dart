import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../screens/full_player_screen.dart';
import '../services/lyrics_service.dart';
import '../services/player_service.dart';

class MiniPlayerBar extends StatelessWidget {
  final PlayerService player;

  const MiniPlayerBar({super.key, required this.player});

  void _openFull(BuildContext context) {
    if (player.current == null) return;
    Navigator.of(context).push(
      ShadcnPageRoute<void>(
        builder: (_) => FullPlayerScreen(player: player),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.current;
        if (track == null) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;

        return Container(
          color: scheme.card,
          child: GestureDetector(
            onTap: () => _openFull(context),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: scheme.border),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: StreamBuilder<Duration>(
                stream: player.player.positionStream,
                initialData: player.player.position,
                builder: (context, snap) {
                  final t =
                      (snap.data ?? Duration.zero).inMilliseconds / 1000.0;
                  final line = _currentLine(player.lyrics, t);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (track.artworkUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CachedNetworkImage(
                                imageUrl: track.artworkUrl!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: scheme.muted,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(track.title).semiBold(),
                                Text(
                                  [
                                    track.artist,
                                    if (player.playingVia != null)
                                      player.playingVia!,
                                  ].join(' · '),
                                ).small().muted(),
                              ],
                            ),
                          ),
                          IconButton.ghost(
                            onPressed: () => player.playPrevious(),
                            icon: const Icon(LucideIcons.skipBack, size: 18),
                          ),
                          IconButton.ghost(
                            onPressed: () => player.togglePlayPause(),
                            icon: Icon(
                              player.player.playing
                                  ? LucideIcons.pause
                                  : LucideIcons.play,
                            ),
                          ),
                          IconButton.ghost(
                            onPressed:
                                player.hasNext ? () => player.playNext() : null,
                            icon:
                                const Icon(LucideIcons.skipForward, size: 18),
                          ),
                        ],
                      ),
                      if (line != null) ...[
                        const SizedBox(height: 8),
                        // Align under the art + title block (skip control cluster).
                        Row(
                          children: [
                            const SizedBox(width: 56), // art (44) + gap (12)
                            Expanded(
                              child: Text(
                                line,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.foreground.withOpacity(0.88),
                                  height: 1.2,
                                ),
                              ),
                            ),
                            // Leave room so text doesn't sit under transport buttons.
                            const SizedBox(width: 108),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
