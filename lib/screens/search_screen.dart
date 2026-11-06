import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_catalog_service.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import '../widgets/artist_artwork.dart';
import '../widgets/orchid_style.dart';
import '../widgets/song_context_menu.dart';
import 'music_detail_pages.dart';
import 'song_detail_screen.dart';

enum SearchCategory { all, tracks, albums, artists, playlists }

class SearchScreen extends StatefulWidget {
  final AddonService addonService;
  final PlayerService player;
  final MusicLibrary library;
  final List<InstalledAddon> addons;
  const SearchScreen({super.key, required this.addonService,
    required this.player, required this.library, required this.addons});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  SearchCategory _category = SearchCategory.all;
  List<TrackResult> _tracks = [];
  List<MusicAlbum> _albums = [];
  List<String> _artists = [];
  bool _searching = false;
  int _generation = 0;
  String? _status;

  bool get _tracksOn => _category == SearchCategory.all ||
      _category == SearchCategory.tracks;
  bool get _albumsOn => _category == SearchCategory.all ||
      _category == SearchCategory.albums;
  bool get _artistsOn => _category == SearchCategory.all ||
      _category == SearchCategory.artists;
  bool get _playlistsOn => _category == SearchCategory.all ||
      _category == SearchCategory.playlists;
  String _norm(String s) => s.toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  List<MusicPlaylist> get _playlists {
    final query = _norm(_controller.text);
    if (query.isEmpty) return [];
    return widget.library.playlists
        .where((p) => _norm(p.name).contains(query)).toList()
      ..sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  void dispose() {
    ++_generation;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    final generation = ++_generation;
    if (query.isEmpty) {
      setState(() { _tracks=[]; _albums=[]; _artists=[];
        _searching=false; _status=null; });
      return;
    }
    setState(() { _searching=true; _status='Searching…'; });
    Future<List<T>> safe<T>(Future<List<T>> Function() load) async {
      try { return await load(); }
      catch(e) {
        debugPrint('[Orchid Search] Search provider unavailable: $e');
        return <T>[];
      }
    }
    final catalog = MusicCatalogService.instance;
    final response = await Future.wait<dynamic>([
      _tracksOn ? safe<TrackResult>(() => widget.addonService.search(widget.addons, query))
                : Future.value(<TrackResult>[]),
      _albumsOn ? safe<MusicAlbum>(() => catalog.searchAlbums(query))
                : Future.value(<MusicAlbum>[]),
      _artistsOn ? safe<String>(() => catalog.searchArtists(query))
                 : Future.value(<String>[]),
    ]);
    if (!mounted || generation != _generation) return;
    setState(() {
      _tracks = response[0] as List<TrackResult>;
      _albums = response[1] as List<MusicAlbum>;
      _artists = response[2] as List<String>;
      _searching = false;
      final count = _tracks.length + _albums.length + _artists.length +
          (_playlistsOn ? _playlists.length : 0);
      _status = count == 0 ? 'No results found' : '$count results';
    });
  }

  void _choose(SearchCategory category) {
    if (_category == category) return;
    setState(() => _category = category);
    _search();
  }

  void _play(TrackResult track) {
    widget.player.setAddons(widget.addons);
    widget.player.playTrack(track).catchError((Object e) {
      debugPrint('[Orchid] Cannot play search result: $e');
    });
  }

  void _songDetails(TrackResult track) {
    showSongDetailDrawer(context,
      player:widget.player, addonService:widget.addonService,
      addons:widget.addons, library:widget.library,
      title:track.title, artist:track.artist,
      album:track.album, artworkUrl:track.artworkUrl, track:track,
    );
  }

  void _playPlaylist(MusicPlaylist playlist) {
    if (playlist.songs.isEmpty) return;
    widget.player.setAddons(widget.addons);
    final tracks = playlist.songs.map((song) => TrackResult(
      id:song.key, title:song.title, artist:song.artist,
      album:song.album, artworkUrl:song.artwork,
      sourceId:'orchid-library', sourceName:'Library',
    )).toList();
    widget.player.playTrack(tracks.first, fromQueue:tracks).catchError((Object e) {
      debugPrint('[Orchid] Cannot play playlist: $e');
    });
  }

  Widget _art(String? url) => ClipRRect(
    borderRadius:BorderRadius.circular(8),
    child:SizedBox(width:50,height:50,child:url==null||!url.startsWith('https://')
        ? const Icon(LucideIcons.music2,size:24)
        : CachedNetworkImage(imageUrl:url,fit:BoxFit.cover,
          errorWidget:(_,__,___)=>const Icon(LucideIcons.music2,size:24))),
  );

  Widget _tile({required Widget artwork, required String title,
    required String subtitle, required VoidCallback onTap, Widget? trailing}) =>
    Padding(padding:const EdgeInsets.symmetric(vertical:5),child:
      GestureDetector(behavior:HitTestBehavior.opaque,onTap:onTap,
        child:Container(
          decoration:OrchidStyle.panelDecoration(radius:15),
          padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
          child:Row(children:[
            artwork,
            const SizedBox(width:12),
            Expanded(child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                Text(title,maxLines:1,overflow:TextOverflow.ellipsis).semiBold(),
                Text(subtitle,maxLines:1,overflow:TextOverflow.ellipsis).small().muted(),
              ],
            )),
            trailing ?? const Icon(LucideIcons.chevronRight,size:18),
          ]),
        ),
      ),
    );

  Widget _trackTile(TrackResult t) => SongContextMenu(
    track:t, player:widget.player, library:widget.library,
    child:_tile(
      artwork:_art(t.artworkUrl),
      title:t.title,
      subtitle:'${t.artist} · ${t.sourceName}',
      onTap:()=>_play(t),
      trailing:IconButton.ghost(
        onPressed:()=>_songDetails(t),
        icon:const Icon(LucideIcons.info,size:18),
      ),
    ),
  );

  Widget _albumTile(MusicAlbum album) => _tile(
    artwork:_art(album.artwork),
    title:album.title, subtitle:'${album.artist} · Album',
    onTap:()=>openAlbumPage(context,
      artist:album.artist, album:album.title, artwork:album.artwork,
      collectionId:album.id, player:widget.player,
      addonService:widget.addonService, addons:widget.addons,
      library:widget.library),
  );

  Widget _artistTile(String artist) => _tile(
    artwork:ArtistArtwork(artist:artist,size:50,radius:8),
    title:artist, subtitle:'Artist',
    onTap:()=>openArtistPage(context,artist:artist,
      player:widget.player,addonService:widget.addonService,
      addons:widget.addons,library:widget.library),
  );

  Widget _playlistTile(MusicPlaylist p) => _tile(
    artwork:Container(width:50,height:50,
      decoration:OrchidStyle.panelDecoration(radius:9),
      child:const Icon(LucideIcons.listMusic,size:24)),
    title:p.name, subtitle:'Playlist · ${p.songs.length} songs',
    onTap:()=>_playPlaylist(p),
  );

  Widget _section(String title,int length) => Padding(
    padding:const EdgeInsets.fromLTRB(0,20,0,8),
    child:OrchidSectionHeader(title:title,subtitle:'$length results'),
  );

  @override
  Widget build(BuildContext context) {
    return Column(children:[
      const Padding(
        padding:EdgeInsets.fromLTRB(20,20,20,14),
        child:OrchidHero(
          eyebrow:'Explore',title:'Find your next favorite.',
          description:'Search tracks, albums, artists and your playlists.',
          icon:LucideIcons.search,
        ),
      ),
      Padding(
        padding:const EdgeInsets.fromLTRB(20,8,20,10),
        child:Row(children:[
          Expanded(child:TextField(
            controller:_controller,
            placeholder:const Text('Search music…'),
            onSubmitted:(_)=>_search(),
          )),
          const SizedBox(width:8),
          PrimaryButton(onPressed:_searching?null:_search,
            child:Text(_searching?'…':'Search')),
        ]),
      ),
      SizedBox(height:48,child:ListView(
        scrollDirection:Axis.horizontal,
        padding:const EdgeInsets.symmetric(horizontal:18,vertical:5),
        children:[
          for(final category in SearchCategory.values)
            Padding(padding:const EdgeInsets.only(right:8),
              child:category==_category
                ? PrimaryButton(
                    onPressed:()=>_choose(category),
                    child:Text(category.name == 'all'?'All':
                      '${category.name[0].toUpperCase()}${category.name.substring(1)}'))
                : OutlineButton(
                    onPressed:()=>_choose(category),
                    child:Text(category.name == 'all'?'All':
                      '${category.name[0].toUpperCase()}${category.name.substring(1)}')),
            ),
        ],
      )),
      if(_status!=null)
        Padding(padding:const EdgeInsets.symmetric(horizontal:20,vertical:6),
          child:Align(alignment:Alignment.centerLeft,
            child:Text(_status!).small().muted())),
      Expanded(child:ListenableBuilder(
        listenable:widget.library,
        builder:(context,_) => ListView(
          padding:const EdgeInsets.fromLTRB(16,4,16,20),
          children:[
            if(_playlistsOn && _playlists.isNotEmpty)...[
              _section('Playlists',_playlists.length),
              ..._playlists.map(_playlistTile),
            ],
            if(_artistsOn && _artists.isNotEmpty)...[
              _section('Artists',_artists.length),
              ..._artists.map(_artistTile),
            ],
            if(_albumsOn && _albums.isNotEmpty)...[
              _section('Albums',_albums.length),
              ..._albums.map(_albumTile),
            ],
            if(_tracksOn && _tracks.isNotEmpty)...[
              _section('Tracks',_tracks.length),
              ..._tracks.map(_trackTile),
            ],
          ],
        ),
      )),
    ]);
  }
}
