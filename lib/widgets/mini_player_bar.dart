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

/// Keep Liquid Glass blur and tint while cropping its built-in specular
/// perimeter. A zero-width rim alone does not hide the fallback's sheen.
class _BorderlessPlayerGlass extends StatelessWidget {
  final double radius;
  final Widget child;

  const _BorderlessPlayerGlass({
    required this.radius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Stack(
      children: [
        Positioned.fill(
          left: -5, top: -5, right: -5, bottom: -5,
          child: IgnorePointer(
            child: liquid.LiquidGlass(
              shape: liquid.LiquidGlassShape.roundedRect(radius + 5),
              style: liquid.LiquidGlassStyle.clear,
              interactive: false,
              interactionStrength: 0,
              fallback: liquid.LiquidGlassFallback.frosted,
              fallbackBlurSigma: 18,
              tintColor: const Color(0xFF392447),
              tintOpacity: 0.42,
              brightness: liquid.LiquidGlassBrightness.dark,
              opacity: 0.78,
              rimColor: const Color(0x00000000),
              rimWidth: 0,
              child: const SizedBox.expand(),
            ),
          ),
        ),
        child,
      ],
    ),
  );
}

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
          child: _BorderlessPlayerGlass(
            radius: 18,
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
          style: liquid.LiquidGlassStyle.clear,
          interactive: false,
          interactionStrength: 0,
          tintColor: const Color(0xFF392447),
          tintOpacity: 0.42,
          brightness: liquid.LiquidGlassBrightness.dark,
          opacity: 0.78,
          rimColor: const Color(0x00000000),
          rimWidth: 0,
          fallbackBlurSigma: 18,
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


/// Thin, borderless progress track with a larger invisible drag target.
/// Compact track and a visible thumb without the default button hover border.
class _ThinPlayerSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final double width;

  const _ThinPlayerSlider({
    required this.value,
    required this.onChanged,
    required this.width,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 20,
    child: LayoutBuilder(
      builder: (context, bounds) {
        final trackWidth = bounds.maxWidth;
        final progress = value.clamp(0.0, 1.0).toDouble();
        void update(double x) {
          if (onChanged != null && trackWidth > 0) {
            onChanged!((x / trackWidth).clamp(0.0, 1.0).toDouble());
          }
        }
        return MouseRegion(
          cursor: onChanged == null
            ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => update(details.localPosition.dx),
            onHorizontalDragStart: (details) =>
              update(details.localPosition.dx),
            onHorizontalDragUpdate: (details) =>
              update(details.localPosition.dx),
            child: Stack(children: [
              Positioned(
                left: 0, right: 0, top: 8, height: 4,
                child: DecoratedBox(decoration: BoxDecoration(
                  color: const Color(0x88665A76),
                  borderRadius: BorderRadius.circular(2),
                )),
              ),
              if (progress > 0)
                Positioned(
                  left: 0, top: 8, height: 4,
                  width: trackWidth * progress,
                  child: DecoratedBox(decoration: BoxDecoration(
                    color: const Color(0xFFD0B6EE),
                    borderRadius: BorderRadius.circular(2),
                  )),
                ),
              Positioned(
                left: (trackWidth - 12).clamp(0.0, double.infinity).toDouble() * progress,
                top: 4, width: 12, height: 12,
                child: DecoratedBox(decoration: BoxDecoration(
                  color: const Color(0xFFF0E1FF),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Color(0x44000000), blurRadius: 3),
                  ],
                )),
              ),
            ]),
          ),
        );
      },
    ),
  );
}

/// Floating desktop player styled after Eclipse's compact transport deck.
class DesktopPlayerBar extends StatelessWidget {
  final PlayerService player;
  final MusicLibrary library;

  const DesktopPlayerBar({
    super.key,
    required this.player,
    required this.library,
  });

  void _openFull(BuildContext context) {
    if (player.current == null) return;
    showContentDrawer(
      context,
      preferredWidth: 950,
      builder: (_) => FullPlayerScreen(player: player, library: library),
    );
  }

  String _time(Duration position) {
    final seconds = position.inSeconds < 0 ? 0 : position.inSeconds;
    final minutes = (seconds ~/ 60).toString();
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    if (seconds >= 3600) {
      return '${seconds ~/ 3600}:${(seconds % 3600 ~/ 60).toString().padLeft(2, '0')}:$remainder';
    }
    return '$minutes:$remainder';
  }

