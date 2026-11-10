import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/addon.dart';
import 'addon_service.dart';
import 'lyrics_appearance.dart';
import 'lyrics_service.dart';

enum OrchidRepeatMode { off, all, one }

class PlayerService extends ChangeNotifier {
  final AudioPlayer player = AudioPlayer();
  final AddonService addonService;
  final LyricsService lyricsService;
  StreamSubscription<PlayerState>? _stateSubscription;
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
    _stateSubscription = player.playerStateStream.listen((state) {
      if (_disposed) return;
      notifyListeners();
      if (state.processingState == ProcessingState.completed &&
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
          player.processingState != ProcessingState.completed) {
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
  }

  void cycleRepeatMode() {
    repeatMode = switch (repeatMode) {
      OrchidRepeatMode.off => OrchidRepeatMode.all,
      OrchidRepeatMode.all => OrchidRepeatMode.one,
      OrchidRepeatMode.one => OrchidRepeatMode.off,
    };
    notifyListeners();
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
  }

  Future<void> _loadAndPlay(TrackResult track) async {
    resolving = true;
    playingVia = null;
    streamQuality = null;
    streamCodec = null;
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
      await player.setUrl(stream.url).timeout(const Duration(seconds: 20));
      if (generation != lyricsGeneration) return;
      await player.setVolume(volume);
      unawaited(player.play().catchError((Object e) {
        debugPrint('[Orchid] Audio playback failed: $e');
      }));
      resolving = false;
      notifyListeners();

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
    player.dispose();
    super.dispose();
  }
}
