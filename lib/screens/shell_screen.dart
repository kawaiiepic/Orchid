import 'dart:async';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/lyrics_appearance.dart';
import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../widgets/mini_player_bar.dart';
import 'orchid_home_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class ShellScreen extends StatefulWidget {
 const ShellScreen({super.key});
 @override State<ShellScreen> createState()=>_ShellScreenState();
}
class _ShellScreenState extends State<ShellScreen>{
 final _addonService=AddonService();
 final _account=OrchidAccount();
 late final PlayerService _player;
 StreamSubscription<Duration>? _positionSubscription;
 Key? selected=const ValueKey(0);
 List<InstalledAddon> _addons=[];
 int _trackGeneration=0;
 bool _scrobbled=false;
 int _startedAt=0;
 int _maxPositionSeconds=0;
 @override void initState(){
  super.initState();
  _player=PlayerService(addonService:_addonService);
  _player.addListener(_trackChanged);
  _positionSubscription=_player.player.positionStream.listen(_positionChanged);
  LyricsAppearance.instance.load();
  _account.addListener(_accountChanged);
  _account.restore();
  _loadAddons();
 }
 Future<void> _loadAddons() async{
  try{
   final list=await _addonService.load();
   if(!mounted)return;
   setState(()=>_addons=list);_player.setAddons(list);
  }catch(e){debugPrint('Error loading addons: $e');}
 }
 void _accountChanged(){if(mounted)setState((){});}
 void _trackChanged(){
  if(_trackGeneration==_player.lyricsGeneration)return;
  _trackGeneration=_player.lyricsGeneration;
  _scrobbled=false;_maxPositionSeconds=0;
  _startedAt=DateTime.now().millisecondsSinceEpoch~/1000;
  final track=_player.current;
  if(track!=null){
   // Once playback starts, publish the currently playing track.
   void send() async{
    if(!_player.player.playing||!_account.lastfmConnected)return;
    await _account.nowPlaying(artist:track.artist,title:track.title,album:track.album,
      duration:_player.player.duration?.inSeconds??track.duration);
   }
   Future<void>.delayed(const Duration(seconds:2),(){
    if(mounted&&_player.current==track)send();
   });
  }
 }
 void _positionChanged(Duration position){
  final track=_player.current;
  if(track==null||_scrobbled||!_player.player.playing||!_account.lastfmConnected)return;
  final total=_player.player.duration?.inSeconds??track.duration;
  if(total==null||total<=30)return;
  // Position cannot go backwards on a seek; require reasonable elapsed listening
  // time as well as a playback threshold.
  final seconds=position.inSeconds;
  if(seconds>_maxPositionSeconds)_maxPositionSeconds=seconds;
  final threshold=(total/2).ceil().clamp(1,240);
  final elapsed=DateTime.now().millisecondsSinceEpoch~/1000-_startedAt;
  if(_maxPositionSeconds>=threshold&&elapsed>=threshold){
   _scrobbled=true;
   _account.scrobble(artist:track.artist,title:track.title,album:track.album,
    duration:total,timestamp:_startedAt);
  }
 }
 @override void dispose(){
  _positionSubscription?.cancel();_player.removeListener(_trackChanged);
  _player.dispose();_account.removeListener(_accountChanged);_account.dispose();super.dispose();
 }
 NavigationItem _button(String title,IconData icon,int index)=>NavigationItem(
  key:ValueKey(index),style:const ButtonStyle.muted(density:ButtonDensity.icon),
  selectedStyle:const ButtonStyle.fixed(density:ButtonDensity.icon),
  label:Text(title),child:Icon(icon));
 @override Widget build(BuildContext context){
  if(_account.loading){
   return const Scaffold(child:Center(child:Text('Checking your Petal session…')));
  }
  if(!_account.signedIn){
   return Scaffold(child:ProfileScreen(account:_account));
  }
  final page=(selected as ValueKey<int>?)?.value??0;
  final explore=SearchScreen(addonService:_addonService,player:_player,addons:_addons);
  final pages=<Widget>[
   OrchidHomeScreen(player:_player,account:_account,
    openExplore:()=>setState(()=>selected=const ValueKey(1)),
    openProfile:()=>setState(()=>selected=const ValueKey(3))),
   explore,
   OrchidHomeScreen(player:_player,account:_account,
    openExplore:()=>setState(()=>selected=const ValueKey(1)),
    openProfile:()=>setState(()=>selected=const ValueKey(3))),
   ProfileScreen(account:_account),
   SettingsScreen(addonService:_addonService,addons:_addons,onAddonsChanged:(list){
    setState(()=>_addons=list);_player.setAddons(list);
   }),
  ];
  return Scaffold(
   footers:[MiniPlayerBar(player:_player),const Divider(),
    NavigationBar(alignment:NavigationBarAlignment.spaceAround,
     labelType:NavigationLabelType.none,expanded:true,
     onSelected:(key)=>setState(()=>selected=key),selectedKey:selected,
     children:[
      _button('Home',BootstrapIcons.house,0),
      _button('Explore',BootstrapIcons.compass,1),
      _button('Library',BootstrapIcons.musicNoteList,2),
      _button('Profile',BootstrapIcons.person,3),
      _button('App',BootstrapIcons.gear,4),
     ])],
   child:pages[page.clamp(0,pages.length-1)],
  );
 }
}
