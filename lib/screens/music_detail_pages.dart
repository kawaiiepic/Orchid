import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_catalog_service.dart';
import '../services/orchid_account.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import '../widgets/mini_player_bar.dart';
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

Widget _cover(BuildContext context, String? artwork, {double size = 128}) {
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
    PrimaryButton(
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
    OutlineButton(
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
  required Widget artwork,
  required Widget actions,
}) => Container(
  width:double.infinity,
  padding:const EdgeInsets.all(18),
  decoration:OrchidStyle.gradientDecoration(radius:22),
  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Center(child:artwork),
    const SizedBox(height:20),
    Text(eyebrow.toUpperCase(),style:const TextStyle(
      fontSize:11,letterSpacing:2,fontWeight:FontWeight.w600,
      color:OrchidStyle.lilac,
    )),
    const SizedBox(height:8),
    Text(title,style:const TextStyle(fontSize:27,
      height:1.12,fontWeight:FontWeight.w700)),
    const SizedBox(height:8),
    Text(subtitle).small().muted(),
    const SizedBox(height:20),
    actions,
  ]),
);

Widget _trackTile(BuildContext context, TrackResult song, {
  required PlayerService player, required AddonService addonService,
  required List<InstalledAddon> addons, required MusicLibrary library,
  int? number,
}) => SongContextMenu(
  track: song, player: player, library: library,
  child: Button(
  style: const ButtonStyle.ghost(),
  onPressed: () {
    player.setAddons(addons);
    player.playTrack(song).catchError((Object e) {
      debugPrint('[Orchid Catalog] Playback failed: $e');
    });
  },
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
      if (trackDurationLabel(song.duration) != null) ...[
        Text(trackDurationLabel(song.duration)!).xSmall().muted(),
        const SizedBox(width: 6),
      ],
      IconButton.ghost(
        onPressed: () => _openTrack(context, song,
          player: player, addonService: addonService,
          addons: addons, library: library),
        icon: const Icon(LucideIcons.info, size: 18),
      ),
    ]),
  ),
  ),
);

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
    _catalog = widget.account == null
        ? MusicCatalogService.instance.artist(widget.artist)
        : MusicCatalogService.instance.appleArtist(widget.account!,widget.artist);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    footers: [MiniPlayerBar(player: widget.player, library: widget.library)],
    child: FutureBuilder<ArtistCatalog>(
      future: _catalog,
      builder: (context, snapshot) {
        final catalog = snapshot.data;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _back(context),
            const SizedBox(height: 12),
            _musicHeader(context,
              eyebrow:'Artist',
              title:widget.artist,
              subtitle:catalog==null
                ? 'Explore the discography'
                : '${catalog.albums.length} releases · ${catalog.songs.length} catalog tracks',
              artwork:ArtistArtwork(
                artist:widget.artist,size:190,radius:95),
              actions:_catalogActions(
                tracks:catalog?.songs??<TrackResult>[],
                player:widget.player,addons:widget.addons),
            ),
            const SizedBox(height:28),
            if (snapshot.connectionState != ConnectionState.done)
              const Center(child: Text('Loading artist discography…'))
            else if (snapshot.hasError)
              Column(children: [
                Text('Could not load artist: ${snapshot.error}').muted(),
                const SizedBox(height: 12),
                OutlineButton(onPressed: () => setState(() {
                  _catalog = widget.account == null
                      ? MusicCatalogService.instance.artist(widget.artist,
                          refresh:true)
                      : MusicCatalogService.instance.appleArtist(
                          widget.account!,widget.artist);
                }), child: const Text('Retry')),
              ])
            else if (catalog != null) ...[
              OrchidSectionHeader(title: 'Albums', subtitle: '${catalog.albums.length} releases'),
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
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: OrchidStyle.panelDecoration(radius: 17),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _cover(context, album.artwork, size: 128),
                            const SizedBox(height: 10),
                            Text(album.title, maxLines: 2,
                              overflow: TextOverflow.ellipsis).semiBold(),
                            const SizedBox(height: 4),
                            Text('${album.trackCount ?? '?'} tracks').small().muted(),
                          ],
                        ),
                      ),
                    ),
                  )).toList(),
                ),
              const SizedBox(height: 28),
              OrchidSectionHeader(title: 'Popular tracks', subtitle: '${catalog.songs.length} songs · ${_catalogDuration(catalog.songs)}'),
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
            _musicHeader(context,
              eyebrow:'Album',
              title:widget.album,
              subtitle:'${widget.artist} · ${tracks.length} tracks'
                '${_catalogDuration(tracks).isNotEmpty ? ' · ${_catalogDuration(tracks)}' : ''}',
              artwork:_cover(context,
                widget.artwork ?? (tracks.isNotEmpty ? tracks.first.artworkUrl:null),
                size:210),
              actions:Column(
                crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  _catalogActions(tracks:tracks,player:widget.player,
                    addons:widget.addons),
                  const SizedBox(height:12),
                  GhostButton(
                    onPressed:()=>openArtistPage(context,
                      artist:widget.artist,player:widget.player,
                      addonService:widget.addonService,addons:widget.addons,
                      library:widget.library),
                    child:const Text('View artist'),
                  ),
                ],
              ),
            ),
            const SizedBox(height:28),
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
              OrchidSectionHeader(title: 'Tracklist', subtitle: '${tracks.length} songs'),
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
