import 'package:just_audio/just_audio.dart';

import '../models/addon.dart';
import 'addon_service.dart';
import 'lyrics_service.dart';

class PlayerService {
  final AudioPlayer player = AudioPlayer();
  final AddonService addonService;
  final LyricsService lyricsService;

  TrackResult? current;
  String? playingVia;
  LyricsResult? lyrics;
  bool lyricsLoading = false;

  PlayerService({
    required this.addonService,
    LyricsService? lyricsService,
  }) : lyricsService = lyricsService ?? LyricsService();

  Future<void> playTrack(
    TrackResult track,
    List<InstalledAddon> addons,
  ) async {
    final stream = await addonService.resolvePlayback(track, addons);
    current = track;
    playingVia = stream.via ?? stream.quality;
    lyrics = null;
    await player.setUrl(stream.url);
    await player.play();

    // Lyrics in parallel after playback starts
    lyricsLoading = true;
    try {
      lyrics = await lyricsService.fetchFor(track);
    } finally {
      lyricsLoading = false;
    }
  }

  Future<void> togglePlayPause() async {
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> dispose() async {
    await player.dispose();
  }
}
