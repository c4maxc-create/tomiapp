import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets.dart';
import 'game_controller.dart';

const boardRules = <String,String>{
  'jackaroo':'جاكارو تومي: أربعة مقاعد بفريقين؛ 1 و3 ضد 2 و4. الطاولة تبدأ بلاعبين بشريين على الأقل وتكتمل مقاعدها بالكمبيوتر. لكل لاعب أربعة أحجار وأربع أوراق بكل توزيع.\n\nA يخرج حجرًا أو يتحرك1 أو11، وK يخرج حجرًا أو يتحرك13 ويأكل الأحجار غير المحمية بطريقه. 4 يرجع أربع خطوات. J يبدّل حجرين غير محميين. 7 تتوزع على أحجارك بترتيب أرقامها تصاعديًا؛ مجموع الخطوات7. باقي الأوراق بقيمتها وQ=12.\n\nحجر البداية محمي ويغلق المرور. لا يجوز الوقوف فوق حجر لك أو تجاوز حجر بالمسار الآمن، ويجب الوصول بالعدد الصحيح. بعد إدخال أحجارك الأربعة تبدأ مساعدة شريكك بالدور التالي. يفوز الفريق بإدخال أحجاره الثمانية. لا تبديل أوراق بين الشريكين بهذه النسخة. إذا ما عندك أي حركة تتخلص من ورقة. المهلة30ثانية ثم يتحرك الكمبيوتر بلا خبرة مشاركة بشرية.',
  'camel':'الجمل المجنون • تومي: طاولة تعاونية حتى3لاعبين، ولكل لاعب لوح54قطعة بطبقات. اضغط القطع المكشوفة فقط. كل3قطع من نفس الرمز تختفي من خانة التجميع.\n\nسعة الخانة7قطع؛ إذا امتلأت بدون تطابق يخسر الفريق. يفوز الفريق عندما يفرغ الجميع ألواحهم وخاناتهم والمخزن الجانبي. تقدر تتحرك بأي وقت، بدون انتظار دور.\n\nكل لاعب عنده مرة واحدة: نقل أول3قطع إلى مخزن جانبي، وتراجع عن آخر قطعة غير مطابقة، وخلط الرموز المتبقية. ترجع قطع المخزن بالضغط عليها. بعد تطابق3تُثبت النتيجة ولا يمكن إرجاعها بالتراجع. إكمال طلب الفريق يعطي شحن خلط إضافي، بحد2. الطلبات مشتركة، لكن ألواح الأصدقاء تبقى خاصة. لا يوجد دفع حقيقي أو شراء مساعدات.',
};
const boardColors=[Color(0xFFEC6472),Color(0xFF4EA9EE),Color(0xFFF3C86B),Color(0xFF61D4A3)];
const camelSymbols=['🥕','🧀','🥛','🍀','🧶','🫛','🍰','💎','🌽'];
Offset jackCell(int seat,int position){
  if(position<0)return const Offset(.5,.5);
  final angle=math.pi/2+seat*math.pi/2;
  if(position>=64){final r=.13+.045*(position-64);return Offset(.5+math.cos(angle)*r,.5+math.sin(angle)*r);}
  final a=math.pi/2+((seat*16+position)%64)*math.pi/32;
  final r=.355+.035*math.cos(4*a);return Offset(.5+math.cos(a)*r,.5+math.sin(a)*r);
}
Offset jackBase(int seat,int pawn){final angle=math.pi*.75+seat*math.pi/2;return Offset(.5+math.cos(angle)*.35+(pawn%2)*.045,.5+math.sin(angle)*.35+(pawn~/2)*.045);}

