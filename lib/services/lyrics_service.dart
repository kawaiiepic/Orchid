import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/addon.dart';

class LyricsResult {
  final String? plain;
  final String? synced;
  final String source;

  const LyricsResult({
    this.plain,
    this.synced,
    this.source = 'lrclib',
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
}

/// https://lrclib.net/docs
class LyricsService {
  final http.Client _client;

  LyricsService({http.Client? client}) : _client = client ?? http.Client();

  Future<LyricsResult?> fetchFor(TrackResult track) async {
    // 1) Precise get
    final got = await _get(
      trackName: track.title,
      artistName: track.artist,
      albumName: track.album,
      duration: track.duration,
    );
    if (got != null && got.hasAny) return got;

    // 2) Search fallback
    return _search('${track.artist} ${track.title}');
  }

  Future<LyricsResult?> _get({
    required String trackName,
    required String artistName,
    String? albumName,
    int? duration,
  }) async {
    try {
      final params = <String, String>{
        'track_name': trackName,
        'artist_name': artistName,
        if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
        if (duration != null) 'duration': '$duration',
      };
      final uri = Uri.https('lrclib.net', '/api/get', params);
      debugPrint('[Orchid] lyrics GET $uri');
      final res = await _client.get(
        uri,
        headers: {'User-Agent': 'Orchid/0.1 (Flutter music player)'},
      ).timeout(const Duration(seconds: 10));
      debugPrint('[Orchid] lyrics get HTTP ${res.statusCode}');
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) return null;
      return _fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[Orchid] lyrics get error: $e');
      return null;
    }
  }

  Future<LyricsResult?> _search(String q) async {
    try {
      final uri = Uri.https('lrclib.net', '/api/search', {'q': q});
      debugPrint('[Orchid] lyrics search $uri');
      final res = await _client.get(
        uri,
        headers: {'User-Agent': 'Orchid/0.1 (Flutter music player)'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) return null;
      final first = Map<String, dynamic>.from(list.first as Map);
      return _fromJson(first);
    } catch (e) {
      debugPrint('[Orchid] lyrics search error: $e');
      return null;
    }
  }

  LyricsResult _fromJson(Map<String, dynamic> json) {
    return LyricsResult(
      plain: json['plainLyrics'] as String?,
      synced: json['syncedLyrics'] as String?,
      source: 'lrclib',
    );
  }
}
