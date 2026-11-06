import 'dart:async';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/lyrics_appearance.dart';
import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../services/music_library.dart';
import 'library_screen.dart';
import 'daily_mixes_screen.dart';
import 'replay_screen.dart';
import 'radio_screen.dart';
import 'ai_dj_screen.dart';
import 'all_time_top_songs_screen.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/profile_menu.dart';
import '../widgets/orchid_style.dart';
import '../widgets/content_drawer.dart';
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
 final _library=MusicLibrary();
 String? _libraryUser;
 late final PlayerService _player;
 StreamSubscription<Duration>? _positionSubscription;
 Key? selected=const ValueKey(0);
 final Set<int> _initializedTabs={0};
 void _selectTab(int index) {
  setState(() {
   selected=ValueKey(index);
   _initializedTabs.add(index);
  });
 }
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
 void _accountChanged(){
  final user=_account.signedIn ? (_account.email ?? _account.username) : null;
  if(user!=_libraryUser){
   _libraryUser=user;
   _library.setAccount(user);
  }
  if(mounted)setState((){});
 }
 void _trackChanged(){
  if(_trackGeneration==_player.lyricsGeneration)return;
  _trackGeneration=_player.lyricsGeneration;
  _scrobbled=false;_maxPositionSeconds=0;
  _startedAt=DateTime.now().millisecondsSinceEpoch~/1000;
  final track=_player.current;
  if(track!=null){
   _library.recordPlay(SavedSong(track.title,track.artist,
    album:track.album,artwork:track.artworkUrl));
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
  if(track==null||_scrobbled||!_player.player.playing)return;
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
   // Record Orchid listening independently of Last.fm. The event ID is
   // stable across retries, so the backend cannot double-count a listen.
   final eventId='${_startedAt}_${_trackGeneration}_${track.id.hashCode.abs()}';
   _account.recordListen(
    eventId:eventId,title:track.title,artist:track.artist,
    album:track.album,artwork:track.artworkUrl,songId:track.id,
    startedAt:_startedAt,duration:total,genres:track.genres,
   ).catchError((Object error) {
    debugPrint('[Orchid History] Could not save listen: $error');
   });
   if(_account.lastfmConnected) {
    _account.scrobble(artist:track.artist,title:track.title,album:track.album,
     duration:total,timestamp:_startedAt);
   }
  }
 }
 @override void dispose(){
  _positionSubscription?.cancel();_player.removeListener(_trackChanged);
  _player.dispose();_library.dispose();_account.removeListener(_accountChanged);_account.dispose();super.dispose();
 }
 void _openProfile() {
  showContentDrawer(
   context,
   builder: (sheetContext) => Scaffold(
    child: Column(children:[
     Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child:Row(children:[
       const Text('Your Profile').large().semiBold(),
       const Spacer(),
       IconButton.ghost(
        onPressed:()=>dismissContentDrawer(sheetContext),
        icon:const Icon(LucideIcons.x),
       ),
      ]),
     ),
     Expanded(child:ProfileScreen(account:_account)),
    ]),
   ),
  );
 }
 void _openFeatureSheet(String title, Widget child) {
  showContentDrawer(
   context,
   builder:(sheetContext)=>Scaffold(
    child:Column(children:[
     Padding(
      padding:const EdgeInsets.fromLTRB(16,12,16,2),
      child:Row(children:[
       const Icon(LucideIcons.music2,color:OrchidStyle.lilac),
       const SizedBox(width:10),
       Expanded(child:Text(title).large().semiBold()),
       IconButton.ghost(
        onPressed:()=>dismissContentDrawer(sheetContext),
        icon:const Icon(LucideIcons.x),
       ),
      ]),
     ),
     Expanded(child:child),
    ]),
   ),
  );
 }
 void _openSettings() {
  showContentDrawer(context, preferredWidth:700,
    builder:(_) => Scaffold(
      child:Column(children:[
        Padding(
          padding:const EdgeInsets.fromLTRB(12,8,12,0),
          child:Row(children:[
            IconButton.ghost(
              onPressed:()=>dismissContentDrawer(context),
              icon:const Icon(LucideIcons.x),
            ),
            const SizedBox(width:10),
            const Text('Settings').large().semiBold(),
          ]),
        ),
        Expanded(child:SettingsScreen(
          account:_account,
          addonService:_addonService,
          addons:_addons,
          onAddonsChanged:(list) {
            if(!mounted)return;
            setState(()=>_addons=list);
            _player.setAddons(list);
          },
        )),
      ]),
    ),
  );
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
   if(_account.hasStoredSession){
    return Scaffold(
     child:Center(
      child:ConstrainedBox(
       constraints:const BoxConstraints(maxWidth:420),
       child:Padding(
        padding:const EdgeInsets.all(24),
        child:Column(
         mainAxisSize:MainAxisSize.min,
         crossAxisAlignment:CrossAxisAlignment.stretch,
         children:[
          const Text('Session temporarily unavailable').large().semiBold(),
          const SizedBox(height:10),
          Text(_account.restoreError??'We could not verify your saved Petal login. Your session is still saved.').muted(),
          const SizedBox(height:16),
          PrimaryButton(onPressed:_account.retryRestore,child:const Text('Retry connection')),
          const SizedBox(height:8),
          OutlineButton(onPressed:_account.clearSavedSession,child:const Text('Sign in with another account')),
         ],
        ),
       ),
      ),
     ),
    );
   }
   return Scaffold(child:ProfileScreen(account:_account));
  }
  final page=(selected as ValueKey<int>?)?.value??0;
  return Scaffold(
   footers:[
    MiniPlayerBar(player:_player,library:_library),
    const Divider(),
NavigationBar(
     alignment:NavigationBarAlignment.spaceAround,
     labelType:NavigationLabelType.none,
     expanded:true,
     onSelected:(key)=>_selectTab((key as ValueKey<int>).value),
     selectedKey:selected,
     children:[
      _button('Home',BootstrapIcons.house,0),
      _button('Explore',BootstrapIcons.compass,1),
      _button('Library',BootstrapIcons.musicNoteList,2),
     ],
    ),
   ],
   // Keep all three browsing tabs alive while showing a global profile button.
   child:Column(
    children:[
     Padding(
      padding:const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child:Row(children:[
       const Icon(LucideIcons.music2, size:20, color:OrchidStyle.violet),
       const SizedBox(width:9),
       const Text('Orchid').large().semiBold(),
       const Spacer(),
       ProfileMenu(
        account:_account,
        onProfile:_openProfile,
        onSettings:_openSettings,
       ),
      ]),
     ),
     Expanded(child:IndexedStack(
    index:page.clamp(0,2),
    children:[
     OrchidHomeScreen(
      player:_player,addonService:_addonService,addons:_addons,account:_account,
      openExplore:()=>_selectTab(1),
      openProfile:_openProfile,
      openLibrary:()=>_selectTab(2),
      openAiDj:()=>showContentDrawer(
       context,
       builder:(sheetContext)=>Scaffold(
        child:Column(children:[
         Padding(
          padding:const EdgeInsets.fromLTRB(16,12,16,2),
          child:Row(children:[
           const Icon(LucideIcons.bot,color:OrchidStyle.lilac),
           const SizedBox(width:10),
           const Text('AI DJ').large().semiBold(),
           const Spacer(),
           IconButton.ghost(
            onPressed:()=>dismissContentDrawer(sheetContext),
            icon:const Icon(LucideIcons.x),
           ),
          ]),
         ),
         Expanded(child:AiDjScreen(account:_account)),
        ]),
       ),
      ),
      openRadio:()=>_openFeatureSheet(
       'Radio',
       RadioScreen(account:_account,player:_player,addons:_addons),
      ),
      openTopSongs:()=>_openFeatureSheet(
       'All-Time Top Songs',
       AllTimeTopSongsScreen(account:_account,player:_player,addons:_addons),
      ),
      openReplay:()=>_openFeatureSheet(
       'Replay',
       ReplayScreen(account:_account),
      ),
      openDailyMixes:(index)=>_openFeatureSheet(
       'Daily Mixes',
       DailyMixesScreen(
        initialMixIndex:index,
        account:_account,library:_library,player:_player,
        addonService:_addonService,addons:_addons,
       ),
      ),
      library:_library,
     ),
     if(_initializedTabs.contains(1))
      SearchScreen(addonService:_addonService,player:_player,addons:_addons,library:_library,account:_account)
     else const SizedBox.shrink(),
     if(_initializedTabs.contains(2)) LibraryScreen(
      library:_library,
      account:_account,
      player:_player,
      addonService:_addonService,
      addons:_addons,
      openExplore:()=>_selectTab(1),
     ) else const SizedBox.shrink(),
    ],
     )),
    ],
   ),
  );
 }
}
