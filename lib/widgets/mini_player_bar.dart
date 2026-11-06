import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../screens/full_player_screen.dart';
import '../services/player_service.dart';
import 'orchid_style.dart';
import 'queue_sheet.dart';

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.current;
        if (track == null) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;

        return Container(
          margin: const EdgeInsets.fromLTRB(10, 6, 10, 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: OrchidStyle.panelDecoration(radius: 18),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openFull(context),
                  child: Row(
                    children: [
                      if (track.artworkUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(11),
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
                            Text(track.title, maxLines: 1,
                              overflow: TextOverflow.ellipsis).semiBold(),
                            Text(
                              [track.artist, if (!player.resolving && player.playingVia != null) player.sourceLabel].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ).small().muted(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton.ghost(
                onPressed: () => player.playPrevious(),
                icon: const Icon(LucideIcons.skipBack, size: 18),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: OrchidStyle.violet,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: IconButton.ghost(
                  onPressed: () => player.togglePlayPause(),
                  icon: Icon(player.player.playing
                    ? LucideIcons.pause : LucideIcons.play,
                    color: OrchidStyle.ink, size: 20),
                ),
              ),
              IconButton.ghost(
                onPressed: player.hasNext ? () => player.playNext() : null,
                icon: const Icon(LucideIcons.skipForward, size: 18),
              ),
              OverlayAnchor(
                anchor: #orchidQueueDrawer,
                child: IconButton.ghost(
                  onPressed: () => showQueueSheet(context, player),
                  icon: const Icon(LucideIcons.listMusic, size: 18),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(LucideIcons.volume2, size: 17),
              const SizedBox(width: 6),
              SizedBox(
                width: 104,
                child: Slider(
                  value: SliderValue.single(player.volume),
                  min: 0,
                  max: 1,
                  onChanged: (value) => player.setVolume(value.value),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
