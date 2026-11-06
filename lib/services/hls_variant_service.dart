import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Chooses an AVC/H.264 rendition when an HLS master playlist advertises one.
/// This avoids known HEVC/fMP4 byte-range demuxer incompatibilities on some
/// mpv/FFmpeg builds. A media playlist (without variants) is left unchanged.
class HlsVariantService {
  HlsVariantService._();
  static final instance = HlsVariantService._();

  final Map<String, Future<String>> _cache = {};

  Future<String> preferredUrl(String url) =>
      _cache.putIfAbsent(url, () => _resolve(url));

  Future<String> _resolve(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' ||
        !uri.path.toLowerCase().endsWith('.m3u8')) return url;
    try {
      final response = await http.get(uri, headers: const {
        'Accept': 'application/vnd.apple.mpegurl, application/x-mpegURL, */*',
        'User-Agent': 'Mozilla/5.0',
      }).timeout(const Duration(seconds: 7));
      if (response.statusCode != 200 || response.bodyBytes.length > 512 * 1024) {
        return url;
      }
      final body = response.body;
      if (!body.startsWith('#EXTM3U') ||
          !body.contains('#EXT-X-STREAM-INF')) return url;

      // The CODECS attribute belongs to the stream declaration; the next
      // non-comment line supplies the relative or absolute variant URI.
      final lines = body.split(RegExp(r'\r?\n'));
      final options = <({String url, bool avc, bool hevc, int bandwidth})>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
        var j = i + 1;
        while (j < lines.length && lines[j].trim().isEmpty) j++;
        if (j >= lines.length) continue;
        final target = lines[j].trim();
        if (target.isEmpty || target.startsWith('#')) continue;
        final next = uri.resolve(target);
        if (next.scheme != 'https' || next.host.isEmpty) continue;
        final codec = RegExp(r'CODECS="([^"]+)"').firstMatch(line)?.group(1)?.toLowerCase() ?? '';
        final speed = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1);
        options.add((
          url: next.toString(),
          avc: codec.contains('avc1') || codec.contains('avc3'),
          hevc: codec.contains('hvc1') || codec.contains('hev1') ||
              codec.contains('dvhe') || codec.contains('dvh1'),
          bandwidth: int.tryParse(speed ?? '') ?? 0,
        ));
      }
      final avc = options.where((option) => option.avc && !option.hevc).toList()
        ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      if (avc.isNotEmpty) {
        debugPrint('[Orchid Artwork] Using AVC HLS rendition instead of HEVC');
        return avc.first.url;
      }
      debugPrint('[Orchid Artwork] No AVC rendition advertised; using source HLS playlist');
    } catch (e) {
      debugPrint('[Orchid Artwork] HLS variant inspection failed: $e');
    }
    return url;
  }
}
