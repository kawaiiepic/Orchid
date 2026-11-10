import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:liquid_design/liquid_design.dart' as liquid;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Prefer native Apple Liquid Glass, keeping shadcn as Orchid's UI fallback.
/// This is intentionally a small bridge, not a replacement for shadcn's
/// navigation, form, overlay, and layout infrastructure.
abstract final class OrchidAdaptiveControls {
  static bool get nativeGlass => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
       defaultTargetPlatform == TargetPlatform.macOS);

  static Widget button({
    required VoidCallback? onPressed,
    required Widget child,
    bool prominent = false,
  }) {
    if (nativeGlass) {
      return liquid.LiquidGlassButton(
        onPressed: onPressed,
        style: prominent
          ? liquid.LiquidGlassButtonStyle.prominent
          : liquid.LiquidGlassButtonStyle.tinted,
        child: child,
      );
    }
    return prominent
      ? PrimaryButton(onPressed: onPressed, child: child)
      : OutlineButton(onPressed: onPressed, child: child);
  }
}
