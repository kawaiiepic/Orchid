import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/cupertino.dart' as ios;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Shared side-drawer presentation for music details, settings and the player.
/// On narrow screens it occupies the full width; on desktop it leaves the
/// browsing context visible behind the drawer.
void showContentDrawer(
  BuildContext context, {
  required WidgetBuilder builder,
  double preferredWidth = 600,
}) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    Navigator.of(context).push(ios.CupertinoPageRoute<void>(
      builder: (routeContext) => ios.CupertinoPageScaffold(
        child: SafeArea(child: builder(routeContext)),
      ),
    ));
    return;
  }
  final viewport = MediaQuery.sizeOf(context);
  final width = viewport.width < 700
      ? viewport.width
      : (viewport.width * 0.85).clamp(360.0, preferredWidth).toDouble();
  showOverlay(
    context,
    const DrawerConfiguration(
      anchor: LinkedAnchor(#orchidContentDrawer),
      expands: true,
      position: OverlayPosition.end,
    ),
    builder: (drawerContext) => OverlayAnchor(
      anchor: #orchidContentDrawer,
      child: SizedBox(
        width: width,
        height: viewport.height,
        child: builder(drawerContext),
      ),
    ),
  );
}

void dismissContentDrawer(BuildContext context) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    Navigator.of(context).maybePop();
  } else {
    closeOverlay(context);
  }
}
