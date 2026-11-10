import 'package:cached_network_image/cached_network_image.dart';
import 'package:orchid/widgets/karaoke_lyrics.dart';
import 'package:orchid/widgets/liquid_artwork_background.dart';
import 'package:orchid/widgets/queue_sheet.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lyrics_service.dart';
import '../services/player_service.dart';
import '../services/music_library.dart';
import '../widgets/song_context_menu.dart';
import '../widgets/orchid_style.dart';
import '../services/animated_artwork_service.dart';
import '../widgets/canvas_video.dart';

class FullPlayerScreen extends StatefulWidget {
  final PlayerService player;
  final MusicLibrary? library;

  const FullPlayerScreen({super.key, required this.player, this.library});

  @override
  State<StatefulWidget> createState() => _FullPlayerScreen();
}

class _FullPlayerScreen extends State<FullPlayerScreen> {
  // Two views only: animated/static artwork or lyrics.
  int _viewMode = 1;
  bool _showVolume = false;
  bool _mobileLyrics = false;
  bool _mobileVideoReady = false;
  bool _mobileControlsHidden = false;
  bool _animatedEnabled = true;
  bool _animationFailed = false;
  static const _animatedPreferenceKey = 'orchid_animated_artwork_enabled';
  OverlayEntry? _optionsOverlay;
  AnimatedArtwork? _appleArtwork;
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
      _animationFailed = false;
      _mobileVideoReady = false;
    });
    if (!canSearch) return;
    AnimatedArtworkService.instance.fetch(
      artist: track.artist,
      album: track.album,
      title: track.title,
    ).then((artwork) {
      if (!mounted || request != _artworkRequest) return;
      setState(() {
        _appleArtwork = artwork;
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
      if (mounted) {
        setState(() {
          _animatedEnabled = prefs.getBool(_animatedPreferenceKey) ?? true;
        });
      }
    } catch (_) {
      // Animated covers remain enabled by default if storage is unavailable.
    }
  }

  Future<void> _setAnimatedEnabled(bool enabled) async {
    setState(() {
      _animatedEnabled = enabled;
      if (enabled) _animationFailed = false;
      _mobileVideoReady = false;
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
          child: OrchidGlassPanel(
            radius: 16,
            child: SizedBox(
              width: 252,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
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
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_optionsOverlay!);
  }

  void _artworkFailed() {
    if (mounted && !_animationFailed) {
      setState(() {
        _animationFailed = true;
        _mobileVideoReady = false;
      });
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

  Widget _libraryActions() {
    final library=widget.library;
    if(library==null)return const SizedBox.shrink();
    return ListenableBuilder(
      listenable:library,
      builder:(context, _) {
        final track=widget.player.current;
        if(track==null)return const SizedBox.shrink();
        final saved=SavedSong(
          track.title,track.artist,
          album:track.album,artwork:track.artworkUrl,duration:track.duration,
        );
        final liked=library.isFavorite(saved);
        return Padding(
          padding:const EdgeInsets.fromLTRB(20, 8, 20, 6),
          child:Row(
            mainAxisAlignment:MainAxisAlignment.center,
            children:[
              OutlineButton(
                onPressed:()=>library.toggleFavorite(saved),
                child:Row(
                  mainAxisSize:MainAxisSize.min,
                  children:[
                    Icon(LucideIcons.heart,
                      size:18,
                      color:liked?const Color(0xFFC8A2FF):null),
                    const SizedBox(width:8),
                    Text(liked?'Liked':'Like'),
                  ],
                ),
              ),
              const SizedBox(width:12),
              SongContextMenu(
                track:track,
                player:widget.player,
                library:library,
                openOnTap:true,
                child:OrchidGlassPanel(
                  radius:9,
                  child:Padding(
                    padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
                    child:const Row(
                    mainAxisSize:MainAxisSize.min,
                    children:[
                      Icon(LucideIcons.listPlus,size:18),
                      SizedBox(width:8),
                      Text('Add to playlist'),
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

  Widget _trackDetails() {
    final track=widget.player.current;
    return Padding(
      padding:const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Text(
            track?.title??'No track playing',
            textAlign:TextAlign.left,
            maxLines:2,
            overflow:TextOverflow.ellipsis,
            style:const TextStyle(fontSize:26,fontWeight:FontWeight.w700),
          ),
          const SizedBox(height:4),
          Text(
            [
              if(track!=null)track.artist,
              if(track?.album?.trim().isNotEmpty==true)track!.album!,
            ].join(' · '),
            textAlign:TextAlign.left,
            maxLines:1,
            overflow:TextOverflow.ellipsis,
            style:const TextStyle(fontSize:15,color:Color(0xFFDCCDF0)),
          ),
        ],
      ),
    );
  }

  Widget _transportControl({
    required IconData icon,
    required VoidCallback? onTap,
    bool active=false,
    double size=24,
  }) => GestureDetector(
    behavior:HitTestBehavior.opaque,
    onTap:onTap,
    child:SizedBox(
      width:48,height:56,
      child:Center(child:Icon(icon,size:size,
        color:active?const Color(0xFFD8B9FF):null)),
    ),
  );

  Widget _transportBar() => Padding(
    padding:const EdgeInsets.symmetric(horizontal:16,vertical:4),
    child:Row(
      mainAxisAlignment:MainAxisAlignment.spaceBetween,
      children:[
        _transportControl(
          icon:LucideIcons.shuffle,
          onTap:widget.player.toggleShuffle,
          active:widget.player.shuffleEnabled,
        ),
        _transportControl(
          icon:LucideIcons.skipBack,
          onTap:()=>widget.player.playPrevious(),
          size:31,
        ),
        GestureDetector(
          behavior:HitTestBehavior.opaque,
          onTap:widget.player.togglePlayPause,
          child:Container(
            width:72,height:72,
            decoration:const BoxDecoration(
              shape:BoxShape.circle,
              color:Color(0xFFD6B9FF),
            ),
            child:Icon(
              widget.player.player.playing
                  ?LucideIcons.pause:LucideIcons.play,
              size:35,color:const Color(0xFF1D1426),
            ),
          ),
        ),
        _transportControl(
          icon:LucideIcons.skipForward,
          onTap:widget.player.hasNext
              ?()=>widget.player.playNext():null,
          size:31,
        ),
        _transportControl(
          icon:widget.player.repeatMode==OrchidRepeatMode.one
              ?LucideIcons.repeat1:LucideIcons.repeat,
          onTap:widget.player.cycleRepeatMode,
          active:widget.player.repeatMode!=OrchidRepeatMode.off,
        ),
      ],
    ),
  );

  Widget _displayToggles() => Padding(
    padding:const EdgeInsets.fromLTRB(16, 2, 16, 8),
    child:Row(
      mainAxisAlignment:MainAxisAlignment.end,
      children:[
        if(_showVolume)SizedBox(
          width:110,
          child:Slider(
            value:SliderValue.single(widget.player.volume),
            min:0,max:1,
            onChanged:(value)=>widget.player.setVolume(value.value),
          ),
        ),
        IconButton(
          variance:ButtonVariance.ghost,
          onPressed:()=>setState(()=>_showVolume=!_showVolume),
          icon:Icon(widget.player.volume==0
              ?LucideIcons.volumeX:LucideIcons.volume2,size:23),
        ),
        const SizedBox(width:8),
        IconButton(
          variance:ButtonVariance.ghost,
          onPressed:_nextView,
          icon:Icon(_viewMode==0?LucideIcons.image:LucideIcons.mic,
              size:23),
        ),
      ],
    ),
  );

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
        const SizedBox(height: 12),
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
                  color: scheme.foreground.withValues(alpha: 0.92),
                ),
              ),
            );
          },
        ),
      ],
    );
  }


  // iOS-style mobile now playing. Desktop retains the original player.
  Widget _mobileNowPlaying(BuildContext context) {
    final track = widget.player.current;
    const foreground = Color(0xFFF9F5F8);
    const secondary = Color(0xD9F0E7EE);
    return Scaffold(
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Stack(fit: StackFit.expand, children: [
          LiquidArtworkBackground(
            imageUrl: track?.artworkUrl,
            intensity: 0.95,
            child: const SizedBox.expand(),
          ),
          // Play the album's animated Apple Music cover behind the entire
          // mobile player. CanvasVideo loops silently and reports HLS errors.
          // The artwork-reactive static background remains underneath as the
          // fallback if no animation exists or playback fails.
          if (_animatedEnabled && !_animationFailed &&
              _appleArtwork != null)
            Positioned.fill(
              child: ClipRect(
                child: Transform.scale(
                  // CanvasVideo normally rounds cover corners. Overscan keeps
                  // them outside the screen for an edge-to-edge background.
                  scale: 1.06,
                  child: CanvasVideo(
                    key: ValueKey('mobile-background-${_appleArtwork!.url}'),
                    url: _appleArtwork!.url,
                    fallbackArtworkUrl: track?.artworkUrl,
                    onFailure: _artworkFailed,
                    onReady: () {
                      if (!mounted || !_animatedEnabled ||
                          _animationFailed || _mobileVideoReady) return;
                      setState(() => _mobileVideoReady = true);
                    },
                  ),
                ),
              ),
            ),
          // Keep text and controls readable, even over bright video frames.
          Positioned.fill(child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF130D16).withValues(alpha: .33),
                  const Color(0xFF140A14).withValues(alpha: .45),
                  const Color(0xFF080609).withValues(alpha: .76),
                ],
                stops: const [0.0, .52, 1.0],
              )),
            ),
          )),
          if (_mobileControlsHidden)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _mobileControlsHidden = false),
                child: const SizedBox.expand(),
              ),
            )
          else SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _mobileControlsHidden = true),
              child: LayoutBuilder(builder: (context, constraints) {
              final coverSize = (constraints.maxWidth - 52)
                  .clamp(0.0, constraints.maxHeight * .44).toDouble();
              final compact = constraints.maxHeight < 690;
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(26, 12, 26, 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight:
                      (constraints.maxHeight - 32).clamp(0.0, double.infinity)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).maybePop(),
                          child: const SizedBox(
                            width: 42, height: 48,
                            child: Icon(LucideIcons.chevronDown,
                              size: 30, color: foreground),
                          ),
                        ),
                        Expanded(child: Column(children: [
                          Text('PLAYING FROM',
                            style: TextStyle(
                              color: foreground.withValues(alpha: .66),
                              fontSize: 11, letterSpacing: 2.1,
                              fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                            track?.album?.trim().isNotEmpty == true
                                ? track!.album! : 'Now Playing',
                            textAlign: TextAlign.center,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: foreground, fontSize: 15,
                              fontWeight: FontWeight.w600)),
                        ])),
                        const SizedBox(width: 42),
                      ]),
                      SizedBox(height: compact ? 16 : 22),
                      SizedBox.square(
                        dimension: coverSize,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          child: _mobileLyrics
                              ? ClipRRect(
                                  key: const ValueKey('lyrics'),
                                  borderRadius: BorderRadius.circular(12),
                                  child: _lyricsBody(),
                                )
                              : _mobileVideoReady && _animatedEnabled &&
                                  !_animationFailed
                                  ? const SizedBox.expand(
                                      key: ValueKey('animated-background'),
                                    )
                              : ClipRRect(
                                  key: ValueKey(track?.artworkUrl ?? 'no-art'),
                                  borderRadius: BorderRadius.circular(12),
                                  child: track?.artworkUrl?.startsWith('https://') == true
                                      ? CachedNetworkImage(
                                          imageUrl: track!.artworkUrl!,
                                          fit: BoxFit.cover,
                                          width: coverSize,
                                          height: coverSize,
                                          errorWidget: (_, __, ___) =>
                                              _mobileEmptyArtwork(),
                                        )
                                      : _mobileEmptyArtwork(),
                                ),
                        ),
                      ),
                      SizedBox(height: compact ? 20 : 30),
                      Row(children: [
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(track?.title ?? 'No track playing',
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: foreground, fontSize: 26,
                                height: 1.1, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text(track?.artist ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: secondary, fontSize: 18)),
                          ],
                        )),
                        if (track != null && widget.library != null) ...[
                          ListenableBuilder(
                            listenable: widget.library!,
                            builder: (context, _) {
                              final saved = SavedSong(track.title, track.artist,
                                album: track.album, artwork: track.artworkUrl,
                                duration: track.duration);
                              final liked = widget.library!.isFavorite(saved);
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => widget.library!.toggleFavorite(saved),
                                child: SizedBox(
                                  width: 46, height: 50,
                                  child: Icon(LucideIcons.star,
                                    size: 30,
                                    color: liked
                                        ? const Color(0xFFF4D98B) : secondary),
                                ),
                              );
                            },
                          ),
                          SongContextMenu(
                            track: track,
                            player: widget.player,
                            library: widget.library!,
                            openOnTap: true,
                            showMenuButton: false,
                            child: const SizedBox(
                              width: 40, height: 50,
                              child: Icon(LucideIcons.ellipsis,
                                size: 27, color: secondary),
                            ),
                          ),
                        ] else
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _showOptions,
                            child: const SizedBox(
                              width: 42, height: 50,
                              child: Icon(LucideIcons.ellipsis,
                                size: 27, color: secondary)),
                          ),
                      ]),
                      SizedBox(height: compact ? 12 : 20),
                      _mobileProgress(),
                      SizedBox(height: compact ? 16 : 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _mobileTransport(
                            LucideIcons.skipBack,
                            () => widget.player.playPrevious(), 43),
                          _mobileTransport(
                            widget.player.player.playing
                                ? LucideIcons.pause : LucideIcons.play,
                            widget.player.togglePlayPause, 58),
                          _mobileTransport(
                            LucideIcons.skipForward,
                            widget.player.hasNext
                                ? () => widget.player.playNext() : null, 43),
                        ],
                      ),
                      SizedBox(height: compact ? 17 : 26),
                      _mobileVolume(),
                      SizedBox(height: compact ? 16 : 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _mobileBottomAction(
                            _mobileLyrics ? LucideIcons.image : LucideIcons.mic,
                            () => setState(() => _mobileLyrics = !_mobileLyrics),
                            active: _mobileLyrics),
                          _mobileBottomAction(LucideIcons.shuffle,
                            widget.player.toggleShuffle,
                            active: widget.player.shuffleEnabled),
                          _mobileBottomAction(LucideIcons.listMusic,
                            () => showQueueSheet(context, widget.player)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _mobileEmptyArtwork() => const ColoredBox(
    color: Color(0x44201825),
    child: Center(child: Icon(LucideIcons.music2,
      color: Color(0x88FFFFFF), size: 64)),
  );

  Widget _mobileTransport(IconData icon, VoidCallback? action, double size) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action,
        child: SizedBox(
          width: size + 28, height: 74,
          child: Center(child: Icon(icon, size: size,
            color: action == null
                ? const Color(0x77FFFFFF) : const Color(0xFFF9F5F8))),
        ),
      );

  Widget _mobileBottomAction(IconData icon, VoidCallback action,
      {bool active = false}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action,
        child: SizedBox(
          width: 58, height: 48,
          child: Center(child: Icon(icon, size: 26,
            color: active
                ? const Color(0xFFBFE8C1) : const Color(0xD9F0E7EE))),
        ),
      );

  Widget _mobileProgress() => StreamBuilder<Duration>(
    stream: widget.player.player.positionStream,
    initialData: widget.player.player.position,
    builder: (context, snapshot) {
      final duration = widget.player.player.duration ?? Duration.zero;
      final maxMs = duration.inMilliseconds;
      final position = snapshot.data ?? Duration.zero;
      final fraction = maxMs > 0
          ? (position.inMilliseconds / maxMs).clamp(0.0, 1.0).toDouble()
          : 0.0;
      return Column(children: [
        LayoutBuilder(builder: (context, bounds) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: maxMs > 0
              ? (details) => _mobileSeek(details.localPosition.dx,
                  bounds.maxWidth, maxMs) : null,
          onHorizontalDragUpdate: maxMs > 0
              ? (details) => _mobileSeek(details.localPosition.dx,
                  bounds.maxWidth, maxMs) : null,
          child: SizedBox(height: 28, child: Center(
            child: Stack(alignment: Alignment.centerLeft, children: [
              Container(height: 4,
                decoration: BoxDecoration(
                  color: const Color(0x4CFFFFFF),
                  borderRadius: BorderRadius.circular(8))),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1D5E9),
                    borderRadius: BorderRadius.circular(8)))),
              Align(alignment: Alignment(
                (fraction * 2 - 1).clamp(-1.0, 1.0), 0),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    shape: BoxShape.circle),
                  child: SizedBox.square(dimension: 14)),
              ),
            ]),
          )),
        )),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_fmt(position), style: const TextStyle(
            color: Color(0xCCFFFFFF), fontSize: 12)),
          Text('-${_fmt(Duration(milliseconds:
              (maxMs - position.inMilliseconds).clamp(0, maxMs).toInt()))}',
              style: const TextStyle(
                color: Color(0xCCFFFFFF), fontSize: 12)),
        ]),
      ]);
    },
  );

  void _mobileSeek(double x, double width, int durationMs) {
    if (width <= 0 || durationMs <= 0) return;
    final at = (x / width).clamp(0.0, 1.0);
    widget.player.seek(Duration(milliseconds: (at * durationMs).round()));
  }

  Widget _mobileVolume() => Row(children: [
    const Icon(LucideIcons.volume1, size: 18,
      color: Color(0xBFFFFFFF)),
    const SizedBox(width: 12),
    Expanded(child: LayoutBuilder(builder: (context, bounds) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _mobileSetVolume(
          d.localPosition.dx, bounds.maxWidth),
        onHorizontalDragUpdate: (d) => _mobileSetVolume(
          d.localPosition.dx, bounds.maxWidth),
        child: SizedBox(height: 38,
          child: Center(child: Stack(children: [
            Container(height: 4,
              decoration: BoxDecoration(
                color: const Color(0x4CFFFFFF),
                borderRadius: BorderRadius.circular(8))),
            FractionallySizedBox(
              widthFactor: widget.player.volume.clamp(0.0, 1.0),
              child: Container(height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xCFFFFFFF),
                  borderRadius: BorderRadius.circular(8)))),
          ])),
        ),
      ),
    )),
    const SizedBox(width: 12),
    const Icon(LucideIcons.volume2, size: 20,
      color: Color(0xBFFFFFFF)),
  ]);

  void _mobileSetVolume(double x, double width) {
    if (width <= 0) return;
    widget.player.setVolume((x / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).shortestSide < 600;
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        if (isMobile) return _mobileNowPlaying(context);
        final track = widget.player.current;
        final mobileAnimated = isMobile &&
            _animatedEnabled && _appleArtwork != null && !_animationFailed;
        return Scaffold(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: LiquidArtworkBackground(
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
                            const SizedBox(width: 42),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                variance: ButtonVariance.ghost,
                                onPressed: () =>
                                    showQueueSheet(context, widget.player),
                                icon: const Icon(LucideIcons.listMusic),
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      // Preserve the video texture across lyrics/artwork
                      // toggles instead of remounting a black first frame.
                      child: IndexedStack(
                        index: _viewMode == 0 ? 1 : 0,
                        sizing: StackFit.expand,
                        children: [
                          _animatedArtworkBody(scheme),
                          _lyricsBody(),
                        ],
                      ),
                    ),
                  ),

                  _trackDetails(),
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

                  _transportBar(),
                  _displayToggles(),
                  _libraryActions(),
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
