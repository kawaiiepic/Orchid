import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../screens/full_player_screen.dart';
import '../services/player_service.dart';

class MiniPlayerBar extends StatelessWidget {
  final PlayerService player;

  const MiniPlayerBar({super.key, required this.player});

  void _openFull(BuildContext context) {
    if (player.current == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullPlayerScreen(player: player),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.current;
        if (track == null) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;

        return Material(
          color: scheme.card,
          child: InkWell(
            onTap: () => _openFull(context),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: scheme.border),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
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
                            if (player.playingVia != null) player.playingVia!,
                          ].join(' · '),
                        ).small().muted(),
                      ],
                    ),
                  ),
                  IconButton.ghost(
                    onPressed: player.hasPrevious || track != null
                        ? () => player.playPrevious()
                        : null,
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
                    onPressed: player.hasNext ? () => player.playNext() : null,
                    icon: const Icon(LucideIcons.skipForward, size: 18),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
