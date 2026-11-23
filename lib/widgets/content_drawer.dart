import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'orchid_style.dart';

PageRoute<void> _orchidPageRoute(WidgetBuilder builder) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? CupertinoPageRoute<void>(builder: builder)
        : ShadcnPageRoute<void>(builder: builder);

/// Shared content navigator keeps sidebar and mini-player outside page routes.
final orchidContentNavigatorKey = GlobalKey<NavigatorState>();

/// Music details, player, settings and feature views are real navigable
/// pages. Keep the old helper name for existing callers while transitioning
/// everything off modal sheets.
void showContentDrawer(
  BuildContext context, {
  required WidgetBuilder builder,
  double preferredWidth = 600,
  bool fullWidth = true,
}) {
  (orchidContentNavigatorKey.currentState ?? Navigator.of(context))
      .push(_orchidPageRoute(
    // Detail pages share the background of the app shell.
    (pageContext) => SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: _detailBottomPadding(pageContext)),
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Semantics(
                label: 'Back',
                child: OrchidBackButton(onPressed: () => dismissContentDrawer(pageContext)),
              ),
            ),
          ),
          Expanded(child: Builder(builder: builder)),
        ]),
      ),
    ),
  ));
}

double _detailBottomPadding(BuildContext context) {
  final dock = OrchidStyle.iosDockClearance(context);
  return dock == 0 ? 104 : dock + 16;
}

/// Close the current full page rather than dismissing a modal overlay.
void dismissContentDrawer(BuildContext context) {
  Navigator.of(context).maybePop();
}


/// The expanded music player is deliberately above the entire app shell.
void showFullScreenPlayer(BuildContext context, WidgetBuilder builder) {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (MediaQuery.sizeOf(context).shortestSide >= 600) {
    navigator.push(ShadcnPageRoute<void>(builder: builder));
    return;
  }
  // Keep the previous route painted so the home screen is revealed as the
  // fullscreen player follows the finger.
  navigator.push(PageRouteBuilder<void>(
    opaque: false,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic))
          .animate(animation),
      child: child,
    ),
  ));
}

/// Native Liquid Glass mobile action drawer, using the package's modal
/// presentation, snap physics, drag handle and translucent surface.
void showOrchidActionDrawer(
  BuildContext context, {
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double maxHeightFraction = .84,
}) {
  glass.GlassModalSheet.show<void>(
    context: context,
    useRootNavigator: true,
    halfSize: maxHeightFraction.clamp(.35, .85).toDouble(),
    initialState: glass.GlassSheetState.half,
    settings: OrchidStyle.glassSettings,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height *
          maxHeightFraction.clamp(.35, .85).toDouble(),
      child: builder(
        sheetContext,
        () => Navigator.of(sheetContext, rootNavigator: true).pop(),
      ),
    ),
  );
}
