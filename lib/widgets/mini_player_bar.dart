import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:cupertino_ui/cupertino_ui.dart' as ios;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import '../screens/full_player_screen.dart';
import '../services/player_service.dart';
import '../services/music_library.dart';
import 'orchid_style.dart';
import 'queue_sheet.dart';
import 'content_drawer.dart';

class MiniPlayerBar extends StatelessWidget {
  final PlayerService player;
  final MusicLibrary? library;

  const MiniPlayerBar({super.key, required this.player, this.library});

  void _openFull(BuildContext context) {
    if (player.current == null) return;
    showContentDrawer(
      context,
      preferredWidth: 900,
      builder: (_) => FullPlayerScreen(player: player, library: library),
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
        final compact = MediaQuery.sizeOf(context).width < 610;
        final nativeIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

        return Container(
          margin: EdgeInsets.fromLTRB(10, OrchidStyle.compact(context,6), 10, OrchidStyle.compact(context,5)),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: OrchidStyle.compact(context,10)),
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
                            width: OrchidStyle.compact(context,44),
                            height: OrchidStyle.compact(context,44),
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Container(
                          width: OrchidStyle.compact(context,44),
                          height: OrchidStyle.compact(context,44),
                          decoration: BoxDecoration(
                            color: scheme.muted,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      SizedBox(width: OrchidStyle.compact(context,12)),
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
              if (!compact) IconButton.ghost(
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
                child: nativeIOS
                  ? ios.CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => player.togglePlayPause(),
                      child: Icon(player.player.playing
                        ? ios.CupertinoIcons.pause_fill : ios.CupertinoIcons.play_fill,
                        color: OrchidStyle.ink, size: 21),
                    )
                  : IconButton.ghost(
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
              if (!compact) IconButton.ghost(
                onPressed: () => showQueueSheet(context, player),
                icon: const Icon(LucideIcons.listMusic, size: 18),
              ),
              if (!compact) ...[
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
            ],
          ),
        );
      },
    );
  }
}
