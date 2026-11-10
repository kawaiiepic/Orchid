import 'dart:ui' show ImageFilter;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:cupertino_ui/cupertino_ui.dart' as ios;
import 'package:liquid_design/liquid_design.dart' as liquid;
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

        return Padding(
          padding: EdgeInsets.fromLTRB(10, OrchidStyle.compact(context,6), 10, OrchidStyle.compact(context,5)),
          child: liquid.LiquidGlass(
            shape: const liquid.LiquidGlassShape.roundedRect(18),
            style: liquid.LiquidGlassStyle.regular,
            fallback: liquid.LiquidGlassFallback.frosted,
            tintColor: const Color(0xFF332342),
            tintOpacity: 0.22,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: OrchidStyle.compact(context,10)),
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
            ),
          ),
        );
      },
    );
  }
}


/// A compact floating iOS music pill. Used independently of the desktop
/// miniplayer so iPhone's Liquid Glass dock can animate without relayouting
/// the active Flutter tab tree.
class IOSMiniPlayer extends StatelessWidget {
  final PlayerService player;
  final MusicLibrary? library;
  final bool compact;

  const IOSMiniPlayer({
    super.key,
    required this.player,
    this.library,
    this.compact = false,
  });

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
        final artwork = track.artworkUrl;
        return liquid.LiquidGlass(
          shape: const liquid.LiquidGlassShape.capsule(),
          style: liquid.LiquidGlassStyle.regular,
          tintColor: const Color(0xFF57406C),
          tintOpacity: 0.22,
          fallback: liquid.LiquidGlassFallback.frosted,
          child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openFull(context),
                      child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: artwork != null && artwork.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: artwork,
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      const SizedBox(
                                        width: 42,
                                        height: 42,
                                        child: Icon(LucideIcons.music2),
                                      ),
                                )
                              : const SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: Icon(LucideIcons.music2),
                                ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFFDFBFF),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFC6C2CB),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                  ios.CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: player.togglePlayPause,
                    child: Icon(
                      player.player.playing
                          ? ios.CupertinoIcons.pause_fill
                          : ios.CupertinoIcons.play_fill,
                      size: 23,
                      color: const Color(0xFFFDFBFF),
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


/// Full-width desktop player with transport and volume controls.
class DesktopPlayerBar extends StatelessWidget {
  final PlayerService player;
  final MusicLibrary library;
  const DesktopPlayerBar({super.key, required this.player, required this.library});

  void _openFull(BuildContext context) {
    if (player.current == null) return;
    showContentDrawer(context, preferredWidth: 950,
      builder: (_) => FullPlayerScreen(player: player, library: library));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.current;
        final playing = player.player.playing;
        return liquid.LiquidGlass(
          shape: const liquid.LiquidGlassShape.roundedRect(17),
          style: liquid.LiquidGlassStyle.regular,
          fallback: liquid.LiquidGlassFallback.frosted,
          fallbackBlurSigma: 18,
          tintColor: const Color(0xFF332342),
          tintOpacity: 0.22,
          child: SizedBox(
            height: 82,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              child: Row(children: [
            SizedBox(
              width: MediaQuery.sizeOf(context).width < 1250 ? 155 : 245,
              child: track == null
                ? const Align(alignment: Alignment.centerLeft,
                    child: Text('Nothing playing', style: TextStyle(
                      color: Color(0xFFAAA1BA), fontSize: 12)))
                : GestureDetector(
                    onTap: () => _openFull(context),
                    behavior: HitTestBehavior.opaque,
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: track.artworkUrl == null
                          ? const SizedBox(width: 53, height: 53,
                              child: ColoredBox(color: OrchidStyle.panel,
                                child: Icon(LucideIcons.music2, size: 21)))
                          : CachedNetworkImage(
                              imageUrl: track.artworkUrl!,
                              width: 53, height: 53, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                const SizedBox(width: 53, height: 53,
                                  child: Icon(LucideIcons.music2)),
                            ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title, maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFFAF5FF),
                              fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(track.artist, maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFA9A1BB),
                              fontSize: 11)),
                        ],
                      )),
                    ]),
                  ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.ghost(
                        onPressed: track == null ? null : player.playPrevious,
                        icon: const Icon(LucideIcons.skipBack, size: 17),
                      ),
                      IconButton.ghost(
                        onPressed: track == null ? null : player.togglePlayPause,
                        icon: Icon(playing ? LucideIcons.pause : LucideIcons.play,
                          color: const Color(0xFFF7EBFF), size: 21),
                      ),
                      IconButton.ghost(
                        onPressed: track == null || !player.hasNext
                          ? null : player.playNext,
                        icon: const Icon(LucideIcons.skipForward, size: 17),
                      ),
                      IconButton.ghost(
                        onPressed: track == null
                          ? null : () => showQueueSheet(context, player),
                        icon: const Icon(LucideIcons.listMusic, size: 17),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width < 1250 ? 165 : 340,
                    child: StreamBuilder<Duration>(
                      stream: player.player.positionStream,
                      builder: (context, snapshot) {
                        final duration = player.player.duration ?? Duration.zero;
                        final total = duration.inMilliseconds;
                        final value = snapshot.data?.inMilliseconds ?? 0;
                        return Slider(
                          value: SliderValue.single(
                            total > 0 ? (value / total).clamp(0.0, 1.0) : 0),
                          min: 0,
                          max: 1,
                          onChanged: track == null || total <= 0
                            ? null
                            : (v) => player.seek(Duration(
                                milliseconds: (v.value * total).round())),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: MediaQuery.sizeOf(context).width < 1250 ? 95 : 160,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(LucideIcons.volume2, size: 16,
                    color: Color(0xFFBEB0D0)),
                  const SizedBox(width: 10),
                  SizedBox(width: MediaQuery.sizeOf(context).width < 1250 ? 55 : 108,
                    child: Slider(
                      value: SliderValue.single(player.volume),
                      min: 0,
                      max: 1,
                      onChanged: (v) => player.setVolume(v.value),
                    )),
                ],
              ),
            ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
