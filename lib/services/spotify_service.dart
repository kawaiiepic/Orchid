import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/addon.dart';

/// Spotify Web API Client for searching tracks and resolving to track IDs.
/// 
/// This service:
/// - Authenticates with Spotify's client credentials
/// - Searches for tracks by title+artist
/// - Returns Spotify track ID (22 base62 chars) for lyrics lookup
class SpotifyService {
  final http.Client _client;

  SpotifyService({http.Client? client}) : _client = client ?? http.Client();

  /// OAuth token cache key
  
  /// Access token (expires in 1 hour)
  String? _accessToken;
  DateTime? _tokenExpiry;

  /// Get access token for Spotify API
  Future<String> getAccessToken() async {
    // Check cache first
    if (_accessToken != null && _tokenExpiry != null && 
        _tokenExpiry!.isAfter(DateTime.now().add(const Duration(seconds: 60)))) {
      debugPrint('[Orchid] Spotify: Using cached token');
      return _accessToken!;
    }

    try {
      // Exchange client credentials for access token
      final authUri = Uri.parse('https://accounts.spotify.com/api/token');
      
      final authHeaders = {
        'Authorization': 'Basic ${_base64Encode('$_clientId:$_clientSecret')}'.replaceAll('\n', ''),
        'Content-Type': 'application/x-www-form-urlencoded',
      };

      final res = await _client.post(
        authUri,
        headers: authHeaders,
        body: 'grant_type=client_credentials',
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        debugPrint('[Orchid] Spotify: Failed to get token - ${res.statusCode}');
        throw Exception('Failed to authenticate with Spotify API');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final token = body['access_token'] as String;
      
      // Cache token (expires in 3600 seconds per Spotify docs)
      _accessToken = token;
      _tokenExpiry = DateTime.now().add(const Duration(seconds: 3500));
      
      debugPrint('[Orchid] Spotify: Got access token');
      return token;
    } catch (e) {
      debugPrint('[Orchid] Spotify: Error getting token: $e');
      rethrow;
    }
  }

  static String _base64Encode(String text) {
    return base64Encode(utf8.encode(text));
  }

  /// Search for tracks on Spotify
  Future<List<dynamic>> searchTracks(
    String query, {
    int limit = 5,
    bool includeTracksOnly = false,
  }) async {
    try {
      final token = await getAccessToken();
      
      final searchUri = Uri.parse('https://api.spotify.com/v1/search')
        .replace(queryParameters: {
          'q': query,
          'type': includeTracksOnly ? 'track' : 'track,album,artist',
          'limit': limit.toString(),
        });

      debugPrint('[Orchid] Spotify: Searching for "$query"');
      
      final res = await _client.get(searchUri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        debugPrint('[Orchid] Spotify: Search failed - ${res.statusCode}');
        return [];
      }

      final data = jsonDecode(res.body);
      
      if (data is! Map || !data.containsKey('tracks')) return [];

      // Spotify returns tracks as a nested object: { "tracks": { "items": [ ... ] } }
      final trackGroup = data['tracks'];
      final items = trackGroup is Map ? trackGroup['items'] : null;
      if (items is! List) return [];

      final tracks = items;
      debugPrint('[Orchid] Spotify: Found ${tracks.length} tracks for "$query"');
      
      return tracks;
    } catch (e) {
      debugPrint('[Orchid] Spotify: Search error: $e');
      return [];
    }
  }

  /// Search specifically for tracks (not albums/artists)
  Future<List<dynamic>> searchTracksOnly(String query, {int limit = 5}) async {
    final results = await searchTracks(query, includeTracksOnly: true, limit: limit);
    if (results.isEmpty) {
      debugPrint('[Orchid] Spotify: No tracks found for "$query"');
    } else {
      // Log track info
      final firstTrack = results.first;
      if (firstTrack is Map) {
        final name = firstTrack['name'] as String? ?? '';
        // Spotify returns artists as a list of objects: [{ "name": "..." }, ...]
        final artists = firstTrack['artists'];
        String artist = 'unknown';
        if (artists is List && artists.isNotEmpty) {
          final first = artists.first;
          artist = first is Map ? (first['name'] as String? ?? 'unknown') : first.toString();
        }
        debugPrint('[Orchid] Spotify: Top result: "$name" by $artist');
      }
    }
    return results;
  }

  /// Extract Spotify track ID from search results
  String? extractTrackId(dynamic track) {
    if (track is Map && track.containsKey('id')) {
      final id = track['id'] as String? ?? '';
      // Validate: Spotify track IDs are exactly 22 base62 characters
      if (id.length == 22 && _isValidBase62(id)) {
        debugPrint('[Orchid] Spotify: Extracted track ID: $id');
        return id;
      }
    }
    return null;
  }

  /// Check if a string is a valid base62 Spotify ID (alphanumeric only)
  bool _isValidBase62(String id) {
    final regex = RegExp(r'^[A-Za-z0-9]{22}$');
    return regex.hasMatch(id);
  }

  /// Get Spotify track name from search results
  String? getTrackName(dynamic track) {
    if (track is Map && track.containsKey('name')) {
      return track['name'] as String?;
    }
    return null;
  }

  /// Get Spotify artist from search results  
  String? getArtist(dynamic track) {
    if (track is Map && track.containsKey('artists')) {
      final artists = track['artists'] as List<dynamic>;
      if (artists.isNotEmpty) {
        final first = artists.first as Map<String, dynamic>?;
        return first?.toString()
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll('"', '');
      }
    }
    return null;
  }

  /// Get Spotify album from search results
  String? getAlbum(dynamic track) {
    if (track is Map && track.containsKey('album') && 
        track['album'] is Map &&
        track['album'].containsKey('name')) {
      return track['album']['name'] as String?;
    }
    return null;
  }

  /// Get Spotify duration from search results (in milliseconds)
  int? getDuration(dynamic track) {
    if (track is Map && track.containsKey('duration_ms')) {
      return track['duration_ms'] as int?;
    }
    return null;
  }

  /// Get Spotify cover art URL
  String? getCoverArtUrl(dynamic track) {
    if (track is Map && track.containsKey('images') && 
        track['images'] is List) {
      final images = track['images'] as List<dynamic>;
      if (images.isNotEmpty) {
        final image = images.first as Map<String, dynamic>?;
        if (image != null) {
          final url = image['url'] as String?;
          return url;
        }
        return null;
      }
    }
    return null;
  }

  /// Create a TrackResult from Spotify search results
  TrackResult fromSpotify(dynamic track, {String? previewUrl}) {
    final id = extractTrackId(track);
    
    if (id == null) {
      debugPrint('[Orchid] Spotify: Could not extract valid track ID');
      return TrackResult(
        id: '',
        title: getTrackName(track) ?? 'Unknown',
        artist: getArtist(track) ?? 'Unknown',
        previewUrl: previewUrl,
        sourceId: 'spotify-search',
        sourceName: 'Spotify Search',
        fromStreamAddon: false,
      );
    }

    return TrackResult(
      id: id,  // Use Spotify track ID as the main ID for lyrics lookup
      title: getTrackName(track) ?? 'Unknown',
      artist: getArtist(track) ?? 'Unknown',
      album: getAlbum(track),
      duration: getDuration(track),
      artworkUrl: getCoverArtUrl(track)?.replaceAll('300x300bb', '600x600bb'),
      previewUrl: previewUrl,
      spotifyTrackId: id,  // This is what Spicy Lyrics needs!
      sourceId: 'spotify-search',
      sourceName: 'Spotify Search',
      fromStreamAddon: false,
    );
  }

  /// Spotify API credentials (stored in code for now)
  static const _clientId = '3f8ea455038c4abab2e533a540d5de4c';
  static const _clientSecret = 'e0bc707c20d94c07a5ff5b7138be108f';
}