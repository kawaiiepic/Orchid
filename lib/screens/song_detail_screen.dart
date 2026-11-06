import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/player_service.dart';
import '../widgets/mini_player_bar.dart';

/// Native song page. Last.fm records are metadata, not direct audio streams.
class SongDetailScreen extends StatefulWidget {
 final PlayerService player;
 final AddonService addonService;
 final List<InstalledAddon> addons;
 final String title,artist;
 final String? album,artworkUrl;
 final DateTime? listenedAt;
 final bool nowPlaying;
 final TrackResult? track;
 const SongDetailScreen({super.key,required this.player,required this.addonService,
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
 Widget artwork(){
  final url=widget.artworkUrl??widget.track?.artworkUrl;
  if(url==null||!url.startsWith('https://')){
   return Container(width:210,height:210,color:Theme.of(context).colorScheme.muted,
    child:const Icon(LucideIcons.music2,size:48));
  }
  return ClipRRect(borderRadius:BorderRadius.circular(12),
   child:Image.network(url,width:210,height:210,fit:BoxFit.cover,
    errorBuilder:(_,__,___)=>const SizedBox(width:210,height:210,
     child:Center(child:Icon(LucideIcons.music2,size:48)))));
 }
 @override Widget build(BuildContext context)=>Scaffold(
  footers:[MiniPlayerBar(player:widget.player)],
  child:ListView(padding:const EdgeInsets.all(24),children:[
   Align(alignment:Alignment.centerLeft,child:IconButton.ghost(
    onPressed:()=>Navigator.of(context).pop(),
    icon:const Icon(LucideIcons.arrowLeft),
   )),
   const SizedBox(height:12),
   Center(child:artwork()),
   const SizedBox(height:20),
   Center(child:Text(widget.title,textAlign:TextAlign.center).x2Large().semiBold()),
   const SizedBox(height:6),
   Center(child:Text(widget.artist).large().muted()),
   if(widget.album?.isNotEmpty==true)...[
    const SizedBox(height:4),Center(child:Text(widget.album!).muted()),
   ],
   if(widget.nowPlaying||widget.listenedAt!=null)...[
    const SizedBox(height:10),
    Center(child:Text(widget.nowPlaying?'Now playing on Last.fm':
     'Listened: ${widget.listenedAt!.toLocal()}').small().muted()),
   ],
   const SizedBox(height:24),
   PrimaryButton(onPressed:busy?null:playFirst,
    child:Text(searching?'Finding sources…':playing?'Starting playback…':'Play')),
   const SizedBox(height:8),
   OutlineButton(onPressed:busy?null:find,
    child:Text(searching?'Searching music sources…':'Find playback sources')),
   if(error!=null)...[const SizedBox(height:12),Text(error!).small()],
   if(matches.isNotEmpty)...[
    const SizedBox(height:24),
    const Text('Available versions').large().semiBold(),
    const SizedBox(height:8),
    ...matches.take(10).map((t)=>Button(style:const ButtonStyle.ghost(),
     onPressed:busy?null:()=>play(t),
     child:Padding(padding:const EdgeInsets.symmetric(vertical:8),
      child:Row(children:[
       Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(t.title).semiBold(),
        Text('${t.artist} · ${t.sourceName}').small().muted(),
       ])),
       const Icon(LucideIcons.play,size:18),
      ])))),
   ],
  ]),
 );
}
