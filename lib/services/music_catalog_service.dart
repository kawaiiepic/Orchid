import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/addon.dart';
import 'orchid_account.dart';

class MusicAlbum {
  final int id;
  final String title;
  final String artist;
  final String? artwork;
  final int? trackCount;
  final String releaseType;
  const MusicAlbum({
    required this.id, required this.title, required this.artist,
    this.artwork, this.trackCount, this.releaseType = 'album',
  });
}

class ArtistCatalog {
  final String name;
  final List<MusicAlbum> albums;
  final List<TrackResult> songs;
  final List<String> genres;
  final int? monthlyListeners;
  final String? biography;
  final List<String> similarArtists;
  final List<ArtistMusicVideo> musicVideos;
  const ArtistCatalog({
    required this.name, required this.albums, required this.songs,
    this.genres = const [], this.monthlyListeners, this.biography,
    this.similarArtists = const [], this.musicVideos = const [],
  });
}

class ArtistMusicVideo {
  final String title;
  final String? artwork;
  final String? url;
  const ArtistMusicVideo({required this.title, this.artwork, this.url});
}

/// iTunes catalog metadata is separate from playback sources.
/// Full albums and artist catalogs do not depend on recent scrobbles.
class MusicCatalogService {
  static final MusicCatalogService instance = MusicCatalogService._();
  MusicCatalogService._();

  final http.Client _client = http.Client();
  final Map<String, Future<ArtistCatalog>> _artists = {};
  final Map<String, Future<List<TrackResult>>> _albums = {};

  String _norm(String s) => s
      .toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  String? _art(dynamic raw) => raw is String
      ? raw.replaceAll('100x100bb', '600x600bb')
      : null;

