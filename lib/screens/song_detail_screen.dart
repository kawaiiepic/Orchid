import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../widgets/orchid_adaptive_controls.dart';
import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/player_service.dart';
import '../services/music_library.dart';
import '../services/music_catalog_service.dart';
import '../services/lyrics_service.dart';
import '../widgets/artist_artwork.dart';
import 'music_detail_pages.dart';
import '../widgets/song_context_menu.dart';
import '../widgets/content_drawer.dart';
import '../widgets/track_duration.dart';
import '../widgets/orchid_style.dart';
import '../widgets/apple_cover.dart';
import '../widgets/orchid_detail_header.dart';
import '../widgets/orchid_hover_zoom.dart';

void showSongDetailDrawer(BuildContext context, {
  required PlayerService player,
  required AddonService addonService,
  required List<InstalledAddon> addons,
  MusicLibrary? library,
  required String title,
  required String artist,
  String? album,
  String? artworkUrl,
  DateTime? listenedAt,
  bool nowPlaying = false,
  TrackResult? track,
}) {
  showContentDrawer(context, builder: (_) => SongDetailScreen(
    player:player, addonService:addonService, addons:addons,
    library:library, title:title, artist:artist, album:album,
    artworkUrl:artworkUrl, listenedAt:listenedAt,
    nowPlaying:nowPlaying, track:track,
  ));
}

/// Native song page. Last.fm records are metadata, not direct audio streams.
class SongDetailScreen extends StatefulWidget {
 final PlayerService player;
 final MusicLibrary? library;
 final AddonService addonService;
 final List<InstalledAddon> addons;
 final String title,artist;
 final String? album,artworkUrl;
 final DateTime? listenedAt;
 final bool nowPlaying;
 final TrackResult? track;
 const SongDetailScreen({super.key,required this.player,this.library,required this.addonService,
  required this.addons,required this.title,required this.artist,this.album,
  this.artworkUrl,this.listenedAt,this.nowPlaying=false,this.track});
 @override State<SongDetailScreen> createState()=>_SongDetailScreenState();
}
class _SongDetailScreenState extends State<SongDetailScreen>{
 bool searching=false;
 bool playing=false;
 bool get busy=>searching||playing;
 String? error;
 List<TrackResult> matches=[];
 late Future<ArtistCatalog> _artistCatalog;
 late Future<List<TrackResult>> _albumSongs;
 late Future<List<TrackResult>> _recommendations;
 late Future<LyricsResult?> _lyrics;
 final LyricsService _lyricsService = LyricsService();

 @override
 void initState() {
   super.initState();
   final catalog = MusicCatalogService.instance;
   _artistCatalog = catalog.artist(widget.artist);
   _albumSongs = widget.album?.trim().isNotEmpty == true
       ? catalog.album(widget.artist, widget.album!)
       : Future.value(<TrackResult>[]);
   _recommendations = _loadRecommendations();
   final lyricTrack = widget.track ?? TrackResult(
     id: '', title: widget.title, artist: widget.artist,
     album: widget.album, sourceId: 'song-detail',
     sourceName: 'Orchid',
   );
   _lyrics = _lyricsService.fetchFor(lyricTrack);
 }

 Future<List<TrackResult>> _loadRecommendations() async {
   final catalog = MusicCatalogService.instance;
   // A genre match offers broader discovery; fall back to other artist songs.
   final genre = widget.track?.genres
       .where((value) => value.trim().isNotEmpty)
       .firstOrNull;
   try {
     final results = await catalog.searchTracks(
       genre == null ? widget.artist : genre,
     );
     final distinct = <String>{};
     return results.where((song) {
       if (norm(song.artist) == norm(widget.artist) &&
           norm(song.title) == norm(widget.title)) return false;
       return distinct.add('${norm(song.artist)}|${norm(song.title)}');
     }).take(12).toList();
   } catch (error) {
     debugPrint('[Orchid Song] Recommended unavailable: $error');
     return <TrackResult>[];
   }
 }

