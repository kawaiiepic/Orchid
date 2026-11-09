import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../services/music_library.dart';
import '../services/addon_service.dart';
import '../models/addon.dart';
import 'song_detail_screen.dart';
import 'music_detail_pages.dart';
import '../widgets/orchid_style.dart';
import '../widgets/artist_artwork.dart';
import '../widgets/apple_cover.dart';
import '../widgets/song_context_menu.dart';

class OrchidHomeScreen extends StatefulWidget {
  final Widget header;
  final PlayerService player;
  final MusicLibrary library;
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final OrchidAccount account;
  final VoidCallback openExplore;
  final VoidCallback openLibrary;
  final ValueChanged<int?> openDailyMixes;
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
    required this.openDailyMixes,
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
  }) {
    final cardWidth = width ?? OrchidStyle.compact(context, 186);
    final cardHeight = height ?? OrchidStyle.compact(context, 216);
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

  Widget _pinnedPlaylists() => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final playlists = widget.library.playlists.where((p) => p.pinned).toList();
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
                onTap: () => widget.openDailyMixes(i),
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
  );

  String _count(dynamic value) {
    final number = value is num ? value : num.tryParse('$value') ?? 0;
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}m';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}k';
    return number.toStringAsFixed(0);
  }

  Widget _art(String? url, {double size = 48}) {
    if (url == null || !url.startsWith('https://')) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.muted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(LucideIcons.music2, size: 20),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _art(null, size: size),
      ),
    );
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

  void _openSong(Map<String,dynamic> track) {
    final timestamp=track['timestamp'];
    final listenedAt=timestamp is num
      ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt()*1000)
      : null;
    showSongDetailDrawer(context,
      player:widget.player, library:widget.library,
      addonService:widget.addonService, addons:widget.addons,
      title:track['title']?.toString()??'Unknown',
      artist:track['artist']?.toString()??'Unknown',
      album:track['album']?.toString(),
      artworkUrl:track['image']?.toString(),
      listenedAt:listenedAt, nowPlaying:track['nowPlaying']==true,
    );
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

  String _relativeTime(DateTime when) {
    final difference = DateTime.now().difference(when);
    if (difference.isNegative || difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${when.month}/${when.day}/${when.year}';
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
      height: OrchidStyle.compact(context, 216),
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        final stats = _history?['stats'] is Map
            ? Map<String, dynamic>.from(_history!['stats'] as Map)
            : <String, dynamic>{};
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
                  PrimaryButton(
                    onPressed: () => widget.openDailyMixes(null),
                    child: const Text('Explore Daily Mixes'),
                  ),
                  OutlineButton(
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
              const OrchidSectionHeader(title: 'By the numbers'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10, runSpacing: 10,
                children: [
                  _stat('Listens', stats['scrobbles']),
                  _stat('Artists', stats['artists']),
                  _stat('Albums', stats['albums']),
                  _stat('Tracks', stats['tracks']),
                ],
              ),
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