  Future<List<dynamic>> _request(Uri uri) async {
    final response = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Music catalog HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is! Map) return [];
    return data['results'] is List ? data['results'] as List : [];
  }

  TrackResult? _song(Map<String, dynamic> item) {
    if (item['wrapperType'] != 'track' || item['kind'] != 'song') return null;
    final title = (item['trackName'] ?? '').toString();
    final artist = (item['artistName'] ?? '').toString();
    if (title.isEmpty || artist.isEmpty) return null;
    return TrackResult(
      id: (item['trackId'] ?? '').toString(),
      title: title, artist: artist,
      album: item['collectionName']?.toString(),
      duration: item['trackTimeMillis'] is num
          ? ((item['trackTimeMillis'] as num) / 1000).round() : null,
      artworkUrl: _art(item['artworkUrl100']),
      previewUrl: item['previewUrl'] as String?,
      sourceId: 'itunes', sourceName: 'iTunes',
    );
  }

  MusicAlbum? _album(Map<String, dynamic> item) {
    if (item['wrapperType'] != 'collection' ||
        item['collectionType'] != 'Album') {
      return null;
    }
    final id = item['collectionId'];
    if (id is! num) return null;
    return MusicAlbum(
      id: id.toInt(),
      title: (item['collectionName'] ?? '').toString(),
      artist: (item['artistName'] ?? '').toString(),
      artwork: _art(item['artworkUrl100']),
      trackCount: (item['trackCount'] as num?)?.toInt(),
      releaseType: _releaseType((item['collectionName'] ?? '').toString(),
        (item['trackCount'] as num?)?.toInt()),
    );
  }

  String _releaseType(String title, int? trackCount, {bool single = false}) {
    final lower = title.toLowerCase();
    if (single || lower.endsWith(' - single') ||
        (trackCount != null && trackCount <= 3)) return 'single';
    if (lower.endsWith(' - ep') ||
        (trackCount != null && trackCount >= 4 && trackCount <= 6)) {
      return 'ep';
    }
    return 'album';
  }

  /// Canonical Apple catalog search results; playback remains addon-backed.
  Future<List<TrackResult>> searchTracks(String query) async {
    final results = await _request(Uri.https('itunes.apple.com', '/search', {
      'term': query, 'entity': 'song', 'media': 'music', 'limit': '100',
    }));
    final seen = <String>{};
    return results.whereType<Map>().map((item) =>
        _song(Map<String, dynamic>.from(item)))
        .whereType<TrackResult>()
        .where((track) => seen.add(
          '${_norm(track.artist)}|${_norm(track.title)}|${_norm(track.album ?? '')}'))
        .toList();
  }

  /// Search catalog entities independently of track searches.
  Future<List<MusicAlbum>> searchAlbums(String query) async {
    final results = await _request(Uri.https('itunes.apple.com', '/search', {
      'term': query, 'entity': 'album', 'media': 'music', 'limit': '50',
    }));
    final seen = <int>{};
    return results.whereType<Map>().map((item) =>
        _album(Map<String, dynamic>.from(item)))
        .whereType<MusicAlbum>().where((album) => seen.add(album.id))
        .toList();
  }

  Future<List<String>> searchArtists(String query) async {
    final results = await _request(Uri.https('itunes.apple.com', '/search', {
      'term': query, 'entity': 'musicArtist', 'media': 'music', 'limit': '50',
    }));
    final seen = <String>{};
    return results.whereType<Map>().map((item) =>
        (item['artistName'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty && seen.add(_norm(name)))
        .toList();
  }

  /// Artist details from the authenticated Apple Music API. Unlike the
  /// public iTunes endpoints, this shares the catalog's backend proxy.
  Future<ArtistCatalog> appleArtist(OrchidAccount account, String name) async {
    final data=await account.appleArtist(name);
    final albums=<MusicAlbum>[];
    final songs=<TrackResult>[];
    final rawAlbums=data['albums'];
    if(rawAlbums is List) {
      for(final raw in rawAlbums.whereType<Map>()) {
        final item=Map<String,dynamic>.from(raw);
        final id=int.tryParse(item['id']?.toString()??'');
        if(id==null)continue;
        albums.add(MusicAlbum(
          id:id,title:item['title']?.toString()??'',
          artist:item['artist']?.toString()??name,
          artwork:item['image']?.toString(),
          trackCount:item['trackCount'] is num
              ?(item['trackCount'] as num).toInt():null,
          releaseType:_releaseType(item['title']?.toString() ?? '',
            (item['trackCount'] as num?)?.toInt(),
            single:item['isSingle']==true),
        ));
      }
    }
    final rawTracks=data['tracks'];
    if(rawTracks is List) {
      for(final raw in rawTracks.whereType<Map>()) {
        final item=Map<String,dynamic>.from(raw);
        songs.add(TrackResult(
          id:item['id']?.toString()??'',
          title:item['title']?.toString()??'',
          artist:item['artist']?.toString()??name,
          album:item['album']?.toString(),
          artworkUrl:item['image']?.toString(),
          duration:item['duration'] is num
              ?(item['duration'] as num).toInt():null,
          sourceId:'apple-music',sourceName:'Apple Music',
        ));
      }
    }
    List<String> strings(dynamic value) => value is List
        ? value.whereType<String>().where((text) => text.trim().isNotEmpty)
            .toList()
        : const <String>[];
    final rawVideos = data['musicVideos'];
    final videos = <ArtistMusicVideo>[];
    if (rawVideos is List) {
      for (final raw in rawVideos.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final title = item['title']?.toString() ?? '';
        if (title.isEmpty) continue;
        videos.add(ArtistMusicVideo(
          title: title,
          artwork: item['image']?.toString(),
          url: item['url']?.toString(),
        ));
      }
    }
    return ArtistCatalog(
      name:name, albums:albums, songs:songs,
      genres:strings(data['genres']),
      monthlyListeners:(data['monthlyListeners'] as num?)?.toInt(),
      biography:data['biography']?.toString(),
      similarArtists:strings(data['similarArtists']),
      musicVideos:videos,
    );
  }

  Future<ArtistCatalog> artist(String artist, {bool refresh = false}) {
    final key = _norm(artist);
    if (refresh) _artists.remove(key);
    return _artists.putIfAbsent(key, () => _loadArtist(artist));
  }

  Future<ArtistCatalog> _loadArtist(String artist) async {
    final found = await _request(Uri.https('itunes.apple.com', '/search', {
      'term': artist,
      'entity': 'musicArtist',
      'limit': '50',
    }));
    int? id;
    for (final item in found) {
      if (item is! Map) continue;
      final artistName = (item['artistName'] ?? '').toString();
      if (_norm(artistName) == _norm(artist) && item['artistId'] is num) {
        id = (item['artistId'] as num).toInt();
        break;
      }
    }
    if (id == null) {
      return ArtistCatalog(name: artist, albums: const [], songs: const []);
    }

    Future<List<MusicAlbum>> loadAlbums() async {
      final results = await _request(Uri.https('itunes.apple.com', '/lookup', {
        'id': '$id', 'entity': 'album', 'limit': '200',
      }));
      final seen = <int>{};
      return results.whereType<Map>().map((v) =>
          _album(Map<String, dynamic>.from(v))).whereType<MusicAlbum>()
          .where((v) => seen.add(v.id)).toList();
    }

    Future<List<TrackResult>> loadSongs() async {
      final results = await _request(Uri.https('itunes.apple.com', '/lookup', {
        'id': '$id', 'entity': 'song', 'limit': '200',
      }));
      final seen = <String>{};
      return results.whereType<Map>().map((v) =>
          _song(Map<String, dynamic>.from(v))).whereType<TrackResult>()
          .where((v) => seen.add('${_norm(v.title)}|${_norm(v.artist)}'))
          .toList();
    }

    final data = await Future.wait<dynamic>([loadAlbums(), loadSongs()]);
    return ArtistCatalog(
      name: artist,
      albums: data[0] as List<MusicAlbum>,
      songs: data[1] as List<TrackResult>,
    );
  }

  Future<List<TrackResult>> album(String artist, String album,
      {int? collectionId, bool refresh = false}) {
    final key = '${_norm(artist)}|${_norm(album)}';
    if (refresh) _albums.remove(key);
    return _albums.putIfAbsent(key, () =>
        _loadAlbum(artist, album, collectionId: collectionId));
  }

  Future<List<TrackResult>> _loadAlbum(
    String artist, String album, {int? collectionId}
  ) async {
    var id = collectionId;
    if (id == null) {
      final results = await _request(Uri.https('itunes.apple.com', '/search', {
        'term': '$artist $album', 'entity': 'album', 'limit': '80',
      }));
      for (final item in results) {
        if (item is! Map) continue;
        if (_norm((item['collectionName'] ?? '').toString()) == _norm(album) &&
            _norm((item['artistName'] ?? '').toString()) == _norm(artist) &&
            item['collectionId'] is num) {
          id = (item['collectionId'] as num).toInt();
          break;
        }
      }
    }
    if (id == null) return [];
    final results = await _request(Uri.https('itunes.apple.com', '/lookup', {
      'id': '$id', 'entity': 'song', 'limit': '200',
    }));
    final seen = <String>{};
    return results.whereType<Map>().map((v) =>
        _song(Map<String, dynamic>.from(v))).whereType<TrackResult>()
        .where((v) => seen.add(v.id)).toList();
  }
}
