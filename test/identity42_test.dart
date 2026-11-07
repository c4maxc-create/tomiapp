import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/external_auth_ui.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '42 identity choices remain tappable on a compact Arabic display at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final selected = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: IdentityButtons(
                        enabled: const ['google', 'phone', 'facebook', 'apple'],
                        onSelected: selected.add,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (final label in ['Google', 'رقم الهاتف', 'Facebook', 'Apple']) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
          await tester.pump();
        }
        expect(selected, ['google', 'phone', 'facebook', 'apple']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
