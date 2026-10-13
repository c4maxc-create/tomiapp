import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/app.dart';
import 'package:tomi_app/src/model.dart';

void main() {
  for (final viewport in [const Size(320, 640), const Size(800, 420)]) {
    testWidgets('five tabs fit viewport $viewport', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const TomiApp(previewMode: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final key in [
        'nav-chats',
        'nav-rooms',
        'nav-games',
        'nav-profile',
        'nav-home',
      ]) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: key);
      }
    });
  }

  testWidgets('compact screen supports larger text across tabs', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const TomiApp(previewMode: true, textScaler: TextScaler.linear(1.5)),
    );
    await tester.pumpAndSettle();
    for (final key in [
      'nav-home',
      'nav-chats',
      'nav-rooms',
      'nav-games',
      'nav-profile',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: key);
    }
  });

  testWidgets('composer publishes a local text post', (tester) async {
    final store = TomiStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(TomiApp(store: store));
    await tester.tap(find.byKey(const Key('compose-post')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('post-input')),
      'أول تجربة TOMI',
    );
    await tester.tap(find.byKey(const Key('publish-post')));
    await tester.pumpAndSettle();
    expect(store.posts.first.text, 'أول تجربة TOMI');
    expect(find.text('أول تجربة TOMI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat sends local text and clears unread badge', (tester) async {
    final store = TomiStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(TomiApp(store: store));
    await tester.tap(find.byKey(const Key('nav-chats')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('علي').first);
    await tester.pumpAndSettle();
    expect(store.chats.first.unread, 0);
    await tester.enterText(
      find.byKey(const Key('message-input')),
      'هلا من تومي',
    );
    await tester.tap(find.byKey(const Key('send-message')));
    await tester.pumpAndSettle();
    expect(store.chats.first.messages.last.text, 'هلا من تومي');
    expect(tester.takeException(), isNull);
  });
}
