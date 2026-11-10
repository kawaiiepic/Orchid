import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../services/music_library.dart';
import '../services/addon_service.dart';
import '../models/addon.dart';
import 'music_detail_pages.dart';
import '../widgets/orchid_style.dart';
import '../widgets/orchid_adaptive_controls.dart';
import '../widgets/artist_artwork.dart';
import '../widgets/apple_cover.dart';
import '../widgets/song_context_menu.dart';
import '../widgets/track_duration.dart';

class OrchidHomeScreen extends StatefulWidget {
  final Widget header;
  final PlayerService player;
  final MusicLibrary library;
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final OrchidAccount account;
  final VoidCallback openExplore;
  final VoidCallback openLibrary;
  final VoidCallback openReplay;
  final VoidCallback openRadio;
  final VoidCallback openTopSongs;
  final VoidCallback openAiDj;
  final VoidCallback openProfile;

  const OrchidHomeScreen({
    super.key,
    required this.header,
    required this.player,
    required this.library,
    required this.addonService,
    required this.addons,
    required this.account,
    required this.openExplore,
    required this.openLibrary,
    required this.openReplay,
    required this.openRadio,
    required this.openTopSongs,
    required this.openAiDj,
    required this.openProfile,
  });

  @override
  State<OrchidHomeScreen> createState() => _OrchidHomeScreenState();
}

