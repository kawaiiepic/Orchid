import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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


  Widget _pinnedPlaylists() => ListenableBuilder(
    listenable:widget.library,
    builder:(context,_) {
      final playlists=widget.library.playlists.where((p)=>p.pinned).toList();
      if(playlists.isEmpty)return const SizedBox.shrink();
      return Column(
        crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          const OrchidSectionHeader(
            title:'Pinned playlists',
            subtitle:'Your favorites, right where you left them',
          ),
          const SizedBox(height:12),
          SingleChildScrollView(
            scrollDirection:Axis.horizontal,
            child:Row(children:[
              for(final playlist in playlists)...[
                _clickable(
                  onTap:(){
                    if(playlist.songs.isEmpty)return;
                    widget.player.setAddons(widget.addons);
                    final queue=playlist.songs.map((song)=>TrackResult(
                      id:song.key,title:song.title,artist:song.artist,
                      album:song.album,artworkUrl:song.artwork,
                      sourceId:'orchid-library',sourceName:'Library',
                    )).toList();
                    widget.player.playTrack(queue.first,fromQueue:queue)
                      .catchError((Object e) {
                        debugPrint('[Orchid] Cannot play pinned playlist: $e');
                      });
                  },
                  child:Container(
                    width:168,height:232,
                    padding:const EdgeInsets.all(12),
                    decoration:OrchidStyle.panelDecoration(radius:18),
                    child:Column(
                      crossAxisAlignment:CrossAxisAlignment.start,
                      children:[
                        Stack(children:[
                          if (playlist.songs.isNotEmpty)
                            AppleCover(
                              artist: playlist.songs.first.artist,
                              name: playlist.songs.first.title,
                              fallbackUrl: playlist.songs.first.artwork,
                              size: 144,
                              radius: 12,
                            )
                          else _art(null, size: 144),
                          Positioned(right:7,bottom:7,
                            child:Container(
                              padding:const EdgeInsets.all(7),
                              decoration:BoxDecoration(
                                color:OrchidStyle.panel,
                                borderRadius:BorderRadius.circular(9)),
                              child:const Icon(LucideIcons.pin,
                                color:OrchidStyle.lilac,size:16)),
                          ),
                        ]),
                        const SizedBox(height:10),
                        Text(playlist.name,maxLines:2,
                          overflow:TextOverflow.ellipsis).semiBold(),
                        const Spacer(),
                        Text('${playlist.songs.length} songs').xSmall().muted(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width:10),
              ],
            ]),
          ),
          const SizedBox(height:28),
        ],
      );
    },
  );

  Widget _dailyMixCards() => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final source = _homeMixes;
      const titles = ['Favorites Mix', 'Similar Sounds', 'Discover'];
      const subtitles = ['Your comfort songs', 'Songs in your orbit', 'Something different'];
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < titles.length; i++) ...[
            _clickable(
              onTap: () => widget.openDailyMixes(i),
              child: Container(
                width: 168,
                height: 245,
                padding: const EdgeInsets.all(12),
                decoration: OrchidStyle.panelDecoration(radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(children: [
                      if (i < source.length && source[i].isNotEmpty)
                        AppleCover(
                          artist: source[i].first.artist,
                          name: source[i].first.title,
                          fallbackUrl: source[i].first.artwork,
                          size: 144,
                          radius: 12,
                        )
                      else _art(null, size: 144),
                      Positioned(
                        bottom: 8, right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: OrchidStyle.panel,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(LucideIcons.sparkles,
                            size: 16, color: OrchidStyle.lilac),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Text(titles[i], maxLines: 1,
                      overflow: TextOverflow.ellipsis).semiBold(),
                    const SizedBox(height: 4),
                    Text(subtitles[i], maxLines: 1,
                      overflow: TextOverflow.ellipsis).small().muted(),
                    const Spacer(),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ]),
      );
    },
  );

  Widget _madeForYouCard() => _clickable(
    onTap:widget.openReplay,
    child:Container(
      width:168,height:245,padding:const EdgeInsets.all(12),
      decoration:OrchidStyle.panelDecoration(radius:18),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Container(
          width:144,height:144,
          decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(12),
            gradient:const LinearGradient(
              begin:Alignment.topLeft,end:Alignment.bottomRight,
              colors:[Color(0xFF7A3DB3),Color(0xFF262047),Color(0xFF151326)],
            ),
          ),
          child:const Stack(children:[
            Center(child:Icon(LucideIcons.audioLines,size:65,color:Color(0xFFEACFFF))),
            Positioned(right:9,bottom:9,child:Icon(LucideIcons.sparkles,
              size:21,color:Color(0xFFFFFFFF))),
          ]),
        ),
        const SizedBox(height:10),
        const Text('Replay').semiBold(),
        const SizedBox(height:4),
        const Text('Your listening story').small().muted(),
      ]),
    ),
  );

  Widget _personalCard(String title,String subtitle,IconData icon,
      List<Color> colors,VoidCallback onTap) => _clickable(
    onTap:onTap,
    child:Container(
      width:168,height:245,padding:const EdgeInsets.all(12),
      decoration:OrchidStyle.panelDecoration(radius:18),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Container(width:144,height:144,
          decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),
            gradient:LinearGradient(begin:Alignment.topLeft,
              end:Alignment.bottomRight,colors:colors)),
          child:Center(child:Icon(icon,size:64,color:const Color(0xFFFFFFFF))),
        ),
        const SizedBox(height:10),
        Text(title,maxLines:1,overflow:TextOverflow.ellipsis).semiBold(),
        const SizedBox(height:4),
        Text(subtitle,maxLines:2,overflow:TextOverflow.ellipsis).small().muted(),
      ]),
    ),
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

  Future<void> _openLastfm(dynamic rawUrl) async {
    if (rawUrl is! String) return;
    final uri=Uri.tryParse(rawUrl);
    if(uri==null||uri.scheme!='https'||!['last.fm','www.last.fm'].contains(uri.host.toLowerCase()))return;
    await launchUrl(uri,mode:LaunchMode.externalApplication);
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
      width: 138,
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
    final album = track['album']?.toString() ?? '';
    final nowPlaying = track['nowPlaying'] == true;
    final timestamp = track['timestamp'] is num
        ? (track['timestamp'] as num).toInt()
        : null;
    final time = timestamp == null
        ? ''
        : _relativeTime(DateTime.fromMillisecondsSinceEpoch(timestamp * 1000));
    return SongContextMenu(
      track: TrackResult(
        id: '${artist.toLowerCase()}|${(track['title'] ?? '').toString().toLowerCase()}',
        title: track['title']?.toString() ?? '',
        artist: artist,
        album: album,
        artworkUrl: track['image']?.toString(),
        sourceId: 'orchid-history',
        sourceName: 'Orchid History',
      ),
      player: widget.player,
      library: widget.library,
      child: _clickable(
      onTap:(){
        widget.player.setAddons(widget.addons);
        widget.player.playTrack(TrackResult(
          id:'${artist.toLowerCase()}|${(track['title'] ?? '').toString().toLowerCase()}',
          title:track['title']?.toString() ?? '',
          artist:artist, album:album,
          artworkUrl:track['image']?.toString(),
          sourceId:'orchid-history', sourceName:'Orchid History',
        )).catchError((Object e) {
          debugPrint('[Orchid] Recent track playback failed: $e');
        });
      },
      child:Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
      decoration: OrchidStyle.panelDecoration(radius:14),
      padding: const EdgeInsets.symmetric(horizontal:12,vertical:9),
      child: Row(
        children: [
          AppleCover(
            artist: artist,
            name: (track['title'] ?? '').toString(),
            fallbackUrl: track['image'] as String?,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track['title']?.toString() ?? 'Unknown track').semiBold(),
                Text(album.isEmpty ? artist : '$artist · $album').small().muted(),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(nowPlaying ? 'Now playing' : time).xSmall().muted(),
          const SizedBox(width:6),
          IconButton.ghost(
            onPressed:()=>_openSong(track),
            icon:const Icon(LucideIcons.info,size:17),
          ),
        ],
      )),
    )),
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
    final title=item['name']?.toString()??'Unknown';
    final artist=item['artist']?.toString()??'';
    return _clickable(
      onTap:()=>_showMusicDetail(item,isAlbum:isAlbum),
      child:SizedBox(
        width:168,
        height:258,
        child:Container(
          decoration:OrchidStyle.panelDecoration(radius:18),
          padding:const EdgeInsets.all(12),
          child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              isAlbum
                  ? AppleCover(
                      artist: artist,
                      name: title,
                      isAlbum: true,
                      fallbackUrl: item['image'] as String?,
                      size: 144,
                      radius: 12,
                    )
                  : ArtistArtwork(artist: title, size: 144, radius: 12),
              const SizedBox(height:10),
              SizedBox(
                height:38,
                child:Text(title,maxLines:2,overflow:TextOverflow.ellipsis).semiBold(),
              ),
              if(isAlbum)
                Text(artist,maxLines:1,overflow:TextOverflow.ellipsis).small().muted()
              else
                const SizedBox(height:17),
              const Spacer(),
              Text('${_count(item['plays'])} plays').xSmall().muted(),
            ],
          ),
        ),
      ),
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
          padding: const EdgeInsets.all(20),
          children: [
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
            const SizedBox(height: 28),
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
            const SizedBox(height:28),
            const OrchidSectionHeader(
              title: 'AI DJ',
              subtitle: 'Talk music with your personal DJ',
            ),
            const SizedBox(height:12),
            _clickable(
              onTap:widget.openAiDj,
              child:Container(
                width:double.infinity,
                padding:const EdgeInsets.symmetric(horizontal:18,vertical:14),
                decoration:OrchidStyle.panelDecoration(radius:15),
                child:Row(children:[
                  const Icon(LucideIcons.bot,size:22,color:OrchidStyle.lilac),
                  const SizedBox(width:12),
                  const Expanded(child:Text('Chat with AI DJ').semiBold()),
                  const Icon(LucideIcons.chevronRight,size:19,color:OrchidStyle.lilac),
                ]),
              ),
            ),
            const SizedBox(height:28),
            const OrchidSectionHeader(
              title: 'Daily Mixes',
              subtitle: 'Fresh rotations for your listening mood',
            ),
            _dailyMixCards(),
            const SizedBox(height: 28),
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
              else ..._uniqueRecent().map(_recentRow),
              const SizedBox(height:24),
              const OrchidSectionHeader(
                title:'Popular on Apple Music',
                subtitle:'Explore something new',
              ),
              const SizedBox(height:10),
              if(_items('charts').isEmpty)
                const Text('Apple Music charts are unavailable.').muted()
              else ..._items('charts').take(12).map(_recentRow),
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
