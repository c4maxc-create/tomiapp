// Optional design capture: flutter test tool/capture_board_games.dart --no-pub
// Uses fresh server-generated states. Output contains demo users only.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:tomi_app/src/design/tomi_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tomi_app/src/gaming/game_controller.dart';
import 'package:tomi_app/src/gaming/game_table.dart';

import '../test/games17_test.dart' show gameAccount,GameMemoryIntents,ready,viewport,gameUser;

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 for(final kind in ['jackaroo','camel'])testWidgets('capture $kind server-backed layout',(t)async{
  viewport(t,const Size(390,1200));
  await t.runAsync(()async{
   final fonts={
    'CaptureArabic':Platform.environment['TOMI_CAPTURE_FONT']??'/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf',
    'Roboto':'/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    'CaptureSymbols':'/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    'CaptureEmoji':'/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
    'MaterialIcons':'${Platform.environment['FLUTTER_ROOT']??'/workspace/toolchains/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
   };
   for(final entry in fonts.entries){final loader=FontLoader(entry.key);loader.addFont(File(entry.value).readAsBytes().then(ByteData.sublistView));await loader.load();}
  });
  final result=await t.runAsync(()=>Process.run('node',['--input-type=module','-e',"import {newGame,publicGameState} from './server/src/game_engine.mjs';const s=newGame('$kind',Array.from({length:${kind=='camel'?3:4}},(_,seat)=>({seat,bot:seat!==0})));console.log(JSON.stringify(publicGameState(s,0)));"],workingDirectory:Directory.current.path));
  expect(result!.exitCode,0);final m=jsonDecode(result.stdout as String) as Map<String,dynamic>;
  m.addAll({'id':'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','mySeat':0,'revision':0,'mode':'practice','deadlineAt':DateTime.now().millisecondsSinceEpoch+30000,'earnedXp':0});
  for(final player in m['players'] as List){player['user']=player['seat']==0?gameUser():null;}
  final a=await gameAccount();addTearDown(a.dispose);final c=GamesController(a,intents:GameMemoryIntents(),autoPoll:false);addTearDown(c.dispose);await t.pump();await t.runAsync(()=>ready(c));c.match=m;
  final base=TomiTheme.dark();final theme=base.copyWith(textTheme:base.textTheme.apply(fontFamily:'CaptureArabic',fontFamilyFallback:['CaptureSymbols','CaptureEmoji']));
  const key=Key('board-capture');await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,locale:const Locale('ar'),supportedLocales:const [Locale('ar')],localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],theme:theme,home:GameTablePage(controller:c))));await t.pumpAndSettle();expect(t.takeException(),isNull);
  final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await t.runAsync(()async{final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);final out=Directory(Platform.environment['TOMI_CAPTURE_DIR']??'/tmp/tomi-board-captures');await out.create(recursive:true);await File('${out.path}/TOMI-$kind.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();});
  await t.pumpWidget(const SizedBox.shrink());
 });
}
