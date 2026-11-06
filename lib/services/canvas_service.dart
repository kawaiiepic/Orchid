import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Spotify Canvas is served by a user-configured backend. Never put Spotify
/// session cookies in the Flutter client or in this repository.
class CanvasService extends ChangeNotifier {
  static final CanvasService instance = CanvasService._();
  static const _key = 'orchid_canvas_api_url';
  final Map<String, String?> _cache = {};
  String endpoint = '';
  bool loaded = false;

  CanvasService._();

  Future<void> load() async {
    if (loaded) return;
    final prefs = await SharedPreferences.getInstance();
    endpoint = prefs.getString(_key) ?? '';
    loaded = true;
    notifyListeners();
  }

  Future<void> setEndpoint(String input) async {
    final value = input.trim().replaceFirst(RegExp(r'/+$'), '');
    if (value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
          uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
        throw const FormatException('Use an HTTPS Canvas API base URL.');
      }
    }
    endpoint = value;
    _cache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value);
    notifyListeners();
  }

  Future<String?> fetch(String? trackId) async {
    if (!loaded) await load();
    final id = trackId ?? '';
    if (endpoint.isEmpty || !RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(id)) {
      return null;
    }
    if (_cache.containsKey(id)) return _cache[id];
    try {
      final uri = Uri.parse('$endpoint/api/canvas')
          .replace(queryParameters: {'trackId': id});
      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint('[Orchid Canvas] HTTP ${response.statusCode}');
        return null;
      }
      final body = jsonDecode(response.body);
      if (body is! Map) return null;
      final data = body['data'];
      if (data is! Map) return null;
      final canvases = data['canvasesList'];
      if (canvases is! List) return null;
      for (final item in canvases) {
        if (item is! Map) continue;
        final rawUrl = item['canvasUrl'];
        if (rawUrl is! String) continue;
        final video = Uri.tryParse(rawUrl);
        if (video == null || video.scheme != 'https' ||
            video.host != 'canvaz.scdn.co') continue;
        _cache[id] = rawUrl;
        return rawUrl;
      }
    } catch (e) {
      debugPrint('[Orchid Canvas] Lookup failed: $e');
    }
    return null;
  }
}
