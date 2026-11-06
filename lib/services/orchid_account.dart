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
 String? lastfmUsername;
 bool loading=true;
 bool _verified=false;
 bool connecting=false;
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
  try{await refresh();}catch(e){await _clear();rethrow;}
 }
 Future<void> register(String username,String email,String password) async {
  final data=await _request('POST','/users/register',{'username':username.trim(),'email':email.trim(),'password':password});
  _token=data['token'] as String?;
  _verified=false;
  if(_token==null)throw StateError('Registration did not return a session');
  await (await SharedPreferences.getInstance()).setString('orchid_petal_token',_token!);
  try{await refresh();}catch(e){await _clear();rethrow;}
 }
 Future<void> _clear() async {
  _token=null;_verified=false;username=null;email=null;lastfmUsername=null;connecting=false;restoreError=null;
  await (await SharedPreferences.getInstance()).remove('orchid_petal_token');
  notifyListeners();
 }
 Future<void> logout() async {
  try{await _request('POST','/users/sessions/logout');}finally{await _clear();}
 }
 Future<void> refreshLastfm() async {
  if(!signedIn)return;
  final data=await _request('GET','/orchid/lastfm');
  lastfmUsername=data['connected']==true?data['username'] as String?:null;
  notifyListeners();
 }
 Future<Map<String,dynamic>> lastfmHome() async {
  if(!signedIn||!lastfmConnected)throw StateError('Connect Last.fm first');
  return _request('GET','/orchid/lastfm/home');
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
}
