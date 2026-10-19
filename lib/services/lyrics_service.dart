import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/addon.dart';
import './spotify_service.dart';

/// Contributor from UploadAttribution (community syncs only).
class LyricsContributor {
  final String id;
  final String username;
  final String url;
  final String? avatar;

  const LyricsContributor({
    required this.id,
    required this.username,
    required this.url,
    this.avatar,
  });

  factory LyricsContributor.fromJson(Map<String, dynamic> json) {
    return LyricsContributor(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      url: json['url'] as String? ?? '',
      avatar: json['avatar'] as String?,
    );
  }
}

/// One timed syllable (Syllable sync).
class LyricSyllable {
  final String text;
  final double start;
  final double end;
  final bool isPartOfWord;
  final String? transliteratedText;

  const LyricSyllable({
    required this.text,
    required this.start,
    required this.end,
    this.isPartOfWord = false,
    this.transliteratedText,
  });

  factory LyricSyllable.fromJson(Map<String, dynamic> json) {
    return LyricSyllable(
      text: json['Text'] as String? ?? '',
      start: (json['StartTime'] as num?)?.toDouble() ?? 0,
      end: (json['EndTime'] as num?)?.toDouble() ?? 0,
      isPartOfWord: json['IsPartOfWord'] as bool? ?? false,
      transliteratedText: json['TransliteratedText'] as String?,
    );
  }

  /// Strict timing window from the API.
  bool timedAt(double t) => t >= start && t < end;

  /// Legacy alias — prefer [timedAt] or line-level active index helpers.
  bool activeAt(double t) => timedAt(t);
}

/// One timed line (syllable or line-level).
class LyricLine {
  final List<LyricSyllable> lead;
  final List<LyricSyllable> background;
  final double start;
  final double end;
  final bool oppositeAligned;
  final String? plainText;
  final String? translatedText;

  const LyricLine({
    this.lead = const [],
    this.background = const [],
    required this.start,
    required this.end,
    this.oppositeAligned = false,
    this.plainText,
    this.translatedText,
  });

  bool get hasSyllables => lead.isNotEmpty;