class JackarooBoardPainter extends CustomPainter {
  const JackarooBoardPainter();
  @override
  void paint(Canvas canvas,Size size){
    final center=Offset(size.width/2,size.height/2),r=size.shortestSide*.48;
    canvas.drawCircle(center,r,Paint()..color=const Color(0xFF443123));
    canvas.drawCircle(center,r-4,Paint()..shader=const RadialGradient(colors:[Color(0xFFF6DAA0),Color(0xFFC79954)]).createShader(Rect.fromCircle(center:center,radius:r)));
    canvas.drawCircle(center,r-9,Paint()..color=const Color(0xFF785533)..style=PaintingStyle.stroke..strokeWidth=1);
    for(var n=0;n<64;n++){final at=jackCell(0,n);canvas.drawCircle(Offset(at.dx*size.width,at.dy*size.height),size.width*.011,Paint()..color=n%16==0?boardColors[n~/16]:const Color(0xFF72533C));}
    for(var seat=0;seat<4;seat++)for(var n=0;n<4;n++){
      for(final at in [jackCell(seat,64+n),jackBase(seat,n)])canvas.drawCircle(Offset(at.dx*size.width,at.dy*size.height),size.width*.013,Paint()..color=boardColors[seat].withValues(alpha:.55));
    }
    final t=TextPainter(text:const TextSpan(text:'TOMI\nJACKAROO',style:TextStyle(fontFamily:'Roboto',fontSize:12,fontWeight:FontWeight.w900,color:Color(0xFF6F4C2C),height:1.8)),textAlign:TextAlign.center,textDirection:TextDirection.ltr)..layout();t.paint(canvas,center-Offset(t.width/2,t.height/2));
  }
  @override
  bool shouldRepaint(covariant JackarooBoardPainter old)=>false;
}
class JackarooTable extends StatelessWidget {
  const JackarooTable({super.key,required this.controller,required this.match});
  final GamesController controller;
  final Map<String,dynamic> match;
  Future<void> choose(BuildContext context,Map card)async{
    final choices=(match['choices'] as List? ?? []).where((x)=>x['cardId']==card['id']).toList();
    if(choices.isEmpty)return;
    final id=await showModalBottomSheet<String>(context:context,isScrollControlled:true,showDragHandle:true,useSafeArea:true,builder:(context)=>SizedBox(height:MediaQuery.sizeOf(context).height*.7,child:ListView(children:[
      Padding(padding:const EdgeInsets.all(20),child:Text('حركات ${card['value']} • اختر حركة',style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800))),
      for(final choice in choices)ListTile(key:ValueKey('jack-choice-${choice['id']}'),leading:const Icon(Icons.route,color:TomiColors.accent),title:Text(choice['label'] as String),onTap:()=>Navigator.pop(context,choice['id'] as String)),
    ])));
    if(id!=null&&controller.canAct)await controller.choose(id,(match['revision'] as num).toInt());
  }
  @override
  Widget build(BuildContext context){
    final players=match['players'] as List,hand=match['hand'] as List? ?? [],choices=match['choices'] as List? ?? [];
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('فريقك ${(match['mySeat'] as num).toInt()%2+1} • شريكك المقعد ${((match['mySeat'] as num).toInt()+2)%4+1}',style:const TextStyle(color:TomiColors.gold,fontWeight:FontWeight.w700)),
      if(match['controlledSeat']!=match['mySeat'])const Text('أكملت أحجارك • هسة ساعد شريكك',style:TextStyle(color:TomiColors.accent)),
      const SizedBox(height:10),AspectRatio(aspectRatio:1,child:LayoutBuilder(builder:(context,box)=>Stack(children:[
        const Positioned.fill(child:CustomPaint(painter:JackarooBoardPainter())),
        for(final p in players)for(var i=0;i<(p['pawns'] as List).length;i++)_pawn(context,box,p as Map,i),
      ]))),
      const SizedBox(height:16),const Text('أوراقك • اضغط الورقة لتشوف الحركات المسموحة',style:TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:10),
      Wrap(spacing:10,runSpacing:10,children:[for(final card in hand)SizedBox(width:64,child:Semantics(label:'ورقة ${card['value']} ${card['suit']}',button:true,child:OutlinedButton(key:ValueKey('jack-card-${card['id']}'),onPressed:controller.canAct&&choices.any((x)=>x['cardId']==card['id'])?()=>choose(context,card as Map):null,style:OutlinedButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:16,horizontal:4),backgroundColor:const Color(0xFFFFF5E1),foregroundColor:['hearts','diamonds'].contains(card['suit'])?const Color(0xFFBC3E54):const Color(0xFF25384A)),child:Text('${card['value']}\n${const {'clubs':'♣','diamonds':'♦','hearts':'♥','spades':'♠'}[card['suit']]}',textAlign:TextAlign.center,style:TextStyle(fontSize:21,fontWeight:FontWeight.w900,color:['hearts','diamonds'].contains(card['suit'])?const Color(0xFFBC3E54):const Color(0xFF25384A))))))]),
      if(choices.isEmpty&&match['status']=='playing')const Padding(padding:EdgeInsets.only(top:12),child:Text('انتظر دورك؛ أوراق اللاعبين الآخرين تبقى مخفية.',style:TextStyle(color:TomiColors.muted))),
      const SizedBox(height:14),const Text('A=1/11 أو خروج • K=13 أو خروج • 4 للخلف • J تبديل • 7 تقسيم',style:TextStyle(color:TomiColors.muted,fontSize:12,height:1.8)),
    ]);
  }
  Widget _pawn(BuildContext context,BoxConstraints box,Map p,int i){
    final seat=(p['seat'] as num).toInt(),pos=(p['pawns'][i] as num).toInt();final at=pos<0?jackBase(seat,i):jackCell(seat,pos),size=box.maxWidth*.045;
    return AnimatedPositioned(key:ValueKey('jack-pawn-$seat-$i'),duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:450),curve:Curves.easeInOutCubic,left:at.dx*box.maxWidth-size/2,top:at.dy*box.maxWidth-size/2,width:size,height:size,
      child:Semantics(label:'لاعب ${seat+1} حجر ${i+1}: ${pos<0?'القاعدة':pos>=64?'الأمان':'المسار $pos'}',child:Container(decoration:BoxDecoration(color:boardColors[seat],shape:BoxShape.circle,border:Border.all(color:Colors.white,width:1),boxShadow:const[BoxShadow(color:Colors.black45,blurRadius:4,offset:Offset(1,2))]),child:Center(child:FittedBox(child:Text('${i+1}',style:const TextStyle(color:Colors.black,fontWeight:FontWeight.w900,fontSize:10)))))));
  }
}

