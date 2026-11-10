import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/orchid_hover_zoom.dart';
import '../widgets/orchid_detail_header.dart';
import '../widgets/orchid_adaptive_controls.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_catalog_service.dart';
import '../services/orchid_account.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import 'song_detail_screen.dart';
import '../widgets/orchid_style.dart';
import '../widgets/artist_artwork.dart';
import '../widgets/song_context_menu.dart';
import '../widgets/content_drawer.dart';
import '../widgets/track_duration.dart';

void openArtistPage(BuildContext context, {
  required String artist,
  String? artwork,
  OrchidAccount? account,
  required PlayerService player,
  required AddonService addonService,
  required List<InstalledAddon> addons,
  required MusicLibrary library,
}) {
  showContentDrawer(context, builder: (_) => ArtistDetailPage(
    artist:artist, artwork:artwork, account:account, player:player,
    addonService:addonService, addons:addons, library:library,
  ));
}

void openAlbumPage(BuildContext context, {
  required String artist,
  required String album,
  String? artwork,
  int? collectionId,
  required PlayerService player,
  required AddonService addonService,
  required List<InstalledAddon> addons,
  required MusicLibrary library,
}) {
  showContentDrawer(context, builder: (_) => AlbumDetailPage(
    artist:artist, album:album, artwork:artwork,
    collectionId:collectionId, player:player,
    addonService:addonService, addons:addons, library:library,
  ));
}

Widget _cover(BuildContext context, String? artwork, {
  double size = 128,
  bool zoomOnHover = false,
}) {
  if (artwork == null || !artwork.startsWith('https://')) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(LucideIcons.music2, size: 32),
    );
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Builder(builder: (context) {
      final image = Image.network(
        artwork, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _cover(context, null, size: size),
      );
      return zoomOnHover ? OrchidHoverZoom(child: image) : image;
    }),
  );
}

/// Only reveal the video play overlay while the artwork is hovered.
class _HoverMusicVideoArtwork extends StatefulWidget {
  final String? artwork;

  const _HoverMusicVideoArtwork({this.artwork});

  @override
  State<_HoverMusicVideoArtwork> createState() =>
      _HoverMusicVideoArtworkState();
}

class _HoverMusicVideoArtworkState extends State<_HoverMusicVideoArtwork> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(
        width: 220,
        height: 124,
        child: Stack(fit: StackFit.expand, children: [
          if (widget.artwork?.startsWith('https://') == true)
            Image.network(widget.artwork!, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: OrchidStyle.panel))
          else
            const ColoredBox(color: OrchidStyle.panel),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _hovered ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: const Center(
                child: Icon(LucideIcons.play,
                  size: 29, color: Color(0xFFF9F5FF)),
              ),
            ),
          ),
        ]),
      ),
    ),
  );
}

Widget _back(BuildContext context) => Align(
  alignment: Alignment.centerLeft,
  child: IconButton.ghost(
    onPressed: () => dismissContentDrawer(context),
    icon: const Icon(LucideIcons.arrowLeft),
  ),
);

void _openTrack(BuildContext context, TrackResult track, {
  required PlayerService player, required AddonService addonService,
  required List<InstalledAddon> addons, required MusicLibrary library,
}) {
  showSongDetailDrawer(context, player:player,
    addonService:addonService, addons:addons, library:library,
    title:track.title, artist:track.artist,
    album:track.album, artworkUrl:track.artworkUrl, track:track);
}

String _catalogDuration(List<TrackResult> tracks) {
  final available=tracks.where((t)=>(t.duration??0)>0).toList();
  if(available.isEmpty)return '';
  final total=available.fold<int>(0,(sum,t)=>sum+t.duration!);
  final minutes=total~/60;
  return minutes>=60 ? '${minutes~/60} hr ${minutes%60} min' : '$minutes min';
}

