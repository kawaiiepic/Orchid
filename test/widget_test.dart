import 'package:flutter_test/flutter_test.dart';

import 'package:orchid/app.dart';
import 'package:orchid/services/addon_service.dart';
import 'package:orchid/services/player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Orchid asks for sign-in without a saved session', (tester) async {
    await tester.pumpWidget(const OrchidApp());
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('last song is restored without starting playback', (tester) async {
    SharedPreferences.setMockInitialValues({
      'orchid_last_track': '{"id":"1","title":"Last song","artist":"Artist",'
          '"sourceId":"itunes","sourceName":"iTunes"}',
    });
    final service = PlayerService(addonService: AddonService());
    try {
      await tester.pump();
      expect(service.current?.title, 'Last song');
      expect(service.player.playing, isFalse);
      expect(service.playbackLoading, isFalse);
    } finally {
      service.dispose();
    }
  });
}