class CamelTable extends StatelessWidget {
  const CamelTable({super.key,required this.controller,required this.match});
  final GamesController controller;
  final Map<String,dynamic> match;
  @override
  Widget build(BuildContext context){
    final tiles=(match['tiles'] as List? ?? []).toList()..sort((a,b)=>(a['z'] as num).compareTo(b['z'] as num));
    final tray=match['tray'] as List? ?? [],side=match['side'] as List? ?? [],choices=match['choices'] as List? ?? [],tools=match['tools'] as Map? ?? {},orders=match['orders'] as Map? ?? {};
    final available=choices.map((c)=>c['id']).toSet();
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      TomiCard(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('الجمل المجنون • نتعاون ونفرغ الألواح',style:TextStyle(fontWeight:FontWeight.w800,color:TomiColors.gold)),
        const SizedBox(height:8),Text('طلب الفريق: ${camelSymbols[(orders['kind'] as num? ?? 0).toInt()]} • ${orders['count']??0}/${orders['required']??2} مطابقات • المنجزة ${orders['completed']??0}',style:const TextStyle(fontSize:12)),
      ])),const SizedBox(height:12),
      AspectRatio(aspectRatio:1.25,child:LayoutBuilder(builder:(context,box){
        final unit=box.maxWidth/14,tileSize=unit*1.9;
        return DecoratedBox(decoration:BoxDecoration(color:const Color(0xFFDAC18E),borderRadius:BorderRadius.circular(22),border:Border.all(color:TomiColors.gold,width:2)),child:Stack(clipBehavior:Clip.hardEdge,children:[
          if(tiles.isEmpty)const Center(child:Text('أفرغت اللوح! رتّب المتبقي بالمخزن والخانة.',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF61492E)))),
          for(final tile in tiles)AnimatedPositioned(key:ValueKey('camel-pos-${tile['id']}'),duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:180),left:unit*((tile['x'] as num).toDouble()+.5),top:unit*((tile['y'] as num).toDouble()+.5),width:tileSize,height:tileSize,
            child:_tile(tile,available.contains(tile['id'])&&controller.canAct,()=>controller.choose(tile['id'] as String,(match['revision'] as num).toInt()))),
        ]));
      })),
      const SizedBox(height:18),Text('خانة التجميع • ${tray.length}/7',style:TextStyle(fontWeight:FontWeight.w800,color:tray.length>=5?TomiColors.gold:TomiColors.accent)),const SizedBox(height:8),
      LayoutBuilder(builder:(context,box){final size=(box.maxWidth-6*4)/7;return Row(textDirection:TextDirection.ltr,children:[for(var i=0;i<7;i++)Padding(padding:EdgeInsets.only(right:i<6?4:0),child:SizedBox(width:size,height:size*1.15,child:AnimatedSwitcher(duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:220),child:i<tray.length?_tile(tray[i] as Map,false,null,slot:true):Container(key:ValueKey('empty-$i'),decoration:BoxDecoration(color:TomiColors.raised,borderRadius:BorderRadius.circular(7),border:Border.all(color:TomiColors.border))))))]);}),
      if(side.isNotEmpty)...[const SizedBox(height:12),const Text('المخزن الجانبي • اضغط القطعة حتى ترجعها'),const SizedBox(height:8),Wrap(spacing:8,runSpacing:8,children:[for(final t in side)SizedBox(width:48,height:52,child:_tile(t as Map,controller.canAct,()=>controller.choose('side:${t['id']}',(match['revision'] as num).toInt())))])],
      const SizedBox(height:14),Wrap(spacing:8,runSpacing:8,children:[for(final tool in const {'remove':'نقل3 للمخزن','undo':'تراجع','shuffle':'خلط'}.entries)OutlinedButton(key:ValueKey('camel-tool-${tool.key}'),onPressed:controller.canAct&&available.contains('tool:${tool.key}')?()=>controller.choose('tool:${tool.key}',(match['revision'] as num).toInt()):null,child:Text('${tool.value} (${tools[tool.key]??0})'))]),
      const SizedBox(height:10),const Text('اختار القطع المكشوفة؛ كل3نفس الرمز تختفي. انتبه: امتلاء الخانة7يخسّر الفريق. المساعدات مجانية ومحدودة.',style:TextStyle(color:TomiColors.muted,fontSize:12,height:1.8)),
    ]);
  }
  Widget _tile(Map tile,bool enabled,VoidCallback? onTap,{bool slot=false})=>Semantics(label:'قطعة ${camelSymbols[(tile['kind'] as num).toInt()]} ${enabled?'متاحة':'بالخانة أو مغطاة'}',button:onTap!=null,child:Material(key:ValueKey('camel-tile-${tile['id']}'),color:enabled||slot?const Color(0xFFFFF4D7):const Color(0xFFAEAE89),borderRadius:BorderRadius.circular(7),elevation:enabled?4:1,child:InkWell(key:ValueKey('camel-pick-${tile['id']}'),onTap:enabled?onTap:null,borderRadius:BorderRadius.circular(7),child:Padding(padding:const EdgeInsets.all(4),child:FittedBox(child:Text(camelSymbols[(tile['kind'] as num).toInt()],style:TextStyle(fontSize:25,color:enabled||slot?Colors.black:Colors.black45)))))));
}

