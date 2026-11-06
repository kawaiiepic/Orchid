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
    debugPrint('[Orchid UI] ${details.exceptionAsString()}');
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF17141D),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Orchid couldn’t display this screen.\\n'
              'Please restart the app or report the error from device logs.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFE0CBFF),fontSize:14),
            ),
          ),
        ),
      ),
    );
  };
  MediaKit.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(systemNavigationBarColor: Color(0x00000000)),
  );
  runApp(const OrchidApp());
}
