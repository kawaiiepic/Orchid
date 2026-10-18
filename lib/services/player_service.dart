import 'package:just_audio/just_audio.dart';

import '../models/addon.dart';
import 'addon_service.dart';

class PlayerService {
  final AudioPlayer player = AudioPlayer();
  final AddonService addonService;

  TrackResult? current;
  String? playingVia;

  PlayerService({required this.addonService});

  Future<void> playTrack(
    TrackResult track,
    List<InstalledAddon> addons,
  ) async {
    final stream = await addonService.resolvePlayback(track, addons);
    current = track;
    playingVia = stream.via ?? stream.quality;
    await player.setUrl(stream.url);
    await player.play();
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
