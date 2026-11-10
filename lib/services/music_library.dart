import 'dart:async';
import 'package:flutter/foundation.dart';
import 'orchid_account.dart';

/// Library entries are source-independent so saved songs survive addon changes.
class SavedSong {
  final String title;
  final String artist;
  final String? album;
  final String? artwork;
  final int? duration;
  const SavedSong(this.title, this.artist, {this.album, this.artwork, this.duration});

  String get key => '${artist.trim().toLowerCase()}|${title.trim().toLowerCase()}';
  Map<String, dynamic> toJson() => {
    'title': title, 'artist': artist,
    if (album != null) 'album': album,
    if (artwork != null) 'artwork': artwork,
    if (duration != null && duration! > 0) 'duration': duration,
  };
  factory SavedSong.fromJson(Map<String, dynamic> data) => SavedSong(
    (data['title'] ?? '').toString(),
    (data['artist'] ?? '').toString(),
    album: data['album']?.toString(),
    artwork: data['artwork']?.toString(),
    duration: data['duration'] is num ? (data['duration'] as num).toInt() : null,
  );
}

class PlaylistFolder {
  final String id;
  String name;
  PlaylistFolder({required this.id, required this.name});
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory PlaylistFolder.fromJson(Map<String, dynamic> json) =>
      PlaylistFolder(id: json['id'].toString(), name: json['name'].toString());
}