  Widget _control(
    IconData icon,
    VoidCallback? action, {
    Color color = const Color(0xFFB4ACC4),
    double size = 17,
  }) => MouseRegion(
    cursor: action == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: action,
      child: SizedBox(
        width: 31,
        height: 31,
        child: Center(
          child: Icon(icon, size: size, color: action == null
            ? const Color(0xFF61586D) : color),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.current;
        final active = track != null;
        return LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 800;
          final sideWidth = narrow ? 150.0 : 235.0;
          final volumeWidth = narrow ? 40.0 : 54.0;
          return _BorderlessPlayerGlass(
            radius: 17,
            child: SizedBox(
              height: 82,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: sideWidth,
                      child: active
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _openFull(context),
                            child: Row(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: track.artworkUrl == null
                                  ? const SizedBox(
                                      width: 52, height: 52,
                                      child: ColoredBox(
                                        color: OrchidStyle.panel,
                                        child: Icon(LucideIcons.music2, size: 19),
                                      ),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: track.artworkUrl!,
                                      width: 52, height: 52,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                        const SizedBox(
                                          width: 52, height: 52,
                                          child: Icon(LucideIcons.music2),
                                        ),
                                    ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(track.title,
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFF9F4FF),
                                      fontSize: 12, fontWeight: FontWeight.w600,
                                    )),
                                  const SizedBox(height: 3),
                                  Text(track.artist,
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFA9A0B9), fontSize: 11,
                                    )),
                                ],
                              )),
                              const SizedBox(width: 3),
                              ListenableBuilder(
                                listenable: library,
                                builder: (context, _) {
                                  final saved = SavedSong(
                                    track.title, track.artist,
                                    album: track.album,
                                    artwork: track.artworkUrl,
                                  );
                                  final liked = library.isFavorite(saved);
                                  return MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () { library.toggleFavorite(saved); },
                                      child: SizedBox(
                                        width: 27, height: 52,
                                        child: Center(child: Icon(
                                          LucideIcons.heart,
                                          size: 16,
                                          color: liked
                                            ? const Color(0xFFF0A0CB)
                                            : const Color(0xFFA79AB9),
                                        )),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ]),
                          )
                        : const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Nothing playing',
                              style: TextStyle(
                                color: Color(0xFFA9A0B9), fontSize: 12,
                              )),
                          ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 33,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _control(LucideIcons.shuffle,
                                  active ? player.toggleShuffle : null,
                                  color: player.shuffleEnabled
                                    ? OrchidStyle.lilac
                                    : const Color(0xFFAAA3B9),
                                  size: 15),
                                _control(LucideIcons.skipBack,
                                  active ? player.playPrevious : null),
                                _control(
                                  player.player.playing
                                    ? LucideIcons.pause
                                    : LucideIcons.play,
                                  active ? player.togglePlayPause : null,
                                  color: const Color(0xFFF7F1FF), size: 22,
                                ),
                                _control(LucideIcons.skipForward,
                                  active && player.hasNext
                                    ? player.playNext : null),
                                _control(LucideIcons.repeat,
                                  active ? player.cycleRepeatMode : null,
                                  color: player.repeatMode != OrchidRepeatMode.off
                                    ? OrchidStyle.lilac
                                    : const Color(0xFFAAA3B9),
                                  size: 15),
                              ],
                            ),
                          ),
                          StreamBuilder<Duration>(
                            stream: player.player.positionStream,
                            builder: (context, snapshot) {
                              final duration = player.player.duration ??
                                (track?.duration != null
                                  ? Duration(seconds: track!.duration!)
                                  : Duration.zero);
                              final total = duration.inMilliseconds;
                              final pos = snapshot.data ?? Duration.zero;
                              final elapsed = total > 0
                                ? pos.inMilliseconds.clamp(0, total)
                                : 0;
                              return Row(children: [
                                SizedBox(
                                  width: 34,
                                  child: Text(_time(Duration(milliseconds: elapsed)),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      color: Color(0xFF968DA7), fontSize: 10,
                                    )),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Center(
                                    child: LayoutBuilder(builder: (context, bounds) {
                                      final width = bounds.maxWidth.clamp(0.0, narrow ? 150.0 : 240.0).toDouble();
                                      return _ThinPlayerSlider(
                                        width: width,
                                        value: total > 0 ? elapsed / total : 0,
                                        onChanged: active && total > 0
                                          ? (value) => player.seek(Duration(
                                              milliseconds: (value * total).round()))
                                          : null,
                                      );
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 34,
                                  child: Text(total > 0 ? _time(duration) : '0:00',
                                    style: const TextStyle(
                                      color: Color(0xFF968DA7), fontSize: 10,
                                    )),
                                ),
                              ]);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: narrow ? 116 : 140,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(LucideIcons.volume2,
                            color: Color(0xFFB9AFCB), size: 15),
                          const SizedBox(width: 7),
                          _ThinPlayerSlider(
                            width: volumeWidth,
                            value: player.volume,
                            onChanged: player.setVolume,
                          ),
                          const SizedBox(width: 16),
                          _control(
                            LucideIcons.listMusic,
                            active ? () => showQueueSheet(context, player) : null,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }
}
