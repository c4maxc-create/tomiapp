import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/design/tomi_theme.dart';
import 'package:tomi_app/src/gaming/board_games.dart';
import 'package:tomi_app/src/gaming/game_controller.dart';
import 'package:tomi_app/src/gaming/game_models.dart';
import 'package:tomi_app/src/gaming/game_table.dart';
import 'games17_test.dart' show gameAccount,gameSummary,reply,ready,GameMemoryIntents,viewport;

Map<String,dynamic> boardMatch(String kind)=>{
 'id':'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','code':'ABCD1234','kind':kind,'mode':'practice','status':'playing','turn':0,'mySeat':0,'controlledSeat':0,'sequence':0,'revision':0,'serverTime':100000,'deadlineAt':130000,
 'players':[for(var seat=0;seat<(kind=='camel'?3:4);seat++){'seat':seat,'bot':seat!=0,'user':null,'pawns':[-1,-1,-1,-1],'cardCount':4,'progress':0}],
 'hand':kind=='jackaroo'?[{'id':'clubs-A','value':'A','suit':'clubs'}]:[],
 'choices':kind=='jackaroo'?[{'id':'entry-choice','cardId':'clubs-A','label':'A • إخراج حجر1'}]:[{'id':'top','type':'tile'},{'id':'tool:shuffle','type':'shuffle'}],
 'tiles':[{'id':'bottom','x':0,'y':0,'z':0,'kind':0},{'id':'top','x':1,'y':1,'z':1,'kind':1}],
 'tray':[{'id':'tray-a','kind':2},{'id':'tray-b','kind':2}],'side':[], 'tools':{'remove':1,'undo':1,'shuffle':1},'orders':{'kind':0,'count':0,'required':2,'completed':0},
};
Widget app(Widget child,double scale)=>MaterialApp(theme:TomiTheme.dark(),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:child!),home:child);
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('new names and jackaroo path distinguish bases, track and home',(){
  expect(gameName('jackaroo'),contains('جاكارو'));expect(gameName('camel'),'الجمل المجنون');
  expect(jackCell(0,0),isNot(jackCell(1,0)));expect(jackCell(0,64),isNot(jackCell(0,0)));expect(boardRules['jackaroo'],contains('تصاعديًا'));expect(boardRules['camel'],contains('سعة الخانة7'));
 });
 for(final size in [const Size(320,640),const Size(800,420)])for(final scale in [1.0,2.0])for(final kind in ['jackaroo','camel']){
  testWidgets('$kind table and rules fit $size at $scale text',(t)async{
   viewport(t,size);final a=await gameAccount();addTearDown(a.dispose);final c=GamesController(a,intents:GameMemoryIntents(),autoPoll:false);addTearDown(c.dispose);
   await t.pump();await t.runAsync(()=>ready(c));c.match=boardMatch(kind);
   await t.pumpWidget(app(GameTablePage(controller:c),scale));await t.pumpAndSettle();expect(t.takeException(),isNull);
   await t.tap(find.byTooltip('قواعد اللعبة'));await t.pumpAndSettle();expect(find.text(boardRules[kind]!),findsOneWidget);expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox.shrink());
  });
 }
 testWidgets('jackaroo sends one server choice through the existing durable controller',(t)async{
  viewport(t,const Size(390,844));final requests=<Map<String,dynamic>>[];final match=boardMatch('jackaroo');
  final a=await gameAccount(handler:(r)async{if(r.method=='POST'){requests.add(jsonDecode(r.body) as Map<String,dynamic>);return reply({...gameSummary(),'match':{...match,'revision':1,'sequence':1,'turn':1,'choices':[]}});}return reply(gameSummary());});addTearDown(a.dispose);
  final c=GamesController(a,intents:GameMemoryIntents(),autoPoll:false);addTearDown(c.dispose);await t.pump();await t.runAsync(()=>ready(c));c.match=match;
  await t.pumpWidget(app(GameTablePage(controller:c),1));await t.pumpAndSettle();await t.scrollUntilVisible(find.byKey(const ValueKey('jack-card-clubs-A')),200,scrollable:find.byType(Scrollable).first);await t.pumpAndSettle();await t.tap(find.byKey(const ValueKey('jack-card-clubs-A')));await t.pumpAndSettle();await t.tap(find.byKey(const ValueKey('jack-choice-entry-choice')));await t.pumpAndSettle();
  expect(requests.length,1);expect(requests.single['choice'],'entry-choice');expect(requests.single['expectedRevision'],0);expect(requests.single['requestId'],isNotEmpty);expect(c.match!['revision'],1);expect(await c.choose('entry-choice',0),false);expect(requests.length,1);await t.pumpAndSettle();expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox.shrink());
 });
 test('a definitive GAME_CHOICE rejection clears the durable intent and allows a fresh choice',()async{
  final match=boardMatch('camel'),requests=<Map<String,dynamic>>[];
  final a=await gameAccount(handler:(r)async{
   if(r.method=='POST'){
    final body=jsonDecode(r.body) as Map<String,dynamic>;requests.add(body);
    if(body['choice']=='bad')return http.Response(jsonEncode({'error':{'code':'GAME_CHOICE','message':'هذه القطعة مغطاة'}}),409,headers:{'content-type':'application/json'});
    return reply({...gameSummary(),'match':{...match,'revision':1}});
   }
   if(r.url.path.contains('/matches/'))return reply({'match':match});
   return reply(gameSummary());
  });addTearDown(a.dispose);final store=GameMemoryIntents(),c=GamesController(a,intents:store,autoPoll:false);addTearDown(c.dispose);await ready(c);c.match=match;
  expect(await c.choose('bad',0),false);expect(c.pending,isNull);expect(store.values,isEmpty);expect(c.canAct,true);
  expect(await c.choose('top',0),true);expect(requests.length,2);expect(requests[0]['requestId'],isNot(requests[1]['requestId']));expect(c.match!['revision'],1);
 });
 testWidgets('camel covered piece is disabled and an exposed tile sends its server identity',(t)async{
  viewport(t,const Size(390,844));final requests=<Map<String,dynamic>>[];final match=boardMatch('camel');
  final a=await gameAccount(handler:(r)async{if(r.method=='POST'){requests.add(jsonDecode(r.body) as Map<String,dynamic>);return reply({...gameSummary(),'match':{...match,'revision':1,'sequence':1,'tiles':[],'choices':[]}});}return reply(gameSummary());});addTearDown(a.dispose);
  final c=GamesController(a,intents:GameMemoryIntents(),autoPoll:false);addTearDown(c.dispose);await t.pump();await t.runAsync(()=>ready(c));c.match=match;
  await t.pumpWidget(app(GameTablePage(controller:c),1));await t.pumpAndSettle();expect(t.widget<InkWell>(find.byKey(const ValueKey('camel-pick-bottom'))).onTap,isNull);
  await t.scrollUntilVisible(find.byKey(const ValueKey('camel-pick-top')),150,scrollable:find.byType(Scrollable).first);await t.pumpAndSettle();await t.tap(find.byKey(const ValueKey('camel-pick-top')));await t.pumpAndSettle();expect(requests.single['choice'],'top');expect(c.match!['revision'],1);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox.shrink());
 });
}
