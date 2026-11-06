import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Soft album-art wash behind the player.
///
/// No [ImageFiltered] / runtime blur — those were laggy and could trip
/// painting asserts when layout sizes were not finite yet.
class LiquidArtworkBackground extends StatelessWidget {
  final String? imageUrl;
  final Widget child;
  final double intensity;

  const LiquidArtworkBackground({
    super.key,
    required this.imageUrl,
    required this.child,
    this.intensity = 0.35,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = imageUrl;
    final op = intensity.clamp(0.12, 0.55);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.background),
        if (url != null)
          Positioned.fill(
            child: Opacity(
              opacity: op,
              child: Transform.scale(
                scale: 1.15,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  memCacheWidth: 128,
                  memCacheHeight: 128,
                  fadeInDuration: Duration.zero,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
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
                scheme.background.withValues(alpha: 0.45),
                scheme.background.withValues(alpha: 0.65),
                scheme.background.withValues(alpha: 0.88),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
