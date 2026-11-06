import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/addon.dart';
import './internal_addons/spotify_addon_service.dart';
import 'search_ranker.dart';

class AddonService {
  static const _storageKey = 'orchid_addons_v1';
  static const _itunesSearch = 'https://itunes.apple.com/search';

  final http.Client _client;

  /// Last resolve steps for UI (newest last).
  final List<String> lastDebug = [];

  AddonService({http.Client? client}) : _client = client ?? http.Client();

  void _log(String msg) {
    debugPrint('[Orchid] $msg');
    lastDebug.add(msg);
    if (lastDebug.length > 40) {
      lastDebug.removeRange(0, lastDebug.length - 40);
    }
  }

  static String normalizeBase(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.endsWith('/manifest.json')) {
      u = u.substring(0, u.length - '/manifest.json'.length);
    }
    return u;
  }

  Future<List<InstalledAddon>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => InstalledAddon.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> save(List<InstalledAddon> addons) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(addons.map((a) => a.toJson()).toList()),
    );
  }

  Future<InstalledAddon> fetchAndBuild(String url) async {
    final base = normalizeBase(url);
    final manifestUri = Uri.parse('$base/manifest.json');
    _log('fetch manifest $manifestUri');
    final res =
        await _client.get(manifestUri).timeout(const Duration(seconds: 12));
    _log('manifest HTTP ${res.statusCode}');
    if (res.statusCode != 200) {
      throw Exception('manifest HTTP ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final manifest = AddonManifest.fromJson(json);
    if (manifest.id.isEmpty || manifest.name.isEmpty) {
      throw Exception('Invalid manifest (missing id/name)');
    }
    _log(
      'installed ${manifest.name} id=${manifest.id} resources=${manifest.resources}',
    );
    return InstalledAddon(baseUrl: base, manifest: manifest);
  }

  Future<List<TrackResult>> search(
    List<InstalledAddon> addons,
    String query,
  ) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    lastDebug.clear();
    _log('search q="$q" addons=${addons.length}');
    for (final a in addons) {
      _log(
        '  addon ${a.manifest.name} search=${a.manifest.canSearch} stream=${a.manifest.canStream} ${a.baseUrl}',
      );
    }

    final buckets = await Future.wait([
      _searchItunes(q),
      _searchAddons(addons, q),
      _searchSpotifyAddon(q),
    ]);

    final merged = [
      ...buckets[0],  // iTunes results
      ...buckets[1],  // User addon results
      ...buckets[2],  // Spotify addon results (fallback)
    ];
    _log('raw hits: itunes=${buckets[0].length} addons=${buckets[1].length} spotify=${buckets[2].length}');
    final deduped = _dedupe(merged);
    _log('after dedupe: ${deduped.length}');
    return SearchRanker.rank(q, deduped);
  }

  Future<List<TrackResult>> _searchItunes(String q) async {
    try {
      final uri = Uri.parse(_itunesSearch).replace(queryParameters: {
        'term': q,
        'entity': 'song',
        'media': 'music',
        'limit': '25',
      });
      final res = await _getWithRetry(uri);
      _log('itunes search HTTP ${res.statusCode}');
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List? ?? [];
      final out = <TrackResult>[];
      for (final item in results) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        if (m['wrapperType'] != 'track' || m['kind'] != 'song') continue;
        final art = m['artworkUrl100'] as String?;
        // Extract Spotify track ID if available in iTunes response
        String? spotifyTrackId;
        final hasSpotifyUrl = m.containsKey('spotifyUrl') || m.containsKey('spotifyURL');
        if (hasSpotifyUrl) {
          final spotifyUrl = m['spotifyUrl'] as String? ?? m['spotifyURL'] as String? ?? '';
          // Extract track ID from Spotify URL: https://open.spotify.com/track/{ID}...
          final match = RegExp(r'/track/([a-zA-Z0-9_-]+)').firstMatch(spotifyUrl);
          if (match != null) {
            spotifyTrackId = match.group(1)!;
          }
        }

        out.add(
          TrackResult(
            id: '${m['trackId']}',
            title: m['trackName'] as String? ?? 'Unknown',
            artist: m['artistName'] as String? ?? 'Unknown',
            album: m['collectionName'] as String?,
            duration: m['trackTimeMillis'] is int
                ? ((m['trackTimeMillis'] as int) / 1000).round()
                : null,
            artworkUrl: art?.replaceAll('100x100bb', '600x600bb'),
            format: 'm4a',
            previewUrl: m['previewUrl'] as String?,
            spotifyTrackId: spotifyTrackId,
            sourceId: 'itunes',
            sourceName: 'iTunes',
            fromStreamAddon: false,
          ),
        );
      }
      return out;
    } catch (e) {
      _log('itunes search error: $e');
      return [];
    }
  }

  Future<List<TrackResult>> _searchAddons(
    List<InstalledAddon> addons,
    String q,
  ) async {
    final searchable = addons.where((a) => a.manifest.canSearch).toList();
    _log('searchable addons: ${searchable.length}');
    final results = <TrackResult>[];

    await Future.wait(searchable.map((addon) async {
      try {
        final uri = Uri.parse('${addon.baseUrl}/search').replace(
          queryParameters: {'q': q},
        );
        _log('GET $uri');
        final res =
            await _client.get(uri).timeout(const Duration(seconds: 15));
        _log('${addon.manifest.name} search HTTP ${res.statusCode}');
        if (res.statusCode != 200) {
          _log('${addon.manifest.name} body: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
          return;
        }
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final tracks = body['tracks'] as List? ?? [];
        _log('${addon.manifest.name} tracks=${tracks.length}');
        for (final t in tracks) {
          if (t is! Map) continue;
          results.add(
            TrackResult.fromAddonJson(
              Map<String, dynamic>.from(t),
              addonBaseUrl: addon.baseUrl,
              addonName: addon.manifest.name,
              canStream: addon.manifest.canStream,
            ),
          );
        }
      } catch (e) {
        _log('${addon.manifest.name} search error: $e');
      }
    }));

    return results;
  }

  Future<List<TrackResult>> _searchSpotifyAddon(String q) async {
    try {
      final spotify = SpotifyAddonService();
      final results = await spotify.searchTracks(q, limit: 25);
      
      if (results.isNotEmpty) {
        _log('spotify addon found ${results.length} tracks');
      }
      return results;
    } catch (e) {
      _log('spotify addon search error: $e');
      return [];
    }
  }

  /// Collapse duplicate recordings even when providers attach different ISRCs,
  /// IDs or albums to the same title/artist. Explicit version titles remain
  /// separate (for example: live, acoustic or remastered).
  List<TrackResult> _dedupe(List<TrackResult> input) {
    int priority(TrackResult t) {
      if (t.fromStreamAddon) return 0;
      if (t.spotifyTrackId?.isNotEmpty ?? false) return 1;
      if (t.previewUrl?.isNotEmpty ?? false) return 2;
      return 3;
    }

    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\\s+'), ' ');

    final ranked = List<TrackResult>.from(input)
      ..sort((a, b) => priority(a).compareTo(priority(b)));

    final seen = <String>{};
    final result = <TrackResult>[];
    for (final track in ranked) {
      // Do not use ISRC as the primary key: the same song can have several
      // ISRCs, while many other hits have no ISRC at all.
      final title = normalize(track.title);
      final artist = normalize(track.artist);
      final identity = title.isNotEmpty && artist.isNotEmpty
          ? 'song:$artist|$title'
          : 'id:${track.sourceId}|${track.id}';
      if (seen.add(identity)) {
        result.add(track);
      }
    }
    _log('collapsed ${input.length - result.length} duplicate songs');
    return result;
  }

  Future<StreamInfo> resolvePlayback(
    TrackResult track,
    List<InstalledAddon> addons,
  ) async {
    lastDebug.clear();
    _log(
      'resolvePlayback "${track.title}" – ${track.artist} '
      'source=${track.sourceName} fromStreamAddon=${track.fromStreamAddon} '
      'addonBase=${track.addonBaseUrl} id=${track.id} '
      'preview=${track.previewUrl != null}',
    );

    final streamAddons =
        addons.where((a) => a.manifest.canStream).toList();
    _log('stream-capable addons: ${streamAddons.length}');
    for (final a in streamAddons) {
      _log(
        '  stream addon ${a.manifest.name} search=${a.manifest.canSearch} '
        '${a.baseUrl} resources=${a.manifest.resources}',
      );
    }

    if (streamAddons.isEmpty) {
      _log('no stream addons installed');
    }

    // 1) Track already tied to a stream addon
    if (track.fromStreamAddon &&
        track.addonBaseUrl != null &&
        track.addonBaseUrl!.isNotEmpty) {
      _log('step1: direct stream from ${track.addonBaseUrl} id=${track.id}');
      try {
        final info = await _streamFromAddon(track.addonBaseUrl!, track.id);
        _log('step1 OK via ${info.via}');
        return info;
      } catch (e) {
        _log('step1 FAILED: $e');
      }
    } else {
      _log('step1 skipped (not from stream addon)');
    }

    // 2) Match on each stream addon
    final query = '${track.artist} ${track.title}';
    _log('step2: match query="$query"');
    for (final addon in streamAddons) {
      if (track.addonBaseUrl == addon.baseUrl) {
        _log('step2 skip same addon ${addon.manifest.name}');
        continue;
      }
      _log('step2 try ${addon.manifest.name}');
      try {
        final matched = await _matchOnAddon(addon, track, query);
        if (matched == null) {
          _log('step2 ${addon.manifest.name}: no match');
          continue;
        }
        _log('step2 ${addon.manifest.name}: matched id=$matched → stream');
        final info = await _streamFromAddon(addon.baseUrl, matched);
        _log('step2 OK via ${info.via} url=${info.url.substring(0, info.url.length.clamp(0, 80))}…');
        return info;
      } catch (e) {
        _log('step2 ${addon.manifest.name} FAILED: $e');
        continue;
      }
    }

    // 3) Preview fallback
    if (track.previewUrl != null && track.previewUrl!.isNotEmpty) {
      _log('step3: falling back to preview (${track.sourceName})');
      return StreamInfo(
        url: track.previewUrl!,
        format: track.format ?? 'm4a',
        quality: 'preview',
        via: '${track.sourceName} preview',
      );
    }

    _log('step3: no preview either — giving up');
    throw Exception('No stream addon could play this track');
  }

  // Retry only transient transport failures, not valid 'not found' answers.
  Future<http.Response> _getWithRetry(Uri uri) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _client.get(uri)
            .timeout(const Duration(seconds: 12));
        if (![429, 500, 502, 503, 504].contains(response.statusCode) ||
            attempt == 2) {
          return response;
        }
        _log('Temporary source HTTP ${response.statusCode}; retry ${attempt + 1}/2');
      } catch (e) {
        if (attempt == 2) rethrow;
        _log('Temporary source error: $e; retry ${attempt + 1}/2');
      }
      await Future<void>.delayed(Duration(milliseconds: 450 * (attempt + 1)));
    }
    throw StateError('Source request retry exhausted');
  }

  Future<String?> _matchOnAddon(
    InstalledAddon addon,
    TrackResult target,
    String query,
  ) async {
    if (!addon.manifest.canSearch) {
      _log(
        '  ${addon.manifest.name}: no search capability '
        '(resources=${addon.manifest.resources}) — cannot match iTunes hit',
      );
      return null;
    }

    final uri = Uri.parse('${addon.baseUrl}/search').replace(
      queryParameters: {'q': query},
    );
    _log('  GET $uri');
    final res = await _client.get(uri).timeout(const Duration(seconds: 12));
    _log('  ${addon.manifest.name} match-search HTTP ${res.statusCode}');
    if (res.statusCode != 200) {
      final snippet =
          res.body.length > 180 ? '${res.body.substring(0, 180)}…' : res.body;
      _log('  body: $snippet');
      return null;
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final tracks = body['tracks'] as List? ?? [];
    _log('  candidates=${tracks.length}');

    String? bestId;
    var bestScore = -1;
    String? bestLabel;
    for (final t in tracks) {
      if (t is! Map) continue;
      final m = Map<String, dynamic>.from(t);
      final score = _matchScore(target, m);
      final label = '${m['title']} – ${m['artist']}';
      if (score > bestScore) {
        bestScore = score;
        bestId = '${m['id']}';
        bestLabel = label;
      }
    }
    _log('  best score=$bestScore id=$bestId ($bestLabel) need>=2');
    if (bestScore >= 2 && bestId != null) return bestId;
    return null;
  }

  int _matchScore(TrackResult target, Map<String, dynamic> candidate) {
    var score = 0;
    final cTitle = '${candidate['title'] ?? ''}'.toLowerCase();
    final cArtist = '${candidate['artist'] ?? ''}'.toLowerCase();
    final tTitle = target.title.toLowerCase();
    final tArtist = target.artist.toLowerCase();

    if (target.isrc != null &&
        candidate['isrc'] != null &&
        '${candidate['isrc']}'.toUpperCase() == target.isrc!.toUpperCase()) {
      return 100;
    }
    if (cTitle == tTitle) {
      score += 3;
    } else if (cTitle.contains(tTitle) || tTitle.contains(cTitle)) {
      score += 2;
    }
    if (cArtist == tArtist) {
      score += 3;
    } else if (cArtist.contains(tArtist) || tArtist.contains(cArtist)) {
      score += 1;
    }
    if (target.duration != null && candidate['duration'] is int) {
      final d = ((candidate['duration'] as int) - target.duration!).abs();
      if (d <= 3) {
        score += 2;
      } else if (d <= 8) {
        score += 1;
      }
    }
    return score;
  }

  Future<StreamInfo> _streamFromAddon(String baseUrl, String id) async {
    final uri = Uri.parse('$baseUrl/stream/${Uri.encodeComponent(id)}');
    _log('  GET $uri');
    final res = await _client.get(uri).timeout(const Duration(seconds: 12));
    _log('  stream HTTP ${res.statusCode}');
    if (res.statusCode != 200) {
      final snippet =
          res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body;
      _log('  stream body: $snippet');
      throw Exception('stream HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    _log('  stream keys: ${body.keys.toList()}');
    if (body['url'] is! String || (body['url'] as String).isEmpty) {
      _log(
        '  no direct url — client-resolved or unexpected payload '
        '(playback may need X-Eclipse-Access / client resolve)',
      );
      throw Exception('Addon returned no direct url (client-resolved?)');
    }
    return StreamInfo.fromJson(body, via: baseUrl);
  }
}
