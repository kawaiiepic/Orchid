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
  final String addonBaseUrl;
  final String addonName;

  const TrackResult({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.artworkUrl,
    this.format,
    required this.addonBaseUrl,
    required this.addonName,
  });

  factory TrackResult.fromJson(
    Map<String, dynamic> json, {
    required String addonBaseUrl,
    required String addonName,
  }) {
    return TrackResult(
      id: '${json['id']}',
      title: json['title'] as String? ?? 'Unknown',
      artist: json['artist'] as String? ?? 'Unknown',
      album: json['album'] as String?,
      duration: json['duration'] is int ? json['duration'] as int : null,
      artworkUrl: json['artworkURL'] as String?,
      format: json['format'] as String?,
      addonBaseUrl: addonBaseUrl,
      addonName: addonName,
    );
  }
}

class StreamInfo {
  final String url;
  final String? format;
  final String? quality;

  const StreamInfo({required this.url, this.format, this.quality});

  factory StreamInfo.fromJson(Map<String, dynamic> json) {
    return StreamInfo(
      url: json['url'] as String,
      format: json['format'] as String?,
      quality: json['quality'] as String?,
    );
  }
}
