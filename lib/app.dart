import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sizer/sizer.dart';
import 'package:shadcn_flutter_cupertino/shadcn_flutter_cupertino.dart';

import 'screens/shell_screen.dart';

Widget _scaleTypography(BuildContext context, Widget? child) {
  final media = MediaQuery.of(context);
  return MediaQuery(
    data: media.copyWith(textScaler: _CompactTextScaler(media.textScaler)),
    child: child ?? const SizedBox.shrink(),
  );
}

class _CompactTextScaler extends TextScaler {
  const _CompactTextScaler(this.system);
  final TextScaler system;

  @override
  double scale(double fontSize) => system.scale(fontSize * .9);

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) => other is _CompactTextScaler && other.system == system;

  @override
  int get hashCode => Object.hash(_CompactTextScaler, system);
}

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
      builder: _scaleTypography,
      localizationsDelegates: [DefaultMaterialLocalizations.delegate],
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
