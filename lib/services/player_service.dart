import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'orchid_audio_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/addon.dart';
import 'addon_service.dart';
import 'lyrics_appearance.dart';
import 'lyrics_service.dart';

enum OrchidRepeatMode { off, all, one }

class PlayerService extends ChangeNotifier {
  final OrchidAudioPlayer player=OrchidAudioPlayer();
  bool eqEnabled=false;
  bool normalizationEnabled=false;
  String eqPreset='Flat';
  List<double> eqBands=List<double>.filled(10,0);
  double crossfadeSeconds=0;
  bool get supportsHardwareEq=>true;
  String? streamUrl;
  int _prefetchRevision=0;
  StreamSubscription<String>? _trackTransitionSubscription;

  static const Map<String,List<double>> eqPresets={
    'Flat':[0,0,0,0,0,0,0,0,0,0],
    'Bass Boost':[6,6,5,3,1,0,0,0,0,0],
    'Vocal':[-3,-2,-1,0,1,3,4,3,1,0],
    'Treble Boost':[-2,-1,0,0,0,1,2,4,5,6],
    'Warm':[3,3,2,1,0,0,-1,-2,-2,-2],
    'Bright':[-2,-1,0,0,1,1,2,3,4,4],
    'Rock':[5,4,2,0,-1,-1,2,3,4,4],
    'Pop':[-1,0,1,3,3,2,1,-1,-1,-2],
    'Jazz':[3,2,1,1,-1,-1,0,2,2,3],
    'Classical':[4,3,2,1,0,-1,-1,-2,-2,-2],
    'Custom':[0,0,0,0,0,0,0,0,0,0],
  };

  Future<void> _restoreAudioPipeline() async{
    try{
      final prefs=await SharedPreferences.getInstance();
      if(_disposed)return;
      eqPreset=prefs.getString('orchid_eq_preset')??'Flat';
      if(!eqPresets.containsKey(eqPreset))eqPreset='Flat';
      eqEnabled=prefs.getBool('orchid_eq_enabled')??false;
      normalizationEnabled=prefs.getBool('orchid_normalization')??false;
      crossfadeSeconds=(prefs.getDouble('orchid_crossfade_seconds')??0).clamp(0.0,12.0);
      final saved=prefs.getStringList('orchid_eq_custom_bands');
      if(saved!=null&&saved.length==10){
        eqBands=saved.map((v)=>(double.tryParse(v)??0).clamp(-12.0,12.0)).toList();
      }
      await player.setCrossfade(Duration(milliseconds:(crossfadeSeconds*1000).round()));
      await player.setNormalization(normalizationEnabled);
      await _applyEqPreset();
      if(!_disposed)notifyListeners();
    }catch(e){debugPrint('[Orchid Audio] Could not restore effects: $e');}
  }

  List<double> get activeEqBands=>eqPreset=='Custom'?List.of(eqBands):
    List.of(eqPresets[eqPreset]??eqPresets['Flat']!);

  Future<void> _applyEqPreset() async{
    await player.setEq(eqEnabled?activeEqBands:eqPresets['Flat']!);
  }
  Future<void> setEqPreset(String preset) async{
    if(!eqPresets.containsKey(preset))return;
    eqPreset=preset;
    await _applyEqPreset();
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('orchid_eq_preset',preset);
  }
  Future<void> setEqBand(int index,double db) async{
    if(index<0||index>=10)return;
    if(eqPreset!='Custom')eqBands=activeEqBands;
    eqPreset='Custom';
    eqBands[index]=db.clamp(-12.0,12.0);
    await _applyEqPreset();
    notifyListeners();
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString('orchid_eq_preset','Custom');
    await prefs.setStringList('orchid_eq_custom_bands',eqBands.map((v)=>v.toString()).toList());
  }
  Future<void> setEqEnabled(bool enabled) async{
    eqEnabled=enabled;
    await _applyEqPreset();
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('orchid_eq_enabled',enabled);
  }
  Future<void> setNormalization(bool enabled) async{
    await player.setNormalization(enabled);
    normalizationEnabled=enabled;notifyListeners();
    (await SharedPreferences.getInstance()).setBool('orchid_normalization',enabled);
  }
  Future<void> setCrossfade(double seconds) async{
    final duration=seconds.clamp(0.0,12.0);
    await player.setCrossfade(Duration(milliseconds:(duration*1000).round()));
    crossfadeSeconds=duration;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble('orchid_crossfade_seconds',crossfadeSeconds);
  }

