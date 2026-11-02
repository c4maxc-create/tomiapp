import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets.dart';
import 'game_models.dart';

Color playingColor(String? color) => const {'red':Color(0xFFD95368),'blue':Color(0xFF487EC8),'green':Color(0xFF319D83),'yellow':Color(0xFFE7B746)}[color] ?? TomiColors.raised;

/// Vector card faces retain sharp type, bevels and shadows at every density.
class TomiPlayingCard extends StatelessWidget {
  const TomiPlayingCard({super.key, this.card, this.width=90, this.selected=false, this.playable=true, this.onTap});
  final PlayingCard? card;
  final double width;
  final bool selected, playable;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: card?.label ?? 'رزمة السحب', selected: selected, button: onTap != null,
    child: GestureDetector(onTap: onTap, child: RepaintBoundary(child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160),
      width: width, height: width*1.45,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(width*.13),
        border: Border.all(color: selected ? TomiColors.accent : Colors.transparent, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:.45), blurRadius: selected?16:9, offset: Offset(0,selected?10:6)),if(selected)BoxShadow(color:TomiColors.accent.withValues(alpha:.28),blurRadius:18)]),
      child: Opacity(opacity:playable?1:.53,child:CustomPaint(painter:_CardPainter(card))),
    ))),
  );
}

class _CardPainter extends CustomPainter {
  const _CardPainter(this.card);
  final PlayingCard? card;
  void text(Canvas c, String value, Offset center, double size, Color color, {FontWeight weight=FontWeight.w900}) {
    final p=TextPainter(text:TextSpan(text:value,style:TextStyle(fontSize:size,color:color,fontWeight:weight,fontFamily:'sans-serif')),textDirection:TextDirection.ltr)..layout();
    p.paint(c,center-Offset(p.width/2,p.height/2));p.dispose();
  }
  @override
  void paint(Canvas c, Size s) {
    final rect=Offset.zero&s,round=RRect.fromRectAndRadius(rect,Radius.circular(s.width*.12));
    c.drawRRect(round,Paint()..shader=const LinearGradient(colors:[Color(0xFFFFFCF0),Color(0xFFD6DDDB)],begin:Alignment.topLeft,end:Alignment.bottomRight).createShader(rect));
    final inner=RRect.fromRectAndRadius(rect.deflate(s.width*.055),Radius.circular(s.width*.08));
    final color=playingColor(card?.color);
    c.drawRRect(inner,Paint()..shader=LinearGradient(colors:[color,Color.lerp(color,TomiColors.background,.4)!],begin:Alignment.topLeft,end:Alignment.bottomRight).createShader(rect));
    c.save();c.clipRRect(inner);
    if(card==null) {
      final paint=Paint()..color=TomiColors.accent.withValues(alpha:.12)..strokeWidth=1;
      for(double x=-s.height;x<s.width+s.height;x+=12)c.drawLine(Offset(x,0),Offset(x+s.height,s.height),paint);
      c.translate(s.width/2,s.height/2);c.rotate(-.38);
      c.drawOval(Rect.fromCenter(center:Offset.zero,width:s.width*.76,height:s.height*.7),Paint()..style=PaintingStyle.stroke..strokeWidth=3..color=TomiColors.accent);
      text(c,'TOMI',Offset.zero,s.width*.22,TomiColors.text);
      text(c,'PLAY',Offset(0,s.width*.25),s.width*.10,TomiColors.gold);
    } else {
      c.translate(s.width/2,s.height/2);c.rotate(.38);
      if(card!.wild) {
        final r=Rect.fromCenter(center:Offset.zero,width:s.width*.68,height:s.height*.68);
        for(var i=0;i<4;i++)c.drawArc(r,-math.pi/2+i*math.pi/2,math.pi/2,true,Paint()..color=playingColor(['red','blue','yellow','green'][i]));
      } else c.drawOval(Rect.fromCenter(center:Offset.zero,width:s.width*.65,height:s.height*.74),Paint()..color=const Color(0xFFF8F4E9));
      c.rotate(-.38);
      text(c,card!.symbol,const Offset(1,2),s.width*(card!.symbol.length>1?0.37:0.62),Colors.black.withValues(alpha:.22));
      text(c,card!.symbol,Offset.zero,s.width*(card!.symbol.length>1?0.37:0.62),card!.wild?Colors.white:card!.color=='yellow'?TomiColors.background:color);
    }
    c.restore();
    if(card!=null) {
      final ink=card!.color=='yellow'?TomiColors.background:Colors.white;
      text(c,card!.symbol,Offset(s.width*.20,s.height*.14),s.width*.19,ink);
      c.save();c.translate(s.width,s.height);c.rotate(math.pi);text(c,card!.symbol,Offset(s.width*.20,s.height*.14),s.width*.19,ink);c.restore();
    }
    c.drawRRect(round,Paint()..style=PaintingStyle.stroke..strokeWidth=1..color=Colors.white.withValues(alpha:.65));
  }
  @override
  bool shouldRepaint(covariant _CardPainter old) => old.card?.id!=card?.id;
}

class UnoFanArt extends StatelessWidget {
  const UnoFanArt({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(width:156,height:132,child:Stack(alignment:Alignment.bottomCenter,children:[
    Transform.translate(offset:const Offset(-36,-2),child:Transform.rotate(angle:-.35,child:const TomiPlayingCard(width:64,card:PlayingCard(id:'art-red',value:'7',color:'red')))),
    const TomiPlayingCard(width:68,card:PlayingCard(id:'art-blue',value:'reverse',color:'blue')),
    Transform.translate(offset:const Offset(36,-2),child:Transform.rotate(angle:.35,child:const TomiPlayingCard(width:64,card:PlayingCard(id:'art-wild',value:'wild4')))),
  ]));
}

class DiceFace extends StatelessWidget {
  const DiceFace({super.key,required this.value,this.size=64});
  final int value;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(label:'النرد $value',child:Container(width:size,height:size,
    decoration:BoxDecoration(borderRadius:BorderRadius.circular(size*.24),gradient:const LinearGradient(colors:[Color(0xFFFFF9E7),Color(0xFFD8DFDD)],begin:Alignment.topLeft,end:Alignment.bottomRight),boxShadow:const[BoxShadow(color:Colors.black38,blurRadius:14,offset:Offset(0,6))]),
    child:CustomPaint(painter:_DicePainter(value))));
}
class _DicePainter extends CustomPainter {
  const _DicePainter(this.value);
  final int value;
  @override
  void paint(Canvas c,Size s){
    final dots=<Offset>[];
    if(value.isOdd)dots.add(const Offset(.5,.5));
    if(value>=2)dots.addAll([const Offset(.26,.26),const Offset(.74,.74)]);
    if(value>=4)dots.addAll([const Offset(.74,.26),const Offset(.26,.74)]);
    if(value==6)dots.addAll([const Offset(.26,.5),const Offset(.74,.5)]);
    for(final p in dots)c.drawCircle(Offset(s.width*p.dx,s.height*p.dy),s.width*.075,Paint()..color=TomiColors.background);
  }
  @override
  bool shouldRepaint(covariant _DicePainter old)=>old.value!=value;
}
