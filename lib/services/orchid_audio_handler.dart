import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../models/addon.dart';
import 'player_service.dart';
import 'apple_artwork_service.dart';

/// Bridges Orchid's existing just_audio player to Android media controls,
/// lock-screen artwork, headset buttons and iOS Control Center.
/// Playback and queue ownership remain in PlayerService.
class OrchidAudioHandler extends BaseAudioHandler {
  PlayerService? _service;
  int _artworkGeneration = 0;
  AudioSession? _session;
  StreamSubscription<ja.PlayerState>? _playbackSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _bufferedSubscription;
  Future<void> configureSession() async {
    _session = await AudioSession.instance;
    // just_audio already handles interruptions and headphone disconnects.
    // Configure the OS session once without installing duplicate listeners.
    await _session!.configure(AudioSessionConfiguration.music());
  }

  void attach(PlayerService service) {
    detach();
    _service = service;
    service.addListener(_sync);
    _playbackSubscription = service.player.playerStateStream.listen((_) => _sync());
    _positionSubscription = service.player.positionStream.listen((_) => _sync());
    _durationSubscription = service.player.durationStream.listen((_) => _sync());
    _bufferedSubscription = service.player.bufferedPositionStream.listen((_) => _sync());
    _sync();
  }

  void detach() {
    final service = _service;
    if (service != null) service.removeListener(_sync);
    _service = null;
    ++_artworkGeneration;
    unawaited(_playbackSubscription?.cancel() ?? Future<void>.value());
    unawaited(_positionSubscription?.cancel() ?? Future<void>.value());
    unawaited(_durationSubscription?.cancel() ?? Future<void>.value());
    unawaited(_bufferedSubscription?.cancel() ?? Future<void>.value());
    _playbackSubscription = null;
    _positionSubscription = null;
    _durationSubscription = null;
    _bufferedSubscription = null;
    mediaItem.add(null);
    queue.add(const []);
    playbackState.add(PlaybackState(
      processingState: AudioProcessingState.idle,
    ));
  }

  MediaItem _itemFor(TrackResult track, {Duration? actualDuration}) {
    final artwork = Uri.tryParse(track.artworkUrl ?? '');
    return MediaItem(
      id: '${track.sourceId}:${track.id}',
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: actualDuration ??
          (track.duration != null && track.duration! > 0
              ? Duration(seconds: track.duration!)
              : null),
      artUri: artwork != null &&
              (artwork.scheme == 'https' || artwork.scheme == 'http')
          ? artwork
          : null,
    );
  }

  Future<void> _findLockscreenArtwork(
      TrackResult track, String id, int generation) async {
    try {
      // Share the same exact-match artwork lookup used by Orchid's covers.
      final url = await AppleArtworkService.instance.trackOrAlbum(
        artist: track.artist,
        title: track.title,
        album: track.album,
      );
      if (url == null || generation != _artworkGeneration ||
          mediaItem.valueOrNull?.id != id) return;
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https') return;
      final previous = mediaItem.valueOrNull;
      if (previous != null) mediaItem.add(previous.copyWith(artUri: uri));
    } catch (e) {
      debugPrint('[Orchid Audio] Lock-screen cover lookup failed: $e');
    }
  }

  void _sync() {
    final service = _service;
    if (service == null) return;
    final player = service.player;
    final track = service.current;
    // Avoid regenerating album art downloads on every position update.
    final previous = mediaItem.valueOrNull;
    final id = track == null ? null : '${track.sourceId}:${track.id}';
    if (track == null) {
      if (previous != null) mediaItem.add(null);
    } else if (previous?.id != id || previous?.duration !=
        (player.duration ?? (track.duration == null
            ? null : Duration(seconds: track.duration!)))) {
      final updated = _itemFor(track, actualDuration: player.duration);
      // Preserve asynchronously loaded cover art when duration changes.
      mediaItem.add(previous?.id == id && previous?.artUri != null &&
              updated.artUri == null
          ? updated.copyWith(artUri: previous!.artUri)
          : updated);
      if (previous?.id != id && (track.artworkUrl == null ||
          track.artworkUrl!.trim().isEmpty)) {
        final generation = ++_artworkGeneration;
        unawaited(_findLockscreenArtwork(track, id!, generation));
      }
    }

    final items = service.queue.map((t) => _itemFor(t)).toList();
    final old = queue.valueOrNull ?? const <MediaItem>[];
    if (old.length != items.length ||
        !listEquals(old.map((e) => e.id).toList(),
            items.map((e) => e.id).toList())) {
      queue.add(items);
    }

    final controls = <MediaControl>[
      if (service.hasPrevious) MediaControl.skipToPrevious,
      player.playing ? MediaControl.pause : MediaControl.play,
      if (service.hasNext) MediaControl.skipToNext,
    ];
    final state = switch (player.processingState) {
      ja.ProcessingState.idle => AudioProcessingState.idle,
      ja.ProcessingState.loading => AudioProcessingState.loading,
      ja.ProcessingState.buffering => AudioProcessingState.buffering,
      ja.ProcessingState.ready => AudioProcessingState.ready,
      ja.ProcessingState.completed => AudioProcessingState.completed,
    };
    playbackState.add(PlaybackState(
      controls: controls,
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices:
          List<int>.generate(controls.length, (i) => i),
      processingState: service.resolving ? AudioProcessingState.loading : state,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: service.queueIndex >= 0 &&
                  service.queueIndex < service.queue.length
          ? service.queueIndex
          : null,
    ));
  }

  @override
  Future<void> play() async {
    final service = _service;
    if (service == null) return;
    if (await (_session?.setActive(true) ?? Future.value(true))) {
      await service.player.play();
    }
  }

  @override
  Future<void> pause() async {
    await _service?.player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _service?.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    await _service?.playNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _service?.playPrevious();
  }

  @override
  Future<void> stop() async {
    await _service?.player.stop();
    _sync();
  }

  void disposeHandler() {
    detach();
  }
}

/// Initialized only on iOS and Android, leaving desktop playback unchanged.
class OrchidBackgroundAudio {
  static OrchidAudioHandler? handler;

  static Future<void> initialize() async {
    if (handler != null) return;
    handler = await AudioService.init<OrchidAudioHandler>(
      builder: OrchidAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.blossomvale.orchid.playback',
        androidNotificationChannelName: 'Orchid music playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
      ),
    );
    await handler!.configureSession();
  }

  static void attach(PlayerService service) => handler?.attach(service);
  static void detach() => handler?.detach();
}