Widget _catalogActions({
  required List<TrackResult> tracks,
  required PlayerService player,
  required List<InstalledAddon> addons,
}) {
  if(tracks.isEmpty)return const SizedBox.shrink();
  return Wrap(spacing:10,runSpacing:10,children:[
    OrchidAdaptiveControls.button(prominent: true, 
      onPressed:(){
        player.setAddons(addons);
        player.playTrack(tracks.first,fromQueue:tracks).catchError((Object e){
          debugPrint('[Orchid Catalog] Play all failed: $e');
        });
      },
      child:const Row(mainAxisSize:MainAxisSize.min,children:[
        Icon(LucideIcons.play,size:17),
        SizedBox(width:9),
        Text('Play all'),
      ]),
    ),
    OrchidAdaptiveControls.button(
      onPressed:(){
        for (final track in tracks) {
          player.addToQueue(track);
        }
      },
      child:const Row(mainAxisSize:MainAxisSize.min,children:[
        Icon(LucideIcons.listMusic,size:17),
        SizedBox(width:9),
        Text('Add to queue'),
      ]),
    ),
  ]);
}

Widget _musicHeader(BuildContext context, {
  required String eyebrow,
  required String title,
  required String subtitle,
  Widget? subtitleContent,
  required Widget artwork,
  required Widget actions,
}) => OrchidDetailHeader(
  eyebrow: eyebrow,
  title: title,
  subtitle: subtitle,
  subtitleContent: subtitleContent,
  artwork: artwork,
  actions: actions,
);

Widget _trackTile(BuildContext context, TrackResult song, {
  required PlayerService player, required AddonService addonService,
  required List<InstalledAddon> addons, required MusicLibrary library,
  int? number,
}) => _CatalogTrackTile(
  song: song,
  player: player,
  addonService: addonService,
  addons: addons,
  library: library,
  number: number,
);

/// A single hover surface wraps the complete row, including the ellipsis.
/// Avoid a ghost Button here: its independent hover highlight disappears
/// when the pointer enters the context menu button.
class _CatalogTrackTile extends StatefulWidget {
  final TrackResult song;
  final PlayerService player;
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final MusicLibrary library;
  final int? number;

  const _CatalogTrackTile({
    required this.song,
    required this.player,
    required this.addonService,
    required this.addons,
    required this.library,
    this.number,
  });

  @override
  State<_CatalogTrackTile> createState() => _CatalogTrackTileState();
}

class _CatalogTrackTileState extends State<_CatalogTrackTile> {
  bool _hovered = false;

  void _play() {
    widget.player.setAddons(widget.addons);
    widget.player.playTrack(widget.song).catchError((Object error) {
      debugPrint('[Orchid Catalog] Playback failed: $error');
    });
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: _hovered
            ? const Color(0x66332940)
            : const Color(0x00000000),
        borderRadius: BorderRadius.circular(9),
      ),
      child: SongContextMenu(
        track: widget.song,
        player: widget.player,
        library: widget.library,
        addonService: widget.addonService,
        addons: widget.addons,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _play,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 8),
              child: Row(children: [
                if (widget.number != null) ...[
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: _hovered
                          ? const Icon(LucideIcons.play,
                              size: 12, color: OrchidStyle.lilac)
                          : Text('${widget.number}',
                              textAlign: TextAlign.center).muted(),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _cover(context, widget.song.artworkUrl, size: 42),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.song.title, maxLines: 1,
                      overflow: TextOverflow.ellipsis).semiBold(),
                    Text(widget.song.artist, maxLines: 1,
                      overflow: TextOverflow.ellipsis).small().muted(),
                  ],
                )),
                const SizedBox(width: 8),
                SizedBox(
                  width: 49,
                  child: Text(
                    trackDurationLabel(widget.song.duration) ?? '',
                    maxLines: 1,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ).xSmall().muted(),
                ),
                // The menu overlays this reserved area, without shifting
                // or recoloring the rest of the song row.
                const SizedBox(width: 44),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
}

