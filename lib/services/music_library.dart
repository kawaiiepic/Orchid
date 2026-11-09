import 'dart:async';
import 'package:flutter/foundation.dart';
import 'orchid_account.dart';

/// Library entries are source-independent so saved songs survive addon changes.
class SavedSong {
  final String title;
  final String artist;
  final String? album;
  final String? artwork;
  const SavedSong(this.title, this.artist, {this.album, this.artwork});

  String get key => '${artist.trim().toLowerCase()}|${title.trim().toLowerCase()}';
  Map<String, dynamic> toJson() => {
    'title': title, 'artist': artist,
    if (album != null) 'album': album,
    if (artwork != null) 'artwork': artwork,
  };
  factory SavedSong.fromJson(Map<String, dynamic> data) => SavedSong(
    (data['title'] ?? '').toString(),
    (data['artist'] ?? '').toString(),
    album: data['album']?.toString(),
    artwork: data['artwork']?.toString(),
  );
}

class MusicPlaylist {
  final String id;
  String name;
  bool pinned;
  final List<SavedSong> songs;
  MusicPlaylist({required this.id, required this.name, this.pinned = false, List<SavedSong>? songs})
      : songs = songs ?? [];
  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'pinned': pinned,
    'songs': songs.map((s) => s.toJson()).toList(),
  };
  factory MusicPlaylist.fromJson(Map<String, dynamic> data) => MusicPlaylist(
    id: data['id'].toString(),
    name: data['name'].toString(),
    pinned: data['pinned'] == true,
    songs: (data['songs'] as List? ?? [])
        .whereType<Map>()
        .map((s) => SavedSong.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
  );
}

class MusicLibrary extends ChangeNotifier {
  final List<SavedSong> favorites = [];
  final List<MusicPlaylist> playlists = [];
  final List<SavedSong> recentlyPlayed = [];
  OrchidAccount? _client;
  String? _account;
  bool loaded = false;
  int _counter = 0;
  int _revision = 0;
  int _loadGeneration = 0;
  Future<void> _pendingSave = Future<void>.value();

  void configure(OrchidAccount account) => _client = account;

  Future<void> setAccount(String? account) async {
    if (_account == account && loaded) return;
    _account = account;
    final generation = ++_loadGeneration;
    favorites.clear();
    playlists.clear();
    recentlyPlayed.clear();
    _revision = 0;
    loaded = false;
    notifyListeners();
    if (account == null) return;
    final api = _client;
    if (api == null) {
      debugPrint('[Orchid Library] Missing account service');
      return;
    }
    try {
      final response = await api.loadLibrary();
      if (_account != account || generation != _loadGeneration) return;
      final raw = response['library'];
      if (raw is Map) {
        final data = Map<String, dynamic>.from(raw);
        favorites.addAll((data['favorites'] as List? ?? [])
            .whereType<Map>()
            .map((s) => SavedSong.fromJson(Map<String, dynamic>.from(s))));
        playlists.addAll((data['playlists'] as List? ?? [])
            .whereType<Map>()
            .map((p) => MusicPlaylist.fromJson(Map<String, dynamic>.from(p))));
      }
      _revision = (response['revision'] as num?)?.toInt() ?? 0;
    } catch (error) {
      debugPrint('[Orchid Library] Cloud library unavailable: $error');
    } finally {
      if (_account == account && generation == _loadGeneration) {
        loaded = true;
        notifyListeners();
      }
    }
  }

  Future<void> _save() async {
    final account = _account;
    final api = _client;
    notifyListeners();
    if (account == null || api == null || !loaded) return;
    final snapshot = <String, dynamic>{
      'favorites': favorites.map((v) => v.toJson()).toList(),
      'playlists': playlists.map((v) => v.toJson()).toList(),
    };
    final generation = _loadGeneration;
    final previous = _pendingSave;
    final done = Completer<void>();
    _pendingSave = done.future;
    try {
      await previous.catchError((Object _) {});
      if (_account != account || generation != _loadGeneration) return;
      final result = await api.saveLibrary(snapshot, _revision);
      if (_account == account && generation == _loadGeneration) {
        _revision = (result['revision'] as num?)?.toInt() ?? _revision + 1;
      }
    } catch (error) {
      debugPrint('[Orchid Library] Could not sync account library: $error');
      rethrow;
    } finally {
      done.complete();
    }
  }

  bool isFavorite(SavedSong song) => favorites.any((s) => s.key == song.key);
  Future<void> toggleFavorite(SavedSong song) async {
    final index = favorites.indexWhere((s) => s.key == song.key);
    if (index >= 0) {
      favorites.removeAt(index);
    } else {
      favorites.insert(0, song);
    }
    await _save();
  }

  Future<MusicPlaylist> createPlaylist(String name) async {
    final playlist = MusicPlaylist(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_counter++}',
      name: name.trim(),
    );
    playlists.add(playlist);
    await _save();
    return playlist;
  }

  Future<void> renamePlaylist(MusicPlaylist list, String name) async {
    list.name = name.trim();
    await _save();
  }

  Future<void> setPlaylistPinned(MusicPlaylist list, bool pinned) async {
    list.pinned = pinned;
    await _save();
  }

  Future<void> deletePlaylist(MusicPlaylist list) async {
    playlists.removeWhere((p) => p.id == list.id);
    await _save();
  }

  bool contains(MusicPlaylist list, SavedSong song) =>
      list.songs.any((s) => s.key == song.key);

  Future<void> addToPlaylist(MusicPlaylist list, SavedSong song) async {
    if (!contains(list, song)) list.songs.add(song);
    await _save();
  }

  Future<void> removeFromPlaylist(MusicPlaylist list, SavedSong song) async {
    list.songs.removeWhere((s) => s.key == song.key);
    await _save();
  }

  Future<void> recordPlay(SavedSong song) async {
    recentlyPlayed.removeWhere((s) => s.key == song.key);
    recentlyPlayed.insert(0, song);
    if (recentlyPlayed.length > 120) recentlyPlayed.removeRange(120, recentlyPlayed.length);
    // Listening history is persisted through /orchid/history by PlayerService.
    // A playback event should never overwrite the account's library snapshot.
    notifyListeners();
  }

  /// Daily mixes use known listening history, without inventing recommendations.
  /// Deterministic daily rotation keeps the same order all day.
  List<SavedSong> dailyMix(int index, List<SavedSong> lastfmSongs) {
    final pool = <String, SavedSong>{};
    for (final s in [...favorites, ...recentlyPlayed, ...lastfmSongs]) {
      if (s.title.isNotEmpty && s.artist.isNotEmpty) pool.putIfAbsent(s.key, () => s);
    }
    final songs = pool.values.toList();
    if (songs.isEmpty) return [];
    final today = DateTime.now();
    final day = today.year * 372 + today.month * 31 + today.day;
    if (index == 0) {
      songs.sort((a, b) {
        final af = isFavorite(a) ? 0 : 1;
        final bf = isFavorite(b) ? 0 : 1;
        return af.compareTo(bf);
      });
    } else if (index == 1) {
      songs.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
    } else {
      songs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    final offset = (day + index * 7) % songs.length;
    return [...songs.skip(offset), ...songs.take(offset)].take(30).toList();
  }
}
