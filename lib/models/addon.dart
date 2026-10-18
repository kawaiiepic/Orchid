class AddonManifest {
  final String id;
  final String name;
  final String version;
  final String? description;
  final List<String> resources;
  final List<String> types;

  const AddonManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.resources = const [],
    this.types = const [],
  });

  bool get canSearch => resources.contains('search');
  bool get canStream => resources.contains('stream');

  factory AddonManifest.fromJson(Map<String, dynamic> json) {
    return AddonManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      version: json['version'] as String? ?? '0',
      description: json['description'] as String?,
      resources: (json['resources'] as List?)?.cast<String>() ?? const [],
      types: (json['types'] as List?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        if (description != null) 'description': description,
        'resources': resources,
        'types': types,
      };
}

class InstalledAddon {
  final String baseUrl;
  final AddonManifest manifest;

  const InstalledAddon({required this.baseUrl, required this.manifest});

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'manifest': manifest.toJson(),
      };

  factory InstalledAddon.fromJson(Map<String, dynamic> json) {
    return InstalledAddon(
      baseUrl: json['baseUrl'] as String,
      manifest: AddonManifest.fromJson(
        Map<String, dynamic>.from(json['manifest'] as Map),
      ),
    );
  }
}

class TrackResult {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final int? duration;
  final String? artworkUrl;
  final String? format;
  final String? isrc;
  /// Direct playable URL when the search source already provides one (e.g. iTunes preview).
  final String? previewUrl;
  /// Spotify track ID (22 base62 chars) for services like Spicy Lyrics.
  final String? spotifyTrackId;
  /// YouTube video ID from stream-capable addons (used for direct Spicy Lyrics lookup).
  final String? videoId;
  final String sourceId;
  final String sourceName;
  /// True when this hit came from a stream-capable addon with a resolvable id.
  final bool fromStreamAddon;
  final String? addonBaseUrl;

  const TrackResult({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.artworkUrl,
    this.format,
    this.isrc,
    this.previewUrl,
    this.spotifyTrackId,
    this.videoId,
    required this.sourceId,
    required this.sourceName,
    this.fromStreamAddon = false,
    this.addonBaseUrl,
  });

  /// Key used to collapse duplicate songs across sources.
  String get dedupeKey {
    if (isrc != null && isrc!.isNotEmpty) {
      return 'isrc:${isrc!.toUpperCase()}';
    }
    return 't:${_norm(title)}|a:${_norm(artist)}';
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  factory TrackResult.fromAddonJson(
    Map<String, dynamic> json, {
    required String addonBaseUrl,
    required String addonName,
    required bool canStream,
  }) {
    // Extract Spotify track ID from addon response
    String? spotifyTrackId;
    
    // Try explicit field first
    if (json.containsKey('spotifyTrackId')) {
      spotifyTrackId = json['spotifyTrackId'] as String? ?? '';
    }
    
    // Try to extract from URL fields if not explicitly provided
    if (spotifyTrackId == null || spotifyTrackId.isEmpty) {
      final urlField = json['url'] as String? ?? json['URL'] as String? ?? json['streamUrl'] as String?;
      if (urlField != null && urlField.contains('open.spotify.com/track/')) {
        final match = RegExp(r'/track/([a-zA-Z0-9_-]+)').firstMatch(urlField);
        if (match != null) {
          spotifyTrackId = match.group(1)!;
        }
      }
    }

    return TrackResult(
      id: '${json['id']}',
      title: json['title'] as String? ?? 'Unknown',
      artist: json['artist'] as String? ?? 'Unknown',
      album: json['album'] as String?,
      duration: json['duration'] is int ? json['duration'] as int : null,
      artworkUrl: json['artworkURL'] as String?,
      format: json['format'] as String?,
      isrc: json['isrc'] as String?,
      previewUrl: json['streamURL'] as String?,
      spotifyTrackId: (spotifyTrackId ?? '').isEmpty ? null : spotifyTrackId,
      videoId: json['videoId'] as String?,
      sourceId: addonBaseUrl,
      sourceName: addonName,
      fromStreamAddon: canStream,
      addonBaseUrl: canStream ? addonBaseUrl : null,
    );
  }
}

class StreamInfo {
  final String url;
  final String? format;
  final String? quality;
  final String? via;

  const StreamInfo({
    required this.url,
    this.format,
    this.quality,
    this.via,
  });

  factory StreamInfo.fromJson(Map<String, dynamic> json, {String? via}) {
    return StreamInfo(
      url: json['url'] as String,
      format: json['format'] as String?,
      quality: json['quality'] as String?,
      via: via,
    );
  }
}
