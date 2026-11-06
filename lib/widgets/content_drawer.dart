import 'package:flutter/cupertino.dart' as ios;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Presents detail views as native push pages on iOS and as a right-hand
/// modal drawer on other platforms. Neither presentation relies on a
/// Shadcn OverlayAnchor, which may not exist in the caller's widget tree.
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

  material.showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close details',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, _, __) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width,
        height: viewport.height,
        child: material.Material(
          color: const Color(0xFF17141D),
          child: SafeArea(child: builder(dialogContext)),
        ),
      ),
    ),
    transitionBuilder: (dialogContext, animation, _, child) =>
        SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      )),
      child: child,
    ),
  );
}

/// Closes the topmost detail view, whether presented as an iOS page or dialog.
void dismissContentDrawer(BuildContext context) {
  Navigator.of(context).maybePop();
}
