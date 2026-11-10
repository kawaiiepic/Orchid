import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/addon.dart';
import 'orchid_account.dart';
import 'player_service.dart';

/// Active Orchid sessions and shared listening. One instance per application
/// shell; only the backend returns remote devices, never fabricated entries.
class OrchidConnect extends ChangeNotifier {
 static OrchidConnect? active;
 OrchidConnect(this.account,this.player);
 final OrchidAccount account;
 final PlayerService player;
 String? deviceId;
 String get displayName {
  if(kIsWeb)return 'Web Player';
  return switch(defaultTargetPlatform){
   TargetPlatform.iOS=>'iPhone / iPad',
   TargetPlatform.android=>'Android',
   TargetPlatform.macOS=>'Mac',
   TargetPlatform.windows=>'Windows PC',
   TargetPlatform.linux=>'Linux Desktop',
   _=>'Orchid',
  };
 }
 String get platform => kIsWeb?'web':defaultTargetPlatform.name;
 List<Map<String,dynamic>> devices=[];
 String? error;
 String? jamId;
 String? jamName;
 bool jamHost=false;
 int jamListeners=0;
 bool working=false;
 Timer? _timer;
 bool _busy=false;
 bool _closed=false;
 int _lastGuestRevision=0;
 Future<void> start() async {
  final prefs=await SharedPreferences.getInstance();
  if(_closed)return;
  deviceId=prefs.getString('orchid_connect_device_id');
  if(deviceId==null){
   final rng=Random.secure();
   final bytes=List<int>.generate(20,(_)=>rng.nextInt(256));
   deviceId=bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
   await prefs.setString('orchid_connect_device_id',deviceId!);
  }
  _timer?.cancel();
  _timer=Timer.periodic(const Duration(seconds:5),(_)=>unawaited(refresh()));
  await refresh();
 }
 Map<String,dynamic> get playback {
  final t=player.current;
  return {
   'playing':player.player.playing,
   'position':player.player.position.inMilliseconds/1000,
   'shuffle':player.shuffleEnabled,
   'repeat':player.repeatMode.name,
   'track':t==null?null:{
    'id':t.id,'title':t.title,'artist':t.artist,
    'album':t.album,'duration':t.duration,'artworkUrl':t.artworkUrl,
    'sourceId':t.sourceId,'sourceName':t.sourceName,
    'previewUrl':t.previewUrl,'shareUrl':t.shareUrl,
    'spotifyTrackId':t.spotifyTrackId,'videoId':t.videoId,
    'fromStreamAddon':t.fromStreamAddon,'addonBaseUrl':t.addonBaseUrl,
   },
  };
 }
 TrackResult? _track(dynamic raw){
  if(raw is! Map)return null;
  final m=Map<String,dynamic>.from(raw);
  final id=m['id'],title=m['title'],artist=m['artist'],
   sourceId=m['sourceId'],sourceName=m['sourceName'];
  if(id is! String||title is! String||artist is! String||
     sourceId is! String||sourceName is! String)return null;
  return TrackResult(id:id,title:title,artist:artist,
   album:m['album'] as String?,duration:(m['duration'] as num?)?.toInt(),
   artworkUrl:m['artworkUrl'] as String?,previewUrl:m['previewUrl'] as String?,
   shareUrl:m['shareUrl'] as String?,spotifyTrackId:m['spotifyTrackId'] as String?,
   videoId:m['videoId'] as String?,sourceId:sourceId,sourceName:sourceName,
   fromStreamAddon:m['fromStreamAddon']==true,
   addonBaseUrl:m['addonBaseUrl'] as String?);
 }
 Future<void> _apply(dynamic data,{bool sync=false}) async{
  if(data is! Map)return;
  final state=Map<String,dynamic>.from(data);
  final target=_track(state['track']);
  if(target==null)return;
  if(player.current?.id!=target.id||player.current?.sourceId!=target.sourceId){
   await player.playTrack(target,fromQueue:[target]);
  }
  final position=(state['position'] as num?)?.toDouble()??0;
  if((player.player.position.inMilliseconds/1000-position).abs()>(sync?3:0.5)){
   await player.seek(Duration(milliseconds:(position*1000).round()));
  }
  final playing=state['playing']==true;
  if(playing!=player.player.playing)await player.togglePlayPause();
 }
 Future<void> refresh() async{
  if(_closed||_busy||deviceId==null)return;
  if(!account.signedIn){
   if(devices.isNotEmpty){devices=[];notifyListeners();}
   return;
  }
  _busy=true;
  try{
   await account.connectPost('/devices/heartbeat',{
    'id':deviceId!,'name':displayName,'platform':platform,'playback':playback,
   });
   final result=await account.connectGet('/devices');
   devices=[for(final item in (result['devices'] as List? ?? []))
    if(item is Map)Map<String,dynamic>.from(item)];
   final cmds=await account.connectGet('/devices/${Uri.encodeComponent(deviceId!)}/commands');
   for(final item in (cmds['commands'] as List? ?? [])){
    if(item is! Map)continue;
    if(item['type']=='transfer'){
     try{
      await _apply(item['playback']);
      await account.connectPost('/devices/${Uri.encodeComponent(deviceId!)}/transfer-complete',{
       'sourceId':item['sourceId'],
      });
     }catch(e){error='Playback transfer failed: $e';}
    }else if(item['type']=='pause'){
     if(player.player.playing)await player.togglePlayPause();
    }
   }
   if(jamId!=null)await _refreshJam();
   error=null;
  }catch(e){
   error='Connect unavailable: $e';
  }finally{
   _busy=false;
   if(!_closed)notifyListeners();
  }
 }
 Future<void> transferTo(String id) async {
  if(deviceId==null||id==deviceId)return;
  working=true;notifyListeners();
  try{
   await account.connectPost('/devices/${Uri.encodeComponent(id)}/transfer',{
    'sourceId':deviceId!,'playback':playback,
   });
   error=null;
  }catch(e){error='Unable to transfer: $e';rethrow;}
  finally{working=false;notifyListeners();}
 }
 Future<void> createJam() async {
  if(deviceId==null||!account.signedIn)throw StateError('Sign in to start a Jam');
  working=true;notifyListeners();
  try{
   final result=await account.connectPost('/jams',{
    'deviceId':deviceId!,'name':"${account.username??'Orchid'}'s Jam",
    'playback':playback,
   });
   jamId=result['jamId'] as String;
   jamName="${account.username??'Orchid'}'s Jam";
   jamHost=true;
   error=null;
  }finally{working=false;notifyListeners();}
 }
 Future<void> joinJam(String code) async {
  if(deviceId==null||!account.signedIn)throw StateError('Sign in to join a Jam');
  final id=code.trim().toUpperCase();
  working=true;notifyListeners();
  try{
   await account.connectPost('/jams/${Uri.encodeComponent(id)}/join',{'deviceId':deviceId!});
   jamId=id;jamHost=false;_lastGuestRevision=0;
   await _refreshJam();
   error=null;
  }finally{working=false;notifyListeners();}
 }
 Future<void> _refreshJam() async {
  if(jamId==null||deviceId==null)return;
  if(jamHost){
   await account.connectPut('/jams/${Uri.encodeComponent(jamId!)}',{
    'deviceId':deviceId!,'playback':playback,
   });
  }
  final result=await account.connectGet('/jams/${Uri.encodeComponent(jamId!)}?deviceId=${Uri.encodeQueryComponent(deviceId!)}');
  final jam=Map<String,dynamic>.from(result['jam'] as Map);
  jamName=jam['name'] as String?;
  jamListeners=(jam['listeners'] as num?)?.toInt()??0;
  if(!jamHost){
   final revision=(jam['updatedAt'] as num?)?.toInt()??0;
   // Sync even if update time did not change: position drifts naturally.
   if(revision>=_lastGuestRevision){
    _lastGuestRevision=revision;
    final state=Map<String,dynamic>.from(jam['playback'] as Map);
    final elapsed=DateTime.now().millisecondsSinceEpoch/1000-revision;
    if(state['playing']==true&&state['position'] is num){
     state['position']=((state['position'] as num).toDouble()+elapsed.clamp(0,7)).clamp(0,86400);
    }
    await _apply(state,sync:true);
   }
  }
 }
 Future<void> leaveJam() async{
  final id=jamId,local=deviceId;
  jamId=null;jamName=null;jamHost=false;jamListeners=0;
  notifyListeners();
  if(id!=null&&local!=null&&account.signedIn){
   try{await account.connectPost('/jams/${Uri.encodeComponent(id)}/leave',{'deviceId':local});}
   catch(e){error='Could not leave Jam: $e';notifyListeners();}
  }
 }
 @override void dispose(){
  _closed=true;_timer?.cancel();super.dispose();
 }
}
