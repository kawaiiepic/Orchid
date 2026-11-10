import 'package:share_plus/share_plus.dart';

import '../models/addon.dart';

/// Public links only. Never share private streaming or addon playback URLs.
abstract final class OrchidShare {
  static Uri? _publicUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    if (host == 'music.apple.com' ||
        host == 'open.spotify.com' ||
        host == 'www.youtube.com' ||
        host == 'youtube.com' ||
        host == 'youtu.be' ||
        host == 'music.youtube.com') return uri;
    return null;
  }

  static Uri songUrl(TrackResult track) {
    final canonical = _publicUrl(track.shareUrl);
    if (canonical != null) return canonical;

    final spotify = track.spotifyTrackId;
    if (spotify != null &&
        RegExp(r'^[a-zA-Z0-9]{22}$').hasMatch(spotify)) {
      return Uri.https('open.spotify.com', '/track/$spotify');
    }

    final video = track.videoId;
    if (video != null &&
        RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(video)) {
      return Uri.https('music.youtube.com', '/watch', {'v': video});
    }

    final source = track.sourceId.toLowerCase();
    final id = track.id.trim();
    if ((source == 'itunes' || source == 'apple-music') &&
        RegExp(r'^\d+$').hasMatch(id)) {
      return Uri.https('music.apple.com', '/us/song/id$id');
    }

    // No verified catalog identity: share a useful search, not a fabricated ID.
    return Uri.https('music.apple.com', '/us/search', {
      'term': '${track.artist} ${track.title}',
    });
  }

  static Uri albumUrl(int? id, String artist, String album) {
    if (id != null && id > 0) {
      return Uri.https('music.apple.com', '/us/album/id$id');
    }
    return Uri.https('music.apple.com', '/us/search', {
      'term': '$artist $album',
    });
  }

  static Uri artistSearchUrl(String artist) => Uri.https(
    'music.apple.com', '/us/search', {'term': artist},
  );

  static Future<void> song(TrackResult track) async {
    await Share.share(songUrl(track).toString());
  }

  static Future<void> album(int? id, String artist, String album) async {
    await Share.share(albumUrl(id, artist, album).toString());
  }

  static Future<void> artist(String artist) async {
    await Share.share(artistSearchUrl(artist).toString());
  }
}
