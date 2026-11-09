import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter_cupertino/shadcn_flutter_cupertino.dart';

import 'screens/shell_screen.dart';

class OrchidApp extends StatelessWidget {
  const OrchidApp({super.key});

  @override
  Widget build(BuildContext context) {
    const theme = ThemeData(
      colorScheme: ColorSchemes.darkZinc,
      radius: 0.6,
    );
    // Keep DrawerOverlay above the shell on both platforms, so Orchid's
    // shadcn sheets work whether the app uses Cupertino or plain shadcn.
    const home = DrawerOverlay(
      child: ColoredBox(
        color: Color(0xFF101018),
        child: ShellScreen(),
      ),
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // Provides CupertinoTheme and CupertinoLocalizations. Native controls
      // like CupertinoTabBar require both in their widget ancestry.
      return const CupertinoShadcnApp(
        title: 'Orchid',
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: home,
      );
    }

    return const ShadcnApp(
      title: 'Orchid',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: home,
    );
  }
}
