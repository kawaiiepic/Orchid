import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class OrchidAuthException implements Exception {
 final int status;
 final String message;
 const OrchidAuthException(this.status,this.message);
 @override String toString()=>message;
}

/// Orchid uses the same account and session endpoints as Petal.
class OrchidAccount extends ChangeNotifier {
 static const baseUrl=String.fromEnvironment('PETAL_BACKEND_URL',defaultValue:'https://petal-backend.blossomvale.dev');
 String? _token;
 String? username;
 String? email;
 String? avatarUrl;
 String? lastfmUsername;
 bool loading=true;
 bool _verified=false;
 bool connecting=false;
 /// Increments after a listen is persisted in Petal's D1 history.
 final ValueNotifier<int> listeningRevision=ValueNotifier<int>(0);
 String? restoreError;
 bool get hasStoredSession=>_token!=null;
 bool get signedIn=>_token!=null && _verified;
 bool get lastfmConnected=>lastfmUsername!=null;

 Future<Map<String,dynamic>> _request(String method,String path,[Map<String,dynamic>? payload]) async {
  final headers=<String,String>{'Content-Type':'application/json'};
  if(_token!=null)headers['Cookie']='auth=${_token!}';
  final uri=Uri.parse('$baseUrl$path');
  final response=await (method=='GET'?http.get(uri,headers:headers):
    method=='DELETE'?http.delete(uri,headers:headers):
    http.post(uri,headers:headers,body:jsonEncode(payload??{}))).timeout(const Duration(seconds:15),onTimeout:()=>throw Exception('Connection timed out. Please try again.'));
  dynamic value;
  try{value=jsonDecode(response.body);}catch(_){throw Exception('Invalid response from Petal backend (HTTP ${response.statusCode}).');}
  if(value is! Map)throw Exception('Unexpected response from Petal backend.');
  final data=Map<String,dynamic>.from(value);
  if(response.statusCode>=400||data['success']==false) {
   final result=data['result'];
   throw OrchidAuthException(response.statusCode, (data['error']??(result is Map?result['error']:null)??'Request failed (${response.statusCode})').toString());
  }
  return data;
 }

 Future<void> restore() async {
  loading=true;
  restoreError=null;
  notifyListeners();
  try{
   final prefs=await SharedPreferences.getInstance();
   _token=prefs.getString('orchid_petal_token');
   _verified=false;
   if(_token!=null)await _verifySavedSession();
  }catch(e){
   restoreError='Could not restore your saved session: $e';
   debugPrint('[Orchid] Session restore failed: $e');
  }finally{
   loading=false;
   notifyListeners();
  }
 }

 Future<void> retryRestore() async {
  if(_token==null){
   await restore();
   return;
  }
  loading=true;
  restoreError=null;
  notifyListeners();
  try{
   await _verifySavedSession();
  }catch(e){
   restoreError='Could not connect to Petal: $e';
  }finally{
   loading=false;
   notifyListeners();
  }
 }

 Future<void> _verifySavedSession() async {
  try{
   await refresh();
  }on OrchidAuthException catch(e){
   if(e.status==401 || e.status==403){
    await _clear();
    return;
   }
   rethrow;
  }
 }

