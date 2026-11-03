import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/account_models.dart';
import 'package:tomi_app/src/design/tomi_theme.dart';
import 'package:tomi_app/src/gaming/game_controller.dart';
import 'package:tomi_app/src/gaming/game_models.dart';
import 'package:tomi_app/src/gaming/game_table.dart';
import 'package:tomi_app/src/gaming/snakes_board.dart';
import 'package:tomi_app/src/identity/identity_models.dart';
import 'package:tomi_app/src/identity/progress_cards.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';

class GameMemoryIntents implements GameIntentStore {
  final values=<String,String>{};
  @override
  Future<String?> read(String key) async=>values[key];
  @override
  Future<void> write(String key,String value) async {values[key]=value;}
  @override
  Future<void> remove(String key) async {values.remove(key);}
}
class GameTokenVault implements TokenVault {
  String? value='test-only-token';
  @override
  Future<String?> read() async=>value;
  @override
  Future<void> write(String token) async {value=token;}
  @override
  Future<void> clear() async {value=null;}
}
Map<String,dynamic> gameUser()=>{
  'id':'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','username':'gameuser','displayName':'لاعب تومي','bio':'','avatarPreset':'initials','followersCount':0,'followingCount':0,
  'identity':{'charisma':4000,'charismaTier':{'level':2,'minimum':4000,'next':12000}},'gameProgress':{'xp':100},
};
Map<String,dynamic> gameSummary()=>{'coins':1000,'progress':{'xp':100},'charisma':{'points':4000,'level':2},'activeMatches':[]};
Map<String,dynamic> tableState({String kind='uno',int sequence=0})=>{
  'id':'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','code':'AABB1717','kind':kind,'mode':'practice','status':'playing','mySeat':0,'turn':0,'revision':sequence,'sequence':sequence,
  'serverTime':100000,'deadlineAt':130000,'startedAt':60000,'result':null,'history':[],'lastMove':null,'earnedXp':0,
  'players':[{'seat':0,'bot':false,'user':gameUser(),'cardCount':2,'position':0},{'seat':1,'bot':true,'user':null,'cardCount':7,'position':0}],
  'hand':[{'id':'red-7-0','color':'red','value':'7'},{'id':'wild-0','color':null,'value':'wild'}],
  'playableCardIds':['red-7-0','wild-0'],'canPass':false,'canDraw':true,'topCard':{'id':'red-3-0','color':'red','value':'3'},'activeColor':'red','deckCount':84,
  'ladders':{'2':38,'28':84},'snakes':{'99':80,'16':6},
};
http.Response reply(Map<String,dynamic> body)=>http.Response(jsonEncode(body),200,headers:{'content-type':'application/json'});
Future<AccountController> gameAccount({Future<http.Response> Function(http.Request)? handler}) async {
  final a=AccountController(api:AccountApi('https://games.tomi.test',client:MockClient((r)async{
    if(r.url.path=='/v1/me')return reply({'user':gameUser()});
    if(r.url.path=='/v1/auth/logout')return reply({});
    if(handler!=null)return handler(r);
    if(r.url.path=='/v1/games')return reply(gameSummary());
    return http.Response('{"error":{"code":"NOT_FOUND","message":"fixture"}}',404);
  })),vault:GameTokenVault(),draftStore:MemoryDraftStore(),realtimeEnabled:false);
  await a.restore();return a;
}
Future<void> ready(GamesController c) async {
  for(var i=0;i<100&&(!c.initialized||c.loading||c.summary==null);i++)await Future<void>.delayed(const Duration(milliseconds:10));
  expect(c.initialized,true);expect(c.summary,isNotNull);
}
void viewport(WidgetTester t,Size size){t.view.devicePixelRatio=1;t.view.physicalSize=size;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);}

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('1.7 gift charisma and game-level boundaries remain independent',(){
    const identity=UserIdentity({'charisma':4000,'xp':999999});
    expect(identity.charismaLevel,2);expect(identity.charismaRemaining,8000);expect(identity.charismaMaxLevel,15);
    expect(const GameProgress(xp:100).level,2);expect(const GameProgress(xp:100).remaining,300);expect(const GameProgress(xp:240100).level,50);expect(const GameProgress(xp:240100).progress,1);
  });
  test('1.7 board topology follows the serpentine physical board',(){
    expect(boardSquare(1),const Offset(.05,.95));expect(boardSquare(10),const Offset(.95,.95));expect(boardSquare(11),const Offset(.95,.85));expect(boardSquare(20),const Offset(.05,.85));expect(boardSquare(100),const Offset(.05,.05));
  });
  test('1.7 lost game reply retries one durable intent without inventing a result',()async{
    final intents=GameMemoryIntents(),requests=<Map<String,dynamic>>[];
    final a=await gameAccount(handler:(r)async{
      if(r.method=='POST'&&r.url.path=='/v1/games/matches'){
        final body=jsonDecode(r.body) as Map<String,dynamic>;requests.add(body);
        expect(intents.values.values.single,contains(body['requestId'] as String));
        if(requests.length==1)throw http.ClientException('lost acknowledgement');
        return reply({...gameSummary(),'match':tableState(),'receipt':{'matchId':tableState()['id'],'replayed':true}});
      }
      if(r.url.path=='/v1/games')return reply(gameSummary());
      return reply({'match':tableState()});
    });addTearDown(a.dispose);
    final c=GamesController(a,intents:intents,autoPoll:false);addTearDown(c.dispose);await ready(c);
    expect(await c.create('uno','practice'),false);expect(c.pending,isNotNull);expect(c.match,isNull);
    expect(await c.retryPending(),true);expect(requests.length,2);expect(requests.first,requests.last);expect(c.pending,isNull);expect(intents.values,isEmpty);expect(c.match!['revision'],0);
  });
  test('1.7 logout fences a delayed game reply and removes private table data',()async{
    final post=Completer<http.Response>(),sent=Completer<void>();
    final a=await gameAccount(handler:(r)async{
      if(r.method=='POST'){sent.complete();return post.future;}
      if(r.url.path=='/v1/games')return reply(gameSummary());
      return reply({'match':tableState()});
    });addTearDown(a.dispose);
    final c=GamesController(a,intents:GameMemoryIntents(),autoPoll:false);addTearDown(c.dispose);await ready(c);
    final pending=c.create('uno','practice');await sent.future;await a.logout();
    post.complete(reply({...gameSummary(),'match':tableState(),'receipt':{}}));expect(await pending,false);
    expect(c.match,isNull);expect(c.summary,isNull);expect(c.pending,isNull);expect(c.canAct,false);
  });
  for(final size in [const Size(320,640),const Size(800,420)]){
    for(final scale in [1.0,2.0]){
      testWidgets('1.7 side-by-side progress and charisma detail fit $size/$scale',(t)async{
        viewport(t,size);await t.pumpWidget(MaterialApp(theme:TomiTheme.dark(),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:child!),home:Scaffold(body:SingleChildScrollView(padding:const EdgeInsets.all(16),child:TomiProgressTiles(user:AccountUser.fromJson(gameUser()))))));
        await t.pumpAndSettle();expect(t.takeException(),isNull);
        final charisma=t.getRect(find.byKey(const Key('profile-charisma-tile'))),level=t.getRect(find.byKey(const Key('profile-game-level-tile')));
        expect(charisma.top,level.top);expect(charisma.overlaps(level),false);
        await t.tap(find.byKey(const Key('profile-charisma-tile')));await t.pumpAndSettle();
        expect(find.text('مستواك الحالي 2 من 15'),findsOneWidget);
        final remaining=find.byKey(const Key('charisma-remaining'));
        await t.scrollUntilVisible(remaining,100,scrollable:find.descendant(of:find.byType(ListView),matching:find.byType(Scrollable)),maxScrolls:20);
        await t.pumpAndSettle();
        expect(find.textContaining('باقي 8000'),findsOneWidget);expect(remaining.hitTestable(),findsOneWidget);expect(t.takeException(),isNull);
      });
      for(final kind in ['uno','snakes']){
        testWidgets('1.7 real table surfaces fit $kind $size/$scale',(t)async{
          viewport(t,size);final a=await gameAccount();addTearDown(a.dispose);
          final c=GamesController(a,intents:GameMemoryIntents(),autoPoll:false);addTearDown(c.dispose);
          await t.pump();await t.runAsync(()=>ready(c));c.match=tableState(kind:kind);
          await t.pumpWidget(MaterialApp(theme:TomiTheme.dark(),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:child!),home:GameTablePage(controller:c)));
          await t.pumpAndSettle();expect(t.takeException(),isNull);
          if(kind=='uno')expect(find.byKey(const Key('game-draw-pile')),findsOneWidget);else expect(find.byKey(const ValueKey('game-pawn-0')),findsOneWidget);
          await t.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
