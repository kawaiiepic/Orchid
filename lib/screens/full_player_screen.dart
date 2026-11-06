import 'package:cached_network_image/cached_network_image.dart';
import 'package:orchid/widgets/karaoke_lyrics.dart';
import 'package:orchid/widgets/liquid_artwork_background.dart';
import 'package:orchid/widgets/queue_sheet.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lyrics_service.dart';
import '../services/player_service.dart';
import '../services/animated_artwork_service.dart';
import '../widgets/canvas_video.dart';
import '../widgets/content_drawer.dart';

class FullPlayerScreen extends StatefulWidget {
  final PlayerService player;

  const FullPlayerScreen({super.key, required this.player});

  @override
  State<StatefulWidget> createState() => _FullPlayerScreen();
}

class _FullPlayerScreen extends State<FullPlayerScreen> {
  // Two views only: animated/static artwork or lyrics.
  int _viewMode = 1;
  bool _animatedEnabled = true;
  bool _animationFailed = false;
  static const _animatedPreferenceKey = 'orchid_animated_artwork_enabled';
  OverlayEntry? _optionsOverlay;
  AnimatedArtwork? _appleArtwork;
  bool _appleLoading = false;
  String? _artworkTrackKey;
  int _artworkRequest = 0;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_onTrackChanged);
    _onTrackChanged();
    _restoreArtworkPreference();
  }

  void _onTrackChanged() {
    final track = widget.player.current;
    final key = '${track?.artist ?? ''}|${track?.album ?? ''}|${track?.title ?? ''}';
    if (key == _artworkTrackKey) return;
    _artworkTrackKey = key;
    final request = ++_artworkRequest;
    final canSearch = track != null &&
        track.artist.trim().isNotEmpty &&
        track.title.trim().isNotEmpty;
    setState(() {
      _appleArtwork = null;
      _appleLoading = canSearch;
      _animationFailed = false;
    });
    if (!canSearch || track == null) return;
    AnimatedArtworkService.instance.fetch(
      artist: track.artist,
      album: track.album,
      title: track.title,
    ).then((artwork) {
      if (!mounted || request != _artworkRequest) return;
      setState(() {
        _appleArtwork = artwork;
        _appleLoading = false;
      });
    });
  }

  @override
  void dispose() {
    ++_artworkRequest;
    _closeOptions();
    widget.player.removeListener(_onTrackChanged);
    super.dispose();
  }

  Future<void> _restoreArtworkPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) setState(() {
        _animatedEnabled = prefs.getBool(_animatedPreferenceKey) ?? true;
      });
    } catch (_) {
      // Animated covers remain enabled by default if storage is unavailable.
    }
  }

  Future<void> _setAnimatedEnabled(bool enabled) async {
    setState(() {
      _animatedEnabled = enabled;
      if (enabled) _animationFailed = false;
    });
    _closeOptions();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_animatedPreferenceKey, enabled);
    } catch (_) {}
  }

  void _closeOptions() {
    _optionsOverlay?.remove();
    _optionsOverlay?.dispose();
    _optionsOverlay = null;
  }

  void _showOptions() {
    _closeOptions();
    final top = MediaQuery.paddingOf(context).top + 54;
    _optionsOverlay = OverlayEntry(
      builder: (_) => Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeOptions,
          ),
        ),
        Positioned(
          top: top, right: 12,
          child: Container(
            width: 252,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF211C2C),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF5D496A)),
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setAnimatedEnabled(!_animatedEnabled),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15, vertical: 12),
                child: Row(children: [
                  Icon(_animatedEnabled
                      ? LucideIcons.check : LucideIcons.image, size: 18),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_animatedEnabled
                      ? 'Disable animated artwork'
                      : 'Enable animated artwork').small()),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_optionsOverlay!);
  }

  void _artworkFailed() {
    if (mounted && !_animationFailed) {
      setState(() => _animationFailed = true);
    }
  }

  Widget _animatedArtworkBody(ColorScheme scheme) {
    final artwork = _appleArtwork;
    if (artwork == null || !_animatedEnabled || _animationFailed) {
      return _artworkBody(scheme);
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: artwork.portrait ? 380 : 450),
              child: AspectRatio(
                aspectRatio: artwork.portrait ? 9 / 16 : 1,
                child: CanvasVideo(
                  key: ValueKey(artwork.url),
                  url: artwork.url,
                  fallbackArtworkUrl: widget.player.current?.artworkUrl,
                  onFailure: _artworkFailed,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// Full-bleed animation for narrow/mobile player layouts. The video fills
  /// the viewport, with dark gradients keeping controls readable.
  Widget _mobileAnimatedBackdrop() {
    final artwork = _appleArtwork;
    final cover = widget.player.current?.artworkUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (artwork != null)
          CanvasVideo(
            key: ValueKey('mobile-${artwork.url}'),
            url: artwork.url,
            fallbackArtworkUrl: cover,
            onFailure: _artworkFailed,
          )
        else if (cover != null && cover.startsWith('https://'))
          CachedNetworkImage(
            imageUrl: cover,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF14111D)),
          )
        else
          const ColoredBox(color: Color(0xFF14111D)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.23, 0.48, 0.73, 1.0],
              colors: [
                Color(0xC9000000),
                Color(0x31000000),
                Color(0x16000000),
                Color(0xA9000000),
                Color(0xEE000000),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobileTrackDetails() {
    final track = widget.player.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            track?.title ?? 'No track playing',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 24, fontWeight: FontWeight.w700,
              color: Color(0xFFFFFFFF),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            track?.artist ?? 'Unknown artist',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, color: Color(0xFFDCCDF0)),
          ),
        ],
      ),
    );
  }

  void _nextView() {
    setState(() => _viewMode = _viewMode == 0 ? 1 : 0);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:${m.padLeft(2, '0')}:$s';
    return '$m:$s';
  }

  String? _currentLine(LyricsResult? lyrics, double t) {
    if (lyrics == null || !lyrics.hasAny) return null;
    if (lyrics.lines.isEmpty) {
      final plain = lyrics.displayText.trim();
      if (plain.isEmpty) return null;
      return plain.split('\n').first;
    }
    final i = lyrics.lineIndexAt(t);
    if (i < 0) return null;
    final line = lyrics.lines[i];
    if (line.isInterlude) return '• • •';
    final text = line.text.trim();
    return text.isEmpty ? null : text;
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v < -400 && widget.player.hasNext) {
      widget.player.playNext();
    } else if (v > 400) {
      widget.player.playPrevious();
    }
  }

  Widget _lyricsBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey(widget.player.lyricsGeneration),
        child: KaraokeLyrics(
          player: widget.player.player,
          lyrics: widget.player.lyrics,
          loading: widget.player.lyricsLoading,
        ),
      ),
    );
  }

  Widget _artworkBody(ColorScheme scheme) {
    final track = widget.player.current;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (track?.artworkUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: track!.artworkUrl!,
              width: 280,
              height: 280,
              fit: BoxFit.cover,
            ),
          )
        else
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              color: scheme.muted,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          track?.title ?? 'No track playing',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          track?.artist ?? 'Unknown artist',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: scheme.primary),
        ),
        const SizedBox(height: 16),
        StreamBuilder<Duration>(
          stream: widget.player.player.positionStream,
          initialData: widget.player.player.position,
          builder: (context, snap) {
            final t = (snap.data ?? Duration.zero).inMilliseconds / 1000.0;
            final line = _currentLine(widget.player.lyrics, t);
            if (line == null) {
              if (widget.player.lyricsLoading) {
                return const Text('Loading lyrics…').small().muted();
              }
              return const SizedBox(height: 20);
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                line,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: scheme.foreground.withOpacity(0.92),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).shortestSide < 600;
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        final track = widget.player.current;
        final mobileAnimated = isMobile &&
            _animatedEnabled && _appleArtwork != null && !_animationFailed;
        return Scaffold(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: mobileAnimated
                    ? _mobileAnimatedBackdrop()
                    : LiquidArtworkBackground(
                        imageUrl: track?.artworkUrl,
                        child: const SizedBox.expand(),
                      ),
              ),
              Positioned.fill(
                child: GestureDetector(
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: SafeArea(
                child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Center the source label independently of the buttons.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 56),
                          child: Center(
                            child: Text(
                              !widget.player.resolving &&
                                      widget.player.playingVia != null
                                  ? widget.player.sourceLabel
                                  : 'Now playing',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: mobileAnimated
                                    ? const Color(0xFFF2E8FF)
                                    : scheme.primary,
                              ),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              variance: ButtonVariance.ghost,
                              onPressed: () => dismissContentDrawer(context),
                              icon: const Icon(LucideIcons.arrowLeft),
                            ),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              OverlayAnchor(
                                anchor: #orchidQueueDrawer,
                                child: IconButton(
                                  variance: ButtonVariance.ghost,
                                  onPressed: () =>
                                      showQueueSheet(context, widget.player),
                                  icon: const Icon(LucideIcons.listMusic),
                                ),
                              ),
                              IconButton(
                                variance: ButtonVariance.ghost,
                                onPressed: _showOptions,
                                icon: const Icon(LucideIcons.ellipsis),
                              ),
                            ]),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: mobileAnimated
                        ? (_viewMode == 0
                            ? Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: _lyricsBody(),
                              )
                            : Align(
                                alignment: Alignment.bottomCenter,
                                child: _mobileTrackDetails(),
                              ))
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _viewMode == 0
                                ? _lyricsBody()
                                : _animatedArtworkBody(scheme),
                          ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: StreamBuilder<Duration>(
                      stream: widget.player.player.positionStream,
                      initialData: widget.player.player.position,
                      builder: (context, snapshot) {
                        final pos = snapshot.data ?? Duration.zero;
                        final dur =
                            widget.player.player.duration ?? Duration.zero;
                        final maxMs = dur.inMilliseconds.toDouble();
                        final hasDur = maxMs > 0 && maxMs.isFinite;
                        final posMs = hasDur
                            ? pos.inMilliseconds
                                .toDouble()
                                .clamp(0.0, maxMs)
                            : 0.0;

                        return Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Slider(
                                value: SliderValue.single(posMs),
                                min: 0,
                                max: hasDur ? maxMs : 1,
                                onChanged: hasDur
                                    ? (v) => widget.player.seek(
                                          Duration(
                                            milliseconds:
                                                v.value.round().clamp(
                                              0,
                                              maxMs.round(),
                                            ),
                                          ),
                                        )
                                    : null,
                              ),
                            ),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _fmt(pos),
                                  style: TextStyle(color: scheme.primary),
                                ),
                                Text(
                                  _fmt(dur),
                                  style: TextStyle(color: scheme.primary),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            variance: ButtonVariance.ghost,
                            onPressed: () => widget.player.playPrevious(),
                            icon: const Icon(LucideIcons.skipBack),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            variance: ButtonVariance.ghost,
                            onPressed: widget.player.togglePlayPause,
                            icon: Icon(
                              widget.player.player.playing
                                  ? LucideIcons.pause
                                  : LucideIcons.play,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            variance: ButtonVariance.ghost,
                            onPressed: widget.player.hasNext
                                ? () => widget.player.playNext()
                                : null,
                            icon: const Icon(LucideIcons.skipForward),
                          ),
                        ],
                      ),
                      Positioned(
                        right: 12,
                        child: IconButton(
                          variance: ButtonVariance.ghost,
                          onPressed: () {
                            _nextView();
                          },
                          icon: Icon(
                            _viewMode == 0
                                ? LucideIcons.image
                                : LucideIcons.mic,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Row(
                      children: [
                        Icon(widget.player.volume == 0
                            ? LucideIcons.volumeX
                            : LucideIcons.volume2, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Slider(
                            value: SliderValue.single(widget.player.volume),
                            min: 0,
                            max: 1,
                            onChanged: (value) =>
                                widget.player.setVolume(value.value),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 42,
                          child: Text(
                            '${(widget.player.volume * 100).round()}%',
                            textAlign: TextAlign.end,
                          ).xSmall().muted(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
              ),
              ),
              ),
            ],
          ),
        );
      },
    );
  }
}
