import 'dart:async';
import 'package:flutter/widgets.dart' show EditableText, FocusNode, TextInputType;
import 'package:flutter/services.dart' show TextEditingValue;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../widgets/orchid_adaptive_controls.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_catalog_service.dart';
import '../services/orchid_account.dart';
import '../widgets/apple_cover.dart';
import '../widgets/content_drawer.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import '../widgets/artist_artwork.dart';
import '../widgets/orchid_style.dart';
import '../widgets/song_context_menu.dart';
import '../widgets/track_duration.dart';
import 'music_detail_pages.dart';
import 'song_detail_screen.dart';

enum SearchCategory { all, artists, tracks, albums, playlists }

class SearchScreen extends StatefulWidget {
  final Widget header;
  final AddonService addonService;
  final OrchidAccount account;
  final PlayerService player;
  final MusicLibrary library;
  final List<InstalledAddon> addons;
  const SearchScreen({super.key, required this.header, required this.account, required this.addonService,
    required this.player, required this.library, required this.addons});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _searchFocus = FocusNode();
  SearchCategory _category = SearchCategory.all;
  List<TrackResult> _tracks = [];
  List<MusicAlbum> _albums = [];
  List<String> _artists = [];
  List<Map<String, dynamic>> _applePlaylists = [];
  bool _applePlaylistsConfigured = false;
  bool _usingAppleCatalog = false;
  bool _searching = false;
  bool _showAllTracks = false;
  bool _showAllAlbums = false;
  bool _showAllPlaylists = false;
  Timer? _searchDebounce;
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
    return widget.library.visiblePlaylists
        .where((p) => _norm(p.name).contains(query)).toList()
      ..sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  void dispose() {
    ++_generation;
    _searchDebounce?.cancel();
    _controller.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    // Invalidate in-flight results immediately, not after debounce expires.
    ++_generation;
    if (value.trim().isEmpty) {
      _search();
    } else {
      _searchDebounce = Timer(const Duration(milliseconds: 320), _search);
    }
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    final generation = ++_generation;
    _showAllTracks = false;
    _showAllAlbums = false;
    _showAllPlaylists = false;
    if (query.isEmpty) {
      setState(() { _tracks=[]; _albums=[]; _artists=[]; _applePlaylists=[];
        _searching=false; _status=null; });
      return;
    }
    setState(() { _searching=true; _status='Searching…'; });
    try {
      final data=await widget.account.searchAppleCatalog(query);
      if(!mounted || generation!=_generation)return;
      List<Map<String,dynamic>> rows(String key) {
        final value=data[key];
        if(value is! List)return [];
        return value.whereType<Map>()
            .map((item)=>Map<String,dynamic>.from(item)).toList();
      }
      final seen=<String>{};
      final tracks=<TrackResult>[];
      for(final item in rows('tracks')) {
        final title=(item['title']??'').toString();
        final artist=(item['artist']??'').toString();
        if(title.isEmpty||artist.isEmpty)continue;
        final album=item['album']?.toString();
        if(!seen.add('${_norm(artist)}|${_norm(title)}|${_norm(album??'')}'))continue;
        tracks.add(TrackResult(
          id:item['id']?.toString()??'',
          title:title,artist:artist,album:album,
          artworkUrl:item['image']?.toString(),
          duration:item['duration'] is num?(item['duration'] as num).toInt():null,
          previewUrl:item['previewUrl']?.toString(),
          sourceId:'apple-music',sourceName:'Apple Music',
        ));
      }
      final albums=<MusicAlbum>[];
      for(final item in rows('albums')) {
        final id=int.tryParse(item['id']?.toString()??'');
        if(id==null)continue;
        albums.add(MusicAlbum(
          id:id,title:item['title']?.toString()??'',
          artist:item['artist']?.toString()??'',
          artwork:item['image']?.toString(),
          trackCount:item['trackCount'] is num
              ?(item['trackCount'] as num).toInt():null,
        ));
      }
      final artists=rows('artists').map((item)=>
          item['name']?.toString()??'')
          .where((name)=>name.isNotEmpty).take(1).toList();
      final playlists=rows('playlists');
      setState(() {
        _tracks=_tracksOn?tracks:[];
        _albums=_albumsOn?albums:[];
        _artists=_artistsOn?artists:[];
        _applePlaylists=_playlistsOn?playlists:[];
        _applePlaylistsConfigured=true;
        _usingAppleCatalog=true;
        _searching=false;
        final count=_tracks.length+_albums.length+_artists.length+
            (_playlistsOn?_playlists.length+_applePlaylists.length:0);
        _status=count==0?'No results found':'$count results';
      });
    }catch(error) {
      debugPrint('[Orchid Search] Apple Music catalog error: $error');
      // Older Petal deployments don't have /orchid/apple/search yet.
      // Keep browsing usable until the backend update is deployed.
      if(error is OrchidAuthException && error.status==404) {
        try {
          final catalog=MusicCatalogService.instance;
          final fallback=await Future.wait<dynamic>([
            _tracksOn?catalog.searchTracks(query):Future.value(<TrackResult>[]),
            _albumsOn?catalog.searchAlbums(query):Future.value(<MusicAlbum>[]),
            _artistsOn?catalog.searchArtists(query):Future.value(<String>[]),
          ]);
          if(!mounted||generation!=_generation)return;
          setState(() {
            _tracks=fallback[0] as List<TrackResult>;
            _albums=fallback[1] as List<MusicAlbum>;
            _artists=(fallback[2] as List<String>).take(1).toList();
            _applePlaylists=[];
            _applePlaylistsConfigured=false;
            _usingAppleCatalog=false;
            _searching=false;
            _status='Showing public catalog results. Update Petal for Apple Music search.';
          });
          return;
        }catch(fallbackError) {
          debugPrint('[Orchid Search] Public catalog fallback failed: $fallbackError');
        }
      }
      if(!mounted||generation!=_generation)return;
      setState(() {
        _tracks=[];
        _albums=[];
        _artists=[];
        _applePlaylists=[];
        _searching=false;
        _status='Music search unavailable: $error';
      });
    }
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

  Widget _tile({required Widget artwork, required String title,
    required String subtitle, required VoidCallback onTap, Widget? trailing}) =>
    Padding(padding:const EdgeInsets.symmetric(vertical:5),child:
      GestureDetector(behavior:HitTestBehavior.opaque,onTap:onTap,
        child:OrchidGlassPanel(
          radius:15,
          child:Padding(
            padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
            child:Row(children:[
            artwork,
            const SizedBox(width:12),
            Expanded(child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                Text(title,maxLines:1,overflow:TextOverflow.ellipsis).semiBold(),
                Text(subtitle,maxLines:2,overflow:TextOverflow.ellipsis).small().muted(),
              ],
            )),
            trailing ?? const Icon(LucideIcons.chevronRight,size:18),
            ]),
          ),
        ),
      ),
    );

  Widget _trackTile(TrackResult t) => SongContextMenu(
    track:t, player:widget.player, library:widget.library,
    child:_tile(
      artwork:AppleCover(
        artist:t.artist,
        name:t.title,
        album:t.album,
        fallbackUrl:t.artworkUrl,
        // Tracks returned by the Apple Music playlist API already include
        // canonical artwork. Do not replace it with an iTunes search guess.
        preferredUrl:t.sourceId == 'apple-music' ? t.artworkUrl : null,
        size:50,
      ),
      title:t.title,
      subtitle:[t.artist, if(t.album?.trim().isNotEmpty==true) t.album!].join('\n'),
      onTap:()=>_play(t),
      trailing:Row(mainAxisSize:MainAxisSize.min,children:[
        if(trackDurationLabel(t.duration)!=null)...[
          Text(trackDurationLabel(t.duration)!).xSmall().muted(),
          const SizedBox(width:8),
        ],
        IconButton.ghost(
          onPressed:()=>_songDetails(t),
          icon:const Icon(LucideIcons.info,size:18),
        ),
      ]),
    ),
  );

  void _openAlbum(MusicAlbum album) => openAlbumPage(context,
    artist:album.artist, album:album.title, artwork:album.artwork,
    collectionId:album.id, player:widget.player,
    addonService:widget.addonService, addons:widget.addons,
    library:widget.library);

  Widget _albumTile(MusicAlbum album) => GestureDetector(
    behavior:HitTestBehavior.opaque,
    onTap:()=>_openAlbum(album),
    child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        AspectRatio(
          aspectRatio:1,
          child:LayoutBuilder(builder:(context,constraints) =>
            AppleCover(
              artist:album.artist,
              name:album.title,
              isAlbum:true,
              fallbackUrl:album.artwork,
              size:constraints.maxWidth,
              radius:13,
            ),
          ),
        ),
        const SizedBox(height:8),
        Text(album.title,maxLines:1,overflow:TextOverflow.ellipsis).semiBold(),
        Text(album.artist,maxLines:1,overflow:TextOverflow.ellipsis).small().muted(),
      ],
    ),
  );

  Widget _artistTile(String artist) => GestureDetector(
    behavior:HitTestBehavior.opaque,
    onTap:()=>openArtistPage(context,artist:artist,
      account:_usingAppleCatalog ? widget.account : null,
      player:widget.player,addonService:widget.addonService,
      addons:widget.addons,library:widget.library),
    child:OrchidGlassPanel(
      radius:18,
      child:Padding(
        padding:const EdgeInsets.all(16),
        child:Row(children:[
        ArtistArtwork(artist:artist,size:112,radius:18),
        const SizedBox(width:18),
        Expanded(child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            const Text('TOP ARTIST').xSmall().muted(),
            const SizedBox(height:9),
            Text(artist,maxLines:2,overflow:TextOverflow.ellipsis).xLarge().semiBold(),
          ],
        )),
        const Icon(LucideIcons.chevronRight),
        ]),
      ),
    ),
  );

  Widget _playlistCover(String? url) => LayoutBuilder(
    builder:(context, constraints) => ClipRRect(
      borderRadius:BorderRadius.circular(13),
      child:SizedBox(
        width:constraints.maxWidth,
        height:constraints.maxWidth,
        child:url != null && url.startsWith('https://')
          ? CachedNetworkImage(
              imageUrl:url,
              fit:BoxFit.cover,
              errorWidget:(_,__,___)=>_emptyPlaylistCover(),
            )
          : _emptyPlaylistCover(),
      ),
    ),
  );

  Widget _emptyPlaylistCover() => const OrchidGlassPanel(
    radius:13,
    child:Center(child:Icon(LucideIcons.listMusic,size:38)),
  );

  Widget _playlistCard({
    required String title,
    required String subtitle,
    required String? image,
    required VoidCallback onTap,
  }) => GestureDetector(
    behavior:HitTestBehavior.opaque,
    onTap:onTap,
    child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        AspectRatio(
          aspectRatio:1,
          child:_playlistCover(image),
        ),
        const SizedBox(height:8),
        Text(title,maxLines:1,overflow:TextOverflow.ellipsis).semiBold(),
        Text(subtitle,maxLines:1,overflow:TextOverflow.ellipsis).small().muted(),
      ],
    ),
  );

  Widget _playlistTile(MusicPlaylist p) => _playlistCard(
    title:p.name,
    subtitle:'Your playlist · ${p.songs.length} songs',
    image:p.songs.isNotEmpty ? p.songs.first.artwork : null,
    onTap:()=>_playPlaylist(p),
  );

  TrackResult _applePlaylistTrack(Map<String,dynamic> item) => TrackResult(
    id:(item['id'] ?? '').toString(),
    title:(item['title'] ?? '').toString(),
    artist:(item['artist'] ?? '').toString(),
    album:item['album']?.toString(),
    artworkUrl:item['image']?.toString(),
    duration:item['duration'] is num ? (item['duration'] as num).toInt() : null,
    previewUrl:item['previewUrl']?.toString(),
    sourceId:'apple-music', sourceName:'Apple Music',
  );

  void _openApplePlaylist(Map<String,dynamic> item) {
    final id = item['id']?.toString() ?? '';
    if(id.isEmpty) return;
    final future = widget.account.applePlaylist(id);
    showContentDrawer(context,builder:(sheetContext) =>
      FutureBuilder<Map<String,dynamic>>(
        future:future,
        builder:(context,snapshot) {
          final raw = snapshot.data;
          final songs = (raw?['tracks'] is List
              ? (raw!['tracks'] as List).whereType<Map>()
                  .map((entry)=>_applePlaylistTrack(Map<String,dynamic>.from(entry)))
                  .toList()
              : <TrackResult>[]);
          final name = (raw?['name'] ?? item['name'] ?? 'Apple Music playlist').toString();
          return Scaffold(
            child:ListView(
              padding:const EdgeInsets.all(20),
              children:[
                const SizedBox(height:12),
                Text(name).x2Large().semiBold(),
                const SizedBox(height:5),
                Text((raw?['curator'] ?? item['curator'] ?? 'Apple Music').toString()).muted(),
                const SizedBox(height:14),
                if(snapshot.connectionState != ConnectionState.done)
                  const Text('Loading Apple Music tracks…').muted()
                else if(snapshot.hasError)
                  Text('Could not load playlist: ${snapshot.error}').muted()
                else if(songs.isEmpty)
                  const Text('No playable song metadata found.').muted()
                else ...[
                  OrchidAdaptiveControls.button(prominent: true, 
                    onPressed:(){
                      widget.player.setAddons(widget.addons);
                      widget.player.playTrack(songs.first,fromQueue:songs).catchError(
                        (Object e)=>debugPrint('[Orchid Apple Playlist] Playback failed: $e'));
                    },
                    child:const Text('Play all'),
                  ),
                  const SizedBox(height:12),
                  for(final song in songs)
                    _trackTile(song),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _applePlaylistTile(Map<String,dynamic> item) => _playlistCard(
    title:item['name']?.toString() ?? 'Apple Music Playlist',
    subtitle:'Apple Music · ${item['curator'] ?? 'Apple Music'}',
    image:item['image']?.toString(),
    onTap:()=>_openApplePlaylist(item),
  );

  Widget _coverGrid(List<Widget> items) => LayoutBuilder(
    builder:(context,constraints) {
      final columns=(constraints.maxWidth / 165).floor().clamp(2,6).toInt();
      return GridView.builder(
        shrinkWrap:true,
        physics:const NeverScrollableScrollPhysics(),
        itemCount:items.length,
        gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:columns,
          crossAxisSpacing:12,
          mainAxisSpacing:16,
          childAspectRatio:0.72,
        ),
        itemBuilder:(context,index)=>items[index],
      );
    },
  );

  Widget _showMoreButton({
    required bool expanded,
    required VoidCallback onPressed,
  }) => Padding(
    padding:const EdgeInsets.symmetric(vertical:10),
    child:OrchidAdaptiveControls.button(
      onPressed:onPressed,
      child:Text(expanded ? 'Show Less' : 'Show More'),
    ),
  );

  Widget _section(String title,int length) => Padding(
    padding:const EdgeInsets.fromLTRB(0,20,0,8),
    child:OrchidSectionHeader(title:title,subtitle:'$length results'),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:widget.library,
      builder:(context,_) => ListView(
        padding:EdgeInsets.only(bottom:OrchidStyle.iosDockClearance(context) + (MediaQuery.sizeOf(context).width >= 850 ? 110 : 0)),
        children:[
      widget.header,
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
          Expanded(
            child: OrchidGlassPanel(
              radius: 14,
              transparentOnDesktop: false,
              child: SizedBox(
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    const Icon(LucideIcons.search,
                      size: 18, color: Color(0xFFCDBAE2)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) => Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            if (value.text.isEmpty)
                              const IgnorePointer(
                                child: Text('Search songs, artists, albums…',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFFB8A9C6),
                                  )),
                              ),
                            EditableText(
                              controller: _controller,
                              focusNode: _searchFocus,
                              style: const TextStyle(
                                color: Color(0xFFF7F0FF),
                                fontSize: 14,
                                height: 1.25,
                              ),
                              cursorColor: OrchidStyle.lilac,
                              backgroundCursorColor: OrchidStyle.lilac,
                              selectionColor: const Color(0x665F4391),
                              maxLines: 1,
                              keyboardType: TextInputType.text,
                              onChanged: _onQueryChanged,
                              onSubmitted: (_) => _search(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : GestureDetector(
                            onTap: () {
                              _controller.clear();
                              _onQueryChanged('');
                              _searchFocus.requestFocus();
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(LucideIcons.x,
                                size: 16, color: Color(0xFFBEACC9)),
                            ),
                          ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width:8),
          OrchidAdaptiveControls.button(prominent: true, onPressed:_searching?null:_search,
            child:Text(_searching?'…':'Search')),
        ]),
      ),
      SizedBox(height:58,child:ListView(
        scrollDirection:Axis.horizontal,
        padding:const EdgeInsets.symmetric(horizontal:18,vertical:7),
        children:[
          for(final category in SearchCategory.values)
            Padding(padding:const EdgeInsets.only(right:8),
              child:category==_category
                ? OrchidAdaptiveControls.button(prominent: true, 
                    onPressed:()=>_choose(category),
                    child:Text(category.name == 'all'?'All':
                      '${category.name[0].toUpperCase()}${category.name.substring(1)}'))
                : OrchidAdaptiveControls.button(
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
      Padding(
        padding:const EdgeInsets.fromLTRB(16,4,16,20),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            if(_artistsOn && _artists.isNotEmpty)...[
              _section('Artist',_artists.length),
              ..._artists.map(_artistTile),
            ],
            if(_tracksOn && _tracks.isNotEmpty)...[
              _section('Tracks',_tracks.length),
              ...(_showAllTracks ? _tracks : _tracks.take(15)).map(_trackTile),
              if(_tracks.length > 15)
                _showMoreButton(
                  expanded:_showAllTracks,
                  onPressed:()=>setState(() => _showAllTracks = !_showAllTracks),
                ),
            ],
            if(_albumsOn && _albums.isNotEmpty)...[
              _section('Albums',_albums.length),
              _coverGrid(
                (_showAllAlbums ? _albums : _albums.take(15))
                    .map(_albumTile).toList(),
              ),
              if(_albums.length > 15)
                _showMoreButton(
                  expanded:_showAllAlbums,
                  onPressed:()=>setState(() => _showAllAlbums = !_showAllAlbums),
                ),
            ],
            if(_playlistsOn && (_playlists.isNotEmpty || _applePlaylists.isNotEmpty))...[
              _section('Playlists',_playlists.length + _applePlaylists.length),
              _coverGrid([
                ..._playlists.map(_playlistTile),
                ..._applePlaylists.map(_applePlaylistTile),
              ].take(_showAllPlaylists ? _playlists.length + _applePlaylists.length : 15).toList()),
              if(_playlists.length + _applePlaylists.length > 15)
                _showMoreButton(
                  expanded:_showAllPlaylists,
                  onPressed:()=>setState(() => _showAllPlaylists = !_showAllPlaylists),
                ),
            ],
            if(_playlistsOn && _controller.text.trim().isNotEmpty &&
                !_applePlaylistsConfigured)
              Padding(
                padding:const EdgeInsets.symmetric(vertical:8),
                child:const Text('Apple Music playlists require a server-side developer token.').small().muted(),
              ),
           ],
         ),
       ),
     ],
    ),
   );
  }
}
