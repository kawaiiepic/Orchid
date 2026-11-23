import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/content_drawer.dart';
import '../lib/widgets/player_dismiss_gestures.dart';

void main() {
  testWidgets('dismisses the fullscreen route by pulling down or from left', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => TextButton(
                onPressed: () => showFullScreenPlayer(
                  context,
                  (context) => PlayerDismissGestures(
                    onDismiss: () => Navigator.of(context).pop(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (_) {},
                      child: const Center(child: Text('Playing')),
                    ),
                  ),
                ),
                child: const Text('Open player'),
              )),
    ));

    for (final (start, delta) in [
      (const Offset(200, 210), const Offset(0, 135)),
      (const Offset(10, 210), const Offset(130, 0)),
      (const Offset(220, 210), const Offset(-130, 0)),
      (const Offset(65, 210), const Offset(130, 0)),
    ]) {
      await tester.tap(find.text('Open player'));
      await tester.pumpAndSettle();
      expect(find.text('Playing'), findsOneWidget);
      await tester.dragFrom(start, delta);
      await tester.pumpAndSettle();
      expect(find.text('Playing'), findsNothing);
    }
  });

  testWidgets('player follows a downward drag and snaps back on a short pull',
      (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(MaterialApp(
        home: PlayerDismissGestures(
      onDismiss: () => dismissed++,
      child: const Center(child: Text('Artwork')),
    )));
    final artwork = find.text('Artwork');
    final before = tester.getCenter(artwork);
    final finger = await tester.startGesture(const Offset(180, 180));
    await finger.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(tester.getCenter(artwork).dy, closeTo(before.dy + 40, 1));
    await finger.up();
    await tester.pumpAndSettle();
    expect(tester.getCenter(artwork), before);
    expect(dismissed, 0);
  });

  testWidgets('does not dismiss on seeking, upward swipes, or lower controls', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(MaterialApp(
        home: PlayerDismissGestures(
      onDismiss: () => dismissed++,
      child: const SizedBox.expand(),
    )));
    await tester.dragFrom(const Offset(150, 470), const Offset(180, 0));
    await tester.dragFrom(const Offset(150, 280), const Offset(0, -160));
    await tester.dragFrom(const Offset(150, 470), const Offset(0, 100));
    await tester.tapAt(const Offset(10, 200));
    expect(dismissed, 0);
  });
}
