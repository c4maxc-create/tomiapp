import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../accounts/account_models.dart';
import '../accounts/account_widgets.dart';
import '../identity/progress_cards.dart';
import '../widgets.dart';
import 'game_models.dart';
import 'board_games.dart';
import 'game_controller.dart';
import 'game_art.dart';
import 'snakes_board.dart';

class GameTablePage extends StatefulWidget {
  const GameTablePage({super.key,required this.controller});
  final GamesController controller;
  @override
  State<GameTablePage> createState()=>_GameTablePageState();
}
class _GameTablePageState extends State<GameTablePage> {
  GamesController get c=>widget.controller;
  final clock=ValueNotifier<int>(0);
  Timer? timer;
  String? selected;
  bool announce=false;
  @override
  void initState(){super.initState();timer=Timer.periodic(const Duration(milliseconds:500),(_){if(mounted&&c.foreground)clock.value++;});}
  @override
  void dispose(){timer?.cancel();clock.dispose();super.dispose();}
  Future<void> rules() => showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,useSafeArea:true,
    builder:(context)=>SizedBox(height:MediaQuery.sizeOf(context).height*.76,child:ListView(padding:const EdgeInsets.all(22),children:[
      const Text('قواعد طاولة تومي',style:TextStyle(fontSize:24,fontWeight:FontWeight.w800)),const SizedBox(height:16),
      Text(boardRules[c.match?['kind']] ?? (c.match?['kind']=='uno'
        ? 'كل لاعب يبدأ بسبع أوراق. طابق لون الورقة أو رمزها، أو اختر ورقة تغيير اللون. اسحب ورقة واحدة؛ إذا كانت صالحة يمكنك لعبها أو تمرير الدور. بعد السحب لا يمكن لعب ورقة قديمة.\n\n⊘ يتجاوز اللاعب التالي. ⇄ يعكس الاتجاه، ويعيد دورك في مباراة لاعبين. +2 و+4 يسحبان للخصم ويتجاوزان دوره، ولا تتراكم أوراق السحب. +4 مسموحة فقط إذا ما عندك ورقة من اللون الحالي؛ الخادم يمنع الاستخدام المخالف بدل تحدّي التخمين.\n\nاختَر اللون عند لعب الورقة المتعددة. فعّل زر UNO قبل لعب الورقة التي تترك بيدك ورقة واحدة؛ في نسخة تومي تُطبق عقوبة ورقتين تلقائيًا عند نسيانه. أول لاعب يفرغ يده يفوز.'
        : 'ارمِ النرد في دورك، ثم يتحرك البيدق حسب الرقم الذي اختاره الخادم. السلم يرفعك والأفعى تنزلك عند الوقوف على بدايتها. الرقم6 يمنح دورًا إضافيًا. الوصول للخانة100 يحتاج الرقم بالضبط؛ إذا تجاوزتها تبقى بمكانك. أول من يصل100 يفوز.'),style:const TextStyle(height:1.9)),
      const SizedBox(height:18),const Text('المهلة30ثانية للدور. الكمبيوتر يكمل خطوة المتأخر، ولا تُحسب الخطوة التلقائية مشاركة فعلية لخبرة اللعب. عند مغادرة غرفة الأصدقاء يكمل الكمبيوتر مكانك، ويمكنك الرجوع من القسم دون مغادرة الجولة باستخدام زر الرجوع العادي.',style:TextStyle(height:1.8,color:TomiColors.muted)),
      TextButton(onPressed:()=>showGameProgress(context,c.progress),child:const Text('كيف يرتفع مستوى اللعب؟')),
    ])));
  Future<void> leave() async {
    final approved=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(scrollable:true,title:const Text('مغادرة الجولة؟'),content:const Text('يغادر حسابك الطاولة ويكمل الكمبيوتر مكانك إذا بقي أصدقاء. يمكنك استخدام الرجوع العادي لإبقاء جولتك مفتوحة.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('أبقى')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('مغادرة'))]));
    if(approved!=true||!c.canAct)return;
    if(await c.act('leave')&&mounted)Navigator.pop(context);
  }
  Future<void> play(PlayingCard card) async {
    String? color;
    if(card.wild){
      color=await showDialog<String>(context:context,builder:(context)=>AlertDialog(scrollable:true,title:const Text('اختَر اللون التالي'),content:Wrap(spacing:12,runSpacing:12,children:[
        for(final e in const {'red':'أحمر','blue':'أزرق','green':'أخضر','yellow':'أصفر'}.entries) FilledButton(onPressed:()=>Navigator.pop(context,e.key),style:FilledButton.styleFrom(backgroundColor:playingColor(e.key),foregroundColor:e.key=='yellow'?TomiColors.background:Colors.white),child:Text(e.value)),
      ])));
      if(color==null||!mounted)return;
    }
    final accepted=await c.act('play',{'cardId':card.id,if(color!=null)'color':color,'uno':announce});
    if(accepted&&mounted)setState((){selected=null;announce=false;});
  }
  Widget status(Map<String,dynamic> match)=>ValueListenableBuilder<int>(valueListenable:clock,builder:(context,_,child){
    final finished=match['status']=='finished',myTurn=match['kind']=='camel'||match['turn']==match['mySeat'];
    final remaining=(((match['deadlineAt'] as num?)?.toInt()??c.serverNow)-c.serverNow)/1000;
    return TomiCard(padding:const EdgeInsets.all(12),child:Wrap(spacing:12,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
      Icon(finished?Icons.emoji_events_outlined:myTurn?Icons.touch_app_outlined:Icons.hourglass_top_rounded,color:TomiColors.accent),
      Text(finished?'انتهت الجولة':match['status']=='waiting'?'بانتظار أصدقائك':match['status']=='cancelled'?'أُغلقت الجولة':myTurn?(match['kind']=='camel'?'فريقك يقدر يتحرك بأي وقت':'دورك الآن'):'دور اللاعب ${(match['turn'] as num?)?.toInt()==null?'':(match['turn'] as num).toInt()+1}',style:const TextStyle(fontWeight:FontWeight.w800)),
      if(match['status']=='playing'&&match['kind']!='camel')Text('${remaining.ceil().clamp(0,30)} ث',style:const TextStyle(color:TomiColors.gold)),
      Text(match['mode']=='practice'?'ضد الكمبيوتر':'طاولة أصدقاء',style:const TextStyle(color:TomiColors.muted,fontSize:12)),
    ]));
  });
  Widget lobby(Map<String,dynamic> match)=>TomiCard(child:Column(children:[
    const Icon(Icons.groups_2_outlined,size:48,color:TomiColors.accent),const SizedBox(height:12),
    const Text('اجمع أصدقاءك على الطاولة',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800),textAlign:TextAlign.center),
    const SizedBox(height:10),const Text('شارك الكود. من قسم الألعاب يضغط صديقك «انضم بكود».',textAlign:TextAlign.center,style:TextStyle(color:TomiColors.muted,height:1.7)),
    const SizedBox(height:20),FittedBox(child:SelectableText('${match['code']}',textDirection:TextDirection.ltr,style:const TextStyle(fontSize:32,letterSpacing:5,fontWeight:FontWeight.w900,color:TomiColors.gold))),
    TextButton.icon(onPressed:(){Clipboard.setData(ClipboardData(text:'${match['code']}'));showNote(context,'تم نسخ كود الطاولة');},icon:const Icon(Icons.copy_rounded),label:const Text('نسخ كود الطاولة')),
    const SizedBox(height:16),GamePlayers(match:match),const SizedBox(height:18),
    if(match['host']==true)FilledButton.icon(key:const Key('game-start'),onPressed:c.canAct&&(match['players'] as List).length>=2?()=>c.act('start'):null,icon:const Icon(Icons.play_arrow_rounded),label:const Text('ابدأ الجولة'))
    else const Text('صاحب الغرفة يبدأ الجولة عند اكتمالكم.',style:TextStyle(color:TomiColors.muted)),
    const SizedBox(height:8),Text(match['kind']=='camel'?'لاعبان أو3 • تنتهي الدعوة بعد10دقائق':'من2إلى4لاعبين • تنتهي الدعوة بعد10دقائق',style:TextStyle(fontSize:12,color:TomiColors.muted)),
  ]));
  Widget result(Map<String,dynamic> match){
    final result=match['result'] as Map?,seat=result?['winnerSeat'];
    final winners=(match['players'] as List).where((p)=>p['seat']==seat).toList();
    final winner=winners.isEmpty?null:winners.first as Map;
    final name=(winner?['user'] as Map?)?['displayName']??'الكمبيوتر ${seat is num?seat.toInt()+1:''}';
    return TomiCard(child:Column(children:[
      const Icon(Icons.emoji_events_rounded,size:48,color:TomiColors.gold),const SizedBox(height:12),
      Text(seat==match['mySeat']?'فوز جميل!':'الفائز $name',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900),textAlign:TextAlign.center),
      const SizedBox(height:8),Text((match['earnedXp'] as num? ?? 0)>0?'+${match['earnedXp']} XP لمستوى اللعب':'اكتملت الجولة • تفاصيل الخبرة من مستواك',style:const TextStyle(color:TomiColors.accent)),
      TextButton(onPressed:()=>showGameProgress(context,c.progress),child:const Text('شوف تقدّم مستواك')),
      FilledButton(onPressed:()=>Navigator.pop(context),child:const Text('الرجوع لقسم الألعاب')),
    ]));
  }
  Widget uno(Map<String,dynamic> match){
    final hand=(match['hand'] as List).map((x)=>PlayingCard.fromJson((x as Map).cast<String,dynamic>())).toList();
    final ids=(match['playableCardIds'] as List? ?? const []).cast<String>();
    final selectedCards=hand.where((card)=>card.id==selected&&ids.contains(card.id));
    final card=selectedCards.isEmpty?null:selectedCards.first;
    final order=[for(var i=0;i<hand.length;i++)if(hand[i].id!=selected)i,for(var i=0;i<hand.length;i++)if(hand[i].id==selected)i];
    final myTurn=match['status']=='playing'&&match['turn']==match['mySeat'];
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      TomiUnoTable(match:match,onDraw:c.canAct&&match['canDraw']==true?()=>c.act('draw'):null),
      const SizedBox(height:18),Wrap(spacing:12,runSpacing:6,crossAxisAlignment:WrapCrossAlignment.center,alignment:WrapAlignment.spaceBetween,children:[const Text('أوراقك',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800)),Text('${hand.length} ورقة • مرّر اليد',style:const TextStyle(fontSize:12,color:TomiColors.muted))]),
      SizedBox(height:192,child:LayoutBuilder(builder:(context,box)=>SingleChildScrollView(scrollDirection:Axis.horizontal,clipBehavior:Clip.none,
        child:SizedBox(width:math.max(box.maxWidth,62.0*math.max(0,hand.length-1)+118),height:192,child:Directionality(textDirection:TextDirection.ltr,child:Stack(clipBehavior:Clip.none,children:[
          for(final i in order)AnimatedPositioned(key:ValueKey('hand-position-${hand[i].id}'),duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:180),curve:Curves.easeOutCubic,left:14+i*62.0,bottom:hand[i].id==selected?29:13,
            child:Transform.rotate(angle:(i-(hand.length-1)/2).clamp(-6,6).toDouble()*.022,child:TomiPlayingCard(
              key:ValueKey('game-card-${hand[i].id}'),card:hand[i],width:90,selected:hand[i].id==selected,playable:!myTurn||ids.contains(hand[i].id),
              onTap:c.canAct&&myTurn&&ids.contains(hand[i].id)?()=>setState(()=>selected=hand[i].id):null))),
        ]))))),
      ),
      Wrap(spacing:10,runSpacing:10,crossAxisAlignment:WrapCrossAlignment.center,children:[
        FilledButton.icon(key:const Key('game-play-card'),onPressed:c.canAct&&myTurn&&card!=null?()=>play(card):null,icon:const Icon(Icons.style_outlined),label:const Text('العب الورقة')),
        OutlinedButton.icon(key:const Key('game-draw'),onPressed:c.canAct&&match['canDraw']==true?()=>c.act('draw'):null,icon:const Icon(Icons.add_rounded),label:const Text('اسحب')),
        if(match['canPass']==true)OutlinedButton(onPressed:c.canAct?()=>c.act('pass'):null,child:const Text('مرّر الدور')),
        FilterChip(key:const Key('game-uno-call'),selected:announce,onSelected:myTurn&&c.canAct?(value)=>setState(()=>announce=value):null,label:const Text('UNO!'),avatar:const Icon(Icons.campaign_outlined,size:18)),
      ]),
      const SizedBox(height:12),const Text('اختَر ورقة ثم العبها. فعّل UNO عندما ستبقى عندك ورقة واحدة.',style:TextStyle(fontSize:12,color:TomiColors.muted,height:1.7)),
    ]);
  }
  Widget snakes(Map<String,dynamic> match){
    final last=match['lastMove'] as Map?,dice=(last?['dice'] as num?)?.toInt()??1;
    return Column(children:[
      SnakesBoard(key:ValueKey('snakes-${match['id']}'),match:match),const SizedBox(height:22),
      Wrap(spacing:20,runSpacing:14,crossAxisAlignment:WrapCrossAlignment.center,alignment:WrapAlignment.center,children:[
        AnimatedSwitcher(duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:350),transitionBuilder:(child,animation)=>RotationTransition(turns:Tween<double>(begin:-.2,end:0).animate(animation),child:ScaleTransition(scale:animation,child:child)),child:DiceFace(key:ValueKey('${match['sequence']}-$dice'),value:dice)),
        FilledButton.icon(key:const Key('game-roll'),onPressed:c.canAct&&match['status']=='playing'&&match['turn']==match['mySeat']?()=>c.act('roll'):null,icon:const Icon(Icons.casino_outlined),label:const Text('ارمِ النرد')),
      ]),const SizedBox(height:14),
      if(last!=null)Text(last['overshoot']==true?'تحتاج الرقم بالضبط للوصول100':last['transport']=='ladder'?'صعود جميل! من ${last['landing']} إلى ${last['to']}':last['transport']=='snake'?'الأفعى نزلت البيدق إلى ${last['to']}':'النرد $dice • الخانة ${last['to']}',textAlign:TextAlign.center,style:const TextStyle(color:TomiColors.gold)),
      const SizedBox(height:8),const Text('6 = دور إضافي • الفوز بالخانة100بالضبط',textAlign:TextAlign.center,style:TextStyle(color:TomiColors.muted,fontSize:12)),
    ]);
  }
  @override
  Widget build(BuildContext context)=>AnimatedBuilder(animation:c,builder:(context,_){
    final match=c.match;
    return Scaffold(appBar:AppBar(title:FittedBox(fit:BoxFit.scaleDown,child:Text(gameName(match?['kind'] as String? ?? 'uno'))),actions:[IconButton(tooltip:'قواعد اللعبة',onPressed:rules,icon:const Icon(Icons.help_outline)),PopupMenuButton<String>(onSelected:(_)=>leave(),itemBuilder:(_)=>[const PopupMenuItem(value:'leave',child:Text('مغادرة الجولة'))])]),
      body:match==null?const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('ارجع إلى قسم الألعاب لفتح جولتك.'))):SafeArea(child:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,32),children:[
        status(match),const SizedBox(height:12),
        if(c.pending!=null)TomiCard(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Text('المحاولة محفوظة؛ استعدها للتحقق من نفس الخطوة.'),TextButton(key:const Key('game-recover'),onPressed:c.busy?null:()=>c.retryPending(),child:const Text('استعادة نفس المحاولة'))])),
        if(c.error!=null)AccountErrorMessage(c.error!),
        if(match['status']=='waiting')lobby(match)
        else if(match['status']=='cancelled')const FeaturePlaceholder(icon:Icons.flag_outlined,title:'أُغلقت الجولة',body:'انتهى وقتها أو غادر أصحابها. ارجع إلى الألعاب لبدء جولة جديدة.')
        else ...[
          if(['jackaroo','camel'].contains(match['kind']))BoardPlayers(match:match)else GamePlayers(match:match),const SizedBox(height:18),
          if(match['status']=='finished')...[['jackaroo','camel'].contains(match['kind'])?BoardGameResult(match:match):result(match),const SizedBox(height:20)],
          if(match['kind']=='uno')uno(match)else if(match['kind']=='jackaroo')JackarooTable(controller:c,match:match)else if(match['kind']=='camel')CamelTable(controller:c,match:match)else snakes(match),
        ],
      ])));
  });
}

