import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_library.dart';
import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../widgets/apple_cover.dart';
import '../widgets/artist_artwork.dart';
import '../widgets/orchid_style.dart';
import '../widgets/song_context_menu.dart';
import 'music_detail_pages.dart';

/// Catalog-driven browsing, intentionally separate from keyword search.
class DiscoverScreen extends StatefulWidget {
  final Widget header;
  final OrchidAccount account;
  final PlayerService player;
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final MusicLibrary library;

  const DiscoverScreen({
    super.key,
    required this.header,
    required this.account,
    required this.player,
    required this.addonService,
    required this.addons,
    required this.library,
  });

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  Map<String, dynamic>? home;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.account.orchidHome();
      if (mounted) setState(() => home = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> _items(String key) {
    final raw = home?[key];
    if (raw is! List) return [];
    return raw.whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item)).toList();
  }

  void _play(Map<String, dynamic> item) {
    final title = (item['title'] ?? '').toString();
    final artist = (item['artist'] ?? '').toString();
    if (title.isEmpty || artist.isEmpty) return;
    widget.player.setAddons(widget.addons);
    widget.player.playTrack(TrackResult(
      id: (item['id'] ?? '${artist.toLowerCase()}|${title.toLowerCase()}').toString(),
      title: title,
      artist: artist,
      album: item['album']?.toString(),
      artworkUrl: (item['image'] ?? item['artwork'])?.toString(),
      sourceId: 'orchid-discover',
      sourceName: 'Discover',
    )).catchError((Object e) {
      debugPrint('[Orchid Discover] Could not play track: $e');
    });
  }

  Widget _tracks() {
    final tracks = _items('charts');
    if (tracks.isEmpty) {
      return const Text('New recommendations will appear here soon.').muted();
    }
    return SizedBox(
      height: 194,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final item in tracks.take(20))
            SizedBox(
              width: 150,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SongContextMenu(
                  track: TrackResult(
                    id: (item['id'] ?? '${item['artist']}|${item['title']}').toString(),
                    title: (item['title'] ?? '').toString(),
                    artist: (item['artist'] ?? '').toString(),
                    album: item['album']?.toString(),
                    artworkUrl: (item['image'] ?? item['artwork'])?.toString(),
                    sourceId: 'orchid-discover',
                    sourceName: 'Discover',
                  ),
                  player: widget.player,
                  library: widget.library,
                  addonService: widget.addonService,
                  addons: widget.addons,
                  showMenuButton: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _play(item),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppleCover(
                          artist: (item['artist'] ?? '').toString(),
                          name: (item['title'] ?? '').toString(),
                          fallbackUrl: (item['image'] ?? item['artwork'])?.toString(),
                          size: 130, radius: 11, zoomOnHover: true,
                        ),
                        const SizedBox(height: 7),
                        SizedBox(width: 130, child: Text(
                          (item['title'] ?? '').toString(),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: 130, child: Text(
                          (item['artist'] ?? '').toString(),
                          maxLines: 1, overflow: TextOverflow.ellipsis).small().muted()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _artists() {
    final artists = _items('artists');
    if (artists.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 177,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final item in artists.take(14))
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openArtistPage(context,
                artist: (item['name'] ?? '').toString(),
                artwork: item['image']?.toString(),
                account: widget.account,
                player: widget.player, addonService: widget.addonService,
                addons: widget.addons, library: widget.library),
              child: SizedBox(
                width: 128,
                child: Column(children: [
                  ClipOval(child: ArtistArtwork(
                    artist: (item['name'] ?? '').toString(),
                    fallbackUrl: item['image']?.toString(),
                    size: 102, radius: 50, zoomOnHover: true)),
                  const SizedBox(height: 9),
                  Text((item['name'] ?? '').toString(),
                    textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis).small(),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _albums() {
    final albums = _items('featuredAlbums');
    if (albums.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 192,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final item in albums.take(14))
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openAlbumPage(
                context,
                artist: (item['artist'] ?? '').toString(),
                album: (item['name'] ?? '').toString(),
                artwork: item['image']?.toString(),
                player: widget.player, addonService: widget.addonService,
                addons: widget.addons, library: widget.library,
              ),
              child: SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppleCover(
                      artist: (item['artist'] ?? '').toString(),
                      name: (item['name'] ?? '').toString(),
                      isAlbum: true,
                      fallbackUrl: item['image']?.toString(),
                      size: 130, radius: 11, zoomOnHover: true,
                    ),
                    const SizedBox(height: 7),
                    SizedBox(width: 130, child: Text(
                      (item['name'] ?? '').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                    SizedBox(width: 130, child: Text(
                      (item['artist'] ?? '').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis).small().muted()),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(28,
      22 + MediaQuery.paddingOf(context).top, 30,
      MediaQuery.sizeOf(context).width >= 850
          ? 136 : 24 + OrchidStyle.iosDockClearance(context)),
    children: [
      widget.header,
      const OrchidHero(
        eyebrow: 'Find your next favorite',
        title: 'Discover',
        description: 'Fresh tracks, popular releases and artists worth exploring.',
        icon: LucideIcons.compass,
      ),
      const SizedBox(height: 24),
      if (loading && home == null)
        const Text('Discovering music…').muted(),
      if (error != null) ...[
        Text('Discover is unavailable right now.').muted(),
        OutlineButton(onPressed: _refresh, child: const Text('Try again')),
      ],
      if (home != null) ...[
        const OrchidSectionHeader(title: 'Artists to Explore'),
        const SizedBox(height: 12),
        _artists(),
        const SizedBox(height: 22),
        if (_items('featuredAlbums').isNotEmpty) ...[
          const OrchidSectionHeader(title: 'Featured Albums'),
          const SizedBox(height: 12),
          _albums(),
          const SizedBox(height: 22),
        ],
        const OrchidSectionHeader(title: 'Popular Right Now'),
        const SizedBox(height: 8),
        _tracks(),
      ],
    ],
  );
}
