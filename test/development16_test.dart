import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/identity/identity_models.dart';
import 'package:tomi_app/src/identity/charisma_badge.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/roulette/live_controller.dart';
import 'package:tomi_app/src/roulette/live_sheet.dart';
import 'package:tomi_app/src/social/post_share_screens.dart';
import 'account_fakes.dart';
import 'chat_test.dart' show ChatFakeApi;
import 'messaging10_test.dart' show chatAccount;

const peerId16='33333333-3333-4333-8333-333333333333';
class Features16Api extends ChatFakeApi {
  final shares=<Map<String,dynamic>>[],bets=<Map<String,dynamic>>[],receipts=<String>{};
  bool loseShare=true,loseBet=true,blocked=false;
  int balance=1000,revision=0;
  List<Map<String,dynamic>> chips=[];
  Map<String,dynamic> get peer=>{...accountJson(username:'friend16',name:'صديق المشاركة'),'id':peerId16,'identity':{'charisma':12000}};
  Map<String,dynamic> get live=>{
    'roundId':'44444444-4444-4444-8444-444444444444','revision':revision,'phase':'betting','serverTime':DateTime.now().millisecondsSinceEpoch,'bettingEndsAt':DateTime.now().millisecondsSinceEpoch+30000,'spinEndsAt':DateTime.now().millisecondsSinceEpoch+37000,'resultsEndsAt':DateTime.now().millisecondsSinceEpoch+42000,'result':null,'controlled':false,'allowed':true,'coins':balance,'ownBets':chips,'lastBets':[],'recentRounds':[],'winners':[],
    'slots':[for(var i=0;i<8;i++){'slot':i,'icon':const ['🍉','🍊','🍎','🥬','🐟','🍔','🍤','🍗'][i],'label':'خانة $i','multiplier':i<4?5:10,'chancePercent':i<4?19.4:5.6,'hotRank':0}],
  };
  @override
  Future<Map<String,dynamic>> chatRequest(String token,String method,String path,{Map<String,dynamic>? body,Map<String,String>? query})async{
    final payload = body ?? <String,dynamic>{};
    if(path=='/v1/post-shares/contacts')return {'users':[peer],'nextCursor':null};
    if(path.endsWith('/share')&&method=='POST'){
      shares.add(Map<String,dynamic>.from(payload));if(loseShare){loseShare=false;throw const AccountFailure('NETWORK','انقطع الرد.');}return {'status':'pending'};
    }
    if(path=='/v1/post-shares/requests')return {'items':blocked?[]:[{'id':'55555555-5555-4555-8555-555555555555','sender':peer,'postId':'post16','text':'منشور اختباري'}],'nextCursor':null,'count':blocked?0:1};
    if(path.startsWith('/v1/post-shares/requests/')&&method=='POST'){shares.add(Map<String,dynamic>.from(payload));blocked=true;return {'status':'blocked'};}
    if(path=='/v1/chats')return {'conversations':[],'totalUnread':0,'shareRequestsCount':blocked?0:1,'nextCursor':null};
    if(path.endsWith('/live-roulette')&&method=='GET')return live;
    if(path.endsWith('/live-roulette/bet')){
      bets.add(Map<String,dynamic>.from(payload));if(receipts.add(payload['requestId'] as String)){balance-=20;revision++;chips=[{'slot':0,'denomination':20}];}
      if(loseBet){loseBet=false;throw const AccountFailure('NETWORK','انقطع الرد.');}return {'receipt':{'requestId':payload['requestId']},'state':live};
    }
    return super.chatRequest(token,method,path,body:body,query:query);
  }
}
void viewport16(WidgetTester t,Size size){t.view.devicePixelRatio=1;t.view.physicalSize=size;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>FlutterSecureStorage.setMockInitialValues({}));
  test('1.6 charisma tier fallback matches server boundaries without altering donor XP',(){
    for(final pair in const [(999,0),(1000,1),(4000,2),(12000,3),(30000,4),(16000000,15)]){
      final id=UserIdentity({'charisma':pair.$1,'xp':77});expect(id.charismaLevel,pair.$2);expect(id.xp,77);
    }
    expect(const UserIdentity({'charisma':30000}).charismaIcon,'💎');
  });
  test('1.6 lost wager replies retain one durable nonce and recovery never charges a second bet',()async{
    final api=Features16Api(),a=await chatAccount(api,MemoryDraftStore());addTearDown(a.dispose);
    final c=LiveRouletteController(a,'room16');addTearDown(c.dispose);
    for(var i=0;c.loading&&i<100;i++)await Future<void>.delayed(const Duration(milliseconds:1));
    expect(c.canBet,true);await c.bet(0);expect(c.pending,isNotNull);expect(api.balance,980);expect(c.error,isNotNull);
    await c.submit();expect(api.bets.length,2);expect(api.bets[0]['requestId'],api.bets[1]['requestId']);expect(api.balance,980);expect(c.pending,isNull);expect(a.voiceRooms.coins,980);
  });
  testWidgets('1.6 share retry keeps its nonce and reports stranger-request delivery',(t)async{
    viewport16(t,const Size(390,844));final api=Features16Api(),a=await chatAccount(api,MemoryDraftStore());addTearDown(a.dispose);
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()=>showPostShareSheet(context,a,'post16'),child:const Text('share16'))))));
    await t.tap(find.text('share16'));await t.pumpAndSettle();final person=find.byKey(const ValueKey('share-person-$peerId16'));await t.tap(person);await t.pumpAndSettle();expect(api.shares.length,1);expect(find.text('انقطع الرد.'),findsOneWidget);
    await t.ensureVisible(person);await t.tap(person);await t.pumpAndSettle();expect(api.shares.length,2);expect(api.shares[0]['requestId'],api.shares[1]['requestId']);expect(api.shares[0]['userId'],peerId16);expect(find.byType(PostShareSheet),findsNothing);await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('1.6 recipient can block a stranger request and the request disappears',(t)async{
    viewport16(t,const Size(320,640));final api=Features16Api(),a=await chatAccount(api,MemoryDraftStore());addTearDown(a.dispose);
    await t.pumpWidget(MaterialApp(home:PostShareRequestsPage(accounts:a)));await t.pumpAndSettle();final block=find.byKey(const ValueKey('block-share-55555555-5555-4555-8555-555555555555'));await t.ensureVisible(block);await t.tap(block);await t.pumpAndSettle();expect(api.blocked,true);expect(api.shares.single['action'],'block');expect(find.text('لا توجد طلبات مشاركة جديدة.'),findsOneWidget);await t.pumpWidget(const SizedBox.shrink());
  });
  for(final size in const [Size(320,640),Size(800,420)]){
    for(final scale in [1.0,2.0]){
      testWidgets('1.6 room roulette overlay fits $size at $scale text and recovers a wager',(t)async{
        viewport16(t,size);final api=Features16Api(),a=await chatAccount(api,MemoryDraftStore());addTearDown(a.dispose);
        await t.pumpWidget(MaterialApp(theme:ThemeData.dark(),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale),disableAnimations:true),child:child!),home:Scaffold(body:LiveRouletteSheet(accounts:a,roomId:'room16'))));
        await t.pumpAndSettle();expect(t.takeException(),isNull);final cell=find.byKey(const Key('live-slot-0'));await t.ensureVisible(cell);await t.tap(cell);await t.pumpAndSettle();expect(api.bets.length,1);final recover=find.byKey(const Key('live-recover-bet'));await t.ensureVisible(recover);await t.tap(recover);await t.pumpAndSettle();expect(api.bets.length,2);expect(api.balance,980);expect(api.bets[0]['requestId'],api.bets[1]['requestId']);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox.shrink());await t.pump();
      });
    }
  }
  testWidgets('1.6 public charisma badge exposes full points at enlarged text',(t)async{
    viewport16(t,const Size(320,640));await t.pumpWidget(MaterialApp(home:Scaffold(body:MediaQuery(data:const MediaQueryData(textScaler:TextScaler.linear(2)),child:const Row(children:[CharismaBadge(UserIdentity({'charisma':16000000}))])))));await t.pumpAndSettle();expect(find.byType(CharismaBadge),findsOneWidget);expect(t.takeException(),isNull);
  });
}
