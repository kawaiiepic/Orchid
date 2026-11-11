import 'dart:async';
import 'package:miniaudio_player/miniaudio_player.dart' as mini;

/// Stable Orchid-facing transport API. Backed by miniaudio's dual-deck engine,
/// not just_audio. The existing widgets and lock-screen handler use this
/// narrow facade instead of depending on a particular DSP backend.
enum OrchidProcessingState { idle, loading, buffering, ready, completed }

class OrchidPlayerState {
  final OrchidProcessingState processingState;
  final bool playing;
  const OrchidPlayerState(this.processingState, this.playing);
}

class OrchidAudioPlayer {
  final mini.MiniaudioPlayer<String> engine = mini.MiniaudioPlayer<String>(
    crossfadeConfig: mini.CrossfadeConfig(
      autoDuration: Duration.zero,
      manualDuration: const Duration(milliseconds: 250),
      curve: mini.CrossfadeCurve.equalPower,
    ),
    pauseOnDeviceChange: true,
  );
  final _state = StreamController<OrchidPlayerState>.broadcast();
  final _nextTracks = StreamController<String>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _activeKey;
  String? _preloadedKey;
  bool _disposed = false;
  OrchidAudioPlayer() {
    _subs.add(engine.stream.playbackState.listen((_) {
      _emitState();
    }));
    _subs.add(engine.stream.buffering.listen((_) {
      _emitState();
    }));
    _subs.add(engine.stream.completed.listen((_) {
      _emitState();
    }));
    _subs.add(engine.stream.playing.listen((_) {
      _emitState();
    }));
    _subs.add(engine.stream.currentItem.listen((item) {
      final key = item?.data;
      if (key == null || key == _activeKey) return;
      _activeKey = key;
      _preloadedKey = null;
      _nextTracks.add(key);
      _emitState();
    }));
  }
  Stream<String> get trackTransitions => _nextTracks.stream;
  Stream<OrchidPlayerState> get playerStateStream => _state.stream;
  Stream<Duration> get positionStream => engine.stream.position;
  Stream<Duration?> get durationStream =>
      engine.stream.duration;
  Stream<Duration> get bufferedPositionStream =>
      engine.stream.buffer.map((buffer) => buffer.end);
  Duration get position => engine.state.position;
  Duration? get duration => engine.state.duration;
  Duration get bufferedPosition => engine.state.buffer.end;
  bool get playing => engine.state.isPlaying;
  double get speed => engine.state.rate;
  OrchidProcessingState get processingState {
    if (engine.state.isCompleted) return OrchidProcessingState.completed;
    if (engine.state.isOpening) return OrchidProcessingState.loading;
    if (engine.state.isBuffering) return OrchidProcessingState.buffering;
    if (_activeKey == null) return OrchidProcessingState.idle;
    return OrchidProcessingState.ready;
  }

  void _emitState() {
    if (!_disposed) _state.add(OrchidPlayerState(processingState, playing));
  }

  Future<void> openTrack(String url, String key) async {
    _activeKey = key;
    _preloadedKey = null;
    await engine.action.setQueue([
      mini.AudioSource<String>(url, data: key),
    ]);
    _emitState();
  }

  bool canAdvanceTo(String key) => _preloadedKey == key;
  Future<void> preloadNext(String url, String key) async {
    if (_disposed || _preloadedKey == key || _activeKey == key) return;
    // A changed Play Next/queue order must replace the stale standby deck.
    if (_preloadedKey != null && _preloadedKey != key) {
      final oldIndex = (engine.state.currentIndex ?? -1) + 1;
      if (oldIndex >= 0 && oldIndex < engine.state.queue.length) {
        await engine.action.removeAt(oldIndex);
      }
      _preloadedKey = null;
    }
    await engine.action.append([
      mini.AudioSource<String>(url, data: key),
    ]);
    _preloadedKey = key;
  }

  Future<void> nextPrepared() => engine.action.next();
  Future<void> play() => engine.action.play();
  Future<void> pause() => engine.action.pause();
  Future<void> stop() => engine.action.stop();
  Future<void> seek(Duration value) => engine.action.seek(value);
  Future<void> setVolume(double v) => engine.action.setVolume(v);
  Future<void> setCrossfade(Duration v) =>
      engine.action.setCrossfade(mini.CrossfadeConfig(
        autoDuration: v,
        manualDuration: const Duration(milliseconds: 250),
        curve: mini.CrossfadeCurve.equalPower,
      ));
  Future<void> setNormalization(bool value) =>
      engine.action.setVolumeNormalization(value);
  Future<void> setRepeatOne(bool enabled) => engine.action
      .setLoopMode(enabled ? mini.LoopMode.one : mini.LoopMode.off);
  final List<double> _eqGains = List<double>.filled(10, 0);
  Future<void> setEq(List<double> gains) async {
    _eqGains.setAll(0, gains);
    await engine.action.setEqualizer(mini.Equalizer.fromList(_eqGains));
  }
  Future<void> setEqBand(int band, double db) async {
    _eqGains[band] = db;
    await engine.action.setEqualizer(mini.Equalizer.fromList(_eqGains));
  }
  Future<List<mini.AudioDevice>> getAudioDevices() async =>
      engine.state.globalOutputDevices;
  Future<void> setAudioDevice(mini.AudioDevice device) =>
      engine.action.setOutputs({
        mini.AudioOutput(deviceId: device.isAuto ? null : device.id),
      });
  Future<void> dispose() async {
    _disposed = true;
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _state.close();
    await _nextTracks.close();
    await engine.dispose();
  }
}
