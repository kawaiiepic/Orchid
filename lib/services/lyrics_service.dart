import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/addon.dart';
import './spotify_service.dart';

/// One timed syllable from Spicy Lyrics (Apple Music-style).
class LyricSyllable {
  final String text;
  final double start; // seconds
  final double end; // seconds
  final bool isPartOfWord;

  const LyricSyllable({
    required this.text,
    required this.start,
    required this.end,
    this.isPartOfWord = false,
  });

  factory LyricSyllable.fromJson(Map<String, dynamic> json) {
    return LyricSyllable(
      text: json['Text'] as String? ?? '',
      start: (json['StartTime'] as num?)?.toDouble() ?? 0,
      end: (json['EndTime'] as num?)?.toDouble() ?? 0,
      isPartOfWord: json['IsPartOfWord'] as bool? ?? false,
    );
  }

  bool activeAt(double t) => t >= start && t < end;
}

/// One vocal line (lead and optional background).
/// Not every response has clean per-word data — use [hasSyllables].
class LyricLine {
  final List<LyricSyllable> lead;
  final List<LyricSyllable> background;
  final double start;
  final double end;
  final bool oppositeAligned;

  const LyricLine({
    required this.lead,
    this.background = const [],
    required this.start,
    required this.end,
    this.oppositeAligned = false,
  });

  bool get hasSyllables => lead.isNotEmpty;

  /// Reconstructed plain text for this line (respects IsPartOfWord).
  String get text {
    if (lead.isEmpty) return '';
    final buf = StringBuffer();
    for (var i = 0; i < lead.length; i++) {
      final s = lead[i];
      buf.write(s.text);
      final nextIsContinuation =
          i + 1 < lead.length && lead[i + 1].isPartOfWord;
      if (!s.isPartOfWord && !nextIsContinuation && i + 1 < lead.length) {
        buf.write(' ');
      }
    }
    return buf.toString().trim();
  }

  bool activeAt(double t) => t >= start && t < end;

  /// Active lead syllable index at [t], or -1.
  int activeLeadIndex(double t) {
    for (var i = 0; i < lead.length; i++) {
      if (lead[i].activeAt(t)) return i;
    }
    return -1;
  }
}

/// Lyrics result from Spicy Lyrics API.
///
/// Supports:
/// - Type "Syllable" (nested Vocal → Lead/Background → Syllables) — best quality
/// - Flat / line-level / plain fallbacks when syllable data is missing
class LyricsResult {
  final String? plain;
  final String? synced; // optional LRC-style string for simple UIs
  final List<LyricLine> lines; // structured syllable data (may be empty)
  final bool hasSync;
  final String source;
  final String? bodyType; // e.g. "Syllable"

  const LyricsResult({
    this.plain,
    this.synced,
    this.lines = const [],
    this.hasSync = false,
    this.source = 'spicylyrics',
    this.bodyType,
  });

  bool get hasAny =>
      (plain != null && plain!.trim().isNotEmpty) ||
      (synced != null && synced!.trim().isNotEmpty) ||
      lines.isNotEmpty;

  bool get hasSyllables => lines.any((l) => l.hasSyllables);

  /// Prefer structured plain, then plain field, then strip synced.
  String get displayText {
    if (lines.isNotEmpty) {
      return lines.map((l) => l.text).where((t) => t.isNotEmpty).join('\n');
    }
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

  /// Line active at playback time [t] (seconds), or null.
  LyricLine? lineAt(double t) {
    for (final line in lines) {
      if (line.activeAt(t)) return line;
    }
    return null;
  }

  /// Index of line active at [t], or -1.
  int lineIndexAt(double t) {
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].activeAt(t)) return i;
    }
    return -1;
  }
}

/// Spicy Lyrics API Service.
///
/// Endpoint: GET /v1/lyrics/{SPOTIFY_TRACK_ID}
/// Auth: Authorization: Bearer …
class LyricsService {
  final http.Client _client;
  static const String apiKey =
      'sl_sk_169LGcgCR0Jd02kORnaebr1XxJm59eIjb5NpDJ7zgKM';

  LyricsService({http.Client? client}) : _client = client ?? http.Client();

  Future<LyricsResult?> fetchFor(TrackResult track) async {
    debugPrint(
        '[Orchid] lyrics: Starting lookup for "${track.title}" by "${track.artist}"');

    if (track.spotifyTrackId != null && track.spotifyTrackId!.isNotEmpty) {
      final result = await _fetchBySpotifyTrackId(track.spotifyTrackId!);
      if (result?.hasAny == true) return result;
      debugPrint('[Orchid] lyrics: Spotify track ID lookup failed');
    } else {
      final itunesTrack = await _resolveViaItunes(track);
      if (itunesTrack != null &&
          itunesTrack.spotifyTrackId != null &&
          itunesTrack.spotifyTrackId!.isNotEmpty) {
        debugPrint('[Orchid] lyrics: Resolved via iTunes, fetching with Spotify ID');
        return _fetchBySpotifyTrackId(itunesTrack.spotifyTrackId!);
      } else {
        debugPrint('[Orchid] lyrics: iTunes resolution found no Spotify ID');

        final spotifyTrack =
            await _resolveViaSpotifySearch(track.title, track.artist);
        if (spotifyTrack != null &&
            (spotifyTrack.spotifyTrackId ?? '').isNotEmpty) {
          debugPrint(
              '[Orchid] lyrics: Resolved via Spotify search, fetching with ID ${spotifyTrack.spotifyTrackId}');
          return _fetchBySpotifyTrackId(spotifyTrack.spotifyTrackId!);
        } else {
          debugPrint('[Orchid] lyrics: Spotify search found no matching track');
        }
      }
    }

    debugPrint('[Orchid] lyrics: All lookup methods exhausted - no lyrics available');
    return null;
  }

