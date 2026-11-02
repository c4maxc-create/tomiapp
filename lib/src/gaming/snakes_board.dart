import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets.dart';

Offset boardSquare(int position) {
  final value=position.clamp(1,100).toInt()-1,row=value~/10;
  final column=row.isEven?value%10:9-value%10;
  return Offset((column+.5)/10,(9-row+.5)/10);
}
const pawnColors=[TomiColors.accent,TomiColors.gold,TomiColors.pink,Color(0xFF80A6F3)];

class SnakesBoard extends StatefulWidget {
  const SnakesBoard({super.key,required this.match});
  final Map<String,dynamic> match;
  @override
  State<SnakesBoard> createState()=>_SnakesBoardState();
}
class _SnakesBoardState extends State<SnakesBoard> with SingleTickerProviderStateMixin {
  late final motion=AnimationController(vsync:this,value:1);
  int? movingSeat;
  List<int> path=[];
  @override
  void didUpdateWidget(covariant SnakesBoard old){
    super.didUpdateWidget(old);
    if(old.match['sequence']==widget.match['sequence'])return;
    final last=widget.match['lastMove'] as Map?;
    if(last==null)return;
    movingSeat=(last['seat'] as num).toInt();
    path=[(last['from'] as num).toInt(),for(final p in last['steps'] as List)(p as num).toInt()];
    final destination=(last['to'] as num).toInt();
    if(path.last!=destination)path.add(destination);
    if(path.length<2||MediaQuery.disableAnimationsOf(context)){motion.value=1;return;}
    motion.duration=Duration(milliseconds:160*(path.length-1)+(last['transport']==null?0:340));
    motion.forward(from:0);
  }
  @override
  void dispose(){motion.dispose();super.dispose();}
  Map<int,int> links(String key)=>{for(final e in (widget.match[key] as Map? ?? const {}).entries)int.parse(e.key.toString()):(e.value as num).toInt()};
  @override
  Widget build(BuildContext context)=>AspectRatio(aspectRatio:1,child:LayoutBuilder(builder:(context,box){
    final size=math.min(box.maxWidth,box.maxHeight),pawn=size*.058;
    return DecoratedBox(decoration:BoxDecoration(borderRadius:BorderRadius.circular(20),border:Border.all(color:TomiColors.border,width:3),boxShadow:const[BoxShadow(color:Colors.black38,blurRadius:20,offset:Offset(0,8))]),
      child:ClipRRect(borderRadius:BorderRadius.circular(17),child:Stack(children:[
        Positioned.fill(child:RepaintBoundary(child:CustomPaint(painter:SnakesBoardPainter(ladders:links('ladders'),snakes:links('snakes'))))),
        for(final player in widget.match['players'] as List) AnimatedBuilder(animation:motion,builder:(context,_){
          final seat=(player['seat'] as num).toInt(),position=(player['position'] as num?)?.toInt()??0;
          var point=boardSquare(position);
          if(seat==movingSeat&&path.length>=2&&motion.value<1){
            final value=motion.value*(path.length-1),index=value.floor().clamp(0,path.length-2).toInt();
            point=Offset.lerp(boardSquare(path[index]),boardSquare(path[index+1]),Curves.easeInOut.transform((value-index).clamp(0,1).toDouble()))!;
          }
          final shift=Offset(seat.isEven?-.18:.18,seat<2?-.12:.18)*size*.1;
          return Positioned(left:point.dx*size-pawn/2+shift.dx,top:point.dy*size-pawn/2+shift.dy,
            child:Semantics(label:'اللاعب ${seat+1} في الخانة $position',child:Container(key:ValueKey('game-pawn-$seat'),width:pawn,height:pawn,
              decoration:BoxDecoration(shape:BoxShape.circle,gradient:RadialGradient(center:const Alignment(-.4,-.5),colors:[Colors.white,pawnColors[seat],Color.lerp(pawnColors[seat],Colors.black,.4)!]),border:Border.all(color:Colors.white,width:1.2),boxShadow:const[BoxShadow(color:Colors.black54,blurRadius:4,offset:Offset(0,3))]),
              child:Center(child:FittedBox(child:Text('${seat+1}',style:const TextStyle(fontSize:12,color:TomiColors.background,fontWeight:FontWeight.w900)))))));
        }),
      ])));
  }));
}

