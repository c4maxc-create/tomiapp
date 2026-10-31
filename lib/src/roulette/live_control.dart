import 'dart:convert';
import 'package:flutter/material.dart';
import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import 'pending_store.dart';
import 'roulette_page.dart' show rouletteRequestId;

class LiveRouletteControlPage extends StatefulWidget {
  const LiveRouletteControlPage({super.key,required this.accounts});
  final AccountController accounts;
  @override
  State<LiveRouletteControlPage> createState() => _LiveRouletteControlPageState();
}
class _LiveRouletteControlPageState extends State<LiveRouletteControlPage> {
  String mode = 'random';
  int slot = 0, revision = 0;
  bool loading = true, busy = false;
  String? error, message;
  Map<String,dynamic>? pending;
  late final uid = widget.accounts.user?.id ?? '';
  late final session = widget.accounts.sessionRevision;
  String get key => 'tomi.live.roulette.control.${widget.accounts.api.baseUrl}.$uid';
  bool get current => mounted && uid.isNotEmpty && widget.accounts.user?.id == uid && widget.accounts.sessionRevision == session;
  @override
  void initState() {super.initState();load();}
  Future<void> load() async {
    if(busy)return;
    setState(()=>loading=true);
    try {
      final store=await RoulettePendingStore.getInstance(),raw=await store.getString(key);
      final d=await widget.accounts.chatRequest('GET','/v1/admin/live-roulette');if(!current)return;
      final saved=raw==null?null:(jsonDecode(raw) as Map).cast<String,dynamic>();
      final control=(saved??d['nextControl']) as Map;
      setState((){revision=(d['controlRevision'] as num).toInt();pending=saved;mode=control['mode'] as String;slot=(control['slot'] as num?)?.toInt()??0;error=null;});
    }on AccountFailure catch(f){if(current)setState(()=>error=f.message);}catch(_){if(current)setState(()=>error='تعذّر تحميل التحكم؛ أعد المحاولة.');}finally{if(current)setState(()=>loading=false);}
  }
  Future<void> save() async {
    if(busy||loading)return;setState((){busy=true;error=null;message=null;});
    try {
      final store=await RoulettePendingStore.getInstance();if(!current)return;
      pending??={'requestId':rouletteRequestId(),'expectedRevision':revision,'mode':mode,if(mode=='slot')'slot':slot};
      if(!await store.setString(key,jsonEncode(pending)))throw StateError('Not saved');
      if(!current)return;
      final d=await widget.accounts.chatRequest('POST','/v1/admin/live-roulette',body:pending);if(!current)return;
      await store.remove(key);if(!current)return;
      setState((){pending=null;revision=(d['controlRevision'] as num).toInt();message='تم حفظ الاختيار للجولة القادمة.';});
    }on AccountFailure catch(f){
      if(!current)return;
      if(f.status>=400&&f.status<500){final store=await RoulettePendingStore.getInstance();await store.remove(key);if(!current)return;pending=null;}
      setState(()=>error=f.message);
    }catch(_){if(current)setState(()=>error='تعذّر تأكيد الرد؛ أعد نفس الطلب للتحقق من حفظه.');}finally{if(current)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('تحكم روليت الغرف')),body:ListView(padding:const EdgeInsets.all(18),children:[
    const Text('اختيارك يطبّق على الجولة القادمة التي لم تبدأ بعد. يبقى اختيار الجولة الحالية ثابتًا بعد فتح الرهانات.'),
    const SizedBox(height:16),
    if(loading)const LinearProgressIndicator(),
    if(error!=null)Text(error!,style:const TextStyle(color:Colors.redAccent)),
    if(message!=null)Text(message!,style:const TextStyle(color:Colors.tealAccent)),
    const SizedBox(height:12),
    DropdownButtonFormField<String>(key:ValueKey('live-control-$mode'),initialValue:mode,isExpanded:true,decoration:const InputDecoration(labelText:'نتيجة الجولة القادمة'),items:const [DropdownMenuItem(value:'random',child:Text('عشوائية بالنسب المحددة')),DropdownMenuItem(value:'slot',child:Text('خانة محددة')),DropdownMenuItem(value:'fruit_salad',child:Text('سلطة فواكه')),DropdownMenuItem(value:'meat_salad',child:Text('سلطة لحوم'))],onChanged:busy||loading||pending!=null?null:(v)=>setState(()=>mode=v!)),
    if(mode=='slot')Padding(padding:const EdgeInsets.only(top:16),child:DropdownButtonFormField<int>(key:ValueKey('live-control-slot-$slot'),initialValue:slot,isExpanded:true,decoration:const InputDecoration(labelText:'الخانة'),items:[for(final e in const ['🍉 بطيخ ×5','🍊 برتقال ×5','🍎 تفاح ×5','🥬 خضار ×5','🐟 سمك ×10','🍔 برغر ×15','🍤 روبيان ×25','🍗 دجاج ×45'].indexed)DropdownMenuItem(value:e.$1,child:Text(e.$2))],onChanged:busy||loading||pending!=null?null:(v)=>setState(()=>slot=v!))),
    const SizedBox(height:20),
    FilledButton.icon(onPressed:busy||loading?null:save,icon:const Icon(Icons.save_outlined),label:Text(busy?'نتحقق من الحفظ…':pending==null?'حفظ الجولة القادمة':'استعادة طلب التحكم')),
    OutlinedButton(onPressed:busy?null:load,child:const Text('تحديث')),
  ]));
}
