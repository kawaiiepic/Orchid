import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/addon.dart';
import 'animated_artwork_service.dart';
import 'apple_artwork_service.dart';

/// iOS 26 Now Playing animation. Regular lock-screen metadata remains owned by
/// audio_service; this updates only Apple's animated-artwork property.
class IosAnimatedNowPlaying {
  static const _channel =
      MethodChannel('dev.blossomvale.orchid/animated-now-playing');
  String? _trackId;
  int _revision = 0;
  bool _ready = false;
  Timer? _refresh;
  DateTime? _lastRefresh;
  bool _disposed = false;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  void update(TrackResult? track, String? id) {
    if (!_supported || _disposed) return;
    if (id != _trackId) {
      _trackId = id;
      _ready = false;
      _refresh?.cancel();
      _lastRefresh = null;
      final revision = ++_revision;
      unawaited(_invoke('clear'));
      if (track != null && id != null) {
        unawaited(_load(track, id, revision));
      }
      return;
    }
    if (!_ready || track == null || id == null) return;
    final now = DateTime.now();
    if (_lastRefresh != null &&
        now.difference(_lastRefresh!) < const Duration(seconds: 3)) return;
    _lastRefresh = now;
    _scheduleRefresh(id);
  }

  void _scheduleRefresh(String id) {
    _refresh?.cancel();
    _refresh = Timer(const Duration(milliseconds: 350), () {
      if (!_disposed && _ready && _trackId == id) {
        unawaited(_invoke('refresh'));
      }
    });
  }

  Future<void> _load(TrackResult track, String id, int revision) async {
    try {
      final animation = await AnimatedArtworkService.instance.fetch(
        artist: track.artist, album: track.album, title: track.title);
      final video = animation?.squareUrl;
      if (video == null || _disposed || revision != _revision) return;
      var preview = track.artworkUrl;
      if (preview == null || !preview.startsWith('https://')) {
        preview = await AppleArtworkService.instance.trackOrAlbum(
          artist: track.artist, title: track.title, album: track.album);
      }
      if (preview == null || !preview.startsWith('https://') ||
          _disposed || revision != _revision) return;
      await _invoke('set', <String, String>{
        'id': id, 'title': track.title, 'artist': track.artist,
        'video': video, 'preview': preview,
      });
      if (_disposed || revision != _revision) return;
      _ready = true;
      _lastRefresh = null;
      _scheduleRefresh(id);
    } catch (error) {
      debugPrint('[Orchid Artwork] Lock-screen animation failed: $error');
    }
  }

  Future<void> _invoke(String method, [Map<String, String>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // iOS versions without the native animation bridge use static artwork.
    } catch (error) {
      debugPrint('[Orchid Artwork] Now Playing $method: $error');
    }
  }

  void dispose() {
    _disposed = true;
    _trackId = null;
    ++_revision;
    _refresh?.cancel();
    if (_supported) unawaited(_invoke('clear'));
  }
}