class MusicPlaylist {
  final String id;
  String name;
  bool pinned;
  String? folderId;
  String creator;
  DateTime createdAt;
  DateTime updatedAt;
  final List<SavedSong> songs;
  MusicPlaylist({
    required this.id, required this.name, this.pinned = false,
    this.folderId, this.creator = 'You',
    DateTime? createdAt, DateTime? updatedAt, List<SavedSong>? songs,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       songs = songs ?? [];
  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'pinned': pinned,
    'folderId': folderId, 'creator': creator,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'songs': songs.map((s) => s.toJson()).toList(),
  };
  factory MusicPlaylist.fromJson(Map<String, dynamic> data) => MusicPlaylist(
    id: data['id'].toString(),
    name: data['name'].toString(),
    pinned: data['pinned'] == true,
    folderId: data['folderId']?.toString(),
    creator: (data['creator'] ?? 'You').toString(),
    createdAt: DateTime.tryParse((data['createdAt'] ?? '').toString()),
    updatedAt: DateTime.tryParse((data['updatedAt'] ?? '').toString()),
    songs: (data['songs'] as List? ?? [])
        .whereType<Map>()
        .map((s) => SavedSong.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
  );
}

class MusicLibrary extends ChangeNotifier {
  static const libraryPlaylistId = '__orchid_saved_library__';

  MusicPlaylist get _savedLibrary {
    final existing = playlists.where((p) => p.id == libraryPlaylistId);
    if (existing.isNotEmpty) return existing.first;
    final created = MusicPlaylist(id: libraryPlaylistId, name: 'Library');
    playlists.insert(0, created);
    return created;
  }

  // Reading Library must not mutate playlists during an account load.
  List<SavedSong> get librarySongs {
    for (final playlist in playlists) {
      if (playlist.id == libraryPlaylistId) return playlist.songs;
    }
    return const <SavedSong>[];
  }
  List<MusicPlaylist> get visiblePlaylists =>
      playlists.where((p) => p.id != libraryPlaylistId).toList();
  bool isInLibrary(SavedSong song) =>
      librarySongs.any((s) => s.key == song.key);

  bool _includeInLibrary(SavedSong song) {
    final songs = _savedLibrary.songs;
    final index = songs.indexWhere((s) => s.key == song.key);
    if (index >= 0) {
      final existing = songs[index];
      if ((existing.duration == null || existing.duration! <= 0) &&
          song.duration != null && song.duration! > 0) {
        songs[index] = SavedSong(
          existing.title, existing.artist,
          album: existing.album ?? song.album,
          artwork: existing.artwork ?? song.artwork,
          duration: song.duration,
        );
        return true;
      }
      return false;
    }
    songs.insert(0, song);
    return true;
  }

  Future<void> addToLibrary(SavedSong song) async {
    if (_includeInLibrary(song)) await _save();
  }

  Future<void> removeFromLibrary(SavedSong song) async {
    final existing = playlists.where((p) => p.id == libraryPlaylistId);
    if (existing.isEmpty) return;
    existing.first.songs.removeWhere((s) => s.key == song.key);
    await _save();
  }
  final List<SavedSong> favorites = [];
  final List<MusicPlaylist> playlists = [];
  final List<PlaylistFolder> playlistFolders = [];
  final List<SavedSong> recentlyPlayed = [];
  /// Saved artists and playlists are explicit library entries.
  final Map<String, String?> savedArtists = {};
  final Set<String> savedPlaylistIds = {};

  String? _savedArtistKey(String artist) {
    final normalized = artist.trim().toLowerCase();
    for (final key in savedArtists.keys) {
      if (key.toLowerCase() == normalized) return key;
    }
    return null;
  }
  bool isArtistSaved(String artist) => _savedArtistKey(artist) != null;
  Future<void> toggleArtistSaved(String artist, {String? artwork}) async {
    final name = artist.trim();
    if (name.isEmpty) return;
    final existing = _savedArtistKey(name);
    if (existing != null) {
      savedArtists.remove(existing);
    } else {
      savedArtists[name] = artwork;
    }
    await _save();
  }

  bool isPlaylistSaved(MusicPlaylist playlist) =>
      savedPlaylistIds.contains(playlist.id);
  Future<void> togglePlaylistSaved(MusicPlaylist playlist) async {
    if (!savedPlaylistIds.add(playlist.id)) savedPlaylistIds.remove(playlist.id);
    await _save();
  }

  List<MusicPlaylist> get savedPlaylists =>
      visiblePlaylists.where(isPlaylistSaved).toList();

  OrchidAccount? _client;
  String? _account;
  bool loaded = false;
  bool _needsLibraryMigration = false;
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
    playlistFolders.clear();
    recentlyPlayed.clear();
    savedArtists.clear();
    savedPlaylistIds.clear();
    _revision = 0;
    loaded = false;
    _needsLibraryMigration = false;
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
        playlistFolders.addAll((data['playlistFolders'] as List? ?? [])
            .whereType<Map>()
            .map((p) => PlaylistFolder.fromJson(Map<String, dynamic>.from(p))));
        final rawArtists = data['savedArtists'];
        if (rawArtists is Map) {
          for (final entry in rawArtists.entries) {
            savedArtists[entry.key.toString()] = entry.value?.toString();
          }
        }
        savedPlaylistIds.addAll((data['savedPlaylistIds'] as List? ?? [])
            .map((id) => id.toString()));
        // Upgrade existing accounts once. After that, Library membership
        // is independent: removing a saved song must stay removed.
        final hadLibrary = playlists.any(
          (playlist) => playlist.id == libraryPlaylistId);
        if (!hadLibrary) {
          for (final song in [...favorites,
            for (final playlist in visiblePlaylists) ...playlist.songs]) {
            _includeInLibrary(song);
          }
        }
        _needsLibraryMigration = !hadLibrary && librarySongs.isNotEmpty;
      }
      _revision = (response['revision'] as num?)?.toInt() ?? 0;
    } catch (error) {
      debugPrint('[Orchid Library] Cloud library unavailable: $error');
    } finally {
      if (_account == account && generation == _loadGeneration) {
        loaded = true;
        notifyListeners();
        if (_needsLibraryMigration) {
          _needsLibraryMigration = false;
          // Persist the reserved playlist through the existing revisioned API.
          unawaited(_save().catchError((Object e) {
            debugPrint('[Orchid Library] Migration sync failed: $e');
          }));
        }
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
      'playlistFolders': playlistFolders.map((v) => v.toJson()).toList(),
      'savedArtists': savedArtists,
      'savedPlaylistIds': savedPlaylistIds.toList(),
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
      _includeInLibrary(song);
    }
    await _save();
  }

