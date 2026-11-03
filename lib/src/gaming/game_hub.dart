import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_widgets.dart';
import '../identity/progress_cards.dart';
import '../identity/identity_models.dart';
import '../roulette/live_sheet.dart';
import '../widgets.dart';
import 'game_controller.dart';
import 'game_models.dart';
import 'game_table.dart';
import 'game_art.dart';
import 'snakes_board.dart';
import 'board_games.dart';

class GameHub extends StatefulWidget {
  const GameHub({super.key,required this.accounts,this.visible=true});
  final AccountController accounts;
  final bool visible;
  @override
  State<GameHub> createState()=>_GameHubState();
}
class _GameHubState extends State<GameHub> {
  late final c=GamesController(widget.accounts,visible:widget.visible,autoPoll:widget.accounts.realtimeEnabled);
  @override
  void didUpdateWidget(covariant GameHub old){super.didUpdateWidget(old);c.setVisible(widget.visible);}
  @override
  void dispose(){c.dispose();super.dispose();}
  Future<void> table() async {
    if(!mounted||c.match==null)return;
    await Navigator.push<void>(context,MaterialPageRoute<void>(builder:(_)=>GameTablePage(controller:c)));
    if(!mounted||!c.current)return;
    await c.load(forceSummary:true);
    unawaited(widget.accounts.reloadMe().catchError((Object _){}));
  }
  Future<void> choose(String kind) async {
    final mode=await showModalBottomSheet<String>(context:context,showDragHandle:true,useSafeArea:true,
      builder:(context)=>Column(mainAxisSize:MainAxisSize.min,children:[
        Padding(padding:const EdgeInsets.all(20),child:Text(gameName(kind),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800))),
        ListTile(leading:const Icon(Icons.smart_toy_outlined,color:TomiColors.accent),title:const Text('العب ضد الكمبيوتر'),subtitle:const Text('جولة مباشرة • خبرة لعب عند استيفاء الشروط'),onTap:()=>Navigator.pop(context,'practice')),
        ListTile(leading:const Icon(Icons.groups_outlined,color:TomiColors.gold),title:const Text('أنشئ طاولة للأصدقاء'),subtitle:Text(kind=='camel'?'شارك الكود • لاعبان أو3بفريق واحد':kind=='jackaroo'?'من2إلى4 • المقاعد الباقية يكملها الكمبيوتر':'شارك كود الطاولة • من2إلى4لاعبين'),onTap:()=>Navigator.pop(context,'friends')),
        const SizedBox(height:18),
      ]));
    if(mode!=null&&c.canAct&&await c.create(kind,mode))await table();
  }
  Future<void> join() async {
    final input=TextEditingController();
    String? code;
    try {
      code=await showDialog<String>(context:context,builder:(context)=>StatefulBuilder(builder:(context,setDialog)=>AlertDialog(
        scrollable:true,title:const Text('انضم لطاولة أصدقائك'),content:TextField(key:const Key('game-join-code'),controller:input,autofocus:true,maxLength:8,textDirection:TextDirection.ltr,textCapitalization:TextCapitalization.characters,
          inputFormatters:[FilteringTextInputFormatter.allow(RegExp('[a-fA-F0-9]'))],decoration:const InputDecoration(labelText:'كود الطاولة',hintText:'8 رموز'),onChanged:(_)=>setDialog((){})),
        actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('رجوع')),FilledButton(onPressed:input.text.length==8?()=>Navigator.pop(context,input.text):null,child:const Text('انضم'))],
      )));
    } finally {input.dispose();}
    if(code!=null&&c.canAct&&await c.join(code))await table();
  }
  Widget metric(IconData icon,String label,Color color,{VoidCallback? onTap})=>Material(color:TomiColors.raised,borderRadius:BorderRadius.circular(14),child:InkWell(onTap:onTap,borderRadius:BorderRadius.circular(14),child:Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:17,color:color),const SizedBox(width:6),Text(label,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700))]))));
  Widget tile({required String kind,required String title,required String subtitle,required Widget art,required VoidCallback? onTap})=>Material(color:TomiColors.surface,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(26),side:const BorderSide(color:TomiColors.border)),
    child:InkWell(key:ValueKey('game-tile-$kind'),onTap:onTap,borderRadius:BorderRadius.circular(26),child:Padding(padding:const EdgeInsets.fromLTRB(18,16,12,16),child:Row(children:[
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(kind=='roulette'?'جولة واحدة • من أي مكان':'TOMI PLAY',style:const TextStyle(color:TomiColors.accent,fontSize:10,letterSpacing:1.2,fontWeight:FontWeight.w800)),
        const SizedBox(height:10),Text(title,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900,height:1.3)),
        const SizedBox(height:8),Text(subtitle,style:const TextStyle(color:TomiColors.muted,fontSize:12,height:1.6)),
        const SizedBox(height:16),const Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.play_circle_outline_rounded,color:TomiColors.accent,size:21),SizedBox(width:6),Flexible(child:Text('ادخل والعب',style:TextStyle(color:TomiColors.accent,fontWeight:FontWeight.w800,fontSize:13)))]),
      ])),const SizedBox(width:6),SizedBox(width:126,height:142,child:Center(child:art)),
    ]))),
  );
  Future<void> roulette() async {
    await showLiveRoulette(context,widget.accounts,null);
    if(mounted&&c.current)await c.load(forceSummary:true);
  }
  @override
  Widget build(BuildContext context)=>AnimatedBuilder(animation:c,builder:(context,_){
    final user=widget.accounts.user;if(user==null)return const SizedBox.shrink();
    final charisma=(c.summary?['charisma'] as Map?)?['points']??user.identity.charisma;
    final identity=UserIdentity({...user.identity.data,'charisma':charisma,if(c.summary?['charisma'] is Map)'charismaTier':c.summary!['charisma']});
    final displayUser=user.withIdentity(identity).withGameProgress(c.progress);
    return RefreshIndicator(onRefresh:()=>c.load(forceSummary:true),child:ListView(key:const PageStorageKey('games-scroll'),padding:const EdgeInsets.fromLTRB(18,18,18,28),children:[
      Row(children:[
        const Icon(Icons.sports_esports_outlined,color:TomiColors.accent,size:34),const SizedBox(width:10),
        const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('TOMI PLAY',textDirection:TextDirection.ltr,style:TextStyle(fontSize:23,letterSpacing:2,fontWeight:FontWeight.w900)),Text('طاولتك، أصدقاؤك، وتحدّيك',style:TextStyle(fontSize:12,color:TomiColors.muted))])),
        AccountAvatar(user,size:42),
      ]),const SizedBox(height:16),
      Wrap(key:const Key('games-metrics'),spacing:8,runSpacing:8,children:[
        metric(Icons.monetization_on_outlined,'${c.summary?['coins']??'—'}',TomiColors.gold),
        metric(Icons.sports_esports_outlined,'Lv ${c.progress.level}',TomiColors.accent,onTap:()=>showGameProgress(context,c.progress)),
        metric(Icons.local_fire_department_outlined,'$charisma',TomiColors.pink,onTap:()=>showCharismaProgress(context,identity)),
      ]),const SizedBox(height:18),
      Row(children:[const Expanded(child:Text('العب على مزاجك',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800))),IconButton(key:const Key('game-join'),tooltip:'انضم بكود',onPressed:c.canAct?join:null,icon:const Icon(Icons.vpn_key_outlined,color:TomiColors.accent))]),
      const SizedBox(height:4),const Text('الكمبيوتر جاهز، أو اجمع أصحابك بكود الطاولة.',style:TextStyle(color:TomiColors.muted,fontSize:12,height:1.7)),
      const SizedBox(height:18),
      if(c.loading&&c.summary==null)const Padding(padding:EdgeInsets.only(bottom:12),child:LinearProgressIndicator(minHeight:2)),
      if(c.error!=null)...[AccountErrorMessage(c.error!),TextButton(onPressed:()=>c.storageReady?c.load(forceSummary:true):c.restore(),child:const Text('إعادة المحاولة'))],
      if(c.pending!=null)TomiCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Text('عندك محاولة محفوظة لم يتأكد ردها.'),TextButton(onPressed:c.busy?null:()async{if(await c.retryPending())await table();},child:const Text('استعادة نفس المحاولة'))])),
      for(final active in c.activeMatches)Padding(padding:const EdgeInsets.only(bottom:14),child:TomiCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('طاولتك مستمرة • ${gameName(active['kind'] as String)}',style:const TextStyle(color:TomiColors.gold,fontWeight:FontWeight.w800)),
        const SizedBox(height:8),FilledButton.icon(onPressed:c.busy?null:()async{if(await c.open(active['id'] as String))await table();},icon:const Icon(Icons.play_arrow),label:const Text('ارجع لطاولتك')),
      ]))),
      tile(kind:'uno',title:'أونو',subtitle:'أوراق، ألوان، وقلب للطاولة.\nضد الكمبيوتر أو أصدقائك.',art:const UnoFanArt(),onTap:c.canAct?()=>choose('uno'):null),
      const SizedBox(height:16),
      tile(kind:'snakes',title:'السلم والأفعى',subtitle:'100خانة ومغامرة بنرد واحد.\nحركة بيدق خطوة بخطوة.',art:Transform.rotate(angle:-.12,child:Container(width:112,height:112,decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),boxShadow:const[BoxShadow(color:Colors.black45,blurRadius:14,offset:Offset(0,8))]),child:ClipRRect(borderRadius:BorderRadius.circular(12),child:const CustomPaint(painter:SnakesBoardPainter())))),onTap:c.canAct?()=>choose('snakes'):null),
      const SizedBox(height:16),
      tile(kind:'jackaroo',title:'جاكارو',subtitle:(c.summary?['availableGames'] as List? ?? []).contains('jackaroo')?'أحجار وأوراق وفريق يسندك.\nأربعة مقاعد • فريقان.':'تحتاج تحديث الخادم لتفعيل جاكارو.',art:const SizedBox(width:112,height:112,child:CustomPaint(painter:JackarooBoardPainter())),onTap:c.canAct&&(c.summary?['availableGames'] as List? ?? []).contains('jackaroo')?()=>choose('jackaroo'):null),
      const SizedBox(height:16),
      tile(kind:'camel',title:'الجمل المجنون',subtitle:(c.summary?['availableGames'] as List? ?? []).contains('camel')?'طابق3ونظّف اللوح.\nتعاون مع أصحابك وانتبه للخانة!':'تحتاج تحديث الخادم لتفعيل الجمل.',art:Container(width:108,height:108,decoration:BoxDecoration(color:const Color(0xFFB9945B),borderRadius:BorderRadius.circular(20)),child:const Center(child:Text('🐪\n🥕  🧀  🍀',textAlign:TextAlign.center,style:TextStyle(fontSize:24)))),onTap:c.canAct&&(c.summary?['availableGames'] as List? ?? []).contains('camel')?()=>choose('camel'):null),
      const SizedBox(height:16),
      tile(kind:'roulette',title:'الروليت',subtitle:'نفس جولات الغرف ونفس رصيدك.\nافتحها مباشرة من هنا.',art:Container(width:108,height:108,decoration:BoxDecoration(shape:BoxShape.circle,gradient:const RadialGradient(colors:[TomiColors.raised,TomiColors.background]),border:Border.all(color:TomiColors.gold,width:4),boxShadow:const[BoxShadow(color:Colors.black45,blurRadius:14,offset:Offset(0,8))]),child:const Center(child:Text('🍉\n🍗  ✦  🍊',textAlign:TextAlign.center,style:TextStyle(fontSize:24)))),onTap:c.current&&!c.busy?roulette:null),
      const SizedBox(height:20),TomiProgressTiles(user:displayUser),const SizedBox(height:14),
      const Text('الكارزما من دعم الهدايا، والمستوى من اللعب. أونو والسلم والأفعى وجاكارو والجمل بدون رسوم دخول أو جوائز عملات. الروليت تستخدم رصيدك وتعرض قواعدها قبل الرهان.',style:TextStyle(fontSize:11,color:TomiColors.muted,height:1.8)),
    ]));
  });
}