class SnakesBoardPainter extends CustomPainter {
  const SnakesBoardPainter({this.ladders=const{2:38,7:14,8:31,15:26,21:42,28:84,36:44,51:67,71:91,78:98,87:94},this.snakes=const{16:6,46:25,49:11,62:19,64:60,74:53,89:68,92:88,95:75,99:80}});
  final Map<int,int> ladders,snakes;
  String get signature=>'${ladders.entries.join(',')}|${snakes.entries.join(',')}';
  @override
  void paint(Canvas c,Size s){
    final cell=s.width/10;
    for(var n=1;n<=100;n++){
      final center=boardSquare(n)*s.width;
      final rect=Rect.fromCenter(center:center,width:cell,height:cell);
      c.drawRect(rect,Paint()..color=n==100?const Color(0xFF39695E):(n+(n-1)~/10).isEven?TomiColors.surface:TomiColors.raised);
      c.drawRect(rect,Paint()..style=PaintingStyle.stroke..strokeWidth=.4..color=TomiColors.border);
      final p=TextPainter(text:TextSpan(text:'$n',style:TextStyle(fontSize:cell*.26,color:n==100?TomiColors.gold:TomiColors.muted,fontWeight:FontWeight.w700)),textDirection:TextDirection.ltr)..layout();
      p.paint(c,rect.topLeft+Offset(cell*.07,cell*.04));p.dispose();
    }
    for(final e in ladders.entries){
      final a=boardSquare(e.key)*s.width,b=boardSquare(e.value)*s.width,v=b-a,length=v.distance;
      final side=Offset(-v.dy/length,v.dx/length)*cell*.13;
      final paint=Paint()..color=TomiColors.gold.withValues(alpha:.85)..strokeWidth=cell*.07..strokeCap=StrokeCap.round;
      c.drawLine(a-side,b-side,paint);c.drawLine(a+side,b+side,paint);
      final steps=(length/(cell*.4)).floor();
      for(var i=0;i<=steps;i++){final at=Offset.lerp(a,b,i/steps)!;c.drawLine(at-side,at+side,paint..strokeWidth=cell*.04);}
    }
    for(final e in snakes.entries){
      final a=boardSquare(e.key)*s.width,b=boardSquare(e.value)*s.width,v=b-a,side=Offset(-v.dy,v.dx)*.18;
      final path=Path()..moveTo(a.dx,a.dy)..cubicTo(a.dx+v.dx*.3+side.dx,a.dy+v.dy*.3+side.dy,a.dx+v.dx*.7-side.dx,a.dy+v.dy*.7-side.dy,b.dx,b.dy);
      c.drawPath(path,Paint()..style=PaintingStyle.stroke..strokeWidth=cell*.25..strokeCap=StrokeCap.round..color=TomiColors.background);
      c.drawPath(path,Paint()..style=PaintingStyle.stroke..strokeWidth=cell*.16..strokeCap=StrokeCap.round..color=TomiColors.accent.withValues(alpha:.75));
      c.drawCircle(a,cell*.16,Paint()..color=TomiColors.accent);
      c.drawCircle(a+Offset(-cell*.06,-cell*.035),cell*.025,Paint()..color=TomiColors.background);
      c.drawCircle(a+Offset(cell*.06,-cell*.035),cell*.025,Paint()..color=TomiColors.background);
    }
  }
  @override
  bool shouldRepaint(covariant SnakesBoardPainter old)=>old.signature!=signature;
}
