import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/addon.dart';
import './spotify_service.dart';

/// Lyrics result from Spicy Lyrics API.
/// 
/// Features:
/// - Apple Music syllable-level karaoke timing (best quality!)
/// - Bearer token authentication
/// - Spotify track ID resolution required
///
/// Base URL: https://api.spicylyrics.org/v1/lyrics/{SPOTIFY_TRACK_ID}
class LyricsResult {
  final String? plain;      // Plain text lyrics (no timestamps)
  final String? synced;     // Synced lyrics with per-word timing
  final bool hasSync;       // Whether this result has karaoke-level timing
  final String source;      // 'spicylyrics' or legacy

  const LyricsResult({
    this.plain,
    this.synced,
    this.hasSync = false,
    this.source = 'spicylyrics',
  });

  bool get hasAny =>
      (plain != null && plain!.trim().isNotEmpty) ||
      (synced != null && synced!.trim().isNotEmpty);

  /// Prefer plain; if only synced, strip timestamps for display.
  String get displayText {
    if (plain != null && plain!.trim().isNotEmpty) return plain!.trim();
    if (synced != null && synced!.trim().isNotEmpty) {
      return synced!
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^\[\d+:\d+[.,]?\d*\]\s*'), ''))
          .where((l) => l.trim().isNotEmpty)
          .join('\n');
    }
    return '';
  }

  /// Get plain text only (for simple display modes)
  String get plainOnly {
    if (plain != null && plain!.isNotEmpty) return plain!.trim();
    if (synced != null && synced!.isNotEmpty) {
      return LyricsService._extractPlainFromSynced(synced!);
    }
    return '';
  }
}

/// Spicy Lyrics API Service for lyrics fetching.
/// 
/// Features:
/// - Apple Music syllable-level sync (karaoke timing)
/// - Developer API endpoint for reliable lyrics data
/// - Bearer token authentication required
///
/// Endpoint: GET /v1/lyrics/{SPOTIFY_TRACK_ID}
/// Auth Header: Authorization: Bearer sl_sk_169LGcgCR0Jd02kORnaebr1XxJm59eIjb5NpDJ7zgKM
class LyricsService {
  final http.Client _client;
  static const String apiKey = 'sl_sk_169LGcgCR0Jd02kORnaebr1XxJm59eIjb5NpDJ7zgKM';

  LyricsService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch lyrics for a track using Spicy Lyrics.
  /// 
  /// Strategy:
  /// 1. Try direct Spotify track ID if available (fastest!)
  /// 2. If no Spotify ID, try to resolve via iTunes API
  Future<LyricsResult?> fetchFor(TrackResult track) async {
    debugPrint('[Orchid] lyrics: Starting lookup for "${track.title}" by "${track.artist}"');

    // Strategy 1: Direct Spotify track ID if available (fastest!)
    if (track.spotifyTrackId != null && track.spotifyTrackId!.isNotEmpty) {
      final result = await _fetchBySpotifyTrackId(track.spotifyTrackId!);
      if (result?.hasAny == true) return result;
      debugPrint('[Orchid] lyrics: Spotify track ID lookup failed');
    } else {
      // Strategy 2: Try iTunes resolution for popular tracks
      final itunesTrack = await _resolveViaItunes(track);
      if (itunesTrack != null && itunesTrack.spotifyTrackId != null && 
          itunesTrack.spotifyTrackId!.isNotEmpty) {
        debugPrint('[Orchid] lyrics: Resolved via iTunes, fetching with Spotify ID');
        return _fetchBySpotifyTrackId(itunesTrack.spotifyTrackId!);
      } else {
        debugPrint('[Orchid] lyrics: iTunes resolution found no Spotify ID');
        
        // Strategy 3: Try Spotify search as a last resort
        final spotifyTrack = await _resolveViaSpotifySearch(track.title, track.artist);
        if (spotifyTrack != null && spotifyTrack.spotifyTrackId!.isNotEmpty) {
          debugPrint('[Orchid] lyrics: Resolved via Spotify search, fetching with ID ${spotifyTrack.id}');
          return _fetchBySpotifyTrackId(spotifyTrack.spotifyTrackId!);
        } else {
          debugPrint('[Orchid] lyrics: Spotify search found no matching track');
        }
      }
    }

    debugPrint('[Orchid] lyrics: All lookup methods exhausted - no lyrics available');
    return null;
  }

  /// Search for a track on Spotify and resolve to TrackResult
  Future<TrackResult?> _resolveViaSpotifySearch(String title, String artist) async {
    try {
      debugPrint('[Orchid] lyrics: Attempting Spotify search for "$title" by "$artist"');
      
      // Build query
      final query = '$artist $title';
      
      final spotifyService = SpotifyService();
      final results = await spotifyService.searchTracksOnly(query, limit: 5);
      
      if (results.isEmpty) {
        debugPrint('[Orchid] lyrics: Spotify search found no tracks');
        return null;
      }
      
      // Take the first result and convert to TrackResult
      final first = results.first;
      final track = spotifyService.fromSpotify(first);
      
      if (track.id.isEmpty) {
        debugPrint('[Orchid] lyrics: Spotify search did not return valid track ID');
        return null;
      }
      
      debugPrint('[Orchid] lyrics: Resolved via Spotify search, fetching with ID ${track.id}');
      return track;
    } catch (e) {
      debugPrint('[Orchid] lyrics: Spotify search error: $e');
      return null;
    }
  }