class BoardPlayers extends StatelessWidget {
  const BoardPlayers({super.key,required this.match});
  final Map<String,dynamic> match;
  @override
  Widget build(BuildContext context)=>LayoutBuilder(builder:(context,box){
    final columns=box.maxWidth>=600?4:2,width=(box.maxWidth-8*(columns-1))/columns;
    return Wrap(spacing:8,runSpacing:8,children:[for(final p in match['players'] as List)Container(width:width,padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:TomiColors.surface,borderRadius:BorderRadius.circular(14),border:Border.all(color:p['seat']==match['mySeat']?TomiColors.accent:TomiColors.border)),child:Row(children:[
      Icon(p['bot']==true?Icons.smart_toy_outlined:Icons.person_outline,size:20,color:boardColors[(p['seat'] as num).toInt()]),const SizedBox(width:7),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text((p['user'] as Map?)?['displayName'] as String? ?? (p['seat']==match['mySeat']?'أنت':'كمبيوتر ${(p['seat'] as num).toInt()+1}'),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
        Text(match['kind']=='camel'?'${p['progress']??0}٪':'مقعد ${(p['seat'] as num).toInt()+1} • ${p['cardCount']??0} ورقة',style:const TextStyle(fontSize:10,color:TomiColors.gold)),
      ])),
    ]))]);
  });
}

class BoardGameResult extends StatelessWidget {
  const BoardGameResult({super.key,required this.match});
  final Map<String,dynamic> match;
  @override
  Widget build(BuildContext context){
    final result=match['result'] as Map? ?? {},won=(result['winnerSeats'] as List? ?? []).contains(match['mySeat']);
    return TomiCard(child:Column(children:[Icon(won?Icons.emoji_events_rounded:Icons.flag_outlined,color:TomiColors.gold,size:40),const SizedBox(height:10),Text(won?'فاز فريقك!':result['reason']=='tray_full'?'امتلأت خانة أحد أعضاء الفريق':'انتهت الجولة • فاز الفريق الثاني',textAlign:TextAlign.center,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),const SizedBox(height:8),Text('خبرتك المكتسبة: ${match['earnedXp']??0} XP'),TextButton(onPressed:()=>Navigator.pop(context),child:const Text('ارجع لقسم الألعاب'))]));
  }
}