  Future<TrackResult?> _resolveViaSpotifySearch(String title, String artist) async {
    try {
      debugPrint(
          '[Orchid] lyrics: Attempting Spotify search for "$title" by "$artist"');

      final query = '$artist $title';
      final spotifyService = SpotifyService();
      final results = await spotifyService.searchTracksOnly(query, limit: 5);

      if (results.isEmpty) {
        debugPrint('[Orchid] lyrics: Spotify search found no tracks');
        return null;
      }

      final first = results.first;
      final track = spotifyService.fromSpotify(first);

      if ((track.spotifyTrackId ?? track.id).isEmpty) {
        debugPrint('[Orchid] lyrics: Spotify search did not return valid track ID');
        return null;
      }

      return track;
    } catch (e) {
      debugPrint('[Orchid] lyrics: Spotify search error: $e');
      return null;
    }
  }

  Future<LyricsResult?> _fetchBySpotifyTrackId(String trackId) async {
    try {
      final uri = Uri.parse('https://api.spicylyrics.org/v1/lyrics/$trackId');
      debugPrint('[Orchid] lyrics fetching from Spicy Lyrics: /v1/lyrics/$trackId');

      final res = await _client.get(
        uri,
        headers: {
          'User-Agent': 'Orchid/0.1 (Flutter music player)',
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        debugPrint('[Orchid] lyrics fetch failed with status ${res.statusCode}');
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

      if (!data.containsKey('Body')) {
        debugPrint('[Orchid] lyrics: Unexpected response format');
        return null;
      }

      final bodyData = data['Body'] as Map<String, dynamic>;

      if (bodyData.containsKey('error')) {
        final error = bodyData['error'] as String;
        debugPrint('[Orchid] lyrics: API error - $error');
        return null;
      }

      return _parseBody(bodyData);
    } catch (e) {
      debugPrint('[Orchid] lyrics Spotify track ID error: $e');
      return null;
    }
  }

  /// Parse Spicy Lyrics Body. Handles Type "Syllable" and flat fallbacks.
  LyricsResult _parseBody(Map<String, dynamic> bodyData) {
    final type = bodyData['Type'] as String?;
    final content = bodyData['Content'];

    // --- Syllable format (your example) ---
    if (type == 'Syllable' && content is List) {
      final lines = <LyricLine>[];
      final plainBuf = StringBuffer();

      for (final item in content) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);

        if (map['Type'] == 'Vocal') {
          final lead = _parseSyllableGroup(map['Lead']);
          final bg = _parseSyllableGroupList(map['Background']);
          final start = (map['Lead'] is Map
                  ? (map['Lead']['StartTime'] as num?)
                  : null)
              ?.toDouble() ??
              (lead.isNotEmpty ? lead.first.start : 0.0);
          final end = (map['Lead'] is Map
                  ? (map['Lead']['EndTime'] as num?)
                  : null)
              ?.toDouble() ??
              (lead.isNotEmpty ? lead.last.end : start);

          final line = LyricLine(
            lead: lead,
            background: bg,
            start: start,
            end: end,
            oppositeAligned: map['OppositeAligned'] as bool? ?? false,
          );
          lines.add(line);
          final t = line.text;
          if (t.isNotEmpty) {
            if (plainBuf.isNotEmpty) plainBuf.writeln();
            plainBuf.write(t);
          }
        } else if (map.containsKey('Text')) {
          // occasional flat line inside Content
          final text = map['Text'] as String? ?? '';
          if (text.isNotEmpty) {
            if (plainBuf.isNotEmpty) plainBuf.writeln();
            plainBuf.write(text);
          }
        }
      }

      final plain = plainBuf.toString().trim();
      final synced = _linesToRoughLrc(lines);

      return LyricsResult(
        plain: plain.isEmpty ? null : plain,
        synced: synced.isEmpty ? null : synced,
        lines: lines,
        hasSync: lines.isNotEmpty,
        source: 'spicylyrics',
        bodyType: type,
      );
    }

    // --- Flat Content list with Text/StartTime ---
    if (content is List) {
      final plainBuf = StringBuffer();
      final syncedBuf = StringBuffer();
      final lines = <LyricLine>[];

      for (final item in content) {
        if (item is Map) {
          final text = item['Text'] as String? ?? '';
          final start = (item['StartTime'] as num?)?.toDouble();
          final end = (item['EndTime'] as num?)?.toDouble() ?? start;
          if (text.isEmpty) continue;
          if (plainBuf.isNotEmpty) plainBuf.writeln();
          plainBuf.write(text);
          if (start != null) {
            syncedBuf.writeln('[${_formatLrc(start)}] $text');
            lines.add(LyricLine(
              lead: [
                LyricSyllable(
                  text: text,
                  start: start,
                  end: end ?? start + 2,
                  isPartOfWord: false,
                ),
              ],
              start: start,
              end: end ?? start + 2,
            ));
          }
        } else if (item is String && item.trim().isNotEmpty) {
          if (plainBuf.isNotEmpty) plainBuf.writeln();
          plainBuf.write(item.trim());
        }
      }

      final plain = plainBuf.toString().trim();
      return LyricsResult(
        plain: plain.isEmpty ? null : plain,
        synced: syncedBuf.toString().trim().isEmpty
            ? null
            : syncedBuf.toString().trim(),
        lines: lines,
        hasSync: lines.isNotEmpty,
        source: 'spicylyrics',
        bodyType: type,
      );
    }

    // --- Simple string Content ---
    if (content is String && content.trim().isNotEmpty) {
      return LyricsResult(
        plain: content.trim(),
        hasSync: false,
        source: 'spicylyrics',
        bodyType: type,
      );
    }

    // Last-resort fields
    for (final field in ['plain', 'lyrics', 'text']) {
      final v = bodyData[field];
      if (v is String && v.trim().isNotEmpty) {
        return LyricsResult(
          plain: v.trim(),
          source: 'spicylyrics',
          bodyType: type,
        );
      }
    }

    return const LyricsResult(source: 'spicylyrics');
  }