 Widget _trackRows(List<TrackResult> tracks) => Column(
   children: [
     for (final track in tracks)
       Padding(
         padding: const EdgeInsets.only(bottom: 4),
         child: OrchidHoverSurface(
           child: MouseRegion(
             cursor: SystemMouseCursors.click,
             child: GestureDetector(
               behavior: HitTestBehavior.opaque,
               onTap: () => play(track),
               child: Padding(
                 padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                 child: Row(children: [
                   AppleCover(
                     artist: track.artist,
                     name: track.title,
                     album: track.album,
                     fallbackUrl: track.artworkUrl,
                     size: 44,
                     radius: 7,
                     zoomOnHover: false,
                   ),
                   const SizedBox(width: 12),
                   Expanded(child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Text(track.title, maxLines: 1,
                         overflow: TextOverflow.ellipsis).semiBold(),
                       const SizedBox(height: 3),
                       Text(track.artist, maxLines: 1,
                         overflow: TextOverflow.ellipsis).small().muted(),
                     ],
                   )),
                   if (trackDurationLabel(track.duration) != null)
                     Text(trackDurationLabel(track.duration)!).small().muted(),
                   const SizedBox(width: 10),
                   IconButton.ghost(
                     onPressed: () => widget.player.addToQueue(track),
                     icon: const Icon(LucideIcons.listPlus, size: 17),
                   ),
                 ]),
               ),
             ),
           ),
         ),
       ),
   ],
 );

 Widget _artistDiscovery() => FutureBuilder<ArtistCatalog>(
   future: _artistCatalog,
   builder: (context, snapshot) {
     final catalog = snapshot.data;
     if (catalog == null) return const SizedBox.shrink();
     final popular = catalog.songs.where((song) =>
       !(norm(song.artist) == norm(widget.artist) &&
         norm(song.title) == norm(widget.title))
     ).take(8).toList();
     final related = catalog.similarArtists
         .where((name) => norm(name) != norm(widget.artist))
         .take(12).toList();
     if (popular.isEmpty && related.isEmpty) return const SizedBox.shrink();
     return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         if (popular.isNotEmpty) ...[
           const SizedBox(height: 28),
           OrchidSectionHeader(title: 'Popular tracks by ${widget.artist}'),
           const SizedBox(height: 12),
           _trackRows(popular),
         ],
         if (related.isNotEmpty) ...[
           const SizedBox(height: 28),
           const OrchidSectionHeader(title: 'Fans also like'),
           const SizedBox(height: 12),
           SingleChildScrollView(
             scrollDirection: Axis.horizontal,
             child: Row(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 for (final name in related)
                   Padding(
                     padding: const EdgeInsets.only(right: 20),
                     child: SizedBox(
                       width: 128,
                       child: MouseRegion(
                         cursor: SystemMouseCursors.click,
                         child: GestureDetector(
                           behavior: HitTestBehavior.opaque,
                           onTap: widget.library == null ? null : () =>
                             openArtistPage(context,
                               artist: name,
                               player: widget.player,
                               addonService: widget.addonService,
                               addons: widget.addons,
                               library: widget.library!),
                           child: Column(children: [
                             ArtistArtwork(
                               artist: name, size: 118, radius: 59),
                             const SizedBox(height: 8),
                             Text(name, maxLines: 2,
                               textAlign: TextAlign.center,
                               overflow: TextOverflow.ellipsis).semiBold(),
                           ]),
                         ),
                       ),
                     ),
                   ),
               ],
             ),
           ),
         ],
       ],
     );
   },
 );

 Widget _albumDiscovery() => FutureBuilder<List<TrackResult>>(
   future: _albumSongs,
   builder: (context, snapshot) {
     final songs = (snapshot.data ?? <TrackResult>[])
         .where((song) => norm(song.title) != norm(widget.title))
         .toList();
     if (songs.isEmpty) return const SizedBox.shrink();
     return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         const SizedBox(height: 28),
         OrchidSectionHeader(title: 'Songs from ${widget.album}'),
         const SizedBox(height: 12),
         _trackRows(songs),
       ],
     );
   },
 );

 Widget _recommendedSection() => FutureBuilder<List<TrackResult>>(
   future: _recommendations,
   builder: (context, snapshot) {
     final songs = snapshot.data ?? <TrackResult>[];
     if (songs.isEmpty) return const SizedBox.shrink();
     return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         const SizedBox(height: 28),
         const OrchidSectionHeader(title: 'Recommended'),
         const SizedBox(height: 12),
         _trackRows(songs),
       ],
     );
   },
 );

 Widget _lyricsSection() => FutureBuilder<LyricsResult?>(
   future: _lyrics,
   builder: (context, snapshot) {
     final result = snapshot.data;
     if (result == null || !result.hasAny) return const SizedBox.shrink();
     final lines = result.displayText.trim().split('\n')
         .where((line) => line.trim().isNotEmpty).take(6).toList();
     if (lines.isEmpty) return const SizedBox.shrink();
     return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         const SizedBox(height: 28),
         const OrchidSectionHeader(title: 'Lyrics'),
         const SizedBox(height: 12),
         for (final line in lines)
           Padding(
             padding: const EdgeInsets.only(bottom: 7),
             child: Text(line, style: const TextStyle(
               fontSize: 16, height: 1.35, color: Color(0xFFD6CEE0))),
           ),
         const SizedBox(height: 4),
         Text('Via ${result.providerLabel}').small().muted(),
       ],
     );
   },
 );
 String norm(String s)=>s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'),' ').trim();
 Future<void> find() async{
  if(busy)return;
  setState((){searching=true;error=null;});
  try{
   final results=await widget.addonService.search(widget.addons,
    '${widget.artist} ${widget.title}').timeout(const Duration(seconds:25));
   final exact=results.where((t)=>norm(t.title)==norm(widget.title)&&
    norm(t.artist)==norm(widget.artist)).toList();
   if(!mounted)return;
   setState((){
    matches=exact.isNotEmpty?exact:results;
    if(matches.isEmpty)error='No matching playback sources found.';
   });
  }catch(e){if(mounted)setState(()=>error='Search failed: $e');}
  finally{if(mounted)setState(()=>searching=false);}
 }
 Future<void> play(TrackResult t) async{
  if(busy)return;
  setState((){playing=true;error=null;});
  try{
   widget.player.setAddons(widget.addons);
   await widget.player.playTrack(t);
  }catch(e){if(mounted)setState(()=>error='Playback failed: $e');}
  finally{if(mounted)setState(()=>playing=false);}
 }
 Future<void> playFirst() async{
  if(widget.track!=null){await play(widget.track!);return;}
  if(matches.isEmpty)await find();
  if(mounted&&matches.isNotEmpty)await play(matches.first);
 }
 Future<void> queueFirst() async {
  if (busy) return;
  if (widget.track != null) {
    widget.player.addToQueue(widget.track!);
    return;
  }
  if (matches.isEmpty) await find();
  if (mounted && matches.isNotEmpty) {
    widget.player.addToQueue(matches.first);
  }
 }

 String? get displayedDuration {
  final direct = trackDurationLabel(widget.track?.duration);
  if (direct != null) return direct;
  for (final result in matches) {
    final seconds = trackDurationLabel(result.duration);
    if (seconds != null) return seconds;
  }
  return null;
 }

 SavedSong get savedSong => SavedSong(widget.title,widget.artist,
    album:widget.album,artwork:widget.artworkUrl,
    duration:widget.track?.duration);

 Widget _libraryActions() {
  final library=widget.library;
  if(library==null)return const SizedBox.shrink();
  final t=widget.track ?? TrackResult(
    id:savedSong.key,
    title:widget.title,
    artist:widget.artist,
    album:widget.album,
    artworkUrl:widget.artworkUrl,
    sourceId:'orchid-library',
    sourceName:'Library',
  );
  return SongContextMenu(
    track:t,
    player:widget.player,
    library:library,
    addonService:widget.addonService,
    addons:widget.addons,
    showViewSong:false,
    openOnTap:true,
    child:const Padding(
      padding:EdgeInsets.all(12),
      child:Icon(LucideIcons.ellipsis,size:22),
    ),
  );
 }

 Widget artwork() => AppleCover(
   artist: widget.artist,
   name: widget.title,
   fallbackUrl: widget.artworkUrl ?? widget.track?.artworkUrl,
   size: 148,
   radius: 12,
   zoomOnHover: false,
 );

 @override
 Widget build(BuildContext context) => ListView(
     padding: EdgeInsets.fromLTRB(24, 24, 30,
       28 + (MediaQuery.sizeOf(context).width >= 850 ? 104 : 0)),
     children:[
       Align(
         alignment: Alignment.centerLeft,
         child: MediaQuery.sizeOf(context).width < 850
           ? OrchidBackButton(
               onPressed: () => dismissContentDrawer(context),
             )
           : IconButton.ghost(
               onPressed: () => dismissContentDrawer(context),
               icon: const Icon(LucideIcons.arrowLeft),
             ),
       ),
       const SizedBox(height: 12),
       OrchidDetailHeader(
         eyebrow: 'Song',
         title: widget.title,
         subtitle: [
           widget.artist,
           if (widget.album?.trim().isNotEmpty == true) widget.album!,
           if (displayedDuration != null) displayedDuration!,
           if (widget.nowPlaying) 'Now playing',
         ].join(' · '),
         artwork: artwork(),
         trailing: widget.library != null ? _libraryActions() : null,
         actions: Wrap(spacing: 10, runSpacing: 10, children: [
           OrchidAdaptiveControls.button(
             prominent: true,
             onPressed: busy ? null : playFirst,
             child: Row(mainAxisSize: MainAxisSize.min, children: [
               const Icon(LucideIcons.play, size: 17),
               const SizedBox(width: 9),
               Text(playing ? 'Starting…' : 'Play'),
             ]),
           ),
           OrchidAdaptiveControls.button(
             onPressed: busy ? null : queueFirst,
             child: const Row(mainAxisSize: MainAxisSize.min, children: [
               Icon(LucideIcons.listMusic, size: 17),
               SizedBox(width: 8),
               Text('Add to queue'),
             ]),
           ),
         ]),
       ),
       if (widget.listenedAt != null) ...[
         const SizedBox(height: 28),
         const OrchidSectionHeader(title: 'About this song'),
         const SizedBox(height: 12),
         const Text('Last listened').small().muted(),
         const SizedBox(height: 5),
         Text(widget.listenedAt!.toLocal().toString()).semiBold(),
       ],
       _lyricsSection(),
       _recommendedSection(),
       _artistDiscovery(),
       _albumDiscovery(),
       const SizedBox(height: 28),
       const OrchidSectionHeader(
         title:'Playback sources',
         subtitle:'Find other versions and providers for this song',
       ),
       const SizedBox(height:12),
       OrchidAdaptiveControls.button(
         onPressed:busy?null:find,
         child:Text(searching?'Finding versions…':'Find available versions'),
       ),
       if(error!=null)...[
         const SizedBox(height:12),
         Text(error!).small().muted(),
       ],
       if(matches.isNotEmpty)...[
         const SizedBox(height:12),
         ...matches.take(12).map((t)=>Padding(
           padding:const EdgeInsets.only(bottom:7),
           child:OrchidHoverSurface(
             child:Row(children:[
               Expanded(child:Button(
                 style:const ButtonStyle.ghost(),
                 onPressed:busy?null:()=>play(t),
                 child:Padding(
                   padding:const EdgeInsets.all(12),
                   child:Column(
                     crossAxisAlignment:CrossAxisAlignment.start,
                     children:[
                       Text(t.title,maxLines:1,
                         overflow:TextOverflow.ellipsis).semiBold(),
                       const SizedBox(height:4),
                       Text('${t.artist} · ${t.sourceName}')
                         .small().muted(),
                     ],
                   ),
                 ),
               )),
               if(trackDurationLabel(t.duration)!=null)
                 Text(trackDurationLabel(t.duration)!).small().muted(),
               IconButton.ghost(
                 onPressed:()=>widget.player.addToQueue(t),
                 icon:const Icon(LucideIcons.listMusic,size:18),
               ),
             ]),
           ),
         )),
       ],
     ],
   );
}
