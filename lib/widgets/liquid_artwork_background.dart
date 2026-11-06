import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Full-bleed album colors behind the player, blurred until artwork details
/// disappear. The image is clipped to the finite viewport to keep painting
/// bounded on desktop as well as mobile.
class LiquidArtworkBackground extends StatelessWidget {
  final String? imageUrl;
  final Widget child;
  final double intensity;

  const LiquidArtworkBackground({
    super.key,
    required this.imageUrl,
    required this.child,
    this.intensity = 0.8,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = imageUrl;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.background),
          if (url != null && url.startsWith('https://'))
            Positioned.fill(
              child: RepaintBoundary(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 80,
                    sigmaY: 80,
                    tileMode: ui.TileMode.decal,
                  ),
                  child: Transform.scale(
                    scale: 1.35,
                    child: Opacity(
                      opacity: intensity.clamp(0.0, 1.0),
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 350),
                        errorWidget: (_, __, ___) =>
                            const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0C0915).withValues(alpha: 0.28),
                    const Color(0xFF100C19).withValues(alpha: 0.38),
                    const Color(0xFF080610).withValues(alpha: 0.73),
                  ],
                  stops: const [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
