import 'dart:async';
import 'package:miniaudio_player/miniaudio_player.dart' as mini;

/// Stable Orchid-facing transport API. Backed by miniaudio's dual-deck engine,
/// not just_audio. The existing widgets and lock-screen handler use this
/// narrow facade instead of depending on a particular DSP backend.
enum OrchidProcessingState { idle, loading, buffering, ready, completed }
class OrchidPlayerState {
  final OrchidProcessingState processingState;
  final bool playing;
  const OrchidPlayerState(this.processingState,this.playing);
}

class OrchidAudioPlayer {
  final mini.MiniaudioEngine<String> engine=mini.MiniaudioEngine<String>(
    crossfadeConfig:mini.CrossfadeConfig(
      duration:Duration.zero,
      manualDuration:const Duration(milliseconds:250),
      curve:mini.CrossfadeCurve.equalPower,
    ),
    pauseOnDeviceChange:true,
  );
  final _state=StreamController<OrchidPlayerState>.broadcast();
  final _nextTracks=StreamController<String>.broadcast();
  final List<StreamSubscription<dynamic>> _subs=[];
  String? _activeKey;
  String? _preloadedKey;
  bool _disposed=false;
  OrchidAudioPlayer(){
    _subs.add(engine.stream.playbackState.listen((_){_emitState();}));
    _subs.add(engine.stream.buffering.listen((_){_emitState();}));
    _subs.add(engine.stream.completed.listen((_){_emitState();}));
    _subs.add(engine.stream.playing.listen((_){_emitState();}));
    _subs.add(engine.stream.currentData.listen((key){
      if(key==null||key==_activeKey)return;
      _activeKey=key;
      _preloadedKey=null;
      _nextTracks.add(key);
      _emitState();
    }));
  }
  Stream<String> get trackTransitions=>_nextTracks.stream;
  Stream<OrchidPlayerState> get playerStateStream=>_state.stream;
  Stream<Duration> get positionStream=>engine.stream.position;
  Stream<Duration?> get durationStream=>engine.stream.duration.map((v)=>v==Duration.zero?null:v);
  Stream<Duration> get bufferedPositionStream=>engine.stream.bufferedPosition;
  Duration get position=>engine.state.position;
  Duration? get duration=>engine.state.duration==Duration.zero?null:engine.state.duration;
  Duration get bufferedPosition=>engine.state.bufferedPosition;
  bool get playing=>engine.state.playing;
  double get speed=>engine.state.rate;
  OrchidProcessingState get processingState {
    if(engine.state.completed)return OrchidProcessingState.completed;
    if(engine.state.opening)return OrchidProcessingState.loading;
    if(engine.state.buffering)return OrchidProcessingState.buffering;
    if(_activeKey==null)return OrchidProcessingState.idle;
    return OrchidProcessingState.ready;
  }
  void _emitState(){
    if(!_disposed)_state.add(OrchidPlayerState(processingState,playing));
  }
  Future<void> openTrack(String url,String key) async{
    _activeKey=key;
    _preloadedKey=null;
    await engine.action.open([
      mini.EngineItem<String>(source:mini.AudioSource.uri(url),data:key),
    ]);
    _emitState();
  }
  bool canAdvanceTo(String key)=>_preloadedKey==key;
  Future<void> preloadNext(String url,String key) async{
    if(_disposed||_preloadedKey==key||_activeKey==key)return;
    // A changed Play Next/queue order must replace the stale standby deck.
    if(_preloadedKey!=null && _preloadedKey!=key){
      final oldIndex=engine.state.currentIndex+1;
      if(oldIndex>=0 && oldIndex<engine.state.queue.length){
        await engine.action.removeAt(oldIndex);
      }
      _preloadedKey=null;
    }
    await engine.action.append([
      mini.EngineItem<String>(source:mini.AudioSource.uri(url),data:key),
    ]);
    _preloadedKey=key;
  }
  Future<void> nextPrepared()=>engine.action.next();
  Future<void> play()=>engine.action.play();
  Future<void> pause()=>engine.action.pause();
  Future<void> stop()=>engine.action.stop();
  Future<void> seek(Duration value)=>engine.action.seek(value);
  Future<void> setVolume(double v)=>engine.action.setVolume(v);
  Future<void> setCrossfade(Duration v)=>engine.action.setCrossfadeDuration(v);
  Future<void> setNormalization(bool value)=>engine.action.setVolumeNormalization(value);
  Future<void> setRepeatOne(bool enabled)=>engine.action.setLoopMode(
    enabled?mini.LoopMode.one:mini.LoopMode.off);
  Future<void> setEq(List<double> gains)=>engine.action.setEqualizer(
    mini.Equalizer.fromList(gains));
  Future<void> setEqBand(int band,double db)=>engine.action.setEqualizerBand(band,db);
  Future<List<mini.AudioDevice>> getAudioDevices()=>mini.MiniaudioPlayer.getAudioDevices();
  Future<void> setAudioDevice(mini.AudioDevice device)=>engine.action.setDevice(device);
  Future<void> dispose() async {
    _disposed=true;
    for(final sub in _subs){await sub.cancel();}
    await _state.close();
    await _nextTracks.close();
    await engine.dispose();
  }
}
