import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/addon.dart';

/// Built-in Spotify Web API addon for searching tracks.
/// 
/// This internal addon:
/// - Searches Spotify directly via OAuth token
/// - Returns Spotify track IDs for lyrics lookup
/// - Works like iTunes but returns pure Spotify results
class SpotifyAddonService {
  final http.Client _client;

  SpotifyAddonService({http.Client? client}) : _client = client ?? http.Client();

  /// OAuth token cache key
  static const _tokenKey = 'orchid_spotify_token_v2';
  
  /// Access token (expires in 1 hour)
  String? _accessToken;
  DateTime? _tokenExpiry;

  /// Get access token for Spotify API
  Future<String> getAccessToken() async {
    // Check cache first
    if (_accessToken != null && _tokenExpiry != null && 
        _tokenExpiry!.isAfter(DateTime.now().add(const Duration(seconds: 60)))) {
      debugPrint('[Orchid] Spotify Addon: Using cached token');
      return _accessToken!;
    }

    try {
      // Exchange client credentials for access token
      final authUri = Uri.parse('https://accounts.spotify.com/api/token');
      
      // Base64 encode Client ID:Secret
      final clientId = '3f8ea455038c4abab2e533a540d5de4c';
      final clientSecret = 'e0bc707c20d94c07a5ff5b7138be108f';
      
      final authHeaders = {
        'Authorization': 'Basic ${_base64Encode('$clientId:$clientSecret')}'.replaceAll('\n', ''),
        'Content-Type': 'application/x-www-form-urlencoded',
      };

      final res = await _client.post(
        authUri,
        headers: authHeaders,
        body: 'grant_type=client_credentials',
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        debugPrint('[Orchid] Spotify Addon: Failed to get token - ${res.statusCode}');
        throw Exception('Failed to authenticate with Spotify API');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final token = body['access_token'] as String;
      
      // Cache token (expires in 3600 seconds per Spotify docs)
      _accessToken = token;
      _tokenExpiry = DateTime.now().add(const Duration(seconds: 3500));
      
      debugPrint('[Orchid] Spotify Addon: Got access token');
      return token;
    } catch (e) {
      debugPrint('[Orchid] Spotify Addon: Error getting token: $e');
      rethrow;
    }
  }

  static String _base64Encode(String text) {
    final bytes = utf8.encode(text);
    return base64Encode(bytes);
  }

  /// Search for tracks on Spotify and return TrackResults with Spotify IDs
  Future<List<TrackResult>> searchTracks(
    String query, {
    int limit = 25,
  }) async {
    try {
      final token = await getAccessToken();
      
      // URL encode the query
      final encodedQuery = Uri.encodeComponent(query);
      
      final searchUri = Uri.parse('https://api.spotify.com/v1/search')
        .replace(queryParameters: {
          'q': encodedQuery,
          'type': 'track',
          'limit': limit.toString(),
        });

      debugPrint('[Orchid] Spotify Addon: Searching for "$query"');
      
      final res = await _client.get(searchUri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        debugPrint('[Orchid] Spotify Addon: Search failed - ${res.statusCode}');
        return [];
      }

      final data = jsonDecode(res.body);
      
      if (data is! Map) {
        debugPrint('[Orchid] Spotify Addon: No tracks found for "$query"');
        return [];
      }

      // Spotify returns tracks as a nested object: { "tracks": { "items": [ ... ] } }
      final trackGroup = data['tracks'];
      final items = trackGroup is Map ? trackGroup['items'] : null;
      final tracks = items is List ? items : <dynamic>[];

      if (tracks.isEmpty) {
        debugPrint('[Orchid] Spotify Addon: No tracks found for "$query"');
        return [];
      }
      debugPrint('[Orchid] Spotify Addon: Found ${tracks.length} tracks for "$query"');
      
      // Convert to TrackResult with Spotify track IDs
      return tracks.where((track) => _extractSpotifyId(track) != null)
          .map((track) {
        final id = _extractSpotifyId(track)!;
        return TrackResult(
          id: id,
          title: _extractName(track) ?? '',
          artist: _extractArtist(track) ?? '',
          album: _extractAlbum(track),
          duration: _extractDuration(track),
          artworkUrl: _extractArtwork(track)?.replaceAll('300x300bb', '600x600bb'),
          format: null,
          previewUrl: null,  // Spotify doesn't provide previews via API
          spotifyTrackId: id,
          sourceId: 'spotify-addon',
          sourceName: 'Spotify Addon (Built-in)',
          fromStreamAddon: false,
        );
      }).toList();
    } catch (e) {
      debugPrint('[Orchid] Spotify Addon: Search error: $e');
      return [];
    }
  }

  /// Extract Spotify track ID from search result
  String? _extractSpotifyId(dynamic track) {
    if (track is Map && track.containsKey('id')) {
      final id = track['id'] as String? ?? '';
      // Validate: Spotify track IDs are exactly 22 base62 characters
      if (id.length == 22) {
        return id;
      }
    }
    return null;
  }

  /// Extract track name from search result
  String? _extractName(dynamic track) {
    if (track is Map && track.containsKey('name')) {
      final name = track['name'] as String? ?? '';
      if (name.isNotEmpty) {
        // Clean up common issues
        final cleaned = name
          .replaceAll('&', ' & ')
          .replaceAll('/', ' / ');
        return cleaned.trim();
      }
    }
    return null;
  }

  /// Extract artist from search result
  String? _extractArtist(dynamic track) {
    if (track is Map && track.containsKey('artists')) {
      final artists = track['artists'] as List<dynamic>;
      if (artists.isNotEmpty) {
        final first = artists.first as Map<String, dynamic>?;
        if (first != null && first.containsKey('name')) {
          final name = first['name'] as String? ?? '';
          final cleaned = name
            .replaceAll('&', ' & ')
            .replaceAll('/', ' / ');
          return cleaned.trim();
        }
      }
    }
    return null;
  }

  /// Extract album from search result
  String? _extractAlbum(dynamic track) {
    if (track is Map && track.containsKey('album') && 
        track['album'] is Map) {
      final album = track['album'] as Map<String, dynamic>;
      if (album.containsKey('name')) {
        return album['name'] as String? ?? '';
      }
    }
    return null;
  }

  /// Extract duration from search result (convert ms to seconds)
  int? _extractDuration(dynamic track) {
    if (track is Map && track.containsKey('duration_ms')) {
      final durationMs = track['duration_ms'] as int? ?? 0;
      return (durationMs / 1000).round();
    }
    return null;
  }

  /// Extract artwork URL from search result
  String? _extractArtwork(dynamic track) {
    if (track is Map && track.containsKey('images') && 
        track['images'] is List) {
      final images = track['images'] as List<dynamic>;
      if (images.isNotEmpty) {
        final image = images.first as Map<String, dynamic>?;
        if (image != null && image.containsKey('url')) {
          final url = image['url'] as String?;
          if (url != null) {
            return url;
          }
        }
      }
    }
    return null;
  }

  /// Add this addon to your list for automatic search inclusion
  static Map<String, dynamic> toJson() {
    return {
      'id': 'spotify-addon',
      'name': 'Spotify Search (Built-in)',
      'version': '1.0.0',
      'description': 'Built-in Spotify Web API addon for track search and ID resolution',
      'resources': ['search'],
      'types': ['track'],
    };
  }

  /// Create InstalledAddon from Spotify addon config
  static InstalledAddon create() {
    final manifest = const AddonManifest(
      id: 'spotify-addon',
      name: 'Spotify Search (Built-in)',
      version: '1.0.0',
      description: 'Built-in Spotify Web API addon for track search and ID resolution',
      resources: ['search'],
      types: ['track'],
    );
    return InstalledAddon(baseUrl: '', manifest: manifest);
  }
}