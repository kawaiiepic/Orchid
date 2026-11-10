import 'package:liquid_design/liquid_design.dart' as liquid;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Shared Orchid actions. Desktop uses clean, borderless translucent
/// controls, while mobile retains liquid_design's native glass behavior.
abstract final class OrchidAdaptiveControls {
  static const _glassSettings = liquid.LiquidGlassSettings(
    style: liquid.LiquidGlassStyle.regular,
    brightness: liquid.LiquidGlassBrightness.dark,
    tintColor: Color(0xFF7954AB),
    tintOpacity: 0.24,
    opacity: 0.88,
    fallback: liquid.LiquidGlassFallback.frosted,
    fallbackBlurSigma: 20,
  );

  static Widget button({
    required VoidCallback? onPressed,
    required Widget child,
    bool prominent = false,
    bool useShadcn = false,
  }) {
    if (useShadcn) {
      return prominent
          ? PrimaryButton(onPressed: onPressed, child: child)
          : OutlineButton(onPressed: onPressed, child: child);
    }
    return Builder(builder: (context) {
      if (MediaQuery.sizeOf(context).width < 850) {
        return liquid.LiquidGlassButton(
          settings: _glassSettings,
          onPressed: onPressed,
          style: prominent
              ? liquid.LiquidGlassButtonStyle.prominent
              : liquid.LiquidGlassButtonStyle.tinted,
          child: child,
        );
      }
      final enabled = onPressed != null;
      return MouseRegion(
        cursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 38),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: 17, vertical: 10),
            decoration: BoxDecoration(
              color: prominent
                  ? const Color(0x995D428F)
                  : const Color(0x185E487A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 13,
                height: 1.25,
                fontWeight: prominent
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: enabled
                    ? (prominent
                        ? const Color(0xFFFFFFFF)
                        : const Color(0xFFE8DCF3))
                    : const Color(0xFF9B8CAC),
              ),
              child: child,
            ),
          ),
        ),
      );
    });
  }
}
