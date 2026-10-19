import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/scheduler.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Soft, slowly drifting album-art wash behind the player / lyrics.
class LiquidArtworkBackground extends StatefulWidget {
  final String? imageUrl;
  final Widget child;
  final double intensity;

  const LiquidArtworkBackground({
    super.key,
    required this.imageUrl,
    required this.child,
    this.intensity = 0.55,
  });

  @override
  State<LiquidArtworkBackground> createState() =>
      _LiquidArtworkBackgroundState();
}

class _LiquidArtworkBackgroundState extends State<LiquidArtworkBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final next = elapsed.inMilliseconds / 1000.0;
      if ((next - _t).abs() > 1 / 30) {
        setState(() => _t = next);
      }
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = widget.imageUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.background),
        if (url != null)
          ...List.generate(3, (i) {
            final phase = _t * (0.04 + i * 0.015) + i * 1.7;
            final dx = math.sin(phase) * (18.0 + i * 10);
            final dy = math.cos(phase * 0.85) * (14.0 + i * 8);
            final scale = 1.25 + 0.08 * math.sin(phase * 0.6);
            final blur = 28.0 + i * 12.0;
            final opacity =
                (widget.intensity * (0.45 - i * 0.1)).clamp(0.08, 0.6);

            return Positioned.fill(
              child: Transform.translate(
                offset: Offset(dx, dy),
                child: Transform.scale(
                  scale: scale,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: blur,
                      sigmaY: blur,
                    ),
                    child: Opacity(
                      opacity: opacity,
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        // Gentle vignette so foreground text stays readable.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.background.withOpacity(0.35),
                scheme.background.withOpacity(0.55),
                scheme.background.withOpacity(0.75),
              ],
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
