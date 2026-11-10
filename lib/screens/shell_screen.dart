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
import 'replay_screen.dart';
import 'radio_screen.dart';
import 'ai_dj_screen.dart';
import 'all_time_top_songs_screen.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/desktop_sidebar.dart';
import '../widgets/orchid_style.dart';
import '../widgets/content_drawer.dart';
import 'orchid_home_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'discover_screen.dart';
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
 void _openProfile()=>_openSettings();

 void _openFeatureSheet(String title, Widget child) {
  Navigator.of(context).push(ShadcnPageRoute<void>(
   builder:(_) => Scaffold(
    child:SafeArea(child:Column(children:[
     Padding(
      padding:const EdgeInsets.fromLTRB(18,12,18,8),
      child:Row(children:[
       IconButton.ghost(
        onPressed:()=>Navigator.of(context).pop(),
        icon:const Icon(LucideIcons.arrowLeft)),
       const SizedBox(width:10),
       Expanded(child:Text(title).large().semiBold()),
      ]),
     ),
     Expanded(child:child),
    ])),
   ),
  ));
 }

 void _openSettings()=>_selectTab(9);

 Widget _glassDockAction(IconData icon,int index,int page) {
  return liquid.LiquidGlass(
   shape:const liquid.LiquidGlassShape.circle(),
   style:liquid.LiquidGlassStyle.regular,
   fallback:liquid.LiquidGlassFallback.frosted,
   fallbackBlurSigma:20,
   brightness:liquid.LiquidGlassBrightness.dark,
   tintColor:const Color(0xFF7954AB),
   tintOpacity:0.24,
   opacity:0.88,
   rimColor:const Color(0x00000000),
   rimWidth:0,
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

 IconData _pageIcon(int page) => switch(page) {
  1 => LucideIcons.search,
  2 => LucideIcons.library,
  3 => LucideIcons.compass,
  4 => LucideIcons.listMusic,
  5 => LucideIcons.audioLines,
  6 => LucideIcons.radio,
  7 => LucideIcons.bot,
  8 => LucideIcons.trophy,
  9 => LucideIcons.settings,
  _ => LucideIcons.house,
 };

 Widget _iosFloatingDock(int page) {
  final bottom=MediaQuery.paddingOf(context).bottom;
  return Positioned(
   left:12,right:12,bottom:bottom+4,
   child:ListenableBuilder(
    listenable:_player,
    builder:(context,_) {
     final hasTrack=_player.current!=null;
     final collapsed=hasTrack && _iosDockCollapsed;
     final dockIndex=switch(page) { 3=>1, 2=>2, 1=>3, _=>0 };
     return AnimatedSize(
      duration:const Duration(milliseconds:320),
      curve:Curves.easeInOutCubic,
      alignment:Alignment.bottomCenter,
      child:AnimatedSwitcher(
       duration:const Duration(milliseconds:260),
       switchInCurve:Curves.easeOutCubic,
       switchOutCurve:Curves.easeInCubic,
       transitionBuilder:(child,animation)=>FadeTransition(
        opacity:animation,
        child:SlideTransition(
         position:Tween<Offset>(
          begin:const Offset(0,.14),end:Offset.zero).animate(animation),
         child:child,
        ),
       ),
       child:collapsed
        ? Row(key:const ValueKey('compact-dock'),children:[
          _glassDockAction(_pageIcon(page),page,page),
          const SizedBox(width:8),
          Expanded(child:IOSMiniPlayer(
           player:_player,library:_library,compact:true)),
          const SizedBox(width:8),
          _glassDockAction(LucideIcons.search,1,page),
         ])
        : Column(
         key:const ValueKey('expanded-dock'),
         mainAxisSize:MainAxisSize.min,
         children:[
          if(hasTrack)...[
           Padding(
            padding:const EdgeInsets.symmetric(horizontal:4),
            child:IOSMiniPlayer(player:_player,library:_library),
           ),
           const SizedBox(height:6),
          ],
          liquid.LiquidGlassNavigationBar(
           settings:const liquid.LiquidGlassSettings(
            brightness:liquid.LiquidGlassBrightness.dark,
            tintColor:Color(0xFF7954AB),
            tintOpacity:0.24,
            opacity:0.88,
            fallback:liquid.LiquidGlassFallback.frosted,
            fallbackBlurSigma:20,
           ),
           currentIndex:dockIndex,
           onTap:(index)=>_selectTab([0,3,2,1][index]),
           onReselect:(index)=>_selectTab([0,3,2,1][index]),
           activeColor:const Color(0xFFF8E4FF),
           inactiveColor:const Color(0xFFCEBEDA),
           items:const [
            liquid.LiquidGlassNavItem(
             icon:Icon(LucideIcons.house),label:'Home'),
            liquid.LiquidGlassNavItem(
             icon:Icon(LucideIcons.compass),label:'Discover'),
            liquid.LiquidGlassNavItem(
             icon:Icon(LucideIcons.library),label:'Library'),
            liquid.LiquidGlassNavItem(
             icon:Icon(LucideIcons.search),label:'Search'),
           ],
          ),
         ],
        ),
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
         MouseRegion(
          cursor:SystemMouseCursors.click,
          child:GestureDetector(
           behavior:HitTestBehavior.opaque,
           onTap:_openSettings,
           child:ClipOval(child:SizedBox(width:36,height:36,
            child:_account.avatarUrl==null
             ? const ColoredBox(
                color:Color(0xFF473259),
                child:Icon(LucideIcons.user,color:OrchidStyle.lilac,size:20))
             : Image.network(_account.avatarUrl!,fit:BoxFit.cover,
               errorBuilder:(_,__,___)=>const Icon(
                LucideIcons.user,color:OrchidStyle.lilac,size:20)),
           )),
          ),
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
      index:page.clamp(0,9),
      children:[
     OrchidHomeScreen(
      header:desktop ? _desktopGreeting() : _topBar(context),
      player:_player,addonService:_addonService,addons:_addons,account:_account,
      openExplore:()=>_selectTab(1),
      openProfile:_openProfile,
      openLibrary:()=>_selectTab(2),
      openAiDj:()=>_selectTab(7),
      openRadio:()=>_selectTab(6),
      openTopSongs:()=>_selectTab(8),
      openReplay:()=>_selectTab(5),
      // Mix cards remain playable, but their old detail page is gone.
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
     if(_initializedTabs.contains(3)) DiscoverScreen(
       header:desktop ? const SizedBox.shrink() : _topBar(context),
       account:_account,player:_player,addonService:_addonService,
       addons:_addons,library:_library,
     ) else const SizedBox.shrink(),
     if(_initializedTabs.contains(4)) LibraryScreen(
       header:desktop ? const SizedBox.shrink() : _topBar(context),
       library:_library,account:_account,player:_player,
       addonService:_addonService,addons:_addons,
       openExplore:()=>_selectTab(3),
       playlistsOnly:true,
     ) else const SizedBox.shrink(),
     if(_initializedTabs.contains(5))
      ReplayScreen(account:_account)
     else const SizedBox.shrink(),
     if(_initializedTabs.contains(6))
      RadioScreen(account:_account,player:_player,addons:_addons)
     else const SizedBox.shrink(),
     if(_initializedTabs.contains(7))
      AiDjScreen(account:_account)
     else const SizedBox.shrink(),
     if(_initializedTabs.contains(8))
      AllTimeTopSongsScreen(account:_account,player:_player,addons:_addons)
     else const SizedBox.shrink(),
     if(_initializedTabs.contains(9))
      SettingsScreen(
       account:_account,addonService:_addonService,addons:_addons,
       onAddonsChanged:(list) {
        if(!mounted)return;
        setState(()=>_addons=list);
        _player.setAddons(list);
       },
      )
     else const SizedBox.shrink(),

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
          // Keep the scrollable content behind the floating player so
          // Liquid Glass can sample actual artwork and rows, not empty space.
          Positioned.fill(
            left:leftContent,
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
            onDiscover:()=>_selectTab(3),
            onPlaylists:()=>_selectTab(4),
            onLibrary:()=>_selectTab(2),
            onReplay:()=>_selectTab(5),
            onRadio:()=>_openFeatureSheet('Radio',
              RadioScreen(account:_account,player:_player,addons:_addons)),
            onAiDj:()=>_selectTab(7),
            onSettings:_openSettings,
            onProfile:_openProfile,
          ),
          ),
          Positioned(
            left:leftContent+12,right:gutter,bottom:gutter,
            child:ClipRRect(
              borderRadius:BorderRadius.circular(17),
              child:DesktopPlayerBar(player:_player,library:_library,addons:_addons),
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
