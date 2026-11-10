import 'dart:async';
import 'package:liquid_design/liquid_design.dart' as liquid;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
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
import '../widgets/desktop_sidebar.dart';
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
 String? _addonsUser;
 late final PlayerService _player;
 StreamSubscription<Duration>? _positionSubscription;
 Key? selected=const ValueKey(0);
 final Set<int> _initializedTabs={0};
 bool _iosDockCollapsed=false;
 double _verticalScrollAccum=0;
 bool _onContentScroll(ScrollNotification notification) {
  if (notification.metrics.axis != Axis.vertical ||
      notification is! ScrollUpdateNotification) return false;
  final delta=notification.scrollDelta ?? 0;
  if (notification.metrics.pixels < 80) {
   _verticalScrollAccum=0;
   if (_iosDockCollapsed) setState(() => _iosDockCollapsed=false);
   return false;
  }
  if (delta.abs()<1) return false;
  _verticalScrollAccum=(_verticalScrollAccum+delta).clamp(-120.0,120.0);
  if (!_iosDockCollapsed && _verticalScrollAccum>36) {
   _verticalScrollAccum=0;
   setState(() => _iosDockCollapsed=true);
  } else if (_iosDockCollapsed && _verticalScrollAccum < -28) {
   _verticalScrollAccum=0;
   setState(() => _iosDockCollapsed=false);
  }
  return false;
 }
 void _selectTab(int index) {
  setState(() {
   selected=ValueKey(index);
   _initializedTabs.add(index);
   _iosDockCollapsed=false;
   _verticalScrollAccum=0;
  });
 }
 List<InstalledAddon> _addons=[];
 int _trackGeneration=0;
 bool _scrobbled=false;
 int _startedAt=0;
 int _maxPositionSeconds=0;
 @override void initState(){
  super.initState();
  _library.configure(_account);
  _addonService.configure(_account);
  _player=PlayerService(addonService:_addonService);
  _player.addListener(_trackChanged);
  _positionSubscription=_player.player.positionStream.listen(_positionChanged);
  LyricsAppearance.instance.load();
  _account.addListener(_accountChanged);
  _account.restore();
 }
 Future<void> _loadAddons() async{
  final requestedUser=_addonsUser;
  if(requestedUser==null)return;
  try{
   final list=await _addonService.load();
   if(!mounted || !_account.signedIn || requestedUser!=_addonsUser)return;
   setState(()=>_addons=list);_player.setAddons(list);
  }catch(e){debugPrint('Error loading addons: $e');}
 }
 void _accountChanged(){
  final user=_account.signedIn ? (_account.email ?? _account.username) : null;
  if(user!=_libraryUser){
   _libraryUser=user;
   _library.setAccount(user);
  }
  if(user!=_addonsUser){
   _addonsUser=user;
   _addonService.reset();
   _addons=[];
   _player.setAddons([]);
   if(user!=null)_loadAddons();
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
 Widget _glassDockAction(IconData icon,int index,int page) {
  return liquid.LiquidGlass(
   shape:const liquid.LiquidGlassShape.circle(),
   style:liquid.LiquidGlassStyle.regular,
   fallback:liquid.LiquidGlassFallback.frosted,
   child:GestureDetector(
    onTap:()=>_selectTab(index),
    behavior:HitTestBehavior.opaque,
    child:SizedBox(
     width:58,height:58,
     child:Icon(icon,size:24,
      color:page==index?OrchidStyle.pink:const Color(0xFFF8F6FC)),
    ),
   ),
  );
 }

 Widget _iosFloatingDock(int page) {
  final bottom=MediaQuery.paddingOf(context).bottom;
  return Positioned(
   left:12,right:12,bottom:bottom+8,
   child:ListenableBuilder(
    listenable:_player,
    builder:(context,_) {
     final hasTrack=_player.current!=null;
     final collapsed=hasTrack && _iosDockCollapsed;
     return AnimatedSize(
      duration:const Duration(milliseconds:240),
      curve:Curves.easeOutCubic,
      alignment:Alignment.bottomCenter,
      child:collapsed
       ? Row(children:[
          _glassDockAction(LucideIcons.house,0,page),
          const SizedBox(width:8),
          Expanded(child:IOSMiniPlayer(player:_player,library:_library,compact:true)),
          const SizedBox(width:8),
          _glassDockAction(LucideIcons.search,1,page),
         ])
       : Column(
          mainAxisSize:MainAxisSize.min,
          children:[
           if(hasTrack)...[
            Padding(
             padding:const EdgeInsets.symmetric(horizontal:4),
             child:IOSMiniPlayer(player:_player,library:_library),
            ),
            const SizedBox(height:8),
           ],
           liquid.LiquidGlassNavigationBar(
            currentIndex:page.clamp(0,2),
            onTap:_selectTab,
            onReselect:_selectTab,
            activeColor:const Color(0xFFF8E4FF),
            inactiveColor:const Color(0xFFCEBEDA),
            items:const [
             liquid.LiquidGlassNavItem(
              icon:Icon(LucideIcons.house),
              label:'Home',
             ),
             liquid.LiquidGlassNavItem(
              icon:Icon(LucideIcons.compass),
              label:'Explore',
             ),
             liquid.LiquidGlassNavItem(
              icon:Icon(LucideIcons.library),
              label:'Library',
             ),
            ],
           ),
          ],
         ),
     );
    },
   ),
  );
 }
 Widget _topBar(BuildContext context) {
  return ColoredBox(
        color:OrchidStyle.ink,
        child:SafeArea(
         bottom:false,
         child:Padding(
          padding:EdgeInsets.fromLTRB(OrchidStyle.compact(context,20),OrchidStyle.compact(context,12),OrchidStyle.compact(context,20),OrchidStyle.compact(context,6)),
          child:Row(children:[
         Icon(LucideIcons.music2, size:OrchidStyle.compact(context,20), color:OrchidStyle.violet),
         SizedBox(width:OrchidStyle.compact(context,9)),
         const Text('Orchid').large().semiBold(),
         const Spacer(),
         ProfileMenu(
          account:_account,
          onProfile:_openProfile,
          onSettings:_openSettings,
         ),
          ]),
         ),
        ),
       );
 }
 Widget _desktopGreeting() {
  final now=DateTime.now().hour;
  final greeting=now<12?'Good morning':now<17?'Good afternoon':'Good evening';
  return Padding(
   padding:const EdgeInsets.only(bottom:22),
   child:Column(
    crossAxisAlignment:CrossAxisAlignment.start,
    children:[
     Text(greeting,style:const TextStyle(
      color:Color(0xFF9D90AF),fontSize:12)),
     const SizedBox(height:5),
     Text(_account.username ?? 'Your music',
      style:const TextStyle(fontSize:27,fontWeight:FontWeight.w700,
       color:Color(0xFFF7EDFF))),
    ],
   ),
  );
 }
 NavigationItem _button(String title,IconData icon,int index)=>NavigationItem(
  key:ValueKey(index),style:const ButtonStyle.muted(density:ButtonDensity.icon),
  selectedStyle:const ButtonStyle.fixed(density:ButtonDensity.icon),
  label:Text(title),child:Icon(icon));
 @override Widget build(BuildContext context){
  if(_account.loading){
   return const SafeArea(child:Scaffold(child:Center(child:Text('Checking your Petal session…'))));
  }
  if(!_account.signedIn){
   if(_account.hasStoredSession){
    return SafeArea(child:Scaffold(
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
    ));
   }
   return SafeArea(child:Scaffold(child:ProfileScreen(account:_account)));
  }
  final page=(selected as ValueKey<int>?)?.value??0;
  final desktop=(kIsWeb || (defaultTargetPlatform!=TargetPlatform.iOS
    && defaultTargetPlatform!=TargetPlatform.android))
    && MediaQuery.sizeOf(context).width>=850;
  final browsing=NotificationListener<ScrollNotification>(
    onNotification:_onContentScroll,
    child:IndexedStack(
      index:page.clamp(0,2),
      children:[
     OrchidHomeScreen(
      header:desktop ? _desktopGreeting() : _topBar(context),
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
      SearchScreen(header:desktop ? const SizedBox.shrink() : _topBar(context),addonService:_addonService,player:_player,addons:_addons,library:_library,account:_account)
     else const SizedBox.shrink(),
     if(_initializedTabs.contains(2)) LibraryScreen(
      header:desktop ? const SizedBox.shrink() : _topBar(context),
      library:_library,
      account:_account,
      player:_player,
      addonService:_addonService,
      addons:_addons,
      openExplore:()=>_selectTab(1),
     ) else const SizedBox.shrink(),

      ],
    ),
  );

  if(desktop){
    const sidebarWidth=236.0;
    const gutter=16.0;
    const leftContent=sidebarWidth+gutter*2;
    return Scaffold(
      child:Container(
        decoration:const BoxDecoration(
          gradient:LinearGradient(
            begin:Alignment.topLeft,
            end:Alignment.bottomRight,
            colors:[
              Color(0xFF2D1B36),
              Color(0xFF24152D),
              Color(0xFF130F1A),
              Color(0xFF0D0D15),
            ],
            stops:[0,0.32,0.72,1],
          ),
        ),
        child:Stack(children:[
          Positioned.fill(
            left:leftContent,
            bottom:100,
            child:browsing,
          ),
          Positioned(
            left:gutter,top:gutter,bottom:gutter,
            child:DesktopSidebar(
            selectedTab:page,
            library:_library,
            accountName:_account.username ?? _account.email ?? 'Account',
            onHome:()=>_selectTab(0),
            onSearch:()=>_selectTab(1),
            onLibrary:()=>_selectTab(2),
            onReplay:()=>_openFeatureSheet('Replay',ReplayScreen(account:_account)),
            onRadio:()=>_openFeatureSheet('Radio',
              RadioScreen(account:_account,player:_player,addons:_addons)),
            onAiDj:()=>_openFeatureSheet('AI DJ',AiDjScreen(account:_account)),
            onSettings:_openSettings,
            onProfile:_openProfile,
          ),
          ),
          Positioned(
            left:leftContent+12,right:gutter,bottom:gutter,
            child:ClipRRect(
              borderRadius:BorderRadius.circular(17),
              child:DesktopPlayerBar(player:_player,library:_library),
            ),
          ),
        ]),
      ),
    );
  }

  return Scaffold(
   footers:[
    if(kIsWeb || defaultTargetPlatform!=TargetPlatform.iOS) ...[
     MiniPlayerBar(player:_player,library:_library),
     const Divider(),
     SafeArea(
      top:false,
      child:NavigationBar(
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
     ),
    ],
   ],
   child:Stack(children:[
    browsing,
    if(!kIsWeb && defaultTargetPlatform==TargetPlatform.iOS)
      _iosFloatingDock(page),
   ]),
  );
 }
}
