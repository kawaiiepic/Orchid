import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'orchid_style.dart';

/// Shared Orchid actions. Desktop uses clean, borderless translucent
/// controls, while mobile uses shader-backed liquid_glass_widgets.
abstract final class OrchidAdaptiveControls {
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
        return glass.GlassButton.custom(
          onTap: onPressed ?? () {},
          enabled: onPressed != null,
          useOwnLayer: true,
          settings: OrchidStyle.glassSettings,
          quality: glass.GlassQuality.standard,
          style: prominent
              ? glass.GlassButtonStyle.prominent
              : glass.GlassButtonStyle.filled,
          shape: const glass.LiquidRoundedSuperellipse(borderRadius: 12),
          height: 40,
          stretch: 0.15,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: onPressed == null
                    ? const Color(0xFF9B8CAC)
                    : const Color(0xFFF8E9FF),
                fontSize: 13,
                fontWeight: prominent ? FontWeight.w600 : FontWeight.w500,
              ),
              child: child,
            ),
          ),
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
            padding: const EdgeInsets.symmetric(
              horizontal: 17, vertical: 10),
            decoration: BoxDecoration(
              color: prominent
                  ? const Color(0xE06D4C9F)
                  : const Color(0xB04A385F),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [child],
              ),
            ),
          ),
        ),
      );
    });
  }
}
