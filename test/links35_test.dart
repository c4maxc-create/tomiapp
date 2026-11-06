import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/experience/share_code_page.dart';

void main() {
  test(
    'TOMI links accept only exact profile room and game targets and reject arbitrary navigation',
    () {
      expect(TomiLink.parse('tomi://game/a1b2c3d4')!.target, 'A1B2C3D4');
      expect(
        TomiLink.parse(
          'tomi://profile/11111111-1111-4111-8111-111111111111',
        )!.kind,
        'profile',
      );
      for (final value in [
        'https://attacker.example',
        'tomi://profile/../settings',
        'tomi://room/11111111-1111-4111-8111-111111111111?mic=true',
        'tomi://game/12345678/extra',
        'tomi://game/12345678#token',
        'tomi://game/12345678\n',
        'tomi://admin/11111111-1111-4111-8111-111111111111',
      ])
        expect(TomiLink.parse(value), isNull);
    },
  );
  testWidgets(
    'QR share page remains usable without native QR support at doubled text',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: w!,
          ),
          home: const ShareCodePage(
            url: 'tomi://game/12345678',
            title: 'مشاركة الطاولة',
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byType(SelectableText), 200);
      expect(
        t.widget<SelectableText>(find.byType(SelectableText)).data,
        'tomi://game/12345678',
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
