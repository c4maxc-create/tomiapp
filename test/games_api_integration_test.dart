import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/gaming/game_controller.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'account_fakes.dart';
import 'call_api_integration_test.dart' show LocalBridge;
import 'games17_test.dart' show GameMemoryIntents;

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('1.7 Flutter controllers play a real HTTP friends table and open standalone roulette',()async{
  final child=await Process.start('node',['server/test/fixtures/games-client-api.mjs']);
  final errors=child.stderr.transform(utf8.decoder).listen((_){ });
  addTearDown(()async{child.kill(ProcessSignal.sigterm);await child.exitCode.timeout(const Duration(seconds:10));await errors.cancel();});
  final fixture=jsonDecode(await child.stdout.transform(utf8.decoder).transform(const LineSplitter()).first.timeout(const Duration(seconds:25))) as Map<String,dynamic>;
  final base=Uri.parse(fixture['base'] as String),users=fixture['users'] as List;
  Future<AccountController> account(int i)async{
   final a=AccountController(api:AccountApi('https://games-contract.tomi.test',client:LocalBridge(base)),vault:MemoryTokenVault((users[i] as Map)['token'] as String),draftStore:MemoryDraftStore(),realtimeEnabled:false);
   await a.restore();return a;
  }
  final a=await account(0),b=await account(1);addTearDown(a.dispose);addTearDown(b.dispose);
  final first=GamesController(a,intents:GameMemoryIntents(),autoPoll:false),second=GamesController(b,intents:GameMemoryIntents(),autoPoll:false);addTearDown(first.dispose);addTearDown(second.dispose);
  for(var i=0;i<100&&(first.summary==null||second.summary==null);i++)await Future<void>.delayed(const Duration(milliseconds:20));
  expect(await first.create('snakes','friends'),true,reason:first.error);expect(await second.join(first.match!['code'] as String),true,reason:second.error);
  await first.load();expect(await first.act('start'),true,reason:first.error);expect(await first.act('roll'),true,reason:first.error);
  for(var i=0;i<100&&second.match?['sequence']!=1;i++){await second.load();await Future<void>.delayed(const Duration(milliseconds:20));}
  expect(second.match!['sequence'],1);expect(first.match!['lastMove']['dice'],inInclusiveRange(1,6));
  final roulette=await a.chatRequest('GET','/v1/games/live-roulette');expect(roulette['roundId'],isA<String>());expect(roulette['coins'],1000);
  await a.reloadMe();expect(a.user!.gameProgress.xp,0);expect(a.user!.identity.charisma,0);
  expect(await first.act('leave'),true,reason:first.error);
  expect(await first.create('jackaroo','practice'),true,reason:first.error);
  expect(first.match!['players'].length,4);expect(first.match!['hand'].length,4);
  expect(await first.act('choose',{'choice':first.match!['choices'][0]['id']}),true,reason:first.error);
  expect(first.match!['sequence'],1);expect(await first.act('leave'),true,reason:first.error);
  expect(await first.create('camel','practice'),true,reason:first.error);
  expect(first.match!['tiles'].length,54);expect(first.summary!['availableGames'],containsAll(['jackaroo','camel']));
  final tile=(first.match!['choices'] as List).firstWhere((x)=>x['type']=='tile');
  expect(await first.act('choose',{'choice':tile['id']}),true,reason:first.error);
  expect(first.match!['tiles'].length,53);expect(first.match!['tray'].length,1);
  expect(first.summary!['coins'],1000);

 },skip:Platform.environment['TOMI_GAMES_INTEGRATION']!='1');
}
