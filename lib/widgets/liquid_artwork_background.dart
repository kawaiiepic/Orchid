import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Soft album-art wash behind the player.
///
/// Intentionally static and downscaled — animated multi-layer blurs were too
/// expensive (full-res ImageFiltered every frame).
class LiquidArtworkBackground extends StatelessWidget {
  final String? imageUrl;
  final Widget child;
  final double intensity;

  const LiquidArtworkBackground({
    super.key,
    required this.imageUrl,
    required this.child,
    this.intensity = 0.45,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = imageUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.background),
        if (url != null)
          // One small decoded image + one blur pass, cached by Flutter.
          Positioned.fill(
            child: Opacity(
              opacity: intensity.clamp(0.15, 0.7),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                child: Transform.scale(
                  scale: 1.2,
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    // Decode tiny — blur hides detail and cuts GPU cost.
                    memCacheWidth: 96,
                    memCacheHeight: 96,
                    fadeInDuration: Duration.zero,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.background.withValues(alpha: 0.4),
                scheme.background.withValues(alpha: 0.62),
                scheme.background.withValues(alpha: 0.82),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
