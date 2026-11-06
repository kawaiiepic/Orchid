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
import '../widgets/song_context_menu.dart';

class OrchidHomeScreen extends StatefulWidget {
  final PlayerService player;
  final MusicLibrary library;
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final OrchidAccount account;
  final VoidCallback openExplore;
  final VoidCallback openLibrary;
  final VoidCallback openDailyMixes;
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
    required this.openProfile,
  });

  @override
  State<OrchidHomeScreen> createState() => _OrchidHomeScreenState();
}

class _OrchidHomeScreenState extends State<OrchidHomeScreen> {
  Map<String, dynamic>? _history;
  bool _loading = false;
  String? _error;
  String? _lastfmUser;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_accountChanged);
    _accountChanged();
  }

  @override
  void didUpdateWidget(covariant OrchidHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account) {
      oldWidget.account.removeListener(_accountChanged);
      widget.account.addListener(_accountChanged);
      _accountChanged();
    }
  }

  void _accountChanged() {
    final user = widget.account.lastfmUsername;
    if (_lastfmUser == user) return;
    _lastfmUser = user;
    _requestId++;
    _history = null;
    _error = null;
    if (user != null) {
      _refresh();
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (!widget.account.lastfmConnected) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.account.lastfmHome();
      if (!mounted || requestId != _requestId) return;
      setState(() => _history = result);
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.account.removeListener(_accountChanged);
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
          .toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      final key = '${norm(track['artist'])}|${norm(track['title'])}';
      return key != '|' && seen.add(key);
    }).toList();
  }

  List<SavedSong> _lastfmMixPool() => [
    for (final item in _uniqueRecent())
      if ((item['artist'] ?? '').toString().isNotEmpty &&
          (item['title'] ?? '').toString().isNotEmpty)
        SavedSong(
          item['title'].toString(),
          item['artist'].toString(),
          album: item['album']?.toString(),
          artwork: item['image']?.toString(),
        ),
  ];

  Widget _dailyMixCards() => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final source = _lastfmMixPool();
      const titles = ['Favorites Mix', 'Similar Sounds', 'Discover'];
      const subtitles = ['Your comfort songs', 'Songs in your orbit', 'Something different'];
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < titles.length; i++) ...[
            _clickable(
              onTap: widget.openDailyMixes,
              child: Container(
                width: 168,
                height: 245,
                padding: const EdgeInsets.all(12),
                decoration: OrchidStyle.panelDecoration(radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(children: [
                      _art(widget.library.dailyMix(i, source).isNotEmpty
                          ? widget.library.dailyMix(i, source).first.artwork
                          : null, size: 144),
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
      onTap:()=>_openLastfm('https://www.last.fm/user/${Uri.encodeComponent(widget.account.lastfmUsername ?? '')}'),
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
    Navigator.of(context).push(ShadcnPageRoute<void>(
      builder:(_)=>SongDetailScreen(
        player:widget.player,
        library:widget.library,
        addonService:widget.addonService,
        addons:widget.addons,
        title:track['title']?.toString()??'Unknown',
        artist:track['artist']?.toString()??'Unknown',
        album:track['album']?.toString(),
        artworkUrl:track['image']?.toString(),
        listenedAt:listenedAt,
        nowPlaying:track['nowPlaying']==true,
      ),
    ));
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
        sourceId: 'lastfm',
        sourceName: 'Last.fm',
      ),
      player: widget.player,
      library: widget.library,
      child: _clickable(
      onTap:()=>_openSong(track),
      child:Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
      decoration: OrchidStyle.panelDecoration(radius:14),
      padding: const EdgeInsets.symmetric(horizontal:12,vertical:9),
      child: Row(
        children: [
          _art(track['image'] as String?),
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
          const Icon(LucideIcons.chevronRight,size:16),
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
                  ? _art(item['image'] as String?,size:144)
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
        final linked = widget.account.lastfmConnected;
        final stats = _history?['stats'] is Map
            ? Map<String, dynamic>.from(_history!['stats'] as Map)
            : <String, dynamic>{};
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
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
                    onPressed: widget.openDailyMixes,
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
              title: 'Daily Mixes',
              subtitle: 'Fresh rotations for your listening mood',
            ),
            _dailyMixCards(),
            const SizedBox(height: 28),
            OrchidSectionHeader(
              title: 'Your listening',
              subtitle: 'A little portrait of your music taste',

            ),
            const SizedBox(height: 10),
            if (!linked)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Connect Last.fm to unlock your listening history.').semiBold(),
                      const SizedBox(height: 8),
                      const Text('See music played on all your Last.fm-connected apps, plus your favorite artists, albums, and listening stats.').small().muted(),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        onPressed: widget.openProfile,
                        child: const Text('Connect Last.fm'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (_error != null) ...[
                Text(_error!).small(),
                const SizedBox(height: 8),
                OutlineButton(onPressed: _refresh, child: const Text('Try again')),
              ],
              if (_loading && _history == null)
                const Text('Loading your listening history…').muted(),
              if (_history != null) ...[
                const OrchidSectionHeader(title: 'By the numbers'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _stat('Scrobbles', stats['scrobbles']),
                    _stat('Artists', stats['artists']),
                    _stat('Albums', stats['albums']),
                    _stat('Tracks', stats['tracks']),
                  ],
                ),
                const SizedBox(height: 24),
                const OrchidSectionHeader(title: 'Recently played'),
                const SizedBox(height: 10),
                if (_uniqueRecent().isEmpty)
                  const Text('No Last.fm listening history yet.').muted()
                else
                  ..._uniqueRecent().map(_recentRow),
                const SizedBox(height: 24),
                const OrchidSectionHeader(title: 'Artists on repeat'),
                const SizedBox(height: 5),
                const Text('All time').xSmall().muted(),
                const SizedBox(height: 10),
                _horizontalItems(_items('artists'), albums: false),
                const SizedBox(height: 24),
                const OrchidSectionHeader(title: 'Albums on repeat'),
                const SizedBox(height: 5),
                const Text('All time').xSmall().muted(),
                const SizedBox(height: 10),
                _horizontalItems(_items('albums'), albums: true),
              ],
            ],
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
