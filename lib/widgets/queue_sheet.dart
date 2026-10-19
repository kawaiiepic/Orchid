import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/player_service.dart';

/// Opens the queue / history panel. Uses a custom route so we don't depend on
/// Material's [showModalBottomSheet] (not exported by shadcn_flutter).
Future<void> showQueueSheet(BuildContext context, PlayerService player) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: const Color(0x88000000),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: _QueueSheetPanel(player: player),
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
  );
}

class _QueueSheetPanel extends StatelessWidget {
  final PlayerService player;

  const _QueueSheetPanel({required this.player});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final queue = player.queue;
        final history = player.history;
        final idx = player.queueIndex;
        final maxH = MediaQuery.sizeOf(context).height * 0.72;

        return Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: BoxDecoration(
              color: scheme.card,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                top: BorderSide(color: scheme.border),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                  child: Row(
                    children: [
                      const Text('Queue').large().semiBold(),
                      const Spacer(),
                      Text('${queue.length} tracks').xSmall().muted(),
                      IconButton(
                        variance: ButtonVariance.ghost,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x, size: 18),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    shrinkWrap: true,
                    children: [
                      if (history.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                          child: Text('Recently played').small().muted(),
                        ),
                        ...history.reversed.map(
                          (t) => _TrackTile(
                            track: t,
                            subtitle: 'History',
                            onTap: () {
                              player.playTrack(t);
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                        const Divider(),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                        child: Text('Up next').small().muted(),
                      ),
                      if (queue.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Queue is empty').muted(),
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
                              Navigator.of(context).pop();
                            },
                          );
                        }),
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
