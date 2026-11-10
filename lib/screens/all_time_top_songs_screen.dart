import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../widgets/orchid_adaptive_controls.dart';
import '../models/addon.dart';
import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../widgets/orchid_style.dart';

class AllTimeTopSongsScreen extends StatefulWidget {
  final OrchidAccount account;
  final PlayerService player;
  final List<InstalledAddon> addons;
  const AllTimeTopSongsScreen({super.key,required this.account,required this.player,required this.addons});
  @override State<AllTimeTopSongsScreen> createState()=>_AllTimeTopSongsScreenState();
}

class _AllTimeTopSongsScreenState extends State<AllTimeTopSongsScreen>{
  bool loading=true;
  String? error;
  List<Map<String,dynamic>> songs=[];
  @override void initState(){super.initState();_load();}
  Future<void> _load() async{
    setState(() {loading=true;error=null;});
    try{
      final value=await widget.account.allTimeTopSongs();
      if(!mounted)return;
      setState(() {songs=(value['songs'] as List? ??[])
        .whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList();});
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>loading=false);}
  }
  TrackResult _track(Map<String,dynamic> item)=>TrackResult(
    id:'${item['artist']}|${item['title']}',title:(item['title']??'').toString(),
    artist:(item['artist']??'').toString(),album:item['album']?.toString(),
    artworkUrl:item['image']?.toString(),
    sourceId:'orchid-top-songs',sourceName:'All-Time Top Songs');
  Future<void> _play(int index) async{
    final tracks=songs.map(_track).toList();
    widget.player.setAddons(widget.addons);
    try{await widget.player.playTrack(tracks[index],fromQueue:tracks);}
    catch(e){debugPrint('[Orchid Top Songs] Playback failed: $e');}
  }
  @override Widget build(BuildContext context)=>ListView(
    padding:EdgeInsets.fromLTRB(24,
      24 + MediaQuery.paddingOf(context).top, 24,
      24 + OrchidStyle.iosDockClearance(context)),children: [
      const OrchidHero(eyebrow:'Made for You',title:'All-Time Top Songs',
        description:'The songs you keep coming back to.',icon:LucideIcons.trophy),
      const SizedBox(height:20),
      if(loading)const Center(child:Text('Loading…'))
      else if(error!=null)...[
        Text(error!).muted(),OrchidAdaptiveControls.button(onPressed:_load,child:const Text('Retry')),
      ]else if(songs.isEmpty)
        const Text('Your favorites will appear after you listen to music in Orchid.').muted()
      else...[
        OrchidAdaptiveControls.button(prominent: true, onPressed:()=>_play(0),child:const Text('Play your top songs')),
        const SizedBox(height:16),
        for(var i=0;i<songs.length;i++)
          Padding(
            padding:const EdgeInsets.only(bottom:8),
            child:GestureDetector(
              onTap:()=>_play(i),
              child:OrchidGlassPanel(
                radius:13,
                child:Padding(
                  padding:const EdgeInsets.all(12),
                  child:Row(children:[
              SizedBox(width:35,child:Text('${i+1}').semiBold()),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text((songs[i]['title']??'').toString(),
                  maxLines:1,overflow:TextOverflow.ellipsis).semiBold(),
                Text((songs[i]['artist']??'').toString(),
                  maxLines:1,overflow:TextOverflow.ellipsis).small().muted(),
              ])),
              Text('${songs[i]['plays']} plays').small().muted(),
              const SizedBox(width:8),const Icon(LucideIcons.play,size:16),
                  ]),
                ),
              ),
            ),
          ),
      ],
    ]);
}