class GamePlayers extends StatelessWidget {
  const GamePlayers({super.key,required this.match});
  final Map<String,dynamic> match;
  @override
  Widget build(BuildContext context)=>LayoutBuilder(builder:(context,box){
    final scale=MediaQuery.textScalerOf(context).scale(14)/14;
    final columns=box.maxWidth>=550*scale?4:2,width=(box.maxWidth-10*(columns-1))/columns;
    return Wrap(spacing:10,runSpacing:10,children:[for(final p in match['players'] as List)Container(width:width,padding:const EdgeInsets.all(10),
      decoration:BoxDecoration(color:TomiColors.surface,borderRadius:BorderRadius.circular(16),border:Border.all(color:match['status']=='playing'&&match['turn']==p['seat']?TomiColors.accent:TomiColors.border,width:1.5)),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        if(p['user'] is Map)AccountAvatar(AccountUser.fromJson((p['user'] as Map).cast<String,dynamic>()),size:32)else const Icon(Icons.smart_toy_outlined,color:TomiColors.muted,size:30),
        const SizedBox(height:5),Text((p['user'] as Map?)?['displayName'] as String? ?? 'كمبيوتر ${(p['seat'] as num).toInt()+1}',maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
        Text(match['status']=='waiting'?'جاهز':['uno','jackaroo'].contains(match['kind'])?'${p['cardCount']??0} ورقة':match['kind']=='camel'?'${p['progress']??0}٪':'خانة ${p['position']??0}',style:const TextStyle(color:TomiColors.gold,fontSize:11)),
      ])),
    ]);
  });
}

