import 'package:liquid_design/liquid_design.dart' as liquid;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Orchid's shared controls use liquid_design on every Flutter platform.
/// iOS/macOS 26 render native glass; Linux, Windows, Android, web, and older
/// Apple releases use the package's Flutter-rendered frosted fallback.
///
/// Retain shadcn for screens and controls that have not yet been migrated.
abstract final class OrchidAdaptiveControls {
  static const _glassSettings = liquid.LiquidGlassSettings(
    fallback: liquid.LiquidGlassFallback.frosted,
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
    return liquid.LiquidGlassButton(
      settings: _glassSettings,
      onPressed: onPressed,
      style: prominent
          ? liquid.LiquidGlassButtonStyle.prominent
          : liquid.LiquidGlassButtonStyle.tinted,
      child: child,
    );
  }
}
