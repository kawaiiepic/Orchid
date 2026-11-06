import 'package:flutter/cupertino.dart' as ios;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// iOS uses native navigation; other platforms use a Shadcn drawer.
///
/// No LinkedAnchor is necessary here: these drawers are opened directly from
/// their BuildContext, not positioned relative to a trigger widget.
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
      position: OverlayPosition.end,
      expands: true,
      useSafeArea: true,
    ),
    builder: (drawerContext) => SizedBox(
      width: width,
      height: viewport.height,
      child: builder(drawerContext),
    ),
  );
}

/// Closes the current Shadcn drawer, or the pushed Cupertino page on iOS.
void dismissContentDrawer(BuildContext context) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    Navigator.of(context).maybePop();
  } else {
    closeOverlay(context);
  }
}
