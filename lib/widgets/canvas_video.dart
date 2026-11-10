import 'dart:async';

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
  final VoidCallback? onFailure;
  /// Fired after the video has actually rendered its first frame.
  final VoidCallback? onReady;
  /// Prefer a lower-bandwidth HLS stream for fullscreen ambient playback.
  final bool efficient;
  const CanvasVideo({
    super.key, required this.url, this.fallbackArtworkUrl,
    this.onFailure, this.onReady, this.efficient = false,
  });

  @override
  State<CanvasVideo> createState() => _CanvasVideoState();
}

class _CanvasVideoState extends State<CanvasVideo> {
  late final mk.Player _video;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _completedSubscription;
  Timer? _stallWatchdog;
  DateTime _lastProgress = DateTime.now();
  Duration _lastPosition = Duration.zero;
  bool _recovering = false;
  int _recoveries = 0;
  bool _ready = false;
  bool _failed = false;
  int _generation = 0;
  bool _failureReported = false;

  void _reportFailure() {
    if (_failureReported) return;
    _failureReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFailure?.call();
    });
  }

  @override
  void initState() {
    super.initState();
    _video = mk.Player();
    _controller = VideoController(
      _video,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    _positionSubscription = _video.stream.position.listen((position) {
      // Ignore repeat-loop position resets, but count actual forward motion.
      if (position > _lastPosition + const Duration(milliseconds: 150) ||
          position < _lastPosition - const Duration(milliseconds: 500)) {
        _lastProgress = DateTime.now();
      }
      _lastPosition = position;
    });
    _completedSubscription = _video.stream.completed.listen((completed) {
      if (completed && _ready && !_recovering) {
        debugPrint('[Orchid Artwork] Loop reached EOF; restarting canvas');
        unawaited(_recoverPlayback());
      }
    });
    // HLS can silently freeze without emitting an mpv error or completion.
    // Inspect only this standalone silent artwork player, never music audio.
    _stallWatchdog = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_ready || _failed || _recovering) return;
      final stalledFor = DateTime.now().difference(_lastProgress);
      if (stalledFor >= const Duration(seconds: 9)) {
        debugPrint('[Orchid Artwork] Canvas stalled for '
            '${stalledFor.inSeconds}s; recovering playback');
        unawaited(_recoverPlayback());
      }
    });
    _errorSubscription = _video.stream.error.listen((message) {
      debugPrint('[Orchid Artwork] MPV error: $message');
      if (!mounted || _failed || _recovering) return;
      // Transient HLS failures should retry before disabling animation.
      unawaited(_recoverPlayback());
    });
    _start();
  }

  Future<void> _recoverPlayback() async {
    if (_recovering || !mounted || _failed) return;
    _recovering = true;
    try {
      if (++_recoveries > 3) {
        debugPrint('[Orchid Artwork] Repeated stalls; using still cover');
        if (mounted) setState(() { _failed = true; _ready = false; });
        _reportFailure();
        return;
      }
      await _video.stop();
      if (!mounted) return;
      await _start();
    } catch (e) {
      debugPrint('[Orchid Artwork] Recovery failed: $e');
      if (_recoveries >= 3 && mounted) {
        setState(() { _failed = true; _ready = false; });
        _reportFailure();
      }
    } finally {
      _recovering = false;
    }
  }

  Future<void> _start() async {
    final generation = ++_generation;
    _lastProgress = DateTime.now();
    _lastPosition = Duration.zero;
    _failureReported = false;
    if (mounted) {
      setState(() {
        _ready = false;
        _failed = false;
      });
    }
    try {
      await _video.setVolume(0);
      if (generation != _generation) return;
      await _video.setPlaylistMode(mk.PlaylistMode.single);
      if (generation != _generation) return;
      final playableUrl = await HlsVariantService.instance.preferredUrl(
        widget.url, efficient: widget.efficient);
      if (generation != _generation) return;
      await _video.open(mk.Media(playableUrl, httpHeaders: const {
        'User-Agent': 'Mozilla/5.0',
        'Accept': '*/*',
      }));
      if (!mounted || generation != _generation) return;
      // MPV can report "playing" while the texture still contains a black
      // frame. Wait for media_kit_video's actual first-render notification.
      await _controller.waitUntilFirstFrameRendered
          .timeout(const Duration(seconds: 15));
      if (!mounted || generation != _generation || _failed) return;
      setState(() => _ready = true);
      _lastProgress = DateTime.now();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation && !_failed) {
          widget.onReady?.call();
        }
      });
    } catch (e) {
      debugPrint('[Orchid Artwork] Video could not open: $e');
      if (mounted && generation == _generation) {
        setState(() {
          _failed = true;
          _ready = false;
        });
        _reportFailure();
      }
    }
  }

  @override
  void didUpdateWidget(covariant CanvasVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url ||
        widget.efficient != oldWidget.efficient) {
      // Invalidate any earlier asynchronous HLS load before replacing media.
      ++_generation;
      _recoveries = 0;
      _recovering = false;
      unawaited(_video.stop().then((_) {
        if (mounted) return _start();
      }));
    }
  }

  @override
  void dispose() {
    ++_generation;
    _stallWatchdog?.cancel();
    _positionSubscription?.cancel();
    _completedSubscription?.cancel();
    _errorSubscription?.cancel();
    unawaited(_video.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget cover() {
      final url = widget.fallbackArtworkUrl;
      if (url != null && url.startsWith('https://')) {
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) =>
              const Center(child: Icon(LucideIcons.music2, size: 52)),
        );
      }
      return const Center(child: Icon(LucideIcons.music2, size: 52));
    }
    // Keep the video mounted from the first build so its first frame can
    // actually render, but paint the static artwork above it until then.
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_failed)
            Video(
              controller: _controller,
              controls: NoVideoControls,
              fit: BoxFit.cover,
            ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _ready && !_failed ? 0 : 1,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              child: cover(),
            ),
          ),
        ],
      ),
    );
  }
}
