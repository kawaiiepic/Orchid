import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sizer/sizer.dart';
import 'package:shadcn_flutter_cupertino/shadcn_flutter_cupertino.dart';

import 'screens/shell_screen.dart';

class OrchidApp extends StatelessWidget {
  const OrchidApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Provide Cupertino context globally while keeping Orchid's platform-
    // specific navigation and controls in their existing widgets.
    return Sizer(
      maxMobileWidth: 599,
      maxTabletWidth: 1024,
      builder: (context, orientation, screenType) => const CupertinoShadcnApp(
      title: 'Orchid',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorSchemes.darkZinc,
        radius: 0.6,
      ),
      // Keep a shared overlay ancestor for all popup sheets.
      home: DrawerOverlay(
        child: ColoredBox(
          color: Color(0xFF101018),
          child: ShellScreen(),
        ),
      ),
      ),
    );
  }
}