  final AddonService addonService;
  final LyricsService lyricsService;
  StreamSubscription<OrchidPlayerState>? _stateSubscription;
  bool _autoAdvancing = false;
  bool _disposed = false;
  bool keepPlaying = true;
  bool shuffleEnabled = false;
  Future<List<TrackResult>> Function()? radioNextBatch;
  bool radioLoading = false;
  int _radioToken = 0;
  final Set<String> _radioSeen = {};
  Future<void>? _radioTask;

  void stopRadio() {
    ++_radioToken;
    radioNextBatch = null;
    radioLoading = false;
    _radioSeen.clear();
    notifyListeners();
  }

  Future<void> startRadio(List<TrackResult> tracks,
      Future<List<TrackResult>> Function() nextBatch) async {
    if (tracks.isEmpty) throw StateError('No tracks available for this station');
    stopRadio();
    radioNextBatch = nextBatch;
    _radioSeen.addAll(tracks.map(_trackIdentity));
    await playTrack(tracks.first, fromQueue:tracks);
  }

  Future<void> _extendRadio() async {
    if (radioNextBatch == null || radioLoading || _disposed) return;
    final token = _radioToken;
    radioLoading = true;
    notifyListeners();
    Future<void> run() async {
      try {
        final batch = await radioNextBatch!();
        if (_disposed || token != _radioToken) return;
        for (final track in batch) {
          if (_radioSeen.add(_trackIdentity(track))) queue.add(track);
        }
      } catch (e) {
        debugPrint('[Orchid Radio] Unable to extend station: $e');
      } finally {
        if (!_disposed && token == _radioToken) {
          radioLoading = false;
          notifyListeners();
        }
      }
    }
    final task = run();
    _radioTask = task;
    await task;
    if (identical(_radioTask, task)) _radioTask = null;
  }

  OrchidRepeatMode repeatMode = OrchidRepeatMode.off;
  final Random _shuffleRandom = Random();
  static const _keepPlayingKey = 'orchid_keep_playing';
  /// Suggested songs, shown separately from the user's actual queue.
  List<TrackResult> recommendations = [];
  bool recommendationsLoading = false;
  Future<void>? _recommendationRequest;
  int _recommendationToken = 0;

  TrackResult? current;
  String? playingVia;
  String? streamQuality;
  String? streamCodec;
  LyricsResult? lyrics;
  bool lyricsLoading = false;
  bool resolving = false;
  String? error;

  List<TrackResult> queue = [];
  int queueIndex = -1;
  /// Recent tracks (oldest → newest), excluding the current one.
  List<TrackResult> history = [];
  List<InstalledAddon> _addons = [];

  double volume = 1.0;

  /// Bumps when the loaded track identity changes — drives lyric crossfades.
  int lyricsGeneration = 0;

  PlayerService({
    required this.addonService,
    LyricsService? lyricsService,
  }) : lyricsService = lyricsService ?? LyricsService() {
    unawaited(_restoreKeepPlaying());
    unawaited(_restoreAudioPipeline());
    _trackTransitionSubscription=player.trackTransitions.listen(_handleEngineTransition);
    _stateSubscription = player.playerStateStream.listen((state) {
      if (_disposed) return;
      notifyListeners();
      if (state.processingState == OrchidProcessingState.completed &&
          !_autoAdvancing && !resolving &&
          (hasNext || repeatMode == OrchidRepeatMode.one)) {
        _autoAdvancing = true;
        unawaited(_advanceAfterCompletion());
      }
    });
  }