class TomiUnoTable extends StatelessWidget {
  const TomiUnoTable({super.key,required this.match,this.onDraw});
  final Map<String,dynamic> match;
  final VoidCallback? onDraw;
  @override
  Widget build(BuildContext context)=>AspectRatio(aspectRatio:1.22,child:Container(
    decoration:BoxDecoration(borderRadius:BorderRadius.circular(32),border:Border.all(color:TomiColors.border,width:5),gradient:const RadialGradient(colors:[Color(0xFF285851),TomiColors.surface,TomiColors.background],radius:1.1),boxShadow:const[BoxShadow(color:Colors.black38,blurRadius:22,offset:Offset(0,10))]),
    child:Stack(alignment:Alignment.center,children:[
      const Positioned(left:14,right:14,top:16,child:FittedBox(fit:BoxFit.scaleDown,child:Text('TOMI  /  CARD CLUB',textDirection:TextDirection.ltr,style:TextStyle(fontSize:10,letterSpacing:3,color:TomiColors.muted,fontWeight:FontWeight.w800)))),
      LayoutBuilder(builder:(context,box){final width=math.min(90.0,box.maxWidth*.27);return Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        Transform.rotate(angle:-.08,child:TomiPlayingCard(key:const Key('game-draw-pile'),width:width,onTap:onDraw)),SizedBox(width:box.maxWidth*.12),
        AnimatedSwitcher(duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:260),transitionBuilder:(child,animation)=>FadeTransition(opacity:animation,child:SlideTransition(position:Tween<Offset>(begin:const Offset(.25,-.35),end:Offset.zero).animate(CurvedAnimation(parent:animation,curve:Curves.easeOutCubic)),child:child)),
          child:Transform.rotate(key:ValueKey((match['topCard'] as Map?)?['id']),angle:.09,child:TomiPlayingCard(width:width,card:match['topCard'] is Map?PlayingCard.fromJson((match['topCard'] as Map).cast<String,dynamic>()):null))),
      ]);}),
      Positioned(bottom:14,child:Row(mainAxisSize:MainAxisSize.min,children:[Container(width:10,height:10,decoration:BoxDecoration(shape:BoxShape.circle,color:playingColor(match['activeColor'] as String?))),const SizedBox(width:7),Text('رزمة السحب ${match['deckCount']??0}',style:const TextStyle(fontSize:10,color:TomiColors.muted))])),
    ]),
  ));
}
