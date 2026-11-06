import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../services/apple_artwork_service.dart';

/// Apple's album/track artwork when available, Last.fm image otherwise.
class AppleCover extends StatelessWidget {
  final String artist;
  final String name;
  final String? album;
  final String? fallbackUrl;
  final String? preferredUrl;
  final bool isAlbum;
  final double size;
  final double radius;

  const AppleCover({
    super.key,
    required this.artist,
    required this.name,
    this.album,
    this.fallbackUrl,
    this.preferredUrl,
    this.isAlbum = false,
    this.size = 48,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    // Catalog-provided cover URLs are authoritative; don't issue an extra
    // iTunes request for every result card while search is rendering.
    final direct = preferredUrl != null && preferredUrl!.startsWith('https://')
        ? preferredUrl
        : fallbackUrl != null && fallbackUrl!.startsWith('https://')
            ? fallbackUrl
            : null;
    final lookup = direct != null
        ? Future<String?>.value(direct)
        : isAlbum
            ? AppleArtworkService.instance.album(artist: artist, album: name)
            : AppleArtworkService.instance.trackOrAlbum(
                artist: artist,
                title: name,
                album: album,
              );
    return FutureBuilder<String?>(
      future: lookup,
      builder: (context, snapshot) {
        final apple = snapshot.data;
        final fallback = fallbackUrl;
        final url = preferredUrl != null &&
                preferredUrl!.startsWith('https://')
            ? preferredUrl
            : apple != null && apple.startsWith('https://')
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
                    errorBuilder: (_, __, ___) =>
                        apple != null && fallback != null &&
                                fallback.startsWith('https://') &&
                                fallback != apple
                            ? Image.network(
                                fallback,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => placeholder(),
                              )
                            : placeholder(),
                  ),
          ),
        );
      },
    );
  }
}
