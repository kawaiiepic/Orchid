import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/addon.dart';

class AddonService {
  static const _storageKey = 'orchid_addons_v1';

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
    final res = await _client.get(manifestUri).timeout(const Duration(seconds: 12));
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

  Future<List<TrackResult>> search(List<InstalledAddon> addons, String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final searchable = addons.where((a) => a.manifest.canSearch).toList();
    final results = <TrackResult>[];

    await Future.wait(searchable.map((addon) async {
      try {
        final uri = Uri.parse('${addon.baseUrl}/search').replace(
          queryParameters: {'q': q},
        );
        final res = await _client.get(uri).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) return;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final tracks = body['tracks'] as List? ?? [];
        for (final t in tracks) {
          if (t is! Map) continue;
          results.add(
            TrackResult.fromJson(
              Map<String, dynamic>.from(t),
              addonBaseUrl: addon.baseUrl,
              addonName: addon.manifest.name,
            ),
          );
        }
      } catch (_) {
        // skip failed addon
      }
    }));

    return results;
  }

  Future<StreamInfo> resolveStream(TrackResult track) async {
    final uri = Uri.parse(
      '${track.addonBaseUrl}/stream/${Uri.encodeComponent(track.id)}',
    );
    final res = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('stream HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final info = StreamInfo.fromJson(body);
    if (info.url.isEmpty) throw Exception('Empty stream URL');
    return info;
  }
}