  Future<PlaylistFolder> createPlaylistFolder(String name) async {
    final folder = PlaylistFolder(
      id: 'folder_${DateTime.now().microsecondsSinceEpoch}_${_counter++}',
      name: name.trim(),
    );
    playlistFolders.add(folder);
    await _save();
    return folder;
  }

  Future<void> movePlaylistToFolder(MusicPlaylist playlist, String? folderId) async {
    if (playlist.id == libraryPlaylistId) return;
    playlist.folderId = folderId;
    playlist.updatedAt = DateTime.now();
    await _save();
  }

  Future<void> applyPlaylistOrder(List<MusicPlaylist> ordered) async {
    final movingIds = ordered.map((p) => p.id).toSet();
    final indices = <int>[];
    for (var i = 0; i < playlists.length; i++) {
      if (movingIds.contains(playlists[i].id)) indices.add(i);
    }
    if (indices.length != ordered.length) return;
    for (var i = 0; i < indices.length; i++) {
      playlists[indices[i]] = ordered[i];
    }
    await _save();
  }

  Future<void> movePlaylistBefore(
      MusicPlaylist moving, MusicPlaylist target) async {
    if (moving.id == target.id || moving.id == libraryPlaylistId ||
        target.id == libraryPlaylistId) return;
    if (!playlists.contains(moving) || !playlists.contains(target)) return;
    playlists.remove(moving);
    playlists.insert(playlists.indexOf(target), moving);
    await _save();
  }

  Future<void> reorderPlaylist(int oldIndex, int newIndex) async {
    final visible = visiblePlaylists;
    if (oldIndex < 0 || oldIndex >= visible.length ||
        newIndex < 0 || newIndex >= visible.length) return;
    final moving = visible[oldIndex];
    final target = visible[newIndex];
    final from = playlists.indexOf(moving);
    final to = playlists.indexOf(target);
    playlists.removeAt(from);
    playlists.insert(to, moving);
    await _save();
  }

  Future<void> deletePlaylistFolder(PlaylistFolder folder) async {
    playlistFolders.removeWhere((f) => f.id == folder.id);
    for (final p in visiblePlaylists) {
      if (p.folderId == folder.id) p.folderId = null;
    }
    await _save();
  }

  Future<MusicPlaylist> importPlaylist(
    String name, List<SavedSong> songs,
    {String creator = 'You', String? folderId},
  ) async {
    final unique = <String, SavedSong>{};
    for (final song in songs) {
      if (song.title.trim().isEmpty || song.artist.trim().isEmpty) continue;
      unique.putIfAbsent(song.key, () => song);
    }
    if (unique.isEmpty) throw const FormatException('No valid tracks to import');
    final playlist = MusicPlaylist(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_counter++}',
      name: name.trim(), creator: creator, folderId: folderId,
      songs: unique.values.toList(),
    );
    playlists.add(playlist);
    for (final song in unique.values) {
      _includeInLibrary(song);
    }
    await _save();
    return playlist;
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
    if (list.id == libraryPlaylistId) return;
    list.name = name.trim();
    list.updatedAt = DateTime.now();
    await _save();
  }

  Future<void> setPlaylistPinned(MusicPlaylist list, bool pinned) async {
    if (list.id == libraryPlaylistId) return;
    list.pinned = pinned;
    await _save();
  }

  Future<void> deletePlaylist(MusicPlaylist list) async {
    if (list.id == libraryPlaylistId) return;
    playlists.removeWhere((p) => p.id == list.id);
    savedPlaylistIds.remove(list.id);
    await _save();
  }

  bool contains(MusicPlaylist list, SavedSong song) =>
      list.songs.any((s) => s.key == song.key);

  Future<void> addToPlaylist(MusicPlaylist list, SavedSong song) async {
    if (list.id == libraryPlaylistId) {
      await addToLibrary(song);
      return;
    }
    if (!contains(list, song)) {
      list.songs.add(song);
      list.updatedAt = DateTime.now();
    }
    _includeInLibrary(song);
    await _save();
  }

  Future<void> removeFromPlaylist(MusicPlaylist list, SavedSong song) async {
    list.songs.removeWhere((s) => s.key == song.key);
    list.updatedAt = DateTime.now();
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
