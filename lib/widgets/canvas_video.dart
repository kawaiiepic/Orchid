import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../services/hls_variant_service.dart';

/// Silently plays Apple Music's animated album artwork when its HLS segments
/// are actually decodable. Falls back to the static cover on MPV errors.
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
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _playingSubscription;
  bool _ready = false;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _video = mk.Player();
    _controller = VideoController(_video);
    _errorSubscription = _video.stream.error.listen((message) {
      debugPrint('[Orchid Artwork] MPV error: $message');
      if (!mounted || _failed) return;
      setState(() {
        _failed = true;
        _ready = false;
      });
      unawaited(_video.stop());
    });
    _playingSubscription = _video.stream.playing.listen((playing) {
      if (playing && mounted && !_failed && !_ready) {
        setState(() => _ready = true);
      }
    });
    _start();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _ready = false;
        _failed = false;
      });
    }
    try {
      await _video.setVolume(0);
      if (generation != _generation) return;
      await _video.setPlaylistMode(mk.PlaylistMode.loop);
      if (generation != _generation) return;
      final playableUrl = await HlsVariantService.instance.preferredUrl(widget.url);
      if (generation != _generation) return;
      await _video.open(mk.Media(playableUrl, httpHeaders: const {
        'User-Agent': 'Mozilla/5.0',
        'Accept': '*/*',
      }));
      // Do not treat open() as proof that HLS segments were loaded.
      // _ready is only set when MPV actually reports playback.
    } catch (e) {
      debugPrint('[Orchid Artwork] Video could not open: $e');
      if (mounted && generation == _generation) {
        setState(() {
          _failed = true;
          _ready = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant CanvasVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      unawaited(_video.stop().then((_) => _start()));
    }
  }

  @override
  void dispose() {
    ++_generation;
    _errorSubscription?.cancel();
    _playingSubscription?.cancel();
    unawaited(_video.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || !_ready) {
      if (widget.fallbackArtworkUrl != null &&
          widget.fallbackArtworkUrl!.startsWith('https://')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: widget.fallbackArtworkUrl!,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) =>
                const Center(child: Icon(LucideIcons.music2, size: 52)),
          ),
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
