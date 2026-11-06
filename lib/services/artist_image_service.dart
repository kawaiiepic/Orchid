import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Resolves real artist portraits separately from album cover artwork.
/// Deezer exposes public artist image URLs; no login is necessary.
class ArtistImageService {
  ArtistImageService._();
  static final ArtistImageService instance = ArtistImageService._();

  final Map<String, Future<String?>> _requests = {};

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  Future<String?> imageFor(String artist) {
    final key = _normalize(artist);
    if (key.isEmpty) return Future.value(null);
    return _requests.putIfAbsent(key, () => _lookup(artist, key));
  }

  Future<String?> _lookup(String artist, String normalized) async {
    try {
      final uri = Uri.https('api.deezer.com', '/search/artist', {
        'q': artist,
        'limit': '20',
      });
      final response = await http.get(uri,
          headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) return null;
      for (final item in decoded['data'] as List) {
        if (item is! Map) continue;
        if (_normalize((item['name'] ?? '').toString()) != normalized) {
          continue;
        }
        for (final field in ['picture_xl', 'picture_big', 'picture_medium']) {
          final raw = item[field];
          if (raw is! String || raw.isEmpty) continue;
          final url = Uri.tryParse(raw);
          if (url == null || url.scheme != 'https' || url.host.isEmpty ||
              !url.host.endsWith('dzcdn.net') ||
              raw.contains('/images/artist//')) {
            continue;
          }
          return raw;
        }
      }
    } catch (e) {
      debugPrint('[Orchid] Artist image unavailable for $artist: $e');
    }
    return null;
  }
}
