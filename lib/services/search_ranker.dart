import '../models/addon.dart';

/// Deterministic relevance ranking for results returned by all music sources.
/// Exact title/artist matches beat fuzzy matches; provider playback quality is
/// only a tie-breaker, never a reason to bury the requested song.
class SearchRanker {
  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      var diagonal = previous[0];
      previous[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final old = previous[j];
        previous[j] = [
          previous[j] + 1,
          previous[j - 1] + 1,
          diagonal + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1),
        ].reduce((x, y) => x < y ? x : y);
        diagonal = old;
      }
    }
    return previous[b.length];
  }

  static double _fieldScore(String query, String field) {
    if (query.isEmpty || field.isEmpty) return 0;
    if (query == field) return 100;
    if (field.startsWith('$query ')) return 80;
    if (field.startsWith(query)) return 74;
    if (field.contains(' $query ' ) || field.endsWith(' $query')) return 65;
    if (field.contains(query)) return 57;

    final qTokens = query.split(' ');
    final tokens = field.split(' ');
    var matches = 0.0;
    for (final word in qTokens) {
      if (tokens.contains(word)) {
        matches += 1.0;
      } else if (tokens.any((token) => token.startsWith(word) && word.length >= 3)) {
        matches += 0.75;
      } else if (word.length >= 4 &&
          tokens.any((token) => (token.length - word.length).abs() <= 2 &&
              _editDistance(token, word) <= (word.length >= 7 ? 2 : 1))) {
        matches += 0.5;
      }
    }
    final coverage = matches / qTokens.length;
    if (coverage <= 0) return 0;
    return 48 * coverage;
  }

  static double score(String query, TrackResult track) {
    final q = normalize(query);
    if (q.isEmpty) return 0;
    final title = normalize(track.title);
    final artist = normalize(track.artist);
    final album = normalize(track.album ?? '');
    final combined = normalize('${track.artist} ${track.title}');
    final reversed = normalize('${track.title} ${track.artist}');

    var rank = [
      _fieldScore(q, title) * 1.1,
      _fieldScore(q, artist) * 0.94,
      _fieldScore(q, album) * 0.60,
      _fieldScore(q, combined) * 1.02,
      _fieldScore(q, reversed) * 1.02,
    ].reduce((a, b) => a > b ? a : b);

    // Penalize alternate recordings when the query does not request them.
    final version = RegExp(r'\b(live|remix|karaoke|instrumental|cover|sped up|slowed|nightcore)\b');
    if (version.hasMatch(title) && !version.hasMatch(q)) rank -= 9;
    if (track.fromStreamAddon) rank += 3;
    if (track.artworkUrl?.isNotEmpty ?? false) rank += 0.5;
    return rank;
  }

  static List<TrackResult> rank(String query, List<TrackResult> tracks) {
    final indexed = tracks.asMap().entries.toList();
    indexed.sort((a, b) {
      final diff = score(query, b.value).compareTo(score(query, a.value));
      return diff != 0 ? diff : a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }
}
