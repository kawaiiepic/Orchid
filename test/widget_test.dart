import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:orchid/app.dart';

void main() {
  testWidgets('Orchid app wrapper smoke test (headless)', (tester) async {
    // Native miniaudio requires a real audio device. Test app presentation
    // independently; playback belongs in device/integration tests.
    await tester.pumpWidget(const OrchidApp(
      homeOverride: Center(child: Text('Orchid smoke test')),
    ));
    await tester.pump();
    expect(find.text('Orchid smoke test'), findsOneWidget);
  });
}
