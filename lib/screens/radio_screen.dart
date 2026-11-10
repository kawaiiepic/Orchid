import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../widgets/orchid_adaptive_controls.dart';
import '../models/addon.dart';
import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../widgets/orchid_style.dart';

class RadioScreen extends StatefulWidget {
  final OrchidAccount account;
  final PlayerService player;
  final List<InstalledAddon> addons;
  const RadioScreen({super.key,required this.account,required this.player,required this.addons});
  @override State<RadioScreen> createState()=>_RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen>{
  static const choices=<String,List<String>>{
    'Genre':['Pop','Rock','Hip-Hop','R&B','Electronic','Jazz','Classical','Metal','Country','Latin'],
    'Mood':['Happy','Chill','Focus','Melancholy','Energetic','Romantic','Dreamy'],
    'Era':['1960s','1970s','1980s','1990s','2000s','2010s','2020s'],
    'Activity':['Workout','Study','Driving','Sleeping','Gaming','Party','Relaxing'],
  };
  String type='Genre';
  String? choice;
  bool loading=false;
  String? error;
  int generation=0;

  @override void dispose(){generation++;super.dispose();}

  TrackResult _track(Map item)=>TrackResult(
    id:(item['id']??'${item['artist']}|${item['title']}').toString(),
    title:(item['title']??'').toString(),
    artist:(item['artist']??'').toString(),
    album:item['album']?.toString(),
    artworkUrl:item['image']?.toString(),
    duration:item['duration'] is num?(item['duration'] as num).toInt():null,
    genres:item['genres'] is List?(item['genres'] as List).whereType<String>().toList():const [],
    sourceId:'orchid-radio',sourceName:'Radio',
  );

  Future<void> _start(String selected) async{
    final requestedType=type;
    final id=++generation;
    setState(() {choice=selected;loading=true;error=null;});
    int offset=0;
    final seen=<String>{};
    Future<List<TrackResult>> fetchBatch() async{
      // Search additional catalog seeds when songs have already been heard.
      for(var attempt=0;attempt<4;attempt++){
        final result=await widget.account.radioSongs(
          type:requestedType,choice:selected,offset:offset);
        offset=(result['nextOffset'] as num?)?.toInt()??offset+20;
        final raw=result['songs'];
        if(raw is! List)continue;
        final tracks=<TrackResult>[];
        for(final item in raw.whereType<Map>()){
          final track=_track(item);
          final key='${track.artist.toLowerCase()}|${track.title.toLowerCase()}';
          if(track.title.isNotEmpty&&track.artist.isNotEmpty&&seen.add(key))tracks.add(track);
        }
        if(tracks.isNotEmpty)return tracks;
      }
      return [];
    }
    try{
      final songs=await fetchBatch();
      if(!mounted||id!=generation)return;
      if(songs.isEmpty)throw StateError('No songs found for this station. Try another.');
      widget.player.setAddons(widget.addons);
      await widget.player.startRadio(songs,fetchBatch);
      if(!mounted||id!=generation)return;
      setState(()=>loading=false);
    }catch(e){
      if(mounted&&id==generation)setState(() {loading=false;error=e.toString();});
    }
  }

  @override Widget build(BuildContext context)=>ListView(
    padding:EdgeInsets.fromLTRB(24,
      24 + MediaQuery.paddingOf(context).top, 24,
      24 + OrchidStyle.iosDockClearance(context)),children:
      const OrchidHero(eyebrow:'Made for You',title:'Radio',
        description:'Choose a vibe. Orchid keeps the music flowing.',
        icon:LucideIcons.radio),
      const SizedBox(height:20),
      const Text('Choose your station').large().semiBold(),
      const SizedBox(height:12),
      Wrap(spacing:8,runSpacing:8,children:[
        for(final label in choices.keys)
          if(type==label)OrchidAdaptiveControls.button(prominent: true, 
            onPressed:()=>setState(() {type=label;choice=null;error=null;}),
            child:Text(label))
          else OrchidAdaptiveControls.button(
            onPressed:()=>setState(() {type=label;choice=null;error=null;}),
            child:Text(label)),
      ]),
      const SizedBox(height:20),
      Text('Pick a $type').small().muted(),
      const SizedBox(height:10),
      Wrap(spacing:10,runSpacing:10,children:[
        for(final label in choices[type]!)
          GestureDetector(
            onTap:loading?null:()=>_start(label),
            child:OrchidGlassPanel(
              radius:16,
              child:SizedBox(
                width:148,height:108,
                child:Padding(
                  padding:const EdgeInsets.all(14),
                  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Icon(type=='Genre'?LucideIcons.music2:
                  type=='Mood'?LucideIcons.heart:
                  type=='Era'?LucideIcons.clock:LucideIcons.activity,
                  color:OrchidStyle.lilac,size:23),
                const Spacer(),
                Text(label).semiBold(),
                  ]),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height:20),
      if(loading)const Center(child:Text('Loading…')),
      if(error!=null)...[
        Text(error!).small(),
        const SizedBox(height:12),
        OrchidAdaptiveControls.button(onPressed:()=>choice==null?null:_start(choice!),
          child:const Text('Try again')),
      ],
      if(widget.player.radioNextBatch!=null)...[
        const SizedBox(height:12),
        Text('Radio is playing${choice==null?'':': $choice'}').semiBold(),
        const SizedBox(height:8),
        OrchidAdaptiveControls.button(onPressed:(){widget.player.stopRadio();setState((){});},
          child:const Text('Stop Radio')),
        const SizedBox(height:6),
        const Text('Station recommendations require the Apple Music catalog and a working playback addon. Tracks are generated in batches as the queue runs low.').small().muted(),
      ],
    ]);
}
