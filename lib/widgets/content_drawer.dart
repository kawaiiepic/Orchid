import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Full-screen Shadcn sheet for music details, settings, and the player.
/// Slides up from the bottom on every platform, with no anchor or Material UI.
void showContentDrawer(
  BuildContext context, {
  required WidgetBuilder builder,
  double preferredWidth = 600,
}) {
  showOverlay(
    context,
    const SheetConfiguration(
      position: OverlayPosition.bottom,
      useSafeArea: true,
      barrierDismissible: true,
    ),
    builder: (sheetContext) => SizedBox(
      width: MediaQuery.sizeOf(sheetContext).width,
      height: MediaQuery.sizeOf(sheetContext).height,
      child: builder(sheetContext),
    ),
  );
}

/// Dismisses the current Shadcn sheet.
void dismissContentDrawer(BuildContext context) => closeOverlay(context);