  /// Fetch by direct Spotify track ID
  Future<LyricsResult?> _fetchBySpotifyTrackId(String trackId) async {
    try {
      // Use Spicy Lyrics lyrics endpoint with Spotify track ID
      final uri = Uri.parse('https://api.spicylyrics.org/v1/lyrics/$trackId');
      debugPrint('[Orchid] lyrics fetching from Spicy Lyrics: /v1/lyrics/$trackId');
      
      final res = await _client.get(uri,
        headers: {
          'User-Agent': 'Orchid/0.1 (Flutter music player)',
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        debugPrint('[Orchid] lyrics fetch failed with status ${res.statusCode}');
        
        // Check for specific errors
        final body = res.body;
        if (body.contains('lyrics_not_found')) {
          debugPrint('[Orchid] lyrics: No lyrics available for this track');
        } else if (body.contains('invalid_track_id')) {
          debugPrint('[Orchid] lyrics: Invalid Spotify track ID format');
        } else {
          debugPrint('[Orchid] lyrics: Error response - $body');
        }
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      debugPrint(res.body);
      
      // Spicy Lyrics wraps response in Body/Status/Type envelope
      if (!data.containsKey('Body')) {
        debugPrint('[Orchid] lyrics: Unexpected response format');
        return null;
      }

      final bodyData = data['Body'] as Map<String, dynamic>;
      
      // Check for error messages
      if (bodyData.containsKey('error')) {
        final error = bodyData['error'] as String;
        debugPrint('[Orchid] lyrics: API error - $error');
        return null;
      }

      // Extract lyrics data - handle both "Content" array and simple string formats
      final lyricsData = _normalizeSpicyLyricsResponse(bodyData);
      
      return LyricsResult(
        plain: lyricsData['plain'] ?? '',
        synced: lyricsData['synced'] ?? '',
        hasSync: true,  // Spicy Lyrics provides sync data!
        source: 'spicylyrics',
      );
    } catch (e) {
      debugPrint('[Orchid] lyrics Spotify track ID error: $e');
      return null;
    }
  }

  /// Normalize Spicy Lyrics API response to a consistent format
  Map<String, dynamic> _normalizeSpicyLyricsResponse(Map<String, dynamic> bodyData) {
    final result = <String, dynamic>{};
    
    // Check if we have Content array (structured sync data)
    if (bodyData.containsKey('Content') && bodyData['Content'] is List) {
      final contentList = bodyData['Content'] as List<dynamic>;
      
      // Build plain text lyrics
      String plainText = '';
      for (final item in contentList) {
        if (item is Map) {
          final text = item['Text'] as String? ?? '';
          if (text.isNotEmpty) {
            plainText += '$text\n';
          }
        } else if (item is String) {
          plainText += '$item\n';
        }
      }
      
      // Build synced LRC format
      String synced = '';
      for (final item in contentList) {
        if (item is Map && item.containsKey('StartTime') && item.containsKey('Text')) {
          final startMs = _secondsToMs(item['StartTime'] as num);
          final text = item['Text'] as String? ?? '';
          if (text.isNotEmpty) {
            synced += '[$startMs] $text\n';
          }
        }
      }
      
      result['plain'] = plainText.trim();
      result['synced'] = synced.trim();
    } else {
      // Fallback: try to extract from simple fields
      final plain = bodyData['Content'] as String? ?? '';
      result['plain'] = plain.isNotEmpty ? plain : null;
      
      // Try other sync formats
      for (final field in ['sync', 'lrc', 'timed']) {
        final sync = bodyData[field];
        if (sync != null && sync is String && sync.isNotEmpty) {
          result['synced'] = sync;
          break;
        }
      }
    }
    
    return result;
  }

  /// Convert seconds to milliseconds for LRC format
  int _secondsToMs(num seconds) {
    final intSecs = seconds.toInt();
    final millis = ((seconds - intSecs) * 1000).round();
    final min = intSecs ~/ 60;
    final sec = intSecs % 60;
    return min * 60 * 1000 + sec * 1000 + millis;
  }

  /// Resolve a track to its Spotify track ID via iTunes API.
  Future<TrackResult?> _resolveViaItunes(TrackResult originalTrack) async {
    try {
      debugPrint('[Orchid] lyrics: Attempting iTunes resolution for "${originalTrack.title}" by "${originalTrack.artist}"');
      
      // Build search URL - use exact title+artist match
      final searchTerm = '${originalTrack.artist} ${originalTrack.title}';
      final uri = Uri.parse('https://itunes.apple.com/search')
        .replace(queryParameters: {
          'term': searchTerm,
          'entity': 'song',
          'media': 'music',
          'limit': '1',
        });
      
      final res = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        debugPrint('[Orchid] lyrics: iTunes resolution failed with ${res.statusCode}');
        return null;
      }
      
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List? ?? [];
      if (results.isEmpty) {
        debugPrint('[Orchid] lyrics: No results from iTunes');
        return null;
      }
      
      // Check if the result matches our search
      final item = results[0];
      if (item is! Map) return null;
      final m = Map<String, dynamic>.from(item);
      if (m['wrapperType'] != 'track' || m['kind'] != 'song') return null;
      
      // Extract Spotify ID if iTunes response has it
      String? spotifyTrackId;
      final hasSpotifyUrl = m.containsKey('spotifyUrl') || m.containsKey('spotifyURL');
      if (hasSpotifyUrl) {
        final spotifyUrl = m['spotifyUrl'] as String? ?? m['spotifyURL'] as String? ?? '';
        // Extract track ID from Spotify URL: https://open.spotify.com/track/{ID}...
        final match = RegExp(r'/track/([a-zA-Z0-9_-]+)').firstMatch(spotifyUrl);
        if (match != null) {
          spotifyTrackId = match.group(1)!;
          debugPrint('[Orchid] lyrics: Extracted Spotify ID: $spotifyTrackId');
        } else {
          debugPrint('[Orchid] lyrics: Could not extract Spotify track ID from URL');
        }
      } else {
        debugPrint('[Orchid] lyrics: iTunes response does not contain spotifyUrl field');
      }
      
      if (spotifyTrackId == null || spotifyTrackId.isEmpty) {
        return null;  // No Spotify ID found in iTunes response
      }
      
      return TrackResult(
        id: m['trackId'],
        title: m['trackName'] as String? ?? '',
        artist: m['artistName'] as String? ?? '',
        album: m['collectionName'] as String?,
        duration: m['trackTimeMillis'] is int 
            ? ((m['trackTimeMillis'] as int) / 1000).round()
            : null,
        artworkUrl: (m['artworkUrl100'] as String?)?.replaceAll('100x100bb', '600x600bb'),
        format: 'm4a',
        previewUrl: m['previewUrl'] as String?,
        spotifyTrackId: spotifyTrackId,
        sourceId: 'itunes-resolution',
        sourceName: 'iTunes Resolution',
        fromStreamAddon: false,
      );
    } catch (e) {
      debugPrint('[Orchid] lyrics: iTunes resolution error: $e');
      return null;
    }
  }

  /// Extract plain text from synced lyrics (LRC format like [mm:ss.xx] Line)
  static String _extractPlainFromSynced(String synced) {
    // Remove timestamps [mm:ss.xx] and return plain text
    return synced
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^\[\d+:\d+[.,]?\d*\]\s*'), ''))
        .where((l) => l.trim().isNotEmpty)
        .join('\n');
  }

  /// Format synced lyrics with timestamps for karaoke display (static - no instance)
  static String _formatSyncedLyrics(dynamic syncedData) {
    // Handle different possible structures
    if (syncedData is String) {
      return syncedData;
    }
    
    if (syncedData is Map<String, dynamic>) {
      // Try various sync fields
      final sync = syncedData['sync'] as List?;
      if (sync != null && sync.isNotEmpty) {
        return _convertSyncListToLRC(sync);
      }
      
      // Fallback: try other sync field names
      for (final field in ['lrc', 'timed']) {
        final lrc = syncedData[field] as String?;
        if (lrc != null && lrc.isNotEmpty) return lrc;
      }
    }
    
    debugPrint('[Orchid] lyrics: Could not format synced data');
    return '';
  }

  /// Convert sync list to LRC format (static)
  static String _convertSyncListToLRC(List<dynamic> syncList) {
    return syncList
        .map((item) {
          final startMs = (item['start'] as num?)?.toInt() ?? 0;
          final text = item['text'] as String? ?? '';
          if (text.trim().isNotEmpty) {
            return '[${formatMs(startMs)}] $text';
          }
          return '';
        })
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  }

  /// Format milliseconds to LRC timestamp format.
  static String formatMs(int ms) {
    final min = ms ~/ (60 * 1000);
    final sec = (ms % (60 * 1000)) ~/ 1000;
    final millisecond = (ms % 1000).toString().padLeft(3, '0');
    return '$min:$sec.$millisecond';
  }

  /// Get minutes and milliseconds from an LRC timestamp string.
  static List<int> _parseTimestamp(String timestamp) {
    try {
      final clean = timestamp.replaceAll(RegExp(r'[\[\]]'), '');
      final parts = clean.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final remainingMs = parts[1]; // "ss.mmm"
        final secondsAndMillis = remainingMs.split('.').toList();
        final seconds = int.parse(secondsAndMillis[0]);
        final millis = (secondsAndMillis.length > 1) 
            ? int.parse(secondsAndMillis[1].padLeft(3, '0')) 
            : 0;
        return [minutes, seconds * 1000 + millis];
      }
    } catch (e) {
      debugPrint('[Orchid] lyrics: Failed to parse timestamp: $timestamp');
    }
    return [0, 0];
  }
}