 Future<void> refresh() async {
  final response=await _request('GET','/users/verify');
  final user=Map<String,dynamic>.from(response['user'] as Map);
  _verified=true;
  restoreError=null;
  username=user['username'] as String?;
  email=user['email'] as String?;
  final avatar = user['avatar'] as String?;
  avatarUrl = avatar == null || avatar.isEmpty
      ? null : Uri.parse(baseUrl).resolve(avatar).toString();
  notifyListeners();
  try{await refreshLastfm();}catch(e){debugPrint('[Orchid] Last.fm unavailable: $e');}
 }
 Future<void> login(String email,String password) async {
  final data=await _request('POST','/users/login',{'email':email.trim(),'password':password});
  final result=Map<String,dynamic>.from(data['result'] as Map);
  _token=(result['jwtToken']??result['yummyCookie']) as String?;
  _verified=false;
  if(_token==null)throw StateError('Login response did not contain a session');
  await (await SharedPreferences.getInstance()).setString('orchid_petal_token',_token!);
  try{await refresh();}on OrchidAuthException catch(e){
   if(e.status==401||e.status==403)await _clear();
   rethrow;
  }
 }
 Future<void> register(String username,String email,String password) async {
  final data=await _request('POST','/users/register',{'username':username.trim(),'email':email.trim(),'password':password});
  _token=data['token'] as String?;
  _verified=false;
  if(_token==null)throw StateError('Registration did not return a session');
  await (await SharedPreferences.getInstance()).setString('orchid_petal_token',_token!);
  try{await refresh();}on OrchidAuthException catch(e){
   if(e.status==401||e.status==403)await _clear();
   rethrow;
  }
 }
 Future<void> _clear() async {
  _token=null;_verified=false;username=null;email=null;avatarUrl=null;lastfmUsername=null;connecting=false;restoreError=null;
  await (await SharedPreferences.getInstance()).remove('orchid_petal_token');
  notifyListeners();
 }
 Future<void> clearSavedSession() => _clear();
 Future<void> logout() async {
  try{await _request('POST','/users/sessions/logout');}finally{await _clear();}
 }
 /// Detect actual encoded image data instead of guessing from the filename.
 static String? avatarMimeType(Uint8List bytes) {
  if(bytes.length>=8 &&
      bytes[0]==0x89 && bytes[1]==0x50 &&
      bytes[2]==0x4E && bytes[3]==0x47) {return 'image/png';}
  if(bytes.length>=3 && bytes[0]==0xFF &&
      bytes[1]==0xD8 && bytes[2]==0xFF) {return 'image/jpeg';}
  if(bytes.length>=12 &&
      String.fromCharCodes(bytes.sublist(0,4))=='RIFF' &&
      String.fromCharCodes(bytes.sublist(8,12))=='WEBP') {return 'image/webp';}
  if(bytes.length>=6 &&
      String.fromCharCodes(bytes.sublist(0,3))=='GIF') {return 'image/gif';}
  return null;
 }
 Future<void> uploadAccountAvatar(Uint8List image, String contentType) async {
  if(!signedIn || _token == null)throw StateError('Sign in first');
  final result=await http.put(
    Uri.parse('$baseUrl/users/avatar'),
    headers:{'Cookie':'auth=${_token!}','Content-Type':contentType},
    body:image,
  ).timeout(const Duration(seconds:25));
  Map<String,dynamic>? data;
  try {
   final decoded=jsonDecode(result.body);
   if(decoded is Map)data=Map<String,dynamic>.from(decoded);
  }catch(_){}
  if(result.statusCode!=200 || data?['success']!=true) {
   final errors=data?['errors'];
   final detail=data?['error']?.toString()
       ?? (errors is List && errors.isNotEmpty
           ? errors.first.toString() : null)
       ?? (result.body.trim().isNotEmpty &&
           result.body.length<300 && !result.body.trim().startsWith('<')
           ? result.body.trim() : null)
       ?? 'Avatar upload failed';
   throw Exception('$detail (HTTP ${result.statusCode})');
  }
  final path=data?['avatar']?.toString();
  if(path==null||path.isEmpty)throw StateError('Avatar upload returned no image URL');
  // The upload response is authoritative. Update the UI immediately instead
  // of relying on a subsequent /users/verify request to succeed.
  avatarUrl=Uri.parse(baseUrl).resolve(path).replace(
    queryParameters:{'v':'${DateTime.now().millisecondsSinceEpoch}'},
  ).toString();
  notifyListeners();
 }

 Future<void> removeAccountAvatar() async {
  await _request('DELETE','/users/avatar');
  avatarUrl=null;
  notifyListeners();
 }

