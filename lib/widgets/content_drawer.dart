import 'package:shadcn_flutter/shadcn_flutter.dart';

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
      .push(ShadcnPageRoute<void>(
    // The shell already paints the app-wide gradient. Avoid a second,
    // differently scaled gradient when a detail page replaces its content.
    builder: (pageContext) => SafeArea(
      child: Builder(builder: builder),
    ),
  ));
}

/// Close the current full page rather than dismissing a modal overlay.
void dismissContentDrawer(BuildContext context) {
  Navigator.of(context).maybePop();
}


/// The expanded music player is deliberately above the entire app shell.
void showFullScreenPlayer(BuildContext context, WidgetBuilder builder) {
  Navigator.of(context, rootNavigator: true).push(ShadcnPageRoute<void>(
    builder: (pageContext) => Builder(builder: builder),
  ));
}
