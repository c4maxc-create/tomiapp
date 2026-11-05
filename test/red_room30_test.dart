import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/app.dart';
import 'rooms_test.dart' as rooms;
void main(){testWidgets('minimized room renders in the real app builder without a red error overlay',(t)async{
 final(a,c,api,audio)=await rooms.setup();
 await t.pumpWidget(TomiApp(accounts:a));await t.pumpAndSettle();
 expect(await c.join(rooms.roomId),true);c.minimize();await t.pumpAndSettle();
 expect(t.takeException(),isNull);expect(find.byKey(const Key('mini-room-leave')),findsOneWidget);
 await t.tap(find.byKey(const Key('mini-room-leave')));await t.pumpAndSettle();expect(audio.disposed,true);
 await t.pumpWidget(const SizedBox());a.dispose();
});}