  Future<void> _restoreKeepPlaying() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      keepPlaying = prefs.getBool(_keepPlayingKey) ?? true;
      notifyListeners();
    } catch (e) {
      debugPrint('[Orchid] Keep Playing preference unavailable: $e');
    }
  }

  Future<void> setKeepPlaying(bool enabled) async {
    keepPlaying = enabled;
    if (!enabled) {
      ++_recommendationToken;
      recommendations = [];
      recommendationsLoading = false;
    } else {
      unawaited(prepareRecommendations());
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keepPlayingKey, enabled);
    } catch (e) {
      debugPrint('[Orchid] Could not save Keep Playing preference: $e');
    }
  }

  /// Add a track after all currently queued music, without interrupting audio.
  void addToQueue(TrackResult track) {
    if (queue.isEmpty && current != null) {
      queue = [current!];
      queueIndex = 0;
    }
    queue.add(track);
    notifyListeners();
    unawaited(_schedulePrefetch());
  }

  /// Insert a track immediately after the current track without
  /// interrupting playback.
  void addNextToQueue(TrackResult track) {
    if (queue.isEmpty && current != null) {
      queue = [current!];
      queueIndex = 0;
    }
    final nextIndex = (queueIndex + 1).clamp(0, queue.length);
    queue.insert(nextIndex, track);
    notifyListeners();
    unawaited(_schedulePrefetch());
  }

  String _trackIdentity(TrackResult t) =>
      '${t.artist.trim().toLowerCase()}|${t.title.trim().toLowerCase()}';

  /// Prefetch suggestions while the current song is playing. The suggestions
  /// remain separate from manually queued tracks until the listener skips or
  /// the existing queue ends.
  Future<void> prepareRecommendations({bool refresh = false}) async {
    if (_disposed || !keepPlaying || current == null) return;
    if (_recommendationRequest != null) {
      await _recommendationRequest;
      if (recommendations.isNotEmpty) return;
    }
    if (!refresh && recommendations.isNotEmpty) return;

    final seed = current!;
    final token = ++_recommendationToken;
    recommendationsLoading = true;
    notifyListeners();

    Future<void> load() async {
      try {
        // Artist is a meaningful starting point and works for both catalog
        // tracks and tracks provided by external addons.
        final found = await addonService.search(_addons, seed.artist)
            .timeout(const Duration(seconds: 22));
        if (_disposed || !keepPlaying || token != _recommendationToken) return;
        final seen = <String>{
          ...queue.map(_trackIdentity),
          ...history.map(_trackIdentity),
          _trackIdentity(seed),
        };
        recommendations = [
          for (final track in found)
            if (track.title.trim().isNotEmpty &&
                track.artist.trim().isNotEmpty &&
                seen.add(_trackIdentity(track))) track,
        ].take(12).toList();
      } catch (e) {
        debugPrint('[Orchid] Keep Playing lookup unavailable: $e');
      } finally {
        if (!_disposed && token == _recommendationToken) {
          recommendationsLoading = false;
          notifyListeners();
        }
      }
    }

    final task = load();
    _recommendationRequest = task;
    try {
      await task;
    } finally {
      if (identical(_recommendationRequest, task)) {
        _recommendationRequest = null;
      }
    }
  }

  Future<bool> _appendRecommendations() async {
    if (_disposed || !keepPlaying || current == null) return false;
    if (recommendations.isEmpty) await prepareRecommendations(refresh: true);
    if (_disposed || !keepPlaying || recommendations.isEmpty) return false;
    final seen = queue.map(_trackIdentity).toSet();
    final added = <TrackResult>[];
    for (final track in recommendations) {
      if (seen.add(_trackIdentity(track))) added.add(track);
    }
    recommendations = [];
    if (added.isEmpty) return false;
    queue.addAll(added);
    if (shuffleEnabled) _shuffleUpcoming();
    notifyListeners();
    return true;
  }

  Future<void> _advanceAfterCompletion() async {
    try {
      // Let the audio stream finish delivering its last completion event.
      // The guard prevents duplicate advances while the next source resolves.
      if (_disposed || resolving ||
          player.processingState != OrchidProcessingState.completed) {
        return;
      }
      if (repeatMode == OrchidRepeatMode.one && current != null) {
        await player.seek(Duration.zero);
        await player.play();
        return;
      }
      if (!hasQueuedNext && repeatMode == OrchidRepeatMode.all && queue.isNotEmpty) {
        queueIndex = -1;
        if (shuffleEnabled) _shuffleUpcoming();
      }
      if (!hasQueuedNext && radioNextBatch != null) {
        await _extendRadio();
      }
      if (!hasQueuedNext && keepPlaying && radioNextBatch == null) {
        await _appendRecommendations();
      }
      if (_disposed || !hasQueuedNext || resolving ||
          player.processingState != ProcessingState.completed) {
        return;
      }
      await playNext();
    } catch (e) {
      debugPrint('[Orchid] Unable to auto-play next queue track: $e');
    } finally {
      _autoAdvancing = false;
    }
  }

  /// A human-readable playback provider label, never a raw stream URL.
  String get sourceLabel => playingVia ?? 'Now playing';

  /// Friendly quality names from Eclipse/Tidal stream metadata.
  String? get qualityLabel {
    final raw = streamQuality?.trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (normalized.contains('hires') && normalized.contains('lossless')) {
      return 'Hi-Res Lossless';
    }
    if (normalized.contains('lossless')) return 'Lossless';
    if (normalized == 'high') return 'High Quality';
    if (normalized == 'low') return 'Low Quality';
    return raw.replaceAll('_', ' ').replaceAll('-', ' ');
  }

  String _sourceName(String? via, StreamInfo stream, TrackResult track) {
    final raw = (via ?? '').trim();
    if (raw.isEmpty) return track.sourceName.isNotEmpty ? track.sourceName : 'Stream';
    for (final addon in _addons) {
      if (raw == addon.baseUrl || raw.startsWith('${addon.baseUrl}/')) {
        return addon.manifest.name;
      }
    }
    if (raw == track.addonBaseUrl && track.sourceName.isNotEmpty) {
      return track.sourceName;
    }
    if (raw.contains('://') || raw.startsWith('www.')) {
      final uri = Uri.tryParse(raw.startsWith('www.') ? 'https://$raw' : raw);
      final host = (uri?.host ?? '').toLowerCase();
      if (host.contains('youtube') || host == 'youtu.be' ||
          host.contains('googlevideo')) {
        return 'YouTube';
      }
      if (host.contains('spotify')) return 'Spotify';
      if (host.contains('apple.com') || host.contains('itunes')) return 'iTunes';
      return track.sourceName.isNotEmpty ? track.sourceName : 'Stream';
    }
    return raw.length > 32 ? '${raw.substring(0, 32)}…' : raw;
  }

  bool get hasQueuedNext =>
      queueIndex >= 0 && queueIndex < queue.length - 1;
  bool get hasNext =>
      radioNextBatch != null || hasQueuedNext || (repeatMode == OrchidRepeatMode.all && queue.isNotEmpty) ||
      (keepPlaying && current != null);
  bool get hasPrevious => queueIndex > 0;

  void toggleShuffle() {
    shuffleEnabled = !shuffleEnabled;
    if (shuffleEnabled) _shuffleUpcoming();
    notifyListeners();
    unawaited(_schedulePrefetch());
  }

  /// Apply remote playback options without reshuffling a transferred queue.
  void restoreRemoteOptions({required bool shuffle, required OrchidRepeatMode repeat}) {
    shuffleEnabled=shuffle;
    repeatMode=repeat;
    unawaited(player.setRepeatOne(repeat==OrchidRepeatMode.one));
    notifyListeners();
    unawaited(_schedulePrefetch());
  }

  void cycleRepeatMode() {
    repeatMode = switch (repeatMode) {
      OrchidRepeatMode.off => OrchidRepeatMode.all,
      OrchidRepeatMode.all => OrchidRepeatMode.one,
      OrchidRepeatMode.one => OrchidRepeatMode.off,
    };
    unawaited(player.setRepeatOne(repeatMode==OrchidRepeatMode.one));
    notifyListeners();
    unawaited(_schedulePrefetch());
  }

  void _shuffleUpcoming() {
    final first = queueIndex + 1;
    if (first < 0 || first >= queue.length - 1) return;
    final remaining = queue.sublist(first)..shuffle(_shuffleRandom);
    queue.setRange(first, queue.length, remaining);
  }

  void setAddons(List<InstalledAddon> addons) {
    _addons = addons;
  }

  void _pushHistory(TrackResult? track) {
    if (track == null) return;
    history.removeWhere((t) => _trackIdentity(t) == _trackIdentity(track));
    history.add(track);
    if (history.length > 40) {
      history = history.sublist(history.length - 40);
    }
  }

  Future<void> playTrack(
    TrackResult track, {
    List<TrackResult>? fromQueue,
  }) async {
    if (current != null &&
        !(current!.id == track.id && current!.sourceId == track.sourceId)) {
      _pushHistory(current);
    }

    if (radioNextBatch != null && track.sourceId != 'orchid-radio') stopRadio();
    if (fromQueue != null) {
      queue = List<TrackResult>.from(fromQueue);
      queueIndex = queue.indexWhere(
        (t) => t.id == track.id && t.sourceId == track.sourceId,
      );
      if (queueIndex < 0) {
        queue.insert(0, track);
        queueIndex = 0;
      }
    } else if (queue.isEmpty) {
      queue = [track];
      queueIndex = 0;
    } else {
      final idx = queue.indexWhere(
        (t) => t.id == track.id && t.sourceId == track.sourceId,
      );
      if (idx >= 0) {
        queueIndex = idx;
      } else {
        queue.add(track);
        queueIndex = queue.length - 1;
      }
    }

    if (shuffleEnabled) _shuffleUpcoming();
    await _loadAndPlay(track);
  }

  Future<void> _beginNewRecommendations() async {
    ++_recommendationToken;
    recommendations = [];
    notifyListeners();
    if (keepPlaying) await prepareRecommendations();
    if(!_disposed)unawaited(_schedulePrefetch());
  }

  Future<void> _loadAndPlay(TrackResult track) async {
    resolving = true;
    playingVia = null;
    streamQuality = null;
    streamCodec = null;
    streamUrl=null;
    error = null;
    lyrics = null;
    lyricsLoading = true;
    final generation = ++lyricsGeneration;
    current = track;
    notifyListeners();

    try {
      final stream = await addonService
          .resolvePlayback(track, _addons)
          .timeout(const Duration(seconds: 50));
      if (generation != lyricsGeneration) return;
      playingVia = _sourceName(stream.via ?? stream.quality, stream, track);
      streamQuality = stream.quality;
      streamCodec = stream.format;
      await player.openTrack(stream.url,_trackKey(track))
        .timeout(const Duration(seconds:20));
      streamUrl=stream.url;
      if (generation != lyricsGeneration) return;
      await player.setVolume(volume);
      unawaited(player.play().catchError((Object e) {
        debugPrint('[Orchid] Audio playback failed: $e');
      }));
      resolving = false;
      notifyListeners();

      unawaited(_schedulePrefetch());
      // Lyrics are optional metadata. Never block playback or the Play button
      // on a third-party lyrics provider.
      unawaited(_loadLyricsFor(track, generation));
      if (radioNextBatch != null) {
        if (queue.length - queueIndex <= 3) unawaited(_extendRadio());
      } else {
        unawaited(_beginNewRecommendations());
      }
    } catch (e) {
      if (generation == lyricsGeneration) {
        resolving = false;
        lyricsLoading = false;
        error = 'Playback failed: $e';
        notifyListeners();
      }
      rethrow;
    }
  }

  String _trackKey(TrackResult track)=>'${track.sourceId}|${track.id}';

  /// Resolve only the imminent next track. This is essential for seamless
  /// overlap because Eclipse addons return stream URLs asynchronously.
  Future<void> _schedulePrefetch() async{
    if(_disposed||resolving||!hasQueuedNext||repeatMode==OrchidRepeatMode.one)return;
    final revision=++_prefetchRevision;
    final next=queue[queueIndex+1];
    final key=_trackKey(next);
    if(player.canAdvanceTo(key))return;
    try{
      final result=await addonService.resolvePlayback(next,_addons)
        .timeout(const Duration(seconds:35));
      if(_disposed||revision!=_prefetchRevision||!hasQueuedNext||
        _trackKey(queue[queueIndex+1])!=key)return;
      await player.preloadNext(result.url,key);
    }catch(e){
      debugPrint('[Orchid Audio] Next-track prefetch unavailable: $e');
    }
  }

  void _handleEngineTransition(String key){
    if(_disposed||resolving||!hasQueuedNext||
        _trackKey(queue[queueIndex+1])!=key)return;
    _pushHistory(current);
    queueIndex++;
    final track=queue[queueIndex];
    current=track;
    streamUrl=null;
    playingVia=track.sourceName;
    streamQuality=null;
    streamCodec=null;
    lyrics=null;
    lyricsLoading=true;
    final generation=++lyricsGeneration;
    notifyListeners();
    unawaited(_loadLyricsFor(track,generation));
    unawaited(_schedulePrefetch());
    if(radioNextBatch!=null&&queue.length-queueIndex<=3){
      unawaited(_extendRadio().then((_)=>
        _schedulePrefetch()));
    }else if(keepPlaying&&queue.length-queueIndex<=2){
      unawaited(_beginNewRecommendations());
    }
  }

  Future<void> _loadLyricsFor(TrackResult track, int generation) async {
    try {
      final result = await lyricsService.fetchFor(track)
          .timeout(const Duration(seconds: 12));
      if (generation != lyricsGeneration) return;
      lyrics = result;
      lyricsLoading = false;
      notifyListeners();
      if (LyricsAppearance.instance.skipUnsynced &&
          (result == null || !result.hasSync) && hasNext) {
        await playNext();
      }
    } catch (e) {
      if (generation != lyricsGeneration) return;
      debugPrint('[Orchid] Lyrics unavailable: $e');
      lyricsLoading = false;
      notifyListeners();
    }
  }

  Future<void> playNext() async {
    if (!hasQueuedNext && repeatMode == OrchidRepeatMode.all && queue.isNotEmpty) {
      queueIndex = -1;
      if (shuffleEnabled) _shuffleUpcoming();
    }
    if (!hasQueuedNext && radioNextBatch != null) await _extendRadio();
    if (!hasQueuedNext && keepPlaying && radioNextBatch == null) {
      await _appendRecommendations();
    }
    if (!hasQueuedNext) return;
    if (player.canAdvanceTo(_trackKey(queue[queueIndex+1]))) {
      await player.nextPrepared();
      return;
    }
    if (current != null) _pushHistory(current);
    queueIndex++;
    await _loadAndPlay(queue[queueIndex]);
  }

  Future<void> playPrevious() async {
    if (player.position.inSeconds > 3 || !hasPrevious) {
      await player.seek(Duration.zero);
      return;
    }
    if (current != null) _pushHistory(current);
    queueIndex--;
    await _loadAndPlay(queue[queueIndex]);
  }

  Future<void> togglePlayPause() async {
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0);
    notifyListeners();
    await player.setVolume(volume);
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_radioToken;
    radioNextBatch = null;
    ++_recommendationToken;
    _stateSubscription?.cancel();
    _trackTransitionSubscription?.cancel();
    unawaited(player.dispose());
    super.dispose();
  }
}
