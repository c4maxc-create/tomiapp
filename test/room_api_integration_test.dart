import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';

import 'account_fakes.dart';
import 'call_api_integration_test.dart' show LocalBridge;
import 'rooms_test.dart' show FakeRoomAudio;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('two room controllers create, join, request mic, moderate and leave via real Node API', () async {
    final child = await Process.start('node', [
      'server/test/fixtures/rooms-client-api.mjs',
    ]);
    final stderr = child.stderr.transform(utf8.decoder).listen((_) {});
    addTearDown(() async {
      child.kill(ProcessSignal.sigterm);
      await child.exitCode.timeout(const Duration(seconds: 10));
      await stderr.cancel();
    });
    final first = await child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 20));
    final d = jsonDecode(first) as Map<String, dynamic>,
        base = Uri.parse(d['base'] as String),
        users = d['users'] as List;
    Future<AccountController> account(int i, FakeRoomAudio audio) async {
      final a = AccountController(
        api: AccountApi(
          'https://contract.tomi.test',
          client: LocalBridge(base),
        ),
        vault: MemoryTokenVault((users[i] as Map)['token'] as String),
        realtimeEnabled: false,
        roomAudioFactory: () => audio,
      );
      await a.restore();
      return a;
    }

    final ma = FakeRoomAudio(),
        mb = FakeRoomAudio(),
        a = await account(0, ma),
        b = await account(1, mb),
        ca = a.voiceRooms,
        cb = b.voiceRooms;
    addTearDown(() async {
      await ca.leave();
      await cb.leave();
      a.dispose();
      b.dispose();
    });
    final id = await ca.create('سوالف الاختبار', 10, 4);
    expect(id, isNotNull);
    expect(await ca.join(id!), true);
    expect(ma.enables, 0);
    expect(a.voiceRoomActive, true);
    await cb.load();
    expect(cb.rooms.single.id, id);
    expect(await cb.join(id), true);
    expect(mb.enables, 0);
    await cb.action('request-mic');
    await ca.tick();
    final guest = ca.active!.member(b.user!.id)!;
    expect(guest.requestedAt, isNotNull);
    await ca.moderate(guest, 'approve');
    mb.canPublish = true;
    await cb.tick();
    expect(cb.me!.seat, isNotNull);
    expect(mb.enables, 0);
    await cb.toggleMicrophone();
    expect(mb.micEnabled, true);
    await ca.moderate(guest, 'mute');
    mb.canPublish = false;
    await cb.tick();
    expect(mb.micEnabled, false);
    expect(await ca.moderate(guest, 'promote'), false);
    await cb.tick();
    expect(cb.manage, false);
    expect(ca.me!.seat, -1);
    await ca.action(
      'settings',
      body: {'announcement': 'هلا بالأصدقاء', 'background': 'dusk'},
    );
    await cb.tick();
    expect(cb.active!.announcement, 'هلا بالأصدقاء');
    expect(cb.active!.background, 'dusk');
    await cb.loadGifts();
    expect(cb.coins, 1000);
    expect(await cb.sendGift(a.user!.id, 'diamond', 3), true);
    expect(cb.coins, 700);
    await ca.tick();
    expect(ca.active!.data['hasLevels'], false);
    expect(ca.active!.features['xp'], isNull);
    expect(
      ca.active!.events.where((e) => e.kind == 'gift').single.recipient!.id,
      a.user!.id,
    );
    expect(await cb.sendMessage('وصلت الهدية؟'), true);
    await ca.tick();
    expect(ca.active!.events.last.text, 'وصلت الهدية؟');
    final rank = await ca.roomData('ranking');
    expect((rank!['leaders'] as List).single['points'], 300);
    await ca.moderate(cb.me!, 'kick');
    await cb.tick();
    expect(cb.active, isNull);
    expect(mb.disposed, true);
    await ca.action('close');
    expect(ca.active, isNull);
    expect(ma.disposed, true);
    expect(a.voiceRoomActive, false);
  }, skip: Platform.environment['TOMI_CALL_INTEGRATION'] != '1');
}
