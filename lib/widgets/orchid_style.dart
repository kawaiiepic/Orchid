import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
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
    // The dock floats over content; do not reserve a large blank footer.
    return 12;
  }

  static const violet = Color(0xFFBE9AFF);
  static const lilac = Color(0xFFE0CBFF);
  static const pink = Color(0xFFF3A7D6);
  static const ink = Color(0xFF101018);
  static const panel = Color(0xFF1B1927);
  static const panelLight = Color(0xFF292438);

  /// Shared purple-tinted shader material for Orchid's floating chrome.
  static const glassSettings = glass.LiquidGlassSettings(
    glassColor: Color(0x55392447),
    blur: 12,
    thickness: 24,
    chromaticAberration: 0.012,
    // Keep refraction and tint, but remove the bright specular perimeter.
    lightIntensity: 0,
    ambientStrength: 0,
    ambientRim: 0,
    fresnelStrength: 0,
    glowIntensity: 0,
    rimLight: 0,
    rimShade: 0,
    shadowElevation: 0,
  );

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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(
          color: Color(0xFFF9F5FF),
          fontSize: 26, fontWeight: FontWeight.w700,
        )),
        const SizedBox(height: 7),
        Text(description, style: const TextStyle(
          color: Color(0xFFBCB0CA), fontSize: 12,
        )),
        if (action != null) ...[
          const SizedBox(height: 12),
          action!,
        ],
      ],
    ),
  );
}

/// Shared Orchid glass surface using liquid_glass_widgets on every platform.
/// Desktop content can still opt out of an individual panel background.
class OrchidGlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final bool transparentOnDesktop;

  const OrchidGlassPanel({
    super.key,
    required this.child,
    this.radius = 16,
    this.blur = 16,
    this.transparentOnDesktop = true,
  });

  @override
  Widget build(BuildContext context) {
    if (transparentOnDesktop && MediaQuery.sizeOf(context).width >= 850) {
      return child;
    }
    // The shader draws its specular edge even with rim/light settings at
    // zero. Oversize the glass backdrop and crop the perimeter away, leaving
    // only the tinted, refracted center visible.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          Positioned.fill(
            left: -8, top: -8, right: -8, bottom: -8,
            child: IgnorePointer(
              child: glass.GlassContainer(
                useOwnLayer: true,
                quality: glass.GlassQuality.standard,
                shape: glass.LiquidRoundedSuperellipse(
                  borderRadius: radius + 8),
                settings: OrchidStyle.glassSettings,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
