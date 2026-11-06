import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

/// Silent looping Spotify Canvas with an album artwork fallback.
class CanvasVideo extends StatefulWidget {
  final String url;
  final String? fallbackArtworkUrl;
  const CanvasVideo({super.key, required this.url, this.fallbackArtworkUrl});
  @override
  State<CanvasVideo> createState() => _CanvasVideoState();
}

class _CanvasVideoState extends State<CanvasVideo> {
  late final mk.Player _video;
  late final VideoController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _video = mk.Player();
    _controller = VideoController(_video);
    _start();
  }

  Future<void> _start() async {
    try {
      await _video.setVolume(0);
      await _video.setPlaylistMode(mk.PlaylistMode.loop);
      await _video.open(mk.Media(widget.url));
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('[Orchid Canvas] Video failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant CanvasVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _ready = false;
      _failed = false;
      _start();
    }
  }

  @override
  void dispose() {
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || !_ready) {
      if (widget.fallbackArtworkUrl != null) {
        return CachedNetworkImage(
          imageUrl: widget.fallbackArtworkUrl!,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) =>
              const Center(child: Icon(LucideIcons.music2, size: 52)),
        );
      }
      return const Center(child: Icon(LucideIcons.music2, size: 52));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Video(
        controller: _controller,
        controls: NoVideoControls,
        fit: BoxFit.cover,
      ),
    );
  }
}