 Future<void> refreshLastfm() async {
  if(!signedIn)return;
  final data=await _request('GET','/orchid/lastfm');
  lastfmUsername=data['connected']==true?data['username'] as String?:null;
  notifyListeners();
 }
 Future<Map<String,dynamic>> orchidHome() async {
  if(!signedIn)throw StateError('Sign in first');
  return _request('GET','/orchid/home');
 }
 Future<String> sendAiDjMessage(String message) async {
  if(!signedIn)throw StateError('Sign in to talk to AI DJ');
  final response=await _request('POST','/orchid/ai-dj/chat',{'message':message});
  final text=response['message'];
  if(text is! String)throw StateError('Unexpected AI DJ response');
  return text;
 }
 Future<Map<String,dynamic>> allTimeTopSongs() =>
    _request('GET','/orchid/top-songs');
 Future<Map<String,dynamic>> radioSongs({
  required String type,required String choice,required int offset,
 }) => _request('GET','/orchid/radio?type=${Uri.encodeQueryComponent(type)}&choice=${Uri.encodeQueryComponent(choice)}&offset=$offset');
 Future<Map<String,dynamic>> replay({required int year,required int month}) async {
  if(!signedIn)throw StateError('Sign in first');
  return _request('GET','/orchid/replay?year=$year&month=$month');
 }
 Future<Map<String,dynamic>> listeningHistory() async {
  if(!signedIn)throw StateError('Sign in first');
  return _request('GET','/orchid/history');
 }
 Future<void> recordListen({
  required String eventId,
  required String title,
  required String artist,
  required int startedAt,
  String? album,
  String? artwork,
  String? songId,
  int? duration,
  List<String>? genres,
 }) async {
  if(!signedIn)return;
  await _request('POST','/orchid/history',{
    'eventId':eventId,'title':title,'artist':artist,'startedAt':startedAt,
    if(album!=null)'album':album,
    if(artwork!=null)'artwork':artwork,
    if(songId!=null)'songId':songId,
    if(duration!=null)'duration':duration,
    if(genres!=null && genres.isNotEmpty)'genres':genres,
  });
  listeningRevision.value++;
 }
 Future<Map<String,dynamic>> lastfmHome() async {
  if(!signedIn||!lastfmConnected)throw StateError('Connect Last.fm first');
  return _request('GET','/orchid/lastfm/home');
 }
 Future<Map<String,dynamic>> appleArtist(String name) async {
  if(!signedIn)throw StateError('Sign in first');
  final uri=Uri(queryParameters:{'name':name.trim()});
  return _request('GET','/orchid/apple/artist?${uri.query}');
 }
 Future<Map<String,dynamic>> searchAppleCatalog(String query) async {
  if(!signedIn || query.trim().length < 2) {
   return {'tracks':<dynamic>[], 'albums':<dynamic>[],
    'artists':<dynamic>[], 'playlists':<dynamic>[]};
  }
  final uri=Uri(queryParameters:{'q':query.trim()});
  return _request('GET','/orchid/apple/search?${uri.query}');
 }
 Future<Map<String,dynamic>> searchApplePlaylists(String query) async {
  if (!signedIn || query.trim().length < 2) {
   return {'playlists': <dynamic>[], 'configured': false};
  }
  final uri=Uri(queryParameters: {'q':query.trim()});
  return _request('GET','/orchid/apple/playlists?${uri.query}');
 }
 Future<Map<String,dynamic>> applePlaylist(String id) async {
  if(!signedIn)throw StateError('Sign in first');
  return _request('GET','/orchid/apple/playlists/${Uri.encodeComponent(id)}');
 }
 Future<List<String?>> appleArtworkBatch(List<Map<String,String>> tracks) async {
  if(!signedIn || tracks.isEmpty)return List<String?>.filled(tracks.length,null);
  final data=await _request('POST','/orchid/apple/artwork',{'tracks':tracks});
  final raw=data['artworks'];
  if(raw is! List || raw.length!=tracks.length) {
   return List<String?>.filled(tracks.length,null);
  }
  return raw.map((value)=>value is String&&value.startsWith('https://')
      ?value:null).toList();
 }
 Future<Map<String,dynamic>> dailyMixes() async {
  if(!signedIn)throw StateError('Sign in first');
  return _request('GET','/orchid/daily-mixes');
 }
 Future<void> startLastfm() async {
  final data=await _request('POST','/orchid/lastfm/start');
  final uri=Uri.parse(data['url'] as String);
  if(!await launchUrl(uri,mode:LaunchMode.externalApplication))throw Exception('Unable to open Last.fm');
  connecting=true;notifyListeners();
 }
 Future<void> completeLastfm() async {
  final data=await _request('POST','/orchid/lastfm/complete');
  lastfmUsername=data['username'] as String?;
  connecting=false;notifyListeners();
 }
 Future<void> unlinkLastfm() async {
  await _request('DELETE','/orchid/lastfm');
  lastfmUsername=null;connecting=false;notifyListeners();
 }
 Future<void> nowPlaying({required String artist,required String title,String? album,int? duration}) async {
  if(!lastfmConnected)return;
  try{await _request('POST','/orchid/lastfm/now-playing',{'artist':artist,'track':title,if(album!=null)'album':album,if(duration!=null)'duration':duration});}
  catch(e){debugPrint('[Orchid] Last.fm now-playing: $e');}
 }
 Future<void> scrobble({required String artist,required String title,required int timestamp,String? album,int? duration}) async {
  if(!lastfmConnected)return;
  try{await _request('POST','/orchid/lastfm/scrobble',{'artist':artist,'track':title,'timestamp':timestamp,if(album!=null)'album':album,if(duration!=null)'duration':duration});}
  catch(e){debugPrint('[Orchid] Last.fm scrobble: $e');}
 }
 @override
 void dispose() {
  listeningRevision.dispose();
  super.dispose();
 }

}