class _OrchidHomeScreenState extends State<OrchidHomeScreen> {
  Map<String, dynamic>? _history;
  Map<String, dynamic>? _monthlyStats;
  DateTime? _monthlyPeriod;
  List<List<SavedSong>> _homeMixes = [];
  bool _loading = false;
  String? _error;
  String? _homeAccount;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_accountChanged);
    widget.account.listeningRevision.addListener(_listeningChanged);
    _accountChanged();
  }

  @override
  void didUpdateWidget(covariant OrchidHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account) {
      oldWidget.account.removeListener(_accountChanged);
      oldWidget.account.listeningRevision.removeListener(_listeningChanged);
      widget.account.addListener(_accountChanged);
      widget.account.listeningRevision.addListener(_listeningChanged);
      _accountChanged();
    }
  }

  void _listeningChanged() {
    if(widget.account.signedIn) _refresh();
  }

  void _accountChanged() {
    final user = widget.account.signedIn
        ? (widget.account.email ?? widget.account.username)
        : null;
    if (_homeAccount == user) return;
    _homeAccount = user;
    _requestId++;
    _history = null;
    _monthlyStats = null;
    _monthlyPeriod = null;
    _homeMixes = [];
    _error = null;
    if (user != null) {
      _refresh();
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (!widget.account.signedIn) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // All home metadata comes from Orchid history and Apple Music charts.
      // Last.fm is only used to scrobble, never as a UI catalog.
      final result = await widget.account.orchidHome();
      if (!mounted || requestId != _requestId) return;
      setState(() => _history = result);
      // Load this month's personal listening metrics independently of Home.
      _loadMonthlyStats(requestId);
      // The home cards show the same D1-generated mixes as the detail page.
      _loadHomeMixes(requestId);
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMonthlyStats(int requestId) async {
    final now = DateTime.now();
    try {
      final response = await widget.account.replay(
        year: now.year, month: now.month);
      if (!mounted || requestId != _requestId) return;
      final raw = response['stats'];
      setState(() {
        _monthlyPeriod = now;
        _monthlyStats = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      });
    } catch (error) {
      debugPrint('[Orchid Home] Monthly listening stats unavailable: $error');
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _monthlyPeriod = now;
        _monthlyStats = null;
      });
    }
  }

  Widget _monthlyListening() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final period = _monthlyPeriod ?? DateTime.now();
    final header = '${months[period.month - 1]} ${period.year}';
    final stats = _monthlyStats;
    if (stats == null) {
      return Text(
        _loading ? 'Loading this month’s listening…'
          : 'This month’s listening data is unavailable.',
        style: const TextStyle(fontSize: 13, color: Color(0xFFA99BB7)),
      );
    }
    final plays = _count(stats['plays']);
    final songs = _count(stats['songs']);
    final artists = _count(stats['artists']);
    final seconds = (stats['seconds'] as num?)?.toInt() ?? 0;
    final hours = (seconds / 3600).toStringAsFixed(1);
    return Wrap(
      spacing: 20,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(header, style: const TextStyle(
          fontSize: 13, color: Color(0xFFC7B8D8),
          fontWeight: FontWeight.w600)),
        Text('$plays plays', style: const TextStyle(
          fontSize: 13, color: Color(0xFFF3EAFB))),
        Text('$songs songs', style: const TextStyle(
          fontSize: 13, color: Color(0xFFF3EAFB))),
        Text('$artists artists', style: const TextStyle(
          fontSize: 13, color: Color(0xFFF3EAFB))),
        Text('$hours hours', style: const TextStyle(
          fontSize: 13, color: Color(0xFFF3EAFB))),
      ],
    );
  }

  Future<void> _loadHomeMixes(int requestId) async {
    try {
      final response=await widget.account.dailyMixes();
      if(!mounted||requestId!=_requestId)return;
      final raw=response['mixes'];
      if(raw is! List)return;
      setState(() => _homeMixes=raw.map((mix) {
        if(mix is! Map||mix['tracks'] is! List)return <SavedSong>[];
        return (mix['tracks'] as List).whereType<Map>().map((song) =>
          SavedSong(
            (song['title']??'').toString(),
            (song['artist']??'').toString(),
            album:song['album']?.toString(),
            artwork:song['image']?.toString(),
          ),
        ).where((song)=>song.title.isNotEmpty&&song.artist.isNotEmpty).toList();
      }).toList());
    }catch(error){
      debugPrint('[Orchid Home] Daily Mix preview unavailable: $error');
    }
  }

  @override
  void dispose() {
    widget.account.removeListener(_accountChanged);
    widget.account.listeningRevision.removeListener(_listeningChanged);
    super.dispose();
  }

  List<Map<String, dynamic>> _items(String key) {
    final raw = _history?[key];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList();
  }

  /// Last.fm may report the same song repeatedly. Keep the most recent
  /// occurrence while preserving listening-order and now-playing metadata.
  List<Map<String, dynamic>> _uniqueRecent() {
    final seen = <String>{};
    return _items('recent').where((track) {
      String norm(Object? value) => (value ?? '').toString()
          .toLowerCase()
          // Collapse common Last.fm edition labels, but leave live/acoustic
          // performances distinct from the studio recording.
          .replaceAll(RegExp(
              r'\s*[\(\[]?(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?[\)\]]?',
              caseSensitive: false), '')
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
      final key = '${norm(track['artist'])}|${norm(track['title'])}';
      return key != '|' && seen.add(key);
    }).toList();
  }



  /// Artwork-first home tile shared by mixes, playlists, and features.
  /// Text is part of the image rather than a separate bordered panel.
  Widget _coverTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? artwork,
    IconData? icon,
    List<Color>? colors,
    IconData? badge,
    double? width,
    double? height,
    bool desktopLandscape = false,
    bool desktopCircle = false,
  }) {
    final desktop = _desktop;
    if (desktop && desktopLandscape) {
      final wideWidth = width ?? 294.0;
      final wideHeight = height ?? 174.0;
      return _clickable(
        onTap: onTap,
        child: SizedBox(
          width: wideWidth, height: wideHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(fit: StackFit.expand, children: [
              if (artwork != null)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(width: wideWidth, height: wideWidth,
                    child: artwork),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors ?? const [
                        Color(0xFF77459B),
                        Color(0xFF372847),
                        Color(0xFF171421),
                      ],
                    ),
                  ),
                  child: Center(child: Icon(
                    icon ?? LucideIcons.music2,
                    size: 70,
                    color: const Color(0x88F6E5FF),
                  )),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0x30000000),
                      Color(0xEB090612),
                    ],
                  ),
                ),
              ),
              if (badge != null)
                Positioned(top: 12,right: 12,
                  child: Icon(badge, size: 18,
                    color: const Color(0xFFE6DBF4))),
              Positioned(
                left: 16, right: 16, bottom: 15,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 19, fontWeight: FontWeight.w700,
                      )),
                    const SizedBox(height: 4),
                    Text(subtitle, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE6DEED), fontSize: 12)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );
    }
    final cardWidth = width ?? (desktop ? 186.0 : OrchidStyle.compact(context, 186));
    final cardHeight = height ?? (desktop ? 226.0 : OrchidStyle.compact(context, 216));
    if (desktop) {
      return _clickable(
        onTap: onTap,
        child: SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: Column(
            crossAxisAlignment: desktopCircle
              ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(fit: StackFit.expand, children: [
                    if (artwork != null)
                      desktopCircle
                        ? Center(
                            child: ClipOval(
                              child: SizedBox(
                                width: cardWidth * .62,
                                height: cardWidth * .62,
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: cardWidth, height: cardWidth,
                                    child: artwork,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: cardWidth, height: cardWidth,
                              child: artwork,
                            ),
                          )
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: colors ?? const [
                              Color(0xFF7A3DB3),
                              Color(0xFF332247),
                              Color(0xFF151326),
                            ],
                          ),
                        ),
                        child: Center(child: Icon(
                          icon ?? LucideIcons.music2,
                          size: 58,
                          color: const Color(0xFFF6E5FF),
                        )),
                      ),
                    if (badge != null)
                      Positioned(
                        top: 9, right: 9,
                        child: Icon(badge, size: 16,
                          color: const Color(0xFFF6E5FF)),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 7),
              Text(title, maxLines: 1,
                textAlign: desktopCircle ? TextAlign.center : TextAlign.start,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: Color(0xFFF5EDFF))),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 1,
                textAlign: desktopCircle ? TextAlign.center : TextAlign.start,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11, color: Color(0xFFA99BB7))),
            ],
          ),
        ),
      );
    }
    return _clickable(
      onTap: onTap,
      child: SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (artwork != null)
                ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: cardWidth,
                      height: cardWidth,
                      child: artwork,
                    ),
                  ),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors ?? const [
                        Color(0xFF7A3DB3),
                        Color(0xFF332247),
                        Color(0xFF151326),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      icon ?? LucideIcons.music2,
                      size: OrchidStyle.compact(context, 62),
                      color: const Color(0xFFF6E5FF),
                    ),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.37, 0.70, 1],
                    colors: [
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0x99000000),
                      Color(0xE9000000),
                    ],
                  ),
                ),
              ),
              if (badge != null)
                Positioned(
                  top: 11,
                  right: 11,
                  child: Icon(
                    badge,
                    size: 19,
                    color: const Color(0xFFF8F5FF),
                  ),
                ),
              Positioned(
                left: 13,
                right: 13,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.14,
                        shadows: [Shadow(blurRadius: 8, color: Color(0xAA000000))],
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFE6E0E9),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _desktop => (kIsWeb || (
      defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.android)) &&
      MediaQuery.sizeOf(context).width >= 850;

  Widget _desktopShortcuts() => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final playlists = widget.library.visiblePlaylists;
      return LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth >= 940 ? 3 : 2;
        const gap = 10.0;
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        Widget shortcut(String label, String subtitle, String? artist,
            String? song, String? artwork) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.openLibrary,
            child: Container(
              width: width,
              height: 60,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF34243A),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(children: [
                if (song != null && artist != null)
                  AppleCover(artist: artist, name: song,
                    fallbackUrl: artwork, size: 60, radius: 0)
                else
                  const SizedBox(
                    width: 60, height: 60,
                    child: ColoredBox(
                      color: Color(0xFF6B4284),
                      child: Icon(LucideIcons.heart, size: 24,
                        color: Color(0xFFECD5FF)),
                    ),
                  ),
                const SizedBox(width: 11),
                Expanded(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: Color(0xFFF5EDFF))),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10, color: Color(0xFFA69AB4))),
                  ],
                )),
                const SizedBox(width: 8),
              ]),
            ),
          );
        }
        final items = <Widget>[
          shortcut('Favorites',
            '${widget.library.favorites.length} songs',
            widget.library.favorites.isNotEmpty
              ? widget.library.favorites.first.artist : null,
            widget.library.favorites.isNotEmpty
              ? widget.library.favorites.first.title : null,
            widget.library.favorites.isNotEmpty
              ? widget.library.favorites.first.artwork : null),
          for (final p in playlists.take(8))
            shortcut(p.name, '${p.songs.length} songs',
              p.songs.isNotEmpty ? p.songs.first.artist : null,
              p.songs.isNotEmpty ? p.songs.first.title : null,
              p.songs.isNotEmpty ? p.songs.first.artwork : null),
        ];
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items,
        );
      });
    },
  );

  Widget _pinnedPlaylists() => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final playlists = widget.library.visiblePlaylists.where((p) => p.pinned).toList();
      if (playlists.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OrchidSectionHeader(
            title: 'Pinned playlists',
            subtitle: 'Your favorites, right where you left them',
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final playlist in playlists) ...[
                  _coverTile(
                    title: playlist.name,
                    subtitle: '${playlist.songs.length} songs',
                    badge: LucideIcons.pin,
                    artwork: playlist.songs.isNotEmpty
                        ? AppleCover(
                            artist: playlist.songs.first.artist,
                            name: playlist.songs.first.title,
                            fallbackUrl: playlist.songs.first.artwork,
                            size: OrchidStyle.compact(context, 186),
                            radius: 0,
                          )
                        : null,
                    onTap: () {
                      if (playlist.songs.isEmpty) return;
                      widget.player.setAddons(widget.addons);
                      final queue = playlist.songs.map((song) => TrackResult(
                        id: song.key,
                        title: song.title,
                        artist: song.artist,
                        album: song.album,
                        artworkUrl: song.artwork,
                        sourceId: 'orchid-library',
                        sourceName: 'Library',
                      )).toList();
                      widget.player.playTrack(queue.first, fromQueue: queue)
                        .catchError((Object e) {
                          debugPrint('[Orchid] Cannot play pinned playlist: $e');
                        });
                    },
                  ),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ),
          SizedBox(height: OrchidStyle.compact(context, 28)),
        ],
      );
    },
  );

  void _playHomeMix(int index) {
    if (index < 0 || index >= _homeMixes.length ||
        _homeMixes[index].isEmpty) {
      widget.openExplore();
      return;
    }
    final tracks = _homeMixes[index].map((song) => TrackResult(
      id: song.key,
      title: song.title,
      artist: song.artist,
      album: song.album,
      artworkUrl: song.artwork,
      sourceId: 'orchid-daily-mix',
      sourceName: 'Daily Mix',
    )).toList();
    widget.player.setAddons(widget.addons);
    widget.player.playTrack(tracks.first, fromQueue: tracks)
      .catchError((Object e) {
        debugPrint('[Orchid Home] Could not play mix: $e');
      });
  }

  Widget _dailyMixCards() => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final source = _homeMixes;
      const titles = ['Favorites Mix', 'Similar Sounds', 'Discover'];
      const subtitles = [
        'Your comfort songs',
        'Songs in your orbit',
        'Something different',
      ];
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < titles.length; i++) ...[
              _coverTile(
                title: titles[i],
                subtitle: subtitles[i],
                badge: LucideIcons.sparkles,
                desktopLandscape: true,
                colors: const [
                  Color(0xFF7131A6),
                  Color(0xFF33274E),
                  Color(0xFF171526),
                ],
                artwork: i < source.length && source[i].isNotEmpty
                    ? AppleCover(
                        artist: source[i].first.artist,
                        name: source[i].first.title,
                        fallbackUrl: source[i].first.artwork,
                        size: OrchidStyle.compact(context, 186),
                        radius: 0,
                      )
                    : null,
                onTap: () => _playHomeMix(i),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      );
    },
  );

  Widget _madeForYouCard() => _coverTile(
    title: 'Replay',
    subtitle: 'Your listening story',
    icon: LucideIcons.audioLines,
    badge: LucideIcons.sparkles,
    colors: const [
      Color(0xFFA348A2),
      Color(0xFF5C266B),
      Color(0xFF20142E),
    ],
    onTap: widget.openReplay,
    desktopLandscape: true,
    width: _desktop ? 274 : null,
    height: _desktop ? 158 : null,
  );

  Widget _personalCard(
    String title,
    String subtitle,
    IconData icon,
    List<Color> colors,
    VoidCallback onTap,
  ) => _coverTile(
    title: title,
    subtitle: subtitle,
    icon: icon,
    colors: colors,
    onTap: onTap,
    desktopLandscape: true,
    width: _desktop ? 274 : null,
    height: _desktop ? 158 : null,
  );

  String _count(dynamic value) {
    final number = value is num ? value : num.tryParse('$value') ?? 0;
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}m';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}k';
    return number.toStringAsFixed(0);
  }

  Widget _clickable({required Widget child,required VoidCallback onTap}) {
    return MouseRegion(
      cursor:SystemMouseCursors.click,
      child:GestureDetector(behavior:HitTestBehavior.opaque,onTap:onTap,child:child),
    );
  }

  Widget _stat(String title, dynamic count) {
    return _clickable(
      onTap:_refresh,
      child:SizedBox(
      width: OrchidStyle.compact(context,138),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_count(count)).x2Large().semiBold(),
              const SizedBox(height: 4),
              Text(title).small().muted(),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _recentRow(Map<String, dynamic> track) {
    final artist = track['artist']?.toString() ?? '';
    final title = track['title']?.toString() ?? 'Unknown track';
    final album = track['album']?.toString() ?? '';
    final image = track['image']?.toString();
    final nowPlaying = track['nowPlaying'] == true;
    final result = TrackResult(
      id: '${artist.toLowerCase()}|${title.toLowerCase()}',
      title: title,
      artist: artist,
      album: album,
      artworkUrl: image,
      sourceId: 'orchid-history',
      sourceName: 'Orchid History',
    );
    final size = OrchidStyle.compact(context, 186);
    return SongContextMenu(
      track: result,
      player: widget.player,
      library: widget.library,
      child: _coverTile(
        title: title,
        subtitle: artist,
        width: size,
        height: OrchidStyle.compact(context, 216),
        badge: nowPlaying ? LucideIcons.audioLines : null,
        artwork: AppleCover(
          artist: artist,
          name: title,
          album: album,
          fallbackUrl: image,
          size: size,
          radius: 0,
        ),
        onTap: () {
          widget.player.setAddons(widget.addons);
          widget.player.playTrack(result).catchError((Object error) {
            debugPrint('[Orchid] Recent track playback failed: $error');
          });
        },
      ),
    );
  }

  Widget _recentCards(List<Map<String, dynamic>> tracks) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final track in tracks) ...[
            _recentRow(track),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  /// Dense desktop track rows, keeping the iOS artwork shelf unchanged.
  Widget _desktopSongList(List<Map<String, dynamic>> tracks) {
    if (!_desktop) return _recentCards(tracks.take(12).toList());
    final visible = tracks.take(12).toList();
    // Show two equally sized song columns on desktop, with reading order
    // moving left to right. Each cell retains its own context menu and play.
    return Column(
      children: [
        for (var index = 0; index < visible.length; index += 2) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _desktopSongRow(visible[index], index)),
              const SizedBox(width: 40),
              Expanded(
                child: index + 1 < visible.length
                    ? _desktopSongRow(visible[index + 1], index + 1)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          if (index + 2 < visible.length)
            const Divider(color: Color(0x293C3546)),
        ],
      ],
    );
  }

  Widget _desktopSongRow(Map<String, dynamic> track, int index) {
    final title = track['title']?.toString() ?? 'Unknown track';
    final artist = track['artist']?.toString() ?? 'Unknown artist';
    final album = track['album']?.toString();
    final image = track['image']?.toString();
    final seconds = track['duration'] is num
        ? (track['duration'] as num).toInt()
        : int.tryParse(track['duration']?.toString() ?? '');
    final duration = trackDurationLabel(seconds);
    final song = TrackResult(
      id: '${artist.toLowerCase()}|${title.toLowerCase()}',
      title: title,
      artist: artist,
      album: album,
      artworkUrl: image,
      duration: seconds,
      sourceId: 'orchid-history',
      sourceName: 'Orchid History',
    );
    return SongContextMenu(
      track: song,
      player: widget.player,
      library: widget.library,
      showMenuButton: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.player.setAddons(widget.addons);
            widget.player.playTrack(song).catchError((Object error) {
              debugPrint('[Orchid] Song playback failed: $error');
            });
          },
          child: Container(
            height: 54,
            padding: const EdgeInsets.fromLTRB(5, 0, 45, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              SizedBox(
                width: 24,
                child: Text('${index + 1}',
                  style: const TextStyle(color: Color(0xFF8C8498),
                    fontSize: 12)),
              ),
              AppleCover(
                artist: artist, name: title, album: album,
                fallbackUrl: image, size: 34, radius: 6,
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFF3EDFA),
                        fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(height: 3),
                    Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFA89FB5),
                        fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(duration ?? '—', textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 11, color: Color(0xFFB2A9BC))),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showMusicDetail(Map<String, dynamic> item, {required bool isAlbum}) {
    if (isAlbum) {
      openAlbumPage(context,
        artist: item['artist']?.toString() ?? '',
        album: item['name']?.toString() ?? '',
        artwork: item['image']?.toString(),
        player: widget.player,
        addonService: widget.addonService,
        addons: widget.addons,
        library: widget.library);
    } else {
      openArtistPage(context,
        account: widget.account,
        artist: item['name']?.toString() ?? '',
        artwork: item['image']?.toString(),
        player: widget.player,
        addonService: widget.addonService,
        addons: widget.addons,
        library: widget.library);
    }
  }

  Widget _topCard(Map<String, dynamic> item, {required bool isAlbum}) {
    final title = item['name']?.toString() ?? 'Unknown';
    final artist = item['artist']?.toString() ?? '';
    final size = OrchidStyle.compact(context, 186);
    return _coverTile(
      title: title,
      subtitle: isAlbum ? artist : '${_count(item['plays'])} plays',
      width: size,
      desktopCircle: !isAlbum,
      height: _desktop && !isAlbum ? 172 : OrchidStyle.compact(context, 216),
      artwork: isAlbum
          ? AppleCover(
              artist: artist,
              name: title,
              isAlbum: true,
              fallbackUrl: item['image']?.toString(),
              size: size,
              radius: 0,
            )
          : ArtistArtwork(
              artist: title,
              size: size,
              fallbackUrl: item['image']?.toString(),
              radius: 0,
            ),
      onTap: () => _showMusicDetail(item, isAlbum: isAlbum),
    );
  }

  Widget _horizontalItems(List<Map<String, dynamic>> items, {required bool albums}) {
    if (items.isEmpty) {
      return const Text('Nothing here yet.').muted();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items) ...[
            _topCard(item, isAlbum: albums),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _desktopSection(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Text(title, style: const TextStyle(
          fontSize: 19, fontWeight: FontWeight.w700,
          color: Color(0xFFF8F2FF),
        )),
        if (subtitle != null) ...[
          const SizedBox(width: 12),
          Expanded(child: Text(subtitle, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF9E91B2), fontSize: 11))),
        ],
      ]),
    );
  }

  Widget _desktopHome(Map<String, dynamic> stats) {
    const gap = SizedBox(height: 31);
    final charts = _items('charts');
    final recent = _uniqueRecent();
    return ListView(
      padding: EdgeInsets.fromLTRB(_desktop ? 28 : 16,
        _desktop ? 28 : 12, _desktop ? 30 : 16, 0),
      children: [
        widget.header,
        _desktopShortcuts(),
        gap,
        _desktopSection('Made For You'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _madeForYouCard(),
            const SizedBox(width: 13),
            _personalCard(
              'All-Time Top Songs', 'The songs that stay with you',
              LucideIcons.audioLines,
              const [Color(0xFF496B9A), Color(0xFF1E355B), Color(0xFF17182F)],
              widget.openTopSongs,
            ),
            const SizedBox(width: 13),
            _personalCard(
              'Radio', 'Pick a sound and stay awhile',
              LucideIcons.radio,
              const [Color(0xFF197F78), Color(0xFF24536D), Color(0xFF17273B)],
              widget.openRadio,
            ),
            const SizedBox(width: 13),
            _personalCard(
              'AI DJ', 'Your personal music companion',
              LucideIcons.bot,
              const [Color(0xFF4F2C59), Color(0xFF282036), Color(0xFF131625)],
              widget.openAiDj,
            ),
          ]),
        ),
        gap,
        _desktopSection('Daily Mixes'),
        _dailyMixCards(),
        gap,
        _desktopSection('New For You'),
        if (_loading && _history == null)
          const Text('Finding music for you…').muted()
        else if (charts.isNotEmpty)
          _desktopSongList(charts)
        else
          const Text('Fresh music will appear here soon.').muted(),
        gap,
        if (recent.isNotEmpty) ...[
          _desktopSection('Recently Played'),
          _desktopSongList(recent),
          gap,
        ],
        if (_items('featuredAlbums').isNotEmpty) ...[
          _desktopSection('Featured Albums'),
          _horizontalItems(_items('featuredAlbums'), albums: true),
          gap,
        ],
        if (_items('artists').isNotEmpty) ...[
          _desktopSection('Your Top Artists'),
          _horizontalItems(_items('artists'), albums: false),
          gap,
        ],
        if (_items('albums').isNotEmpty) ...[
          _desktopSection('Your Top Albums'),
          _horizontalItems(_items('albums'), albums: true),
          gap,
        ],
        if (_history != null) ...[
          _desktopSection('This Month’s Listening'),
          _monthlyListening(),
          gap,
        ],
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(
            color: Color(0xFFD7A7BA), fontSize: 12)),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft,
            child: OutlineButton(
              onPressed: _refresh, child: const Text('Try again'))),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        final stats = _history?['stats'] is Map
            ? Map<String, dynamic>.from(_history!['stats'] as Map)
            : <String, dynamic>{};
        if (_desktop) return _desktopHome(stats);
        return ListView(
          padding: EdgeInsets.fromLTRB(OrchidStyle.compact(context,20),OrchidStyle.compact(context,20),OrchidStyle.compact(context,20),OrchidStyle.compact(context,20)+OrchidStyle.iosDockClearance(context)),
          children: [
            widget.header,
            _pinnedPlaylists(),
            OrchidHero(
              eyebrow: 'Your listening space',
              title: 'Made for your ears.',
              description: 'Your favorite music, daily discoveries and the artists you keep coming back to.',
              icon: LucideIcons.audioLines,
              action: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OrchidAdaptiveControls.button(
                    prominent: true,
                    onPressed: () => widget.openDailyMixes(null),
                    child: const Text('Explore Daily Mixes'),
                  ),
                  OrchidAdaptiveControls.button(
                    onPressed: widget.openLibrary,
                    child: const Text('My Library'),
                  ),
                ],
              ),
            ),
            SizedBox(height:OrchidStyle.compact(context,28)),
            const OrchidSectionHeader(
              title: 'Made for You',
              subtitle: 'A little more personal',
            ),
            const SizedBox(height:12),
            SingleChildScrollView(scrollDirection:Axis.horizontal,
              child:Row(children:[
                _madeForYouCard(),
                const SizedBox(width:10),
                _personalCard('All-Time Top Songs','Your most-played tracks',
                  LucideIcons.trophy,
                  const [Color(0xFFC48C31),Color(0xFF774227),Color(0xFF241722)],
                  widget.openTopSongs),
                const SizedBox(width:10),
                _personalCard('Radio','Pick a vibe, play forever',
                  LucideIcons.radio,
                  const [Color(0xFF0E9E91),Color(0xFF265D83),Color(0xFF202244)],
                  widget.openRadio),

              ])),
            SizedBox(height:OrchidStyle.compact(context,28)),
            const OrchidSectionHeader(
              title: 'AI DJ',
              subtitle: 'Talk music with your personal DJ',
            ),
            const SizedBox(height:12),
            _clickable(
              onTap:widget.openAiDj,
              child:Container(
                width:double.infinity,
                padding:EdgeInsets.symmetric(horizontal:OrchidStyle.compact(context,18),vertical:OrchidStyle.compact(context,14)),
                decoration:OrchidStyle.panelDecoration(radius:15),
                child:Row(children:[
                  Icon(LucideIcons.bot,size:OrchidStyle.compact(context,22),color:OrchidStyle.lilac),
                  const SizedBox(width:12),
                  Expanded(child:const Text('Chat with AI DJ').semiBold()),
                  Icon(LucideIcons.chevronRight,size:OrchidStyle.compact(context,19),color:OrchidStyle.lilac),
                ]),
              ),
            ),
            SizedBox(height:OrchidStyle.compact(context,28)),
            const OrchidSectionHeader(
              title: 'Daily Mixes',
              subtitle: 'Fresh rotations for your listening mood',
            ),
            _dailyMixCards(),
            SizedBox(height:OrchidStyle.compact(context,28)),
            const OrchidSectionHeader(
              title: 'Your listening',
              subtitle: 'A little portrait of your music taste',

            ),
            const SizedBox(height: 10),
            if (_error != null) ...[
              Text(_error!).small(),
              const SizedBox(height: 8),
              OutlineButton(onPressed: _refresh, child: const Text('Try again')),
            ],
            if (_loading && _history == null)
              const Text('Loading your music home…').muted(),
            if (_history != null) ...[
              const OrchidSectionHeader(title: 'This month’s stats'),
              const SizedBox(height: 10),
              _monthlyListening(),
              const SizedBox(height: 24),
              const OrchidSectionHeader(title:'Recently played'),
              const SizedBox(height:10),
              if (_uniqueRecent().isEmpty)
                const Text('Play some music to start your Orchid history.').muted()
              else _recentCards(_uniqueRecent()),
              const SizedBox(height:24),
              const OrchidSectionHeader(
                title:'Popular on Apple Music',
                subtitle:'Explore something new',
              ),
              const SizedBox(height:10),
              if(_items('charts').isEmpty)
                const Text('Apple Music charts are unavailable.').muted()
              else _recentCards(_items('charts').take(12).toList()),
              const SizedBox(height:24),
              const OrchidSectionHeader(title:'Featured albums'),
              const SizedBox(height:10),
              _horizontalItems(_items('featuredAlbums'),albums:true),
              if(_items('artists').isNotEmpty)...[
                const SizedBox(height:24),
                const OrchidSectionHeader(title:'Your top artists'),
                const SizedBox(height:10),
                _horizontalItems(_items('artists'),albums:false),
              ],
              if(_items('albums').isNotEmpty)...[
                const SizedBox(height:24),
                const OrchidSectionHeader(title:'Your top albums'),
                const SizedBox(height:10),
                _horizontalItems(_items('albums'),albums:true),
              ],
            ],
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
