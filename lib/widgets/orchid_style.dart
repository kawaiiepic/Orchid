import 'dart:ui' show ImageFilter;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:sizer/sizer.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Compact iOS-style glass navigation button with a true circular shape.
class OrchidBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const OrchidBackButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 48,
    child: glass.GlassButton(
      icon: const Icon(LucideIcons.chevronLeft,
        size: 25, color: Color(0xFFF7EDFF)),
      onTap: onPressed,
      width: 48,
      height: 48,
      useOwnLayer: true,
      quality: glass.GlassQuality.premium,
      settings: OrchidStyle.glassSettings,
      shape: const glass.LiquidOval(),
      style: glass.GlassButtonStyle.filled,
      stretch: 0.1,
    ),
  );
}

/// Shared visual language for Orchid's browsing surfaces.
abstract final class OrchidStyle {
  // Keep desktop's original metrics; use Sizer's viewport width to make
  // phone layouts denser without scaling tap targets to unusable sizes.
  static double compact(BuildContext context, double value) {
    if (MediaQuery.sizeOf(context).width >= 600) return value;
    final factor = (Adaptive.w(100) / 450).clamp(0.76, 0.88);
    return value * factor;
  }

  // The compact floating dock overlays the scrollable content on every
  // platform. Leave enough trailing scroll extent to pull the final card
  // fully above the dock while drawing the page behind the system safe area.
  static double iosDockClearance(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 850 &&
        (kIsWeb || (defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.android))) return 0;
    return 104 + MediaQuery.viewPaddingOf(context).bottom;
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

  /// Reduced-distortion material for Linux/Windows glass chrome.
  /// Keep the background frosted while minimizing pixelated refraction.
  static const desktopGlassSettings = glass.LiquidGlassSettings(
    glassColor: Color(0x84392447),
    blur: 7,
    thickness: 9,
    refractiveIndex: 1.015,
    chromaticAberration: 0,
    saturation: 1,
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
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 850;
    return Padding(
    padding: EdgeInsets.only(bottom: compact ? 18 : 14),
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
            Text(title, style: TextStyle(
              fontSize: compact ? 15 : 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFF7EDFF),
            )),
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
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 850;
    return Padding(
    padding: EdgeInsets.fromLTRB(0, 8, 0, compact ? 18 : 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(
          color: const Color(0xFFF9F5FF),
          fontSize: compact ? 22 : 26,
          fontWeight: FontWeight.w700,
        )),
        const SizedBox(height: 7),
        Text(description, style: TextStyle(
          color: const Color(0xFFBCB0CA),
          fontSize: compact ? 11 : 12,
        )),
        if (action != null) ...[
          const SizedBox(height: 12),
          action!,
        ],
      ],
    ),
    );
  }
}

/// Shared Orchid glass surface using liquid_glass_widgets on every platform.
/// Desktop content can still opt out of an individual panel background.
class OrchidGlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final bool transparentOnDesktop;
  final bool desktopLiquidGlass;

  const OrchidGlassPanel({
    super.key,
    required this.child,
    this.radius = 16,
    this.blur = 16,
    this.transparentOnDesktop = true,
    this.desktopLiquidGlass = false,
  });

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 850;
    if (transparentOnDesktop && desktop) return child;
    if (desktop && desktopLiquidGlass) {
      // Keep controls above a low-distortion shader backdrop. Cropping the
      // oversized shape removes the bright outline without suppressing blur.
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
                  settings: OrchidStyle.desktopGlassSettings,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            child,
          ],
        ),
      );
    }
    if (desktop) {
      // Blur only the backdrop, not this panel's text or controls.
      // A clipped Flutter BackdropFilter avoids the low-resolution
      // refraction artifacts from the Linux glass shader.
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: ColoredBox(
            color: const Color(0xA044345A),
            child: child,
          ),
        ),
      );
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
