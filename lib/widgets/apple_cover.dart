import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../services/apple_artwork_service.dart';

/// Apple's album/track artwork when available, Last.fm image otherwise.
class AppleCover extends StatelessWidget {
  final String artist;
  final String name;
  final String? fallbackUrl;
  final bool isAlbum;
  final double size;
  final double radius;

  const AppleCover({
    super.key,
    required this.artist,
    required this.name,
    this.fallbackUrl,
    this.isAlbum = false,
    this.size = 48,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final lookup = isAlbum
        ? AppleArtworkService.instance.album(artist: artist, album: name)
        : AppleArtworkService.instance.track(artist: artist, title: name);
    return FutureBuilder<String?>(
      future: lookup,
      builder: (context, snapshot) {
        final apple = snapshot.data;
        final fallback = fallbackUrl;
        final url = apple != null && apple.startsWith('https://')
            ? apple
            : fallback != null && fallback.startsWith('https://')
                ? fallback
                : null;
        Widget placeholder() => ColoredBox(
          color: Theme.of(context).colorScheme.muted,
          child: const Center(child: Icon(LucideIcons.music2, size: 20)),
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox(
            width: size,
            height: size,
            child: url == null
                ? placeholder()
                : Image.network(
                    url,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholder(),
                  ),
          ),
        );
      },
    );
  }
}