class ArtistDetailPage extends StatefulWidget {
  final String artist;
  final String? artwork;
  final OrchidAccount? account;
  final PlayerService player;
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final MusicLibrary library;
  const ArtistDetailPage({
    super.key, required this.artist, this.artwork, this.account,
    required this.player, required this.addonService,
    required this.addons, required this.library,
  });
  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
  late Future<ArtistCatalog> _catalog;

  @override
  void initState() {
    super.initState();
    _refreshArtist();
  }

  void _refreshArtist({bool refresh = false}) {
    _catalog = widget.account == null
        ? MusicCatalogService.instance.artist(widget.artist, refresh: refresh)
        : MusicCatalogService.instance.appleArtist(widget.account!, widget.artist);
  }

  void _playArtist(List<TrackResult> tracks) {
    if (tracks.isEmpty) return;
    widget.player.setAddons(widget.addons);
    widget.player.playTrack(tracks.first, fromQueue: tracks).catchError(
      (Object error) => debugPrint('[Orchid Artist] Play failed: $error'),
    );
  }

  Future<void> _playArtistRadio(ArtistCatalog catalog) async {
    final radio = [...catalog.songs];
    // Include related artists where possible. If catalog lookups fail,
    // the artist's available tracks still form a playable station.
    if (catalog.similarArtists.isNotEmpty) {
      try {
        final related = await Future.wait(
          catalog.similarArtists.take(3).map((artist) =>
            MusicCatalogService.instance.searchTracks(artist)),
        );
        for (var i = 0; i < related.length; i++) {
          final name = catalog.similarArtists[i].trim().toLowerCase();
          radio.addAll(related[i].where((song) =>
            song.artist.trim().toLowerCase() == name).take(5));
        }
      } catch (error) {
        debugPrint('[Orchid Artist] Related tracks unavailable: $error');
      }
    }
    if (radio.isEmpty) return;
    final unique = <String, TrackResult>{};
    for (final song in radio) {
      unique.putIfAbsent(
        '${song.artist.toLowerCase()}|${song.title.toLowerCase()}',
        () => song);
    }
    final queue = unique.values.toList()..shuffle();
    if (!mounted) return;
    widget.player.setAddons(widget.addons);
    widget.player.playTrack(queue.first, fromQueue: queue).catchError(
      (Object error) => debugPrint('[Orchid Artist] Radio failed: $error'),
    );
  }

