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
