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

/// Shadcn-styled mobile action drawer. Uses the root Overlay instead of
/// Material's showModalBottomSheet, so it works with Orchid's Shadcn app.
///
/// Returns a close callback and lets the caller supply any scrollable content.
void showOrchidActionDrawer(
  BuildContext context, {
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double maxHeightFraction = .84,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  var closed = false;

  void close() {
    if (closed) return;
    closed = true;
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(builder: (drawerContext) {
    final size = MediaQuery.sizeOf(drawerContext);
    final keyboard = MediaQuery.viewInsetsOf(drawerContext).bottom;
    final bottomInset = MediaQuery.viewPaddingOf(drawerContext).bottom;
    return Stack(children: [
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: close,
        child: const ColoredBox(color: Color(0x99000000)),
      )),
      Positioned(
        left: 8,
        right: 8,
        bottom: keyboard,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 450) close();
          },
          child: Container(
            constraints: BoxConstraints(
              maxHeight: (size.height - keyboard) * maxHeightFraction,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF2E2239),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF806F90),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(child: Padding(
                padding: EdgeInsets.only(
                  bottom: keyboard > 0 ? 12 : bottomInset + 12,
                ),
                child: builder(drawerContext, close),
              )),
            ]),
          ),
        ),
      ),
    ]);
  });
  overlay.insert(entry);
}