  List<LyricSyllable> _parseSyllableGroup(dynamic group) {
    if (group is! Map) return const [];
    final syllables = group['Syllables'];
    if (syllables is! List) return const [];
    return syllables
        .whereType<Map>()
        .map((m) => LyricSyllable.fromJson(Map<String, dynamic>.from(m)))
        .where((s) => s.text.isNotEmpty)
        .toList();
  }

  List<LyricSyllable> _parseSyllableGroupList(dynamic bg) {
    if (bg is! List) return const [];
    final out = <LyricSyllable>[];
    for (final item in bg) {
      if (item is Map) {
        out.addAll(_parseSyllableGroup(item));
      }
    }
    return out;
  }

  String _linesToRoughLrc(List<LyricLine> lines) {
    final buf = StringBuffer();
    for (final line in lines) {
      final t = line.text;
      if (t.isEmpty) continue;
      buf.writeln('[${_formatLrc(line.start)}] $t');
    }
    return buf.toString().trim();
  }

  String _formatLrc(double seconds) {
    final totalMs = (seconds * 1000).round();
    final min = totalMs ~/ 60000;
    final sec = (totalMs % 60000) ~/ 1000;
    final ms = totalMs % 1000;
    return '$min:${sec.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  Future<TrackResult?> _resolveViaItunes(TrackResult originalTrack) async {
    try {
      debugPrint(
          '[Orchid] lyrics: Attempting iTunes resolution for "${originalTrack.title}" by "${originalTrack.artist}"');

      final searchTerm = '${originalTrack.artist} ${originalTrack.title}';
      final uri = Uri.parse('https://itunes.apple.com/search').replace(
        queryParameters: {
          'term': searchTerm,
          'entity': 'song',
          'media': 'music',
          'limit': '1',
        },
      );

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

      final item = results[0];
      if (item is! Map) return null;
      final m = Map<String, dynamic>.from(item);
      if (m['wrapperType'] != 'track' || m['kind'] != 'song') return null;

      String? spotifyTrackId;
      final hasSpotifyUrl =
          m.containsKey('spotifyUrl') || m.containsKey('spotifyURL');
      if (hasSpotifyUrl) {
        final spotifyUrl =
            m['spotifyUrl'] as String? ?? m['spotifyURL'] as String? ?? '';
        final match = RegExp(r'/track/([a-zA-Z0-9_-]+)').firstMatch(spotifyUrl);
        if (match != null) {
          spotifyTrackId = match.group(1)!;
          debugPrint('[Orchid] lyrics: Extracted Spotify ID: $spotifyTrackId');
        }
      }

      if (spotifyTrackId == null || spotifyTrackId.isEmpty) {
        return null;
      }

      return TrackResult(
        id: '${m['trackId']}',
        title: m['trackName'] as String? ?? '',
        artist: m['artistName'] as String? ?? '',
        album: m['collectionName'] as String?,
        duration: m['trackTimeMillis'] is int
            ? ((m['trackTimeMillis'] as int) / 1000).round()
            : null,
        artworkUrl: (m['artworkUrl100'] as String?)
            ?.replaceAll('100x100bb', '600x600bb'),
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

  static String formatMs(int ms) {
    final min = ms ~/ (60 * 1000);
    final sec = (ms % (60 * 1000)) ~/ 1000;
    final millisecond = (ms % 1000).toString().padLeft(3, '0');
    return '$min:$sec.$millisecond';
  }
}
