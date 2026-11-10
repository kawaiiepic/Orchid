import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Music details, player, settings and feature views are real navigable
/// pages. Keep the old helper name for existing callers while transitioning
/// everything off modal sheets.
void showContentDrawer(
  BuildContext context, {
  required WidgetBuilder builder,
  double preferredWidth = 600,
  bool fullWidth = true,
}) {
  Navigator.of(context).push(ShadcnPageRoute<void>(
    builder: (pageContext) => Scaffold(
      child: SafeArea(
        child: Builder(builder: builder),
      ),
    ),
  ));
}

/// Close the current full page rather than dismissing a modal overlay.
void dismissContentDrawer(BuildContext context) {
  Navigator.of(context).maybePop();
}
