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
    final stack = details.stack?.toString() ?? 'No stack trace available';
    debugPrint('[Orchid UI] $exception');
    debugPrintStack(stackTrace: details.stack);

    // Release-mode ErrorWidgets do not expose a useful exception by default.
    // The initial stack frames identify the failing widget and source line.
    final firstFrames = stack.split('\\n').take(16).join('\\n');
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF17141D),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                'Orchid UI error:\\n$exception\\n\\nStack trace:\\n$firstFrames',
                textAlign: TextAlign.left,
                style: const TextStyle(
                  color: Color(0xFFE0CBFF),
                  fontSize: 12,
                ),
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
