import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/player_service.dart';

const Symbol _queueDrawerAnchor = #orchidQueueDrawer;

/// Opens the queue / history panel as a shadcn drawer overlay.
void showQueueSheet(BuildContext context, PlayerService player) {
  showOverlay(
    context,
    const DrawerConfiguration(
      anchor: LinkedAnchor(_queueDrawerAnchor),
      expands: true,
      position: OverlayPosition.end,
    ),
    builder: (context) {
      return OverlayAnchor(
        anchor: _queueDrawerAnchor,
        child: _QueueDrawerBody(player: player),
      );
    },
  );
}

class _QueueDrawerBody extends StatelessWidget {
  final PlayerService player;

  const _QueueDrawerBody({required this.player});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final queue = player.queue;
        final history = player.history;
        final suggestions = player.recommendations;
        final idx = player.queueIndex;

        return Container(
          width: 340,
          color: scheme.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    const Text('Queue').large().semiBold(),
                    const Spacer(),
                    Text('${queue.length} tracks').xSmall().muted(),
                    IconButton(
                      variance: ButtonVariance.ghost,
                      onPressed: () => closeOverlay(context),
                      icon: const Icon(LucideIcons.x, size: 18),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    const Icon(LucideIcons.audioLines, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Keep Playing').semiBold(),
                        const Text('Find more music when the queue ends')
                            .xSmall().muted(),
                      ],
                    )),
                    OutlineButton(
                      onPressed: () => player.setKeepPlaying(!player.keepPlaying),
                      child: Text(player.keepPlaying ? 'On' : 'Off'),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                  children: [
                    if (history.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                        child: const Text('Recently played').small().muted(),
                      ),
                      ...history.reversed.map(
                        (t) => _TrackTile(
                          track: t,
                          subtitle: 'History',
                          onTap: () {
                            player.playTrack(t);
                            closeOverlay(context);
                          },
                        ),
                      ),
                      const Divider(),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                      child: const Text('Up next').small().muted(),
                    ),
                    if (queue.isEmpty)
                       Padding(
                        padding: const EdgeInsets.all(16),
                        child: const Text('Queue is empty').muted(),
                      )
                    else
                      ...List.generate(queue.length, (i) {
                        final t = queue[i];
                        final isCurrent = i == idx;
                        return _TrackTile(
                          track: t,
                          subtitle: isCurrent
                              ? 'Now playing'
                              : (i < idx ? 'Played' : 'Up next'),
                          highlighted: isCurrent,
                          onTap: () {
                            player.playTrack(t, fromQueue: queue);
                            closeOverlay(context);
                          },
                        );
                      }),
                    if (player.keepPlaying) ...[
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 9, 8, 7),
                        child: Row(children: [
                          const Icon(LucideIcons.sparkles, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('Playing Next · Keep Playing').semiBold(),
                          ),
                          if (player.recommendationsLoading)
                            const Text('Finding…').xSmall().muted(),
                        ]),
                      ),
                      if (suggestions.isEmpty && !player.recommendationsLoading)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No suggestions yet.').small().muted(),
                        ),
                      ...suggestions.map((t) => _TrackTile(
                        track: t,
                        subtitle: 'Recommended',
                        onTap: () {
                          player.playTrack(t);
                          closeOverlay(context);
                        },
                      )),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackTile extends StatelessWidget {
  final TrackResult track;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  const _TrackTile({
    required this.track,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).semiBold(),
                  Text(
                    '${track.artist} · $subtitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).xSmall().muted(),
                ],
              ),
            ),
            if (highlighted)
              Icon(LucideIcons.audioLines, size: 16, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
