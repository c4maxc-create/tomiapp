import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/identity/identity_controller.dart';
import 'package:tomi_app/src/identity/ranking_controller.dart';
import 'package:tomi_app/src/identity/room_effects.dart';

import 'account_fakes.dart';
import 'call_api_integration_test.dart' show LocalBridge;
import 'rooms_test.dart' show FakeRoomAudio;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('0.11 Flutter identity, private favorites, daily ranking and entry effects use the real API', () async {
    final child = await Process.start('node', [
      'server/test/fixtures/rooms-client-api.mjs',
    ]);
    final errors = child.stderr.transform(utf8.decoder).listen((_) {});
    addTearDown(() async {
      child.kill(ProcessSignal.sigterm);
      await child.exitCode.timeout(const Duration(seconds: 10));
      await errors.cancel();
    });
    final first = await child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 20));
    final data = jsonDecode(first) as Map<String, dynamic>,
        base = Uri.parse(data['base'] as String),
        users = data['users'] as List;
    Future<AccountController> account(int i) async {
      final a = AccountController(
        api: AccountApi(
          'https://contract.tomi.test',
          client: LocalBridge(base),
        ),
        vault: MemoryTokenVault((users[i] as Map)['token'] as String),
        realtimeEnabled: false,
        roomAudioFactory: FakeRoomAudio.new,
      );
      await a.restore();
      return a;
    }

    final a = await account(0),
        b = await account(1),
        ca = a.voiceRooms,
        cb = b.voiceRooms;
    addTearDown(() async {
      await ca.leave();
      a.dispose();
    });
    final id = (await ca.create('سوالف الهوية', 10, 4))!;
    expect(await ca.join(id), true);
    expect(await cb.join(id), true);
    await cb.setPreference(cb.active!, favorite: true, following: true);
    expect(cb.active!.favorite, true);
    expect(cb.active!.following, true);
    await ca.selectScope('favorites');
    expect(ca.rooms, isEmpty);
    await cb.selectScope('favorites');
    expect(cb.rooms.single.id, id);
    await cb.loadGifts();
    expect(await cb.sendGift(a.user!.id, 'diamond', 2), true);
    expect(b.user!.identity.xp, 200);
    expect(b.user!.identity.level, 3);
    expect(b.user!.identity.badges.any((x) => x['id'] == 'first_gift'), true);
    final identity = IdentityController(b);
    addTearDown(identity.dispose);
    await identity.load();
    await identity.select('frameId', 'rose');
    await identity.select('portraitId', 'panda');
    await identity.select('entranceId', 'glow');
    expect(identity.error, isNull);
    expect(b.user!.identity.frameId, 'rose');
    final rank = RankingController(a, roomId: id);
    addTearDown(rank.dispose);
    await rank.load(selected: 'daily');
    expect(rank.leaders.single['points'], 200);
    expect((rank.leaders.single['user'] as Map)['identity']['frameId'], 'rose');
    final global = RankingController(a);
    addTearDown(global.dispose);
    await global.load(selected: 'weekly');
    expect(global.leaders.single['points'], 200);
    await ca.tick();
    final effects = RoomEffectsController(ca.active!.events);
    addTearDown(effects.dispose);
    final sequence = ca.active!.events.last.sequence;
    await cb.leave();
    expect(await cb.join(id), true);
    await ca.tick();
    final entry = ca.active!.events
        .where(
          (e) =>
              e.effect?['kind'] == 'entrance' &&
              e.actor.id == b.user!.id &&
              e.sequence > sequence,
        )
        .single;
    expect(entry.effect!['styleId'], 'glow');
    expect(entry.actor.identity.portraitId, 'panda');
    effects.ingest(ca.active!.events);
    expect(effects.active!.sequence, entry.sequence);
    await cb.leave();
    b.dispose();
    final restored = await account(1);
    addTearDown(restored.dispose);
    await restored.voiceRooms.selectScope('favorites');
    expect(restored.voiceRooms.rooms.single.id, id);
    expect(restored.user!.identity.portraitId, 'panda');
    expect(restored.user!.identity.xp, 200);
    expect(restored.voiceRooms.rooms.single.following, true);
  }, skip: Platform.environment['TOMI_IDENTITY_INTEGRATION'] != '1');
}
