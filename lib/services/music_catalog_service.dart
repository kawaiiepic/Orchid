import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/addon.dart';

class MusicAlbum {
  final int id;
  final String title;
  final String artist;
  final String? artwork;
  final int? trackCount;
  const MusicAlbum({
    required this.id, required this.title, required this.artist,
    this.artwork, this.trackCount,
  });
}

class ArtistCatalog {
  final String name;
  final List<MusicAlbum> albums;
  final List<TrackResult> songs;
  const ArtistCatalog({
    required this.name, required this.albums, required this.songs,
  });
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
        item['collectionType'] != 'Album') return null;
    final id = item['collectionId'];
    if (id is! num) return null;
    return MusicAlbum(
      id: id.toInt(),
      title: (item['collectionName'] ?? '').toString(),
      artist: (item['artistName'] ?? '').toString(),
      artwork: _art(item['artworkUrl100']),
      trackCount: (item['trackCount'] as num?)?.toInt(),
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
