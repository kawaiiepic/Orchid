import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AnimatedArtwork {
  final String url;
  final bool portrait;
  /// Square HLS variant, suitable for iOS's 1:1 Now Playing artwork API.
  final String? squareUrl;
  const AnimatedArtwork({required this.url, required this.portrait, this.squareUrl});
}

/// Public Apple Music animated cover lookup, separate from Spotify Canvas.
/// The service returns HLS playlists, not downloadable video files.
class AnimatedArtworkService {
  static final AnimatedArtworkService instance = AnimatedArtworkService._();
  AnimatedArtworkService._();

  final Map<String, AnimatedArtwork?> _cache = {};

  String _key(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  Future<String> _findAlbum(String artist, String title) async {
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': '$artist $title',
        'entity': 'song',
        'media': 'music',
        'limit': '10',
      });
      final response = await http.get(uri)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return '';
      final data = jsonDecode(response.body);
      if (data is! Map || data['results'] is! List) return '';
      for (final item in data['results'] as List) {
        if (item is! Map) continue;
        if (_key((item['trackName'] ?? '').toString()) != _key(title) ||
            _key((item['artistName'] ?? '').toString()) != _key(artist)) {
          continue;
        }
        final value = item['collectionName'];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    } catch (e) {
      debugPrint('[Orchid Artwork] Album lookup failed: $e');
    }
    return '';
  }

  Future<AnimatedArtwork?> fetch({
    required String artist,
    String? album,
    String? title,
  }) async {
    if (artist.trim().isEmpty) return null;
    var resolvedAlbum = album?.trim() ?? '';
    if (resolvedAlbum.isEmpty && title?.trim().isNotEmpty == true) {
      resolvedAlbum = await _findAlbum(artist, title!);
    }
    if (resolvedAlbum.isEmpty) return null;
    final key = '${_key(artist)}|${_key(resolvedAlbum)}';
    if (_cache.containsKey(key)) return _cache[key];

    try {
      final uri = Uri.https('artwork.m8tec.top', '/api/v1/artwork/search', {
        'artist': artist,
        'album': resolvedAlbum,
        if (title != null && title.trim().isNotEmpty) 'title': title,
      });
      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 9));
      if (response.statusCode == 404) {
        _cache[key] = null;
        return null;
      }
      if (response.statusCode != 200) {
        debugPrint('[Orchid Artwork] HTTP ${response.statusCode}');
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final result = Map<String, dynamic>.from(decoded);
      final resultArtist = (result['artist'] ?? '').toString();
      if (resultArtist.isNotEmpty && _key(resultArtist) != _key(artist)) {
        debugPrint('[Orchid Artwork] Skipping artwork for a different artist');
        return null;
      }
      final portraitUrl = result['url_tall'];
      final squareUrl = result['url'];
      // HLS streams returned by the API are played directly with media_kit.
      String? valid(Object? candidate) {
        if (candidate is! String || candidate.isEmpty) return null;
        final parsed = Uri.tryParse(candidate);
        if (parsed == null || parsed.scheme != 'https' ||
            parsed.host.isEmpty || !parsed.path.endsWith('.m3u8')) {
          return null;
        }
        return candidate;
      }

      final portrait = valid(portraitUrl);
      final square = valid(squareUrl);
      if (portrait != null) {
        return _cache[key] = AnimatedArtwork(url: portrait, portrait: true, squareUrl: square);
      }
      if (square != null) {
        return _cache[key] = AnimatedArtwork(url: square, portrait: false, squareUrl: square);
      }
    } catch (e) {
      debugPrint('[Orchid Artwork] Lookup failed: $e');
    }
    return null;
  }
}