  Widget _releaseCards(List<MusicAlbum> items) {
    if (items.isEmpty) return const Text('No releases available.').muted();
    return Wrap(
      spacing: 13,
      runSpacing: 20,
      children: [
        for (final album in items)
          SizedBox(
            width: 148,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openAlbumPage(context,
                artist: album.artist, album: album.title,
                artwork: album.artwork, collectionId: album.id,
                player: widget.player, addonService: widget.addonService,
                addons: widget.addons, library: widget.library),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cover(context, album.artwork, size: 148, zoomOnHover: true),
                  const SizedBox(height: 9),
                  Text(album.title, maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13,
                      color: Color(0xFFF5EDFF), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(album.releaseType == 'single' ? 'Single' :
                       album.releaseType == 'ep' ? 'EP' : 'Album')
                    .small().muted(),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _popularTracks(List<TrackResult> songs) {
    if (songs.isEmpty) {
      return const Text('No popular tracks available yet.').muted();
    }
    final popular = songs.take(10).toList();
    return LayoutBuilder(builder: (context, bounds) {
      Widget tile(int index) => _trackTile(context, popular[index],
        number: index + 1,
        player: widget.player, addonService: widget.addonService,
        addons: widget.addons, library: widget.library);
      if (bounds.maxWidth < 680) {
        return Column(children: [
          for (var i = 0; i < popular.length; i++) tile(i),
        ]);
      }
      final split = (popular.length + 1) ~/ 2;
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(children: [
          for (var i = 0; i < split; i++) tile(i),
        ])),
        const SizedBox(width: 22),
        Expanded(child: Column(children: [
          for (var i = split; i < popular.length; i++) tile(i),
        ])),
      ]);
    });
  }

  Widget _similarArtists(List<String> artists) {
    if (artists.isEmpty) {
      return const Text('Related artists are not available yet.').muted();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
      for (final artist in artists)
        SizedBox(
          width: 132,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openArtistPage(context,
              artist: artist, account: widget.account,
              player: widget.player, addonService: widget.addonService,
              addons: widget.addons, library: widget.library),
            child: Column(children: [
              ArtistArtwork(artist: artist, size: 122, radius: 61),
              const SizedBox(height: 9),
              Text(artist, textAlign: TextAlign.center,
                maxLines: 2, overflow: TextOverflow.ellipsis).semiBold(),
              const SizedBox(height: 2),
              const Text('Artist').small().muted(),
            ]),
          ),
        ),
        const SizedBox(width: 20),
      ]),
    );
  }

  Widget _musicVideos(List<ArtistMusicVideo> videos) {
    if (videos.isEmpty) {
      return const Text('No music videos available from the catalog.').muted();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
      for (final video in videos)
        Padding(
          padding: const EdgeInsets.only(right: 20),
          child: SizedBox(
          width: 220,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: video.url == null ? null : () async {
              final url = Uri.tryParse(video.url!);
              if (url != null && url.scheme == 'https') {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HoverMusicVideoArtwork(artwork: video.artwork),
                const SizedBox(height: 8),
                Text(video.title, maxLines: 2,
                  overflow: TextOverflow.ellipsis).semiBold(),
                const SizedBox(height: 3),
                const Text('Music video').small().muted(),
              ],
            ),
          ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ArtistCatalog>(
    future: _catalog,
    builder: (context, snapshot) {
      final catalog = snapshot.data;
      final tracks = catalog?.songs ?? <TrackResult>[];
      final genres = catalog?.genres ?? <String>[];
      final singlesAndEps = catalog?.albums.where(
        (album) => album.releaseType != 'album').toList() ?? <MusicAlbum>[];
      final albums = catalog?.albums.where(
        (album) => album.releaseType == 'album').toList() ?? <MusicAlbum>[];
      return ListView(
        padding: EdgeInsets.fromLTRB(24, 24, 30,
          28 + (MediaQuery.sizeOf(context).width >= 850 ? 104 : 0)),
        children: [
          _back(context),
          const SizedBox(height: 12),
          _musicHeader(context,
            eyebrow: 'Artist',
            title: widget.artist,
            subtitle: [
              if (genres.isNotEmpty) genres.join(' · ')
              else 'Genres unavailable',
              catalog?.monthlyListeners == null
                ? 'Monthly listeners unavailable'
                : '${catalog!.monthlyListeners} monthly listeners',
            ].join('  •  '),
            artwork: Center(child: ArtistArtwork(
              artist: widget.artist, fallbackUrl: widget.artwork,
              size: 148, radius: 74, zoomOnHover: false)),
            actions: Wrap(spacing: 9, runSpacing: 9, children: [
              OrchidAdaptiveControls.button(
                prominent: true,
                onPressed: tracks.isEmpty ? null : () => _playArtist(tracks),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(LucideIcons.play, size: 17),
                  SizedBox(width: 7),
                  Text('Play'),
                ]),
              ),
              OrchidAdaptiveControls.button(
                onPressed: catalog == null || tracks.isEmpty ? null :
                  () => _playArtistRadio(catalog),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(LucideIcons.radio, size: 17),
                  SizedBox(width: 7),
                  Text('Play Radio'),
                ]),
              ),
              ListenableBuilder(
                listenable: widget.library,
                builder: (context, _) => OrchidAdaptiveControls.button(
                  onPressed: () => widget.library.toggleArtistSaved(
                    widget.artist, artwork: widget.artwork),
                  child: Text(widget.library.isArtistSaved(widget.artist)
                    ? 'Following' : 'Follow'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 28),
          if (snapshot.connectionState != ConnectionState.done)
            const Center(child: Text('Loading artist discography…'))
          else if (snapshot.hasError) ...[
            Text('Could not load artist: ${snapshot.error}').muted(),
            const SizedBox(height: 12),
            OrchidAdaptiveControls.button(
              onPressed: () => setState(() => _refreshArtist(refresh: true)),
              child: const Text('Retry')),
          ] else if (catalog != null) ...[
            if (tracks.isNotEmpty) ...[
              const OrchidSectionHeader(title: 'Popular tracks'),
              const SizedBox(height: 8),
              _popularTracks(tracks),
              const SizedBox(height: 28),
            ],
            if (singlesAndEps.isNotEmpty) ...[
              OrchidSectionHeader(title: 'Singles & EPs',
                subtitle: '${singlesAndEps.length} releases'),
              const SizedBox(height: 12),
              _releaseCards(singlesAndEps),
              const SizedBox(height: 28),
            ],
            if (catalog.similarArtists.isNotEmpty) ...[
              const OrchidSectionHeader(title: 'Fans also like'),
              const SizedBox(height: 12),
              _similarArtists(catalog.similarArtists),
              const SizedBox(height: 28),
            ],
            if (catalog.musicVideos.isNotEmpty) ...[
              const OrchidSectionHeader(title: 'Music videos'),
              const SizedBox(height: 12),
              _musicVideos(catalog.musicVideos),
              const SizedBox(height: 28),
            ],
            if (catalog.biography?.trim().isNotEmpty == true ||
                catalog.genres.isNotEmpty) ...[
              const OrchidSectionHeader(title: 'About'),
              const SizedBox(height: 12),
              if (catalog.biography?.trim().isNotEmpty == true) ...[
                Text(catalog.biography!, style: const TextStyle(
                  fontSize: 14, height: 1.5,
                  color: Color(0xFFD6CEE0))),
                if (catalog.genres.isNotEmpty)
                  const SizedBox(height: 16),
              ],
              if (catalog.genres.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final genre in catalog.genres)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: OrchidStyle.panelLight,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(genre, style: const TextStyle(
                          fontSize: 12, color: OrchidStyle.lilac)),
                      ),
                  ],
                ),
              const SizedBox(height: 28),
            ],
            if (albums.isNotEmpty) ...[
              OrchidSectionHeader(title: 'Albums',
                subtitle: '${albums.length} releases'),
              const SizedBox(height: 12),
              _releaseCards(albums),
            ],
          ],
        ],
      );
    },
  );
}

class AlbumDetailPage extends StatefulWidget {
  final String artist;
  final String album;
  final String? artwork;
  final int? collectionId;
  final PlayerService player;
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final MusicLibrary library;
  const AlbumDetailPage({
    super.key, required this.artist, required this.album,
    this.artwork, this.collectionId, required this.player,
    required this.addonService, required this.addons, required this.library,
  });
  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  late Future<List<TrackResult>> _tracks;
  late Future<ArtistCatalog> _otherReleases;
  @override
  void initState() {
    super.initState();
    _tracks = MusicCatalogService.instance.album(
      widget.artist, widget.album, collectionId: widget.collectionId);
    _otherReleases = MusicCatalogService.instance.artist(widget.artist);
  }

  String _normalized(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  Widget _moreByArtist() => FutureBuilder<ArtistCatalog>(
    future: _otherReleases,
    builder: (context, snapshot) {
      final releases = snapshot.data?.albums.where((release) {
        if (widget.collectionId != null &&
            release.id == widget.collectionId) return false;
        return _normalized(release.title) != _normalized(widget.album) &&
            _normalized(release.artist) == _normalized(widget.artist);
      }).toList() ?? <MusicAlbum>[];
      if (releases.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 30),
          OrchidSectionHeader(title: 'More by ${widget.artist}'),
          const SizedBox(height: 12),
          // Albums, EPs and singles all appear in one vertically stacked list.
          for (final release in releases)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OrchidHoverSurface(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => openAlbumPage(context,
                    artist: release.artist,
                    album: release.title,
                    artwork: release.artwork,
                    collectionId: release.id,
                    player: widget.player,
                    addonService: widget.addonService,
                    addons: widget.addons,
                    library: widget.library),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                    child: Row(children: [
                      _cover(context, release.artwork, size: 60, zoomOnHover: true),
                      const SizedBox(width: 14),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(release.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis).semiBold(),
                          const SizedBox(height: 4),
                          Text(release.releaseType == 'single' ? 'Single' :
                            release.releaseType == 'ep' ? 'EP' : 'Album')
                            .small().muted(),
                        ],
                      )),
                      const SizedBox(width: 8),
                      const Icon(LucideIcons.chevronRight,
                        size: 16, color: Color(0xFFB7ABCA)),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<List<TrackResult>>(
      future: _tracks,
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _back(context),
            const SizedBox(height: 12),
            _musicHeader(context,
              eyebrow:'Album',
              title:widget.album,
              subtitle: widget.artist,
              subtitleContent: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 5,
                runSpacing: 4,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => openArtistPage(context,
                        artist: widget.artist,
                        player: widget.player,
                        addonService: widget.addonService,
                        addons: widget.addons,
                        library: widget.library),
                      child: Text(widget.artist, style: const TextStyle(
                        color: Color(0xFFE4D2FA),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )),
                    ),
                  ),
                  Text('· ${tracks.length} tracks'
                    '${_catalogDuration(tracks).isNotEmpty ? ' · ${_catalogDuration(tracks)}' : ''}',
                    style: const TextStyle(
                      color: Color(0xFFB7ABCA), fontSize: 13)),
                ],
              ),
              artwork:_cover(context,
                widget.artwork ?? (tracks.isNotEmpty ? tracks.first.artworkUrl:null),
                size:148),
              actions: Wrap(spacing: 10, runSpacing: 10, children: [
                OrchidAdaptiveControls.button(
                  prominent: true,
                  onPressed: tracks.isEmpty ? null : () {
                    widget.player.setAddons(widget.addons);
                    widget.player.playTrack(
                      tracks.first, fromQueue: tracks,
                    ).catchError((Object error) {
                      debugPrint('[Orchid Album] Playback failed: $error');
                    });
                  },
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.play, size: 17),
                    SizedBox(width: 8),
                    Text('Play'),
                  ]),
                ),
                OrchidAdaptiveControls.button(
                  onPressed: tracks.isEmpty ? null : () {
                    final queue = [...tracks]..shuffle();
                    widget.player.setAddons(widget.addons);
                    widget.player.playTrack(
                      queue.first, fromQueue: queue,
                    ).catchError((Object error) {
                      debugPrint('[Orchid Album] Radio failed: $error');
                    });
                  },
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.radio, size: 17),
                    SizedBox(width: 8),
                    Text('Play Radio'),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height:28),
            if (snapshot.connectionState != ConnectionState.done)
              const Center(child: Text('Loading album tracks…'))
            else if (snapshot.hasError) ...[
              Text('Could not load album: ${snapshot.error}').muted(),
              const SizedBox(height: 12),
              OrchidAdaptiveControls.button(
                onPressed: () => setState(() {
                  _tracks = MusicCatalogService.instance.album(
                    widget.artist, widget.album,
                    collectionId: widget.collectionId, refresh: true);
                }),
                child: const Text('Retry'),
              ),
            ] else ...[
              if (tracks.isEmpty)
                const Text('No tracks found for this album.').muted()
              else
                ...tracks.asMap().entries.map((entry) => _trackTile(
                  context, entry.value, number: entry.key + 1,
                  player: widget.player, addonService: widget.addonService,
                  addons: widget.addons, library: widget.library)),
            ],
            _moreByArtist(),
          ],
        );
      },
    );
}
