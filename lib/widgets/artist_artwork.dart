import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'orchid_hover_zoom.dart';
import '../services/artist_image_service.dart';

/// Artist portraits are looked up by name, not inferred from an album cover.
class ArtistArtwork extends StatelessWidget {
  final String artist;
  final double size;
  final String? fallbackUrl;
  final double radius;
  final bool zoomOnHover;

  const ArtistArtwork({
    super.key,
    required this.artist,
    required this.size,
    this.fallbackUrl,
    this.radius = 12,
    this.zoomOnHover = true,
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: ArtistImageService.instance.imageFor(artist),
    builder: (context, snapshot) {
      final url = snapshot.data ?? fallbackUrl;
      final artwork = SizedBox(
        width: size,
        height: size,
        child: url == null || !url.startsWith('https://')
            ? _placeholder(context)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(context),
              ),
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: zoomOnHover ? OrchidHoverZoom(child: artwork) : artwork,
      );
    },
  );

  Widget _placeholder(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF563876), Color(0xFF211D31)],
      ),
    ),
    child: Center(
      child: Icon(LucideIcons.music2,
          color: const Color(0xFFE0CBFF), size: size * 0.38),
    ),
  );
}
