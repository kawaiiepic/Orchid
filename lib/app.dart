import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sizer/sizer.dart';
import 'package:shadcn_flutter_cupertino/shadcn_flutter_cupertino.dart';

import 'screens/shell_screen.dart';

class OrchidApp extends StatelessWidget {
  /// Allows headless widget tests to exercise the app shell without starting
  /// native audio, network sessions, or the real playback screen.
  final Widget? homeOverride;
  const OrchidApp({super.key, this.homeOverride});

  @override
  Widget build(BuildContext context) {
    // Provide Cupertino context globally while keeping Orchid's platform-
    // specific navigation and controls in their existing widgets.
    return Sizer(
      maxMobileWidth: 599,
      maxTabletWidth: 1024,
      builder: (context, orientation, screenType) => CupertinoShadcnApp(
      title: 'Orchid',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorSchemes.darkZinc,
        radius: 0.6,
      ),
      // Keep a shared overlay ancestor for all popup sheets.
      home: DrawerOverlay(
        child: ColoredBox(
          color: const Color(0xFF101018),
          child: homeOverride ?? const ShellScreen(),
        ),
      ),
      ),
    );
  }
}
