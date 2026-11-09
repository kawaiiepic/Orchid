import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Release builds otherwise replace failed widget subtrees with a blank area.
  // Keep a visible diagnostic instead of an unexplained grey screen.
  ErrorWidget.builder = (details) {
    final exception = details.exceptionAsString();
    debugPrint('[Orchid UI] $exception');
    debugPrintStack(stackTrace: details.stack);
    // Display the real widget exception on TestFlight/iOS release builds so
    // the first failure can be diagnosed without Xcode device logs.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF17141D),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Orchid hit a UI error:\\n$exception',
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: Color(0xFFE0CBFF),
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  };
  MediaKit.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF17141D),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const OrchidApp());
}
