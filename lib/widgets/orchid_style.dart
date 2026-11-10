import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:liquid_design/liquid_design.dart' as liquid;
import 'package:sizer/sizer.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Shared visual language for Orchid's browsing surfaces.
abstract final class OrchidStyle {
  // Keep desktop's original metrics; use Sizer's viewport width to make
  // phone layouts denser without scaling tap targets to unusable sizes.
  static double compact(BuildContext context, double value) {
    if (MediaQuery.sizeOf(context).width >= 600) return value;
    final factor = (Adaptive.w(100) / 450).clamp(0.76, 0.88);
    return value * factor;
  }

  // The iOS dock is an overlay, not a footer. Let content scroll behind it
  // while leaving room to reach the last card at the bottom of the list.
  static double iosDockClearance(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return 0;
    return 152 + MediaQuery.paddingOf(context).bottom;
  }

  static const violet = Color(0xFFBE9AFF);
  static const lilac = Color(0xFFE0CBFF);
  static const pink = Color(0xFFF3A7D6);
  static const ink = Color(0xFF101018);
  static const panel = Color(0xFF1B1927);
  static const panelLight = Color(0xFF292438);

  static BoxDecoration panelDecoration({double radius = 22}) =>
      BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(radius),
      );

  static BoxDecoration gradientDecoration({double radius = 24}) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF493268), Color(0xFF30233F), Color(0xFF211E36)],
        ),
        border: Border.all(color: violet.withValues(alpha: 0.26)),
      );
}

class OrchidSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const OrchidSectionHeader({
    super.key, required this.title, this.subtitle, this.trailing,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: OrchidStyle.compact(context, 14)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4, height: OrchidStyle.compact(context, 24),
          decoration: BoxDecoration(
            color: OrchidStyle.violet,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        SizedBox(width: OrchidStyle.compact(context, 12)),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title).large().semiBold(),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle!).small().muted(),
            ],
          ],
        )),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class OrchidHero extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final Widget? action;
  final String? imageUrl;

  const OrchidHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    this.action,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: OrchidStyle.gradientDecoration(),
    child: Stack(
      children: [
        Positioned(
          right: -54, top: -76,
          child: Container(
            width: OrchidStyle.compact(context, 240), height: OrchidStyle.compact(context, 240),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: OrchidStyle.violet.withValues(alpha: 0.11),
            ),
          ),
        ),
        Positioned(
          right: 24, top: 18,
          child: Icon(icon, size: OrchidStyle.compact(context, 102),
            color: OrchidStyle.lilac.withValues(alpha: 0.12)),
        ),
        Padding(
          padding: EdgeInsets.all(OrchidStyle.compact(context, 24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow.toUpperCase(),
                style: const TextStyle(
                  color: OrchidStyle.lilac, fontSize: 11,
                  letterSpacing: 2, fontWeight: FontWeight.w700,
                )),
              SizedBox(height: OrchidStyle.compact(context, 14)),
              Text(title, style: TextStyle(
                fontSize: OrchidStyle.compact(context, 29), fontWeight: FontWeight.w700,
                height: 1.08, color: Color(0xFFF9F5FF),
              )),
              const SizedBox(height: 9),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(description, style: const TextStyle(
                  fontSize: 13, color: Color(0xFFD1C5DF), height: 1.45,
                )),
              ),
              if (action != null) ...[
                SizedBox(height: OrchidStyle.compact(context, 20)),
                action!,
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Shared dark Liquid Glass panel. Renders native glass on supported Apple
/// releases and a Flutter frosted fallback on Linux, Android, and Windows.
class OrchidGlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  const OrchidGlassPanel({
    super.key,
    required this.child,
    this.radius = 16,
    this.blur = 16,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Stack(children: [
      Positioned.fill(
        left: -4, top: -4, right: -4, bottom: -4,
        child: IgnorePointer(
          child: liquid.LiquidGlass(
            shape: liquid.LiquidGlassShape.roundedRect(radius + 4),
            style: liquid.LiquidGlassStyle.clear,
            interactive: false,
            interactionStrength: 0,
            fallback: liquid.LiquidGlassFallback.frosted,
            fallbackBlurSigma: blur,
            brightness: liquid.LiquidGlassBrightness.dark,
            tintColor: const Color(0xFF392447),
            tintOpacity: 0.36,
            opacity: 0.76,
            rimColor: const Color(0x00000000),
            rimWidth: 0,
            child: const SizedBox.expand(),
          ),
        ),
      ),
      child,
    ]),
  );
}
