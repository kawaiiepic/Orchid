import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_catalog_service.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import '../widgets/mini_player_bar.dart';
import 'song_detail_screen.dart';

void openArtistPage(BuildContext context, {
  required String artist,
  String? artwork,
  required PlayerService player,
  required AddonService addonService,
  required List<InstalledAddon> addons,
  required MusicLibrary library,
}) {
  Navigator.of(context).push(ShadcnPageRoute<void>(
    builder: (_) => ArtistDetailPage(
      artist: artist, artwork: artwork, player: player,
      addonService: addonService, addons: addons, library: library,
    ),
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
  Navigator.of(context).push(ShadcnPageRoute<void>(
    builder: (_) => AlbumDetailPage(
      artist: artist, album: album, artwork: artwork,
      collectionId: collectionId, player: player,
      addonService: addonService, addons: addons, library: library,
    ),
  ));
}

Widget _cover(BuildContext context, String? artwork, {double size = 128}) {
  if (artwork == null || !artwork.startsWith('https://')) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(LucideIcons.music2, size: 32),
    );
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Image.network(
      artwork, width: size, height: size, fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _cover(context, null, size: size),
    ),
  );
}

Widget _back(BuildContext context) => Align(
  alignment: Alignment.centerLeft,
  child: IconButton.ghost(
    onPressed: () => Navigator.of(context).pop(),
    icon: const Icon(LucideIcons.arrowLeft),
  ),
);

void _openTrack(BuildContext context, TrackResult track, {
  required PlayerService player, required AddonService addonService,
  required List<InstalledAddon> addons, required MusicLibrary library,
}) {
  Navigator.of(context).push(ShadcnPageRoute<void>(
    builder: (_) => SongDetailScreen(
      player: player, addonService: addonService, addons: addons,
      library: library, title: track.title, artist: track.artist,
      album: track.album, artworkUrl: track.artworkUrl, track: track,
    ),
  ));
}

Widget _trackTile(BuildContext context, TrackResult song, {
  required PlayerService player, required AddonService addonService,
  required List<InstalledAddon> addons, required MusicLibrary library,
  int? number,
}) => Button(
  style: const ButtonStyle.ghost(),
  onPressed: () => _openTrack(context, song,
    player: player, addonService: addonService,
    addons: addons, library: library),
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      if (number != null)
        SizedBox(width: 32, child: Text('$number').muted())
      else
        _cover(context, song.artworkUrl, size: 42),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis).semiBold(),
          Text(song.artist, maxLines: 1,
            overflow: TextOverflow.ellipsis).small().muted(),
        ],
      )),
      const Icon(LucideIcons.chevronRight, size: 16),
    ]),
  ),
);

class ArtistDetailPage extends StatefulWidget {
  final String artist;
  final String? artwork;
  final PlayerService player;
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final MusicLibrary library;
  const ArtistDetailPage({
    super.key, required this.artist, this.artwork,
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
    _catalog = MusicCatalogService.instance.artist(widget.artist);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    footers: [MiniPlayerBar(player: widget.player)],
    child: FutureBuilder<ArtistCatalog>(
      future: _catalog,
      builder: (context, snapshot) {
        final catalog = snapshot.data;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _back(context),
            const SizedBox(height: 12),
            Center(child: _cover(context,
              widget.artwork ?? (catalog?.albums.isNotEmpty == true
                  ? catalog!.albums.first.artwork : null), size: 180)),
            const SizedBox(height: 20),
            Center(child: Text(widget.artist,
              textAlign: TextAlign.center).x2Large().semiBold()),
            const SizedBox(height: 24),
            if (snapshot.connectionState != ConnectionState.done)
              const Center(child: Text('Loading artist discography…'))
            else if (snapshot.hasError)
              Column(children: [
                Text('Could not load artist: ${snapshot.error}').muted(),
                const SizedBox(height: 12),
                OutlineButton(onPressed: () => setState(() {
                  _catalog = MusicCatalogService.instance.artist(widget.artist,
                    refresh: true);
                }), child: const Text('Retry')),
              ])
            else if (catalog != null) ...[
              Text('Albums (${catalog.albums.length})').large().semiBold(),
              const SizedBox(height: 12),
              if (catalog.albums.isEmpty)
                const Text('No albums found in the music catalog.').muted()
              else
                Wrap(
                  spacing: 12, runSpacing: 18,
                  children: catalog.albums.map((album) => SizedBox(
                    width: 148,
                    child: GestureDetector(
                      onTap: () => openAlbumPage(context,
                        artist: album.artist, album: album.title,
                        artwork: album.artwork, collectionId: album.id,
                        player: widget.player, addonService: widget.addonService,
                        addons: widget.addons, library: widget.library),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _cover(context, album.artwork, size: 148),
                          const SizedBox(height: 8),
                          Text(album.title, maxLines: 2,
                            overflow: TextOverflow.ellipsis).semiBold(),
                          Text('${album.trackCount ?? '?'} tracks').small().muted(),
                        ],
                      ),
                    ),
                  )).toList(),
                ),
              const SizedBox(height: 28),
              Text('Songs (${catalog.songs.length})').large().semiBold(),
              const SizedBox(height: 8),
              if (catalog.songs.isEmpty)
                const Text('No songs found in the music catalog.').muted()
              else
                ...catalog.songs.map((song) => _trackTile(context, song,
                  player: widget.player, addonService: widget.addonService,
                  addons: widget.addons, library: widget.library)),
            ],
          ],
        );
      },
    ),
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
  @override
  void initState() {
    super.initState();
    _tracks = MusicCatalogService.instance.album(
      widget.artist, widget.album, collectionId: widget.collectionId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    footers: [MiniPlayerBar(player: widget.player)],
    child: FutureBuilder<List<TrackResult>>(
      future: _tracks,
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _back(context),
            const SizedBox(height: 12),
            Center(child: _cover(context,
              widget.artwork ?? (tracks.isNotEmpty ? tracks.first.artworkUrl : null),
              size: 200)),
            const SizedBox(height: 20),
            Center(child: Text(widget.album,
              textAlign: TextAlign.center).x2Large().semiBold()),
            const SizedBox(height: 8),
            Center(child: Button(
              style: const ButtonStyle.ghost(),
              onPressed: () => openArtistPage(context, artist: widget.artist,
                player: widget.player, addonService: widget.addonService,
                addons: widget.addons, library: widget.library),
              child: Text(widget.artist).muted(),
            )),
            const SizedBox(height: 24),
            if (snapshot.connectionState != ConnectionState.done)
              const Center(child: Text('Loading album tracks…'))
            else if (snapshot.hasError) ...[
              Text('Could not load album: ${snapshot.error}').muted(),
              const SizedBox(height: 12),
              OutlineButton(
                onPressed: () => setState(() {
                  _tracks = MusicCatalogService.instance.album(
                    widget.artist, widget.album,
                    collectionId: widget.collectionId, refresh: true);
                }),
                child: const Text('Retry'),
              ),
            ] else ...[
              Text('Tracklist (${tracks.length})').large().semiBold(),
              const SizedBox(height: 8),
              if (tracks.isEmpty)
                const Text('No tracks found for this album.').muted()
              else
                ...tracks.asMap().entries.map((entry) => _trackTile(
                  context, entry.value, number: entry.key + 1,
                  player: widget.player, addonService: widget.addonService,
                  addons: widget.addons, library: widget.library)),
            ],
          ],
        );
      },
    ),
  );
}
