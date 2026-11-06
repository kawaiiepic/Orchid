import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/player_service.dart';
import '../services/music_library.dart';
import '../widgets/mini_player_bar.dart';
import 'music_detail_pages.dart';
import '../widgets/song_context_menu.dart';
import '../widgets/content_drawer.dart';
import '../widgets/track_duration.dart';
import '../widgets/orchid_style.dart';

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
    album:widget.album,artwork:widget.artworkUrl);

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
    openOnTap:true,
    child:IconButton.ghost(
      onPressed: null,
      icon:const Icon(LucideIcons.ellipsis,size:22),
    ),
  );
 }

 Widget artwork(){
  final url=widget.artworkUrl??widget.track?.artworkUrl;
  if(url==null||!url.startsWith('https://')){
    return Container(width:210,height:210,
      decoration:OrchidStyle.panelDecoration(radius:16),
      child:const Icon(LucideIcons.music2,size:48));
  }
  return ClipRRect(borderRadius:BorderRadius.circular(16),
    child:Image.network(url,width:210,height:210,fit:BoxFit.cover,
      errorBuilder:(_,__,___)=>const SizedBox(width:210,height:210,
        child:Center(child:Icon(LucideIcons.music2,size:48)))));
 }
 @override
 Widget build(BuildContext context) => Scaffold(
   footers:[MiniPlayerBar(player:widget.player)],
   child:ListView(
     padding:const EdgeInsets.fromLTRB(20,12,20,28),
     children:[
       if(widget.library!=null)
         Align(alignment:Alignment.centerRight,child:_libraryActions()),
       const SizedBox(height:12),
       Container(
         width:double.infinity,
         padding:const EdgeInsets.all(20),
         decoration:OrchidStyle.gradientDecoration(radius:22),
         child:Column(
           crossAxisAlignment:CrossAxisAlignment.start,
           children:[
             Center(child:artwork()),
             const SizedBox(height:20),
             const Text('SONG',style:TextStyle(
               fontSize:11,letterSpacing:2,
               color:OrchidStyle.lilac,fontWeight:FontWeight.w700)),
             const SizedBox(height:9),
             Text(widget.title,style:const TextStyle(
               fontSize:27,height:1.12,fontWeight:FontWeight.w700)),
             const SizedBox(height:8),
             Text(widget.artist,style:const TextStyle(
               fontSize:16,color:OrchidStyle.lilac)),
             const SizedBox(height:12),
             Wrap(spacing:8,runSpacing:7,children:[
               if(displayedDuration!=null)
                 Text(displayedDuration!).small().muted(),
               if(widget.track?.sourceName.isNotEmpty==true)
                 Text(widget.track!.sourceName).small().muted(),
               if(widget.nowPlaying)
                 const Text('Now playing').small().muted(),
             ]),
             const SizedBox(height:19),
             Wrap(spacing:10,runSpacing:10,children:[
               PrimaryButton(
                 onPressed:busy?null:playFirst,
                 child:Row(mainAxisSize:MainAxisSize.min,children:[
                   const Icon(LucideIcons.play,size:17),
                   const SizedBox(width:9),
                   Text(playing?'Starting…':'Play'),
                 ]),
               ),
               OutlineButton(
                 onPressed:busy?null:queueFirst,
                 child:const Row(mainAxisSize:MainAxisSize.min,children:[
                   Icon(LucideIcons.listMusic,size:17),
                   SizedBox(width:8),
                   Text('Add to queue'),
                 ]),
               ),
             ]),
           ],
         ),
       ),
       const SizedBox(height:27),
       const OrchidSectionHeader(title:'About this song'),
       Container(
         padding:const EdgeInsets.all(15),
         decoration:OrchidStyle.panelDecoration(radius:16),
         child:Column(
           crossAxisAlignment:CrossAxisAlignment.start,
           children:[
             const Text('Artist').small().muted(),
             const SizedBox(height:5),
             GhostButton(
               onPressed:widget.library==null?null:()=>openArtistPage(context,
                 artist:widget.artist,player:widget.player,
                 addonService:widget.addonService,
                 addons:widget.addons,library:widget.library!),
               child:Text(widget.artist).semiBold(),
             ),
             if(widget.album?.isNotEmpty==true)...[
               const Divider(),
               const Text('Album').small().muted(),
               const SizedBox(height:5),
               GhostButton(
                 onPressed:widget.library==null?null:()=>openAlbumPage(context,
                   artist:widget.artist,album:widget.album!,
                   artwork:widget.artworkUrl,player:widget.player,
                   addonService:widget.addonService,addons:widget.addons,
                   library:widget.library!),
                 child:Text(widget.album!).semiBold(),
               ),
             ],
             if(displayedDuration!=null)...[
               const Divider(),
               const Text('Duration').small().muted(),
               const SizedBox(height:5),
               Text(displayedDuration!).semiBold(),
             ],
             if(widget.listenedAt!=null)...[
               const Divider(),
               const Text('Last listened').small().muted(),
               const SizedBox(height:5),
               Text(widget.listenedAt!.toLocal().toString()).semiBold(),
             ],
           ],
         ),
       ),
       const SizedBox(height:26),
       const OrchidSectionHeader(
         title:'Playback sources',
         subtitle:'Find other versions and providers for this song',
       ),
       OutlineButton(
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
           child:Container(
             decoration:OrchidStyle.panelDecoration(radius:14),
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
   ),
 );
}
