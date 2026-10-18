import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/addon.dart';

class AddonService {
  static const _storageKey = 'orchid_addons_v1';
  static const _itunesSearch =
      'https://itunes.apple.com/search';

  final http.Client _client;

  AddonService({http.Client? client}) : _client = client ?? http.Client();

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
    final res =
        await _client.get(manifestUri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('manifest HTTP ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final manifest = AddonManifest.fromJson(json);
    if (manifest.id.isEmpty || manifest.name.isEmpty) {
      throw Exception('Invalid manifest (missing id/name)');
    }
    return InstalledAddon(baseUrl: base, manifest: manifest);
  }

  /// Search iTunes + every installed search addon, then dedupe.
  Future<List<TrackResult>> search(
    List<InstalledAddon> addons,
    String query,
  ) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final buckets = await Future.wait([
      _searchItunes(q),
      _searchAddons(addons, q),
    ]);

    return _dedupe([...buckets[0], ...buckets[1]]);
  }

  Future<List<TrackResult>> _searchItunes(String q) async {
    try {
      final uri = Uri.parse(_itunesSearch).replace(queryParameters: {
        'term': q,
        'entity': 'song',
        'media': 'music',
        'limit': '25',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List? ?? [];
      final out = <TrackResult>[];
      for (final item in results) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        if (m['wrapperType'] != 'track' || m['kind'] != 'song') continue;
        final art = m['artworkUrl100'] as String?;
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
            sourceId: 'itunes',
            sourceName: 'iTunes',
            fromStreamAddon: false,
          ),
        );
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<TrackResult>> _searchAddons(
    List<InstalledAddon> addons,
    String q,
  ) async {
    final searchable = addons.where((a) => a.manifest.canSearch).toList();
    final results = <TrackResult>[];

    await Future.wait(searchable.map((addon) async {
      try {
        final uri = Uri.parse('${addon.baseUrl}/search').replace(
          queryParameters: {'q': q},
        );
        final res =
            await _client.get(uri).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) return;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final tracks = body['tracks'] as List? ?? [];
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
      } catch (_) {
        // skip failed addon
      }
    }));

    return results;
  }

  /// Prefer stream-addon hits, then iTunes, keep first of each dedupe key.
  List<TrackResult> _dedupe(List<TrackResult> input) {
    final ranked = List<TrackResult>.from(input)
      ..sort((a, b) {
        final as = a.fromStreamAddon ? 0 : (a.sourceId == 'itunes' ? 1 : 2);
        final bs = b.fromStreamAddon ? 0 : (b.sourceId == 'itunes' ? 1 : 2);
        return as.compareTo(bs);
      });

    final seen = <String>{};
    final out = <TrackResult>[];
    for (final t in ranked) {
      final key = t.dedupeKey;
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(t);
    }
    return out;
  }

  /// Resolve a playable URL using stream-capable addons, then iTunes preview.
  Future<StreamInfo> resolvePlayback(
    TrackResult track,
    List<InstalledAddon> addons,
  ) async {
    final streamAddons =
        addons.where((a) => a.manifest.canStream).toList();

    // 1) Track already tied to a stream addon
    if (track.fromStreamAddon &&
        track.addonBaseUrl != null &&
        track.addonBaseUrl!.isNotEmpty) {
      try {
        return await _streamFromAddon(track.addonBaseUrl!, track.id);
      } catch (_) {
        // fall through
      }
    }

    // 2) Ask each stream addon to search and match this recording
    final query = '${track.artist} ${track.title}';
    for (final addon in streamAddons) {
      // Skip if this is the same addon we already tried
      if (track.addonBaseUrl == addon.baseUrl) continue;
      try {
        final matched = await _matchOnAddon(addon, track, query);
        if (matched == null) continue;
        return await _streamFromAddon(addon.baseUrl, matched);
      } catch (_) {
        continue;
      }
    }

    // 3) iTunes / search-provided preview as last resort
    if (track.previewUrl != null && track.previewUrl!.isNotEmpty) {
      return StreamInfo(
        url: track.previewUrl!,
        format: track.format ?? 'm4a',
        quality: 'preview',
        via: track.sourceName,
      );
    }

    throw Exception('No stream addon could play this track');
  }

  Future<String?> _matchOnAddon(
    InstalledAddon addon,
    TrackResult target,
    String query,
  ) async {
    // Prefer search if available
    if (addon.manifest.canSearch) {
      final uri = Uri.parse('${addon.baseUrl}/search').replace(
        queryParameters: {'q': query},
      );
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final tracks = body['tracks'] as List? ?? [];
      String? bestId;
      var bestScore = -1;
      for (final t in tracks) {
        if (t is! Map) continue;
        final m = Map<String, dynamic>.from(t);
        final score = _matchScore(target, m);
        if (score > bestScore) {
          bestScore = score;
          bestId = '${m['id']}';
        }
      }
      // Require at least title-ish match
      if (bestScore >= 2 && bestId != null) return bestId;
    }
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
      final d = (candidate['duration'] as int - target.duration!).abs();
      if (d <= 3) score += 2;
      else if (d <= 8) score += 1;
    }
    return score;
  }

  Future<StreamInfo> _streamFromAddon(String baseUrl, String id) async {
    final uri = Uri.parse('$baseUrl/stream/${Uri.encodeComponent(id)}');
    final res = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('stream HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['url'] is! String || (body['url'] as String).isEmpty) {
      throw Exception('Addon returned no direct url (client-resolved?)');
    }
    return StreamInfo.fromJson(body, via: baseUrl);
  }
}
