import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'screens/home_screen.dart';

class OrchidApp extends StatelessWidget {
  const OrchidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadcnApp(
      title: 'Orchid',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorSchemes.darkZinc,
        radius: 0.6,
      ),
      home: const HomeScreen(),
    );
  }
}
