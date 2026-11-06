import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Canonical public catalog metadata. Last.fm remains the source for
/// scrobble timestamps, play counts, and listening history.
class AppleCatalogTrack {
  final String title;
  final String artist;
  final String? album;
  final String? artwork;
  final int? trackId;

  const AppleCatalogTrack({
    required this.title,
    required this.artist,
    this.album,
    this.artwork,
    this.trackId,
  });
}

class AppleCatalogService {
  AppleCatalogService._();
  static final AppleCatalogService instance = AppleCatalogService._();

  final Map<String, Future<AppleCatalogTrack?>> _cache = {};

  String normalize(String value) => value.toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<AppleCatalogTrack?> matchTrack({
    required String artist,
    required String title,
    String? album,
  }) {
    final a = normalize(artist);
    final t = normalize(title);
    if (a.isEmpty || t.isEmpty) return Future.value(null);
    return _cache.putIfAbsent('$a|$t|${normalize(album ?? '')}',
      () => _lookup(artist, title, album));
  }

  Future<AppleCatalogTrack?> _lookup(
      String artist, String title, String? album) async {
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': '$artist $title',
        'media': 'music',
        'entity': 'song',
        'limit': '25',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['results'] is! List) return null;
      final a = normalize(artist);
      final t = normalize(title);
      final matches = <AppleCatalogTrack>[];
      for (final raw in decoded['results'] as List) {
        if (raw is! Map) continue;
        final candidateArtist = (raw['artistName'] ?? '').toString();
        final candidateTitle = (raw['trackName'] ?? '').toString();
        // No fuzzy matching: different versions and recordings must not be
        // mistaken for one another.
        if (normalize(candidateArtist) != a ||
            normalize(candidateTitle) != t) {
          continue;
        }
        final image = raw['artworkUrl100'];
        matches.add(AppleCatalogTrack(
          title: candidateTitle,
          artist: candidateArtist,
          album: raw['collectionName']?.toString(),
          artwork: image is String && image.startsWith('https://')
              ? image.replaceFirst(RegExp(r'100x100bb(?=\.|$)'), '600x600bb')
              : null,
          trackId: raw['trackId'] is int ? raw['trackId'] as int : null,
        ));
      }
      if (matches.isEmpty) return null;
      // Respect the scrobble's album when it matches a particular edition.
      final requestedAlbum = normalize(album ?? '');
      if (requestedAlbum.isNotEmpty) {
        for (final match in matches) {
          if (normalize(match.album ?? '') == requestedAlbum) return match;
        }
      }
      // Avoid assigning arbitrary albums where Apple has multiple editions.
      if (matches.length > 1 &&
          matches.map((m) => normalize(m.album ?? '')).toSet().length > 1) {
        return null;
      }
      return matches.first;
    } catch (error) {
      debugPrint('[Orchid Catalog] Lookup failed: $error');
      return null;
    }
  }

  /// Merge Apple metadata into Last.fm records, never replacing listening data.
  Future<Map<String, dynamic>> enrichRecent(Map<String, dynamic> item) async {
    final matched = await matchTrack(
      artist: (item['artist'] ?? '').toString(),
      title: (item['title'] ?? '').toString(),
      album: item['album']?.toString(),
    );
    if (matched == null) return item;
    return {
      ...item,
      'title': matched.title,
      'artist': matched.artist,
      'album': matched.album ?? item['album'],
      'image': matched.artwork ?? item['image'],
      'appleTrackId': matched.trackId,
    };
  }
}
