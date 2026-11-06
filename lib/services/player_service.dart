import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/addon.dart';
import 'addon_service.dart';
import 'lyrics_appearance.dart';
import 'lyrics_service.dart';

class PlayerService extends ChangeNotifier {
  final AudioPlayer player = AudioPlayer();
  final AddonService addonService;
  final LyricsService lyricsService;
  StreamSubscription<PlayerState>? _stateSubscription;
  bool _autoAdvancing = false;
  bool _disposed = false;

  TrackResult? current;
  String? playingVia;
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
    _stateSubscription = player.playerStateStream.listen((state) {
      if (_disposed) return;
      notifyListeners();
      if (state.processingState == ProcessingState.completed &&
          !_autoAdvancing && !resolving && hasNext) {
        _autoAdvancing = true;
        unawaited(_advanceAfterCompletion());
      }
    });
  }

  Future<void> _advanceAfterCompletion() async {
    try {
      // Let the audio stream finish delivering its last completion event.
      // The guard prevents duplicate advances while the next source resolves.
      if (_disposed || !hasNext || resolving ||
          player.processingState != ProcessingState.completed) return;
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
          host.contains('googlevideo')) return 'YouTube';
      if (host.contains('spotify')) return 'Spotify';
      if (host.contains('apple.com') || host.contains('itunes')) return 'iTunes';
      return track.sourceName.isNotEmpty ? track.sourceName : 'Stream';
    }
    return raw.length > 32 ? '${raw.substring(0, 32)}…' : raw;
  }

  bool get hasNext => queueIndex >= 0 && queueIndex < queue.length - 1;
  bool get hasPrevious => queueIndex > 0;

  void setAddons(List<InstalledAddon> addons) {
    _addons = addons;
  }

  void _pushHistory(TrackResult? track) {
    if (track == null) return;
    history.removeWhere(
      (t) => t.id == track.id && t.sourceId == track.sourceId,
    );
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

    await _loadAndPlay(track);
  }

  Future<void> _loadAndPlay(TrackResult track) async {
    resolving = true;
    playingVia = null;
    error = null;
    lyrics = null;
    lyricsLoading = true;
    final generation = ++lyricsGeneration;
    current = track;
    notifyListeners();

    try {
      final stream = await addonService
          .resolvePlayback(track, _addons)
          .timeout(const Duration(seconds: 30));
      if (generation != lyricsGeneration) return;
      playingVia = _sourceName(stream.via ?? stream.quality, stream, track);
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
    if (!hasNext) return;
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
    _stateSubscription?.cancel();
    player.dispose();
    super.dispose();
  }
}
