import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Retrieves high-resolution static cover art from Apple's public iTunes catalog.
/// A match must have the same normalized artist and song/album name.
class AppleArtworkService {
  AppleArtworkService._();
  static final AppleArtworkService instance = AppleArtworkService._();

  final Map<String, Future<String?>> _requests = {};

  String _normalize(String value) => value.toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<String?> track({
    required String artist,
    required String title,
  }) {
    final key = 'song|${_normalize(artist)}|${_normalize(title)}';
    if (_normalize(artist).isEmpty || _normalize(title).isEmpty) {
      return Future.value(null);
    }
    return _requests.putIfAbsent(key,
        () => _find(artist: artist, name: title, entity: 'song'));
  }

  Future<String?> album({
    required String artist,
    required String album,
  }) {
    final key = 'album|${_normalize(artist)}|${_normalize(album)}';
    if (_normalize(artist).isEmpty || _normalize(album).isEmpty) {
      return Future.value(null);
    }
    return _requests.putIfAbsent(key,
        () => _find(artist: artist, name: album, entity: 'album'));
  }

  Future<String?> _find({
    required String artist,
    required String name,
    required String entity,
  }) async {
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': '$artist $name',
        'media': 'music',
        'entity': entity,
        'limit': '20',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['results'] is! List) return null;
      for (final item in decoded['results'] as List) {
        if (item is! Map) continue;
        final candidateArtist = (item['artistName'] ?? '').toString();
        final candidateName =
            (item[entity == 'song' ? 'trackName' : 'collectionName'] ?? '')
                .toString();
        if (_normalize(candidateArtist) != _normalize(artist) ||
            _normalize(candidateName) != _normalize(name)) {
          continue;
        }
        final image = item['artworkUrl100'];
        if (image is! String || !image.startsWith('https://')) continue;
        return image.replaceFirst(
          RegExp(r'100x100bb(?=\.|$)'), '600x600bb');
      }
    } catch (error) {
      debugPrint('[Orchid Artwork] Apple lookup failed: $error');
    }
    return null;
  }
}
