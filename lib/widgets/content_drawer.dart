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
    builder: (pageContext) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: MediaQuery.sizeOf(pageContext).width >= 850
              ? const [
                  Color(0xFF6E6C90),
                  Color(0xFF624E78),
                  Color(0xFF512A50),
                  Color(0xFF302637),
                ]
              : const [
                  Color(0xFF2D1B36),
                  Color(0xFF24152D),
                  Color(0xFF130F1A),
                  Color(0xFF0D0D15),
                ],
          stops: const [0, 0.32, 0.72, 1],
        ),
      ),
      child: SafeArea(child: Builder(builder: builder)),
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
