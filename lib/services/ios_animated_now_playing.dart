import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/addon.dart';
import 'animated_artwork_service.dart';
import 'apple_artwork_service.dart';
import 'player_service.dart';

/// Temporary iOS 26 diagnostic path: the Swift bridge exclusively owns
/// MPNowPlayingInfoCenter, removing audio_service's competing metadata writer.
/// Android and older iOS versions keep the existing audio_service implementation.
class IosAnimatedNowPlaying {
  static const _channel =
      MethodChannel('dev.blossomvale.orchid/animated-now-playing');

  static Future<bool> probeNativeMode() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _channel.invokeMethod<bool>('nativeAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('[Orchid Artwork] Native mode unavailable: $error');
      return false;
    }
  }

  PlayerService? _service;
  String? _trackId;
  int _revision = 0;
  int _metadataRevision = 0;
  Timer? _refresh;
  StreamSubscription<dynamic>? _position;
  StreamSubscription<dynamic>? _state;
  bool _disposed = false;

  void attach(PlayerService service) {
    detach();
    _disposed = false;
    _service = service;
    _channel.setMethodCallHandler(_remoteCommand);
    service.addListener(_sync);
    _position = service.player.positionStream.listen((_) => _sync());
    _state = service.player.playerStateStream.listen((_) => _sync());
    _sync();
  }

  Future<void> _remoteCommand(MethodCall call) async {
    final player = _service;
    if (player == null) return;
    switch (call.method) {
      case 'play':
        await player.player.play();
      case 'pause':
        await player.player.pause();
      case 'next':
        await player.playNext();
      case 'previous':
        await player.playPrevious();
      case 'seek':
        final value = call.arguments;
        if (value is num) {
          await player.seek(Duration(milliseconds: (value.toDouble() * 1000).round()));
        }
    }
  }

  void _sync() {
    if (_disposed) return;
    final service = _service;
    if (service == null) return;
    final track = service.current;
    final id = track == null ? null : '${track.sourceId}:${track.id}';
    if (id != _trackId) {
      _trackId = id;
      final revision = ++_revision;
      _refresh?.cancel();
      if (track != null && id != null) {
        unawaited(_load(track, id, revision));
      }
    }

    if (track == null) {
      unawaited(_invoke('clear'));
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _metadataRevision < 900) return;
    _metadataRevision = now;
    unawaited(_invoke('nowPlaying', <String, dynamic>{
      'id': id,
      'title': track.title,
      'artist': track.artist,
      'album': track.album,
      'artwork': track.artworkUrl ?? '',
      'duration': (service.player.duration?.inMilliseconds ??
          ((track.duration ?? 0) * 1000)) / 1000,
      'elapsed': service.player.position.inMilliseconds / 1000,
      'playing': service.player.playing,
      'rate': service.player.speed,
    }));
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
      await _invoke('set', <String, dynamic>{
        'id': id, 'title': track.title, 'artist': track.artist,
        'video': video, 'preview': preview,
      });
      if (_disposed || revision != _revision) return;
      _refresh = Timer(const Duration(seconds: 2), () {
        if (!_disposed && _trackId == id) unawaited(_invoke('refresh'));
      });
      unawaited(Future<void>.delayed(const Duration(seconds: 8), () async {
        if (_disposed || revision != _revision || _trackId != id) return;
        try {
          final status = await _channel.invokeMapMethod<String, dynamic>('status');
          debugPrint('[Orchid Artwork] Native Now Playing status: $status');
        } catch (error) {
          debugPrint('[Orchid Artwork] Native Now Playing status failed: $error');
        }
      }));
    } catch (error) {
      debugPrint('[Orchid Artwork] Animated cover lookup failed: $error');
    }
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (error) {
      debugPrint('[Orchid Artwork] Native Now Playing $method failed: $error');
    }
  }

  void detach() {
    final service = _service;
    if (service != null) service.removeListener(_sync);
    _service = null;
    ++_revision;
    _trackId = null;
    _refresh?.cancel();
    _position?.cancel();
    _state?.cancel();
    _channel.setMethodCallHandler(null);
    unawaited(_invoke('clear'));
  }

  void dispose() {
    detach();
    _disposed = true;
  }
}
