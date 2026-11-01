import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/design/tomi_theme.dart';
import 'package:tomi_app/src/social/post_share_screens.dart';
import 'package:tomi_app/src/design/tomi_tokens.dart';
import 'package:tomi_app/src/messaging/chat_widgets.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/roulette/live_controller.dart';
import 'package:tomi_app/src/roulette/live_round.dart';
import 'package:tomi_app/src/roulette/live_sheet.dart';
import 'account_fakes.dart';
import 'development16_test.dart' show Features16Api, viewport16;
import 'messaging10_test.dart' show chatAccount;

Map<String,dynamic> round17({int slot = 0}) => {
  'roundId':'round17','phase':'spinning','serverTime':30000,
  'bettingEndsAt':30000,'spinEndsAt':37000,'resultsEndsAt':42000,
  'result':{'displaySlot':slot,'icon':'🍉','label':'بطيخ'},
  'winnersRoundId':'round17',
  'winners':[for(var i=0;i<4;i++){'user':accountJson(id:'winner-$i',name:'الفائز $i'),'payout':1000-i*100}],
};
class PolishApi extends Features16Api {
  PolishApi() { loseShare = false; }
  final started = DateTime.now().millisecondsSinceEpoch;
  Completer<void>? betGate;
  Map<String,dynamic>? forced;
  @override
  Map<String,dynamic> get live {
    final base=super.live;
    return forced ?? {
      ...base,
      'slots':[for(final cell in base['slots'] as List){...(cell as Map).cast<String,dynamic>(),'hotRank':chips.isNotEmpty && cell['slot']==0 ? 1 : 0}],
      'bettingEndsAt':started+30000,'spinEndsAt':started+37000,'resultsEndsAt':started+42000,
    };
  }
  @override
  Future<Map<String,dynamic>> chatRequest(String token,String method,String path,{Map<String,dynamic>? body,Map<String,String>? query}) async {
    if (path.endsWith('/live-roulette/bet')) await betGate?.future;
    return super.chatRequest(token,method,path,body:body,query:query);
  }
}
class RateRecoveryApi extends PolishApi {
  bool rateOnce = false;
  @override
  Future<Map<String,dynamic>> chatRequest(String token,String method,String path,{Map<String,dynamic>? body,Map<String,String>? query}) async {
    if (path.endsWith('/live-roulette/bet') && rateOnce) {
      rateOnce = false;
      throw const AccountFailure('RATE_LIMITED','انتظر قليلًا',status:429);
    }
    return super.chatRequest(token,method,path,body:body,query:query);
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('1.6.1 result presentation uses exactly the five server seconds despite a stale phase label', () {
    final d=round17();
    expect(LiveRoundView(d,29999).phase,LiveRoundPhase.betting);
    expect(LiveRoundView(d,30000).phase,LiveRoundPhase.spinning);
    expect(LiveRoundView(d,36999).phase,LiveRoundPhase.spinning);
    expect(LiveRoundView(d,37000).phase,LiveRoundPhase.results);
    expect(LiveRoundView(d,37000).seconds,5);
    expect(LiveRoundView(d,41999).phase,LiveRoundPhase.results);
    expect(LiveRoundView(d,42000).phase,LiveRoundPhase.waiting);
    expect(LiveRoundView(d,42000).winners,isEmpty);
  });
  test('1.6.1 no result is fabricated while settlement has not arrived', () {
    final d=round17()..['result']=null;
    expect(LiveRoundView(d,32000).phase,LiveRoundPhase.waiting);
    expect(LiveRoundView(d,38000).winners,isEmpty);
    expect(LiveRoundView(d,38000).activeSlot(),-1);
  });
  test('1.6.1 podium is limited to three current-round winners and rejects a mismatched round', () {
    final d=round17();expect(LiveRoundView(d,38000).winners.length,3);
    d['winnersRoundId']='previous-round';expect(LiveRoundView(d,38000).winners,isEmpty);
    d['winnersRoundId']='round17';d['winners']=[];expect(LiveRoundView(d,38000).winners,isEmpty);
  });
  test('1.6.1 every stop reaches the server target without a local result draw', () {
    for(var i=0;i<8;i++) {
      final d=round17(slot:i);
      expect(LiveRoundView(d,37000).activeSlot(),i);
      expect(LiveRoundView(d,34000).activeSlot(reducedMotion:true),i);
      expect(LiveRoundView(d,42000).activeSlot(),-1);
    }
  });
  test('1.6.1 phase progress is bounded at every deadline', () {
    for(final t in [-1000,0,29999,30000,36999,37000,41999,42000,999999]) {
      final p=LiveRoundView(round17(),t).progress;expect(p,inInclusiveRange(0.0,1.0));
    }
  });
  test('1.6.1 dark conversation surfaces share the app design tokens', () {
    final p=ChatPalette(true),theme=TomiTheme.dark();
    expect(p.background,TomiColors.background);expect(p.surface,TomiColors.surface);
    expect(p.text,TomiColors.text);expect(p.line,TomiColors.border);
    expect(theme.colorScheme.primary,TomiColors.accent);
    expect(theme.scaffoldBackgroundColor,p.background);
  });
  test('1.6.1 stale snapshots cannot replace a newer round, balance or server clock', () async {
    final api=PolishApi(),a=await chatAccount(api,MemoryDraftStore());addTearDown(a.dispose);
    final c=LiveRouletteController(a,'room17');addTearDown(c.dispose);
    for(var i=0;c.loading&&i<100;i++)await Future<void>.delayed(const Duration(milliseconds:1));
    final fresh={...api.live,'revision':20,'coins':1234};expect(c.apply(fresh),true);
    final before=c.serverNow;expect(c.apply({...fresh,'revision':19,'coins':1,'serverTime':1}),false);
    expect(c.state!['coins'],1234);expect(c.serverNow,greaterThanOrEqualTo(before));
  });
  test('1.6.1 rate-limited recovery retains the original accepted wager intent', () async {
    final api=RateRecoveryApi(),a=await chatAccount(api,MemoryDraftStore());addTearDown(a.dispose);
    final c=LiveRouletteController(a,'room17');addTearDown(c.dispose);
    for(var i=0;c.loading&&i<100;i++)await Future<void>.delayed(const Duration(milliseconds:1));
    await c.bet(0);final nonce=c.pending!['requestId'];expect(api.balance,980);
    api.rateOnce=true;await c.submit();expect(c.pending!['requestId'],nonce);expect(api.balance,980);
    await c.submit();expect(c.pending,isNull);expect(api.balance,980);expect(api.bets[0]['requestId'],api.bets[1]['requestId']);
  });
  testWidgets('1.6.1 closing an account session clears cached share contacts and disables sending',(t) async {
    viewport16(t,const Size(390,844));final api=PolishApi(),a=await chatAccount(api,MemoryDraftStore());addTearDown(a.dispose);
    await t.pumpWidget(MaterialApp(theme:TomiTheme.dark(),home:Scaffold(body:PostShareSheet(accounts:a,postId:'post17'))));await t.pumpAndSettle();
    expect(find.text('@friend16'),findsOneWidget);await a.logout();await t.pumpAndSettle();
    expect(find.text('@friend16'),findsNothing);expect(api.shares,isEmpty);
    expect(t.widget<TextField>(find.byKey(const Key('post-share-search'))).enabled,false);
    expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox.shrink());
  });
  for(final size in const [Size(320,640),Size(800,420)]) {
    for(final scale in [1.0,2.0]) {
      testWidgets('1.6.1 wheel stays fixed while sending, losing and recovering a wager at $size/$scale',(t) async {
        viewport16(t,size);
        final api=PolishApi(),gate=Completer<void>();api.betGate=gate;
        final a=await chatAccount(api,MemoryDraftStore());addTearDown(a.dispose);
        await t.pumpWidget(MaterialApp(theme:TomiTheme.dark(),builder:(context,child)=>MediaQuery(
          data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale),disableAnimations:true),child:child!),
          home:Scaffold(body:LiveRouletteSheet(accounts:a,roomId:'room17'))));
        await t.pumpAndSettle();final slot=find.byKey(const Key('live-slot-0')),board=find.byKey(const Key('live-wheel-board'));
        await t.ensureVisible(slot);await t.pumpAndSettle();final before=t.getRect(board);
        await t.tap(slot);await t.pump(const Duration(milliseconds:50));
        expect(t.getRect(board),before,reason:'A pending wager must not resize or move the board');
        gate.complete();await t.pumpAndSettle();
        expect(api.balance,980);expect(t.getRect(board),before,reason:'Lost ACK recovery must not shift the board');
        final recover=find.byKey(const Key('live-recover-bet'));await t.tap(recover);await t.pumpAndSettle();
        expect(api.balance,980);expect(api.bets.length,2);expect(api.bets[0]['requestId'],api.bets[1]['requestId']);
        expect(t.getRect(board),before);expect(t.takeException(),isNull);
        await t.pumpWidget(const SizedBox.shrink());await t.pump();
      });
    }
  }
  testWidgets('1.6.1 podium shows this round top three and clears immediately for the next round',(t) async {
    viewport16(t,const Size(390,844));final api=PolishApi();final now=DateTime.now().millisecondsSinceEpoch;
    final users=[for(var i=0;i<4;i++){'user':accountJson(id:'person-$i',name:'فائز الجولة $i'),'payout':400-i*50}];
    api.forced={...api.live,'phase':'results','bettingEndsAt':now-8000,'spinEndsAt':now-1000,'resultsEndsAt':now+4000,'result':{'kind':'item','displaySlot':0,'icon':'🍉','label':'بطيخ'},'winnersRoundId':api.live['roundId'],'winners':users,'revision':3};
    final a=await chatAccount(api,MemoryDraftStore());addTearDown(a.dispose);
    await t.pumpWidget(MaterialApp(theme:TomiTheme.dark(),home:Scaffold(body:LiveRouletteSheet(accounts:a,roomId:'room17'))));await t.pumpAndSettle();
    expect(find.text('أفضل 3 في هذه الجولة'),findsOneWidget);
    for(var i=0;i<3;i++)expect(find.byKey(ValueKey('live-winner-person-$i')),findsOneWidget);
    expect(find.byKey(const ValueKey('live-winner-person-3')),findsNothing);
    api.forced={...api.live,'roundId':'next-round','phase':'betting','serverTime':now+42000,'bettingEndsAt':now+72000,'spinEndsAt':now+79000,'resultsEndsAt':now+84000,'result':null,'winners':[],'winnersRoundId':'next-round','revision':4};
    await t.pump(const Duration(seconds:2));await t.pumpAndSettle();
    expect(find.text('أفضل 3 في هذه الجولة'),findsNothing);expect(find.byKey(const ValueKey('live-winner-person-0')),findsNothing);
    expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox.shrink());await t.pump();
  });
}