  String get text {
    if (plainText != null && plainText!.isNotEmpty) return plainText!;
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

  /// Active lead syllable at [t].
  ///
  /// Holds the last syllable that has *started* until the next one starts.
  /// That covers inter-syllable gaps and the tail of a line after the last
  /// syllable's EndTime — avoids a blank highlight for ~1s between words.
  int activeLeadIndex(double t) {
    if (lead.isEmpty) return -1;
    if (t < lead.first.start) return -1;

    var idx = 0;
    for (var i = 0; i < lead.length; i++) {
      if (t >= lead[i].start) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }
}

/// Parsed Spicy Lyrics Body.
class LyricsResult {
  final String? plain;
  final String? synced;
  final List<LyricLine> lines;
  final bool hasSync;
  final String source;
  final String? sourceVia;
  final String? bodyType; // Syllable | Line | Static
  final String? trackId;
  final List<String> songWriters;
  final LyricsContributor? uploader;
  final LyricsContributor? maker;
  final double? startTime;
  final double? endTime;

  const LyricsResult({
    this.plain,
    this.synced,
    this.lines = const [],
    this.hasSync = false,
    this.source = 'unknown',
    this.sourceVia,
    this.bodyType,
    this.trackId,
    this.songWriters = const [],
    this.uploader,
    this.maker,
    this.startTime,
    this.endTime,
  });

  bool get hasAny =>
      (plain != null && plain!.trim().isNotEmpty) ||
      (synced != null && synced!.trim().isNotEmpty) ||
      lines.isNotEmpty;

  bool get hasSyllables =>
      bodyType == 'Syllable' && lines.any((l) => l.hasSyllables);

  bool get isCommunity => source == 'spicy_lyrics';

  String get providerLabel {
    switch (source) {
      case 'spicy_lyrics':
        return 'Spicy Lyrics';
      case 'apple_music':
        return 'Apple Music';
      case 'spotify':
        return 'Spotify';
      default:
        return 'Lyrics';
    }
  }

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

  LyricLine? lineAt(double t) {
    final i = lineIndexAt(t);
    if (i < 0 || i >= lines.length) return null;
    return lines[i];
  }

  /// Active line, or the last started line during gaps (no snap-to-top).
  int lineIndexAt(double t) {
    if (lines.isEmpty) return -1;
    var lastStarted = -1;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (t >= line.start) lastStarted = i;
      if (line.activeAt(t)) return i;
    }
    return lastStarted;
  }
}

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
        return _fetchBySpotifyTrackId(itunesTrack.spotifyTrackId!);
      }

      final spotifyTrack =
          await _resolveViaSpotifySearch(track.title, track.artist);
      if (spotifyTrack != null &&
          (spotifyTrack.spotifyTrackId ?? '').isNotEmpty) {
        return _fetchBySpotifyTrackId(spotifyTrack.spotifyTrackId!);
      }
    }

    debugPrint('[Orchid] lyrics: All lookup methods exhausted');
    return null;
  }

  Future<TrackResult?> _resolveViaSpotifySearch(String title, String artist) async {
    try {
      final query = '$artist $title';
      final spotifyService = SpotifyService();
      final results = await spotifyService.searchTracksOnly(query, limit: 5);
      if (results.isEmpty) return null;
      final track = spotifyService.fromSpotify(results.first);
      if ((track.spotifyTrackId ?? track.id).isEmpty) return null;
      return track;
    } catch (e) {
      debugPrint('[Orchid] lyrics: Spotify search error: $e');
      return null;
    }
  }

  Future<LyricsResult?> _fetchBySpotifyTrackId(String trackId) async {
    try {
      final uri = Uri.parse('https://api.spicylyrics.org/v1/lyrics/$trackId');
      debugPrint('[Orchid] lyrics fetching: /v1/lyrics/$trackId');

      final res = await _client.get(
        uri,
        headers: {
          'User-Agent': 'Orchid/0.1 (Flutter music player)',
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        debugPrint('[Orchid] lyrics status ${res.statusCode}');
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!data.containsKey('Body')) return null;

      final bodyData = data['Body'] as Map<String, dynamic>;
      if (bodyData.containsKey('error')) {
        debugPrint('[Orchid] lyrics API error: ${bodyData['error']}');
        return null;
      }

      return _parseBody(bodyData);
    } catch (e) {
      debugPrint('[Orchid] lyrics fetch error: $e');
      return null;
    }
  }

  LyricsResult _parseBody(Map<String, dynamic> bodyData) {
    final type = bodyData['Type'] as String?;
    final source = bodyData['source'] as String? ?? 'unknown';
    final sourceVia = bodyData['source_via'] as String?;
    final trackId = bodyData['id'] as String?;
    final songWriters = (bodyData['SongWriters'] as List?)
            ?.map((e) => '$e')
            .toList() ??
        const <String>[];
    final startTime = (bodyData['StartTime'] as num?)?.toDouble();
    final endTime = (bodyData['EndTime'] as num?)?.toDouble();

    LyricsContributor? uploader;
    LyricsContributor? maker;
    final attr = bodyData['UploadAttribution'];
    if (attr is Map && source == 'spicy_lyrics') {
      final u = attr['Uploader'];
      if (u is Map) {
        uploader = LyricsContributor.fromJson(Map<String, dynamic>.from(u));
      }
      final m = attr['Maker'];
      if (m is Map) {
        maker = LyricsContributor.fromJson(Map<String, dynamic>.from(m));
      }
    }

    final content = bodyData['Content'];

    if (type == 'Syllable' && content is List) {
      final lines = <LyricLine>[];
      final plainBuf = StringBuffer();

      for (final item in content) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        if (map['Type'] != 'Vocal') continue;

        final lead = _parseSyllableGroup(map['Lead']);
        final bg = _parseSyllableGroupList(map['Background']);
        final leadMap = map['Lead'] is Map
            ? Map<String, dynamic>.from(map['Lead'] as Map)
            : null;
        final start = (leadMap?['StartTime'] as num?)?.toDouble() ??
            (lead.isNotEmpty ? lead.first.start : 0.0);
        final end = (leadMap?['EndTime'] as num?)?.toDouble() ??
            (lead.isNotEmpty ? lead.last.end : start);

        final line = LyricLine(
          lead: lead,
          background: bg,
          start: start,
          end: end,
          oppositeAligned: map['OppositeAligned'] as bool? ?? false,
          translatedText: leadMap?['TranslatedText'] as String?,
        );
        lines.add(line);
        final t = line.text;
        if (t.isNotEmpty) {
          if (plainBuf.isNotEmpty) plainBuf.writeln();
          plainBuf.write(t);
        }
      }

      final plain = plainBuf.toString().trim();
      return LyricsResult(
        plain: plain.isEmpty ? null : plain,
        synced: _linesToRoughLrc(lines),
        lines: lines,
        hasSync: lines.isNotEmpty,
        source: source,
        sourceVia: sourceVia,
        bodyType: type,
        trackId: trackId,
        songWriters: songWriters,
        uploader: uploader,
        maker: maker,
        startTime: startTime,
        endTime: endTime,
      );
    }

    if (type == 'Line' && content is List) {
      final lines = <LyricLine>[];
      final plainBuf = StringBuffer();

      for (final item in content) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final text = map['Text'] as String? ?? '';
        if (text.isEmpty) continue;
        final start = (map['StartTime'] as num?)?.toDouble() ?? 0;
        final end = (map['EndTime'] as num?)?.toDouble() ?? start + 2;
        lines.add(LyricLine(
          plainText: text,
          start: start,
          end: end,
          oppositeAligned: map['OppositeAligned'] as bool? ?? false,
          translatedText: map['TranslatedText'] as String?,
        ));
        if (plainBuf.isNotEmpty) plainBuf.writeln();
        plainBuf.write(text);
      }

      final plain = plainBuf.toString().trim();
      return LyricsResult(
        plain: plain.isEmpty ? null : plain,
        synced: _linesToRoughLrc(lines),
        lines: lines,
        hasSync: lines.isNotEmpty,
        source: source,
        sourceVia: sourceVia,
        bodyType: type,
        trackId: trackId,
        songWriters: songWriters,
        uploader: uploader,
        maker: maker,
        startTime: startTime,
        endTime: endTime,
      );
    }

    if (type == 'Static') {
      String plain = '';
      if (content is List) {
        plain = content.map((e) {
          if (e is Map) return e['Text'] as String? ?? '';
          return '$e';
        }).where((s) => s.isNotEmpty).join('\n');
      } else if (content is String) {
        plain = content;
      }
      return LyricsResult(
        plain: plain.trim().isEmpty ? null : plain.trim(),
        hasSync: false,
        source: source,
        sourceVia: sourceVia,
        bodyType: type,
        trackId: trackId,
        songWriters: songWriters,
        uploader: uploader,
        maker: maker,
      );
    }

    if (content is List) {
      final lines = <LyricLine>[];
      final plainBuf = StringBuffer();
      for (final item in content) {
        if (item is Map) {
          final text = item['Text'] as String? ?? '';
          final start = (item['StartTime'] as num?)?.toDouble();
          final end = (item['EndTime'] as num?)?.toDouble() ?? start;
          if (text.isEmpty) continue;
          if (plainBuf.isNotEmpty) plainBuf.writeln();
          plainBuf.write(text);
          if (start != null) {
            lines.add(LyricLine(
              plainText: text,
              start: start,
              end: end ?? start + 2,
            ));
          }
        }
      }
      final plain = plainBuf.toString().trim();
      return LyricsResult(
        plain: plain.isEmpty ? null : plain,
        lines: lines,
        hasSync: lines.isNotEmpty,
        source: source,
        sourceVia: sourceVia,
        bodyType: type,
        trackId: trackId,
        songWriters: songWriters,
        uploader: uploader,
        maker: maker,
        startTime: startTime,
        endTime: endTime,
      );
    }

    if (content is String && content.trim().isNotEmpty) {
      return LyricsResult(
        plain: content.trim(),
        source: source,
        sourceVia: sourceVia,
        bodyType: type,
        trackId: trackId,
        songWriters: songWriters,
        uploader: uploader,
        maker: maker,
      );
    }

    return LyricsResult(
      source: source,
      sourceVia: sourceVia,
      bodyType: type,
      trackId: trackId,
      songWriters: songWriters,
      uploader: uploader,
      maker: maker,
    );
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
      if (item is Map) out.addAll(_parseSyllableGroup(item));
    }
    return out;
  }

  String? _linesToRoughLrc(List<LyricLine> lines) {
    if (lines.isEmpty) return null;
    final buf = StringBuffer();
    for (final line in lines) {
      final t = line.text;
      if (t.isEmpty) continue;
      buf.writeln('[${_formatLrc(line.start)}] $t');
    }
    final s = buf.toString().trim();
    return s.isEmpty ? null : s;
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
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List? ?? [];
      if (results.isEmpty) return null;

      final item = results[0];
      if (item is! Map) return null;
      final m = Map<String, dynamic>.from(item);
      if (m['wrapperType'] != 'track' || m['kind'] != 'song') return null;

      String? spotifyTrackId;
      final spotifyUrl =
          m['spotifyUrl'] as String? ?? m['spotifyURL'] as String? ?? '';
      final match = RegExp(r'/track/([a-zA-Z0-9_-]+)').firstMatch(spotifyUrl);
      if (match != null) spotifyTrackId = match.group(1);

      if (spotifyTrackId == null || spotifyTrackId.isEmpty) return null;

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
