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

  TrackResult? current;
  String? playingVia;
  LyricsResult? lyrics;
  bool lyricsLoading = false;
  bool resolving = false;
  String? error;

  List<TrackResult> queue = [];
  int queueIndex = -1;
  List<InstalledAddon> _addons = [];

  double volume = 1.0;

  PlayerService({
    required this.addonService,
    LyricsService? lyricsService,
  }) : lyricsService = lyricsService ?? LyricsService() {
    player.playerStateStream.listen((_) => notifyListeners());
  }

  bool get hasNext => queueIndex >= 0 && queueIndex < queue.length - 1;
  bool get hasPrevious => queueIndex > 0;

  void setAddons(List<InstalledAddon> addons) {
    _addons = addons;
  }

  Future<void> playTrack(
    TrackResult track, {
    List<TrackResult>? fromQueue,
  }) async {
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
    error = null;
    lyrics = null;
    lyricsLoading = true;
    current = track;
    notifyListeners();

    try {
      final stream = await addonService.resolvePlayback(track, _addons);
      playingVia = stream.via ?? stream.quality;
      await player.setUrl(stream.url);
      await player.setVolume(volume);
      await player.play();
      resolving = false;
      notifyListeners();

      try {
        lyrics = await lyricsService.fetchFor(track);
        if (LyricsAppearance.instance.skipUnsynced &&
            (lyrics == null || !lyrics!.hasSync) &&
            hasNext) {
          debugPrint('[Orchid] skipUnsynced: advancing');
          lyricsLoading = false;
          notifyListeners();
          await playNext();
          return;
        }
      } finally {
        lyricsLoading = false;
        notifyListeners();
      }
    } catch (e) {
      resolving = false;
      lyricsLoading = false;
      error = '$e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playNext() async {
    if (!hasNext) return;
    queueIndex++;
    await _loadAndPlay(queue[queueIndex]);
  }

  Future<void> playPrevious() async {
    if (player.position.inSeconds > 3 || !hasPrevious) {
      await player.seek(Duration.zero);
      return;
    }
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
    await player.setVolume(volume);
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
    notifyListeners();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
