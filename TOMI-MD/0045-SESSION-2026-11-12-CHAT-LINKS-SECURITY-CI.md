# جلسة متابعة 2026-11-12 — اختبارات الروابط والأمان

## النطاق
استكمال المراحل غير المتعلقة بالألعاب فقط. لم تتغير قواعد الألعاب أو ملفات منطقها.

## تغييرات هذه الجلسة
- `lib/src/messaging/chat_link_text.dart`: التخلص من recognizers السابقة قبل بناء spans الجديدة، لتفادي تراكمها عند إعادة بناء الودجت بسبب تغيّر Theme/Inherited widgets.
- `test/chat_links_test.dart`: اختبار ظهور روابط HTTP وwww، إبقاء علامات الترقيم خارج الرابط، واستبدال recognizers بأمان عند تحديث النص والثيم والتخلص من الودجت.
- `.github/workflows/tomi-chat-links.yml`: CI مخصص لـ Flutter analyze واختبار الروابط. أُضيف توليد أصول C# الحالية قبل Flutter لأن `pubspec.yaml` يشير إلى مجلدات يتم إنشاؤها بواسطة `tool/build_csharp_games.py`.
- `.github/workflows/tomi-security.yml`: فحوص الأمان تعمل عند تحديثات main ذات الصلة، وليس فقط يدويًا أو وفق الجدولة.

## نتائج CI
- Run `43287008401` فشل في `flutter analyze` بسبب عدم وجود `assets/tomi_games/` و`assets/tomi_games/_framework/` في بيئة workflow النظيفة. لم يصل إلى اختبار الروابط.
- عولج سبب الفشل بإضافة .NET 8 وتشغيل `python3 tool/build_csharp_games.py` قبل Flutter analyze في workflow المخصص.
- إعادة الاختبار: run `43287277743` على commit `dcb848f91e11cd5a88118e916fb7b30736089ecd`؛ كان قيد التنفيذ عند تسجيل هذه الملاحظة، في خطوة Generate required CSharp UI assets.
- Security run `43287277437` على نفس commit؛ نجحت خطوات التحقق من إعدادات الهوية العامة، فحص أنماط الأسرار، تثبيت اعتماديات Node، تدقيق advisories الإنتاجية، وفحص server typecheck/admin build. تدقيق Rust native cryptography كان قيد التنفيذ. لا تُسجّل النتيجة النهائية قبل اكتمال workflow.

## ما لم يثبت بعد
لا يوجد بعد نجاح نهائي لاختبار chat links بعد إصلاح workflow، ولا Android APK جديد على آخر commit، ولا اختبار هاتفين أو نشر Render أو قياس حمل إنتاجي. يجب مراجعة run IDs أعلاه قبل أي ادعاء بالاكتمال.

## الحدود
الألعاب مؤجلة بالكامل بطلب المستخدم. بناء C# في CI هو توليد ملفات أصول موجودة لازمة لتشغيل Flutter analyzer، وليس تغييرًا في تصميم أو قواعد الألعاب.


## النتيجة النهائية لإعادة اختبار الروابط
اكتمل run `43287277743` بنجاح على commit `dcb848f91e11cd5a88118e916fb7b30736089ecd`: نجح توليد أصول C#، استعادة Flutter dependencies، `flutter analyze`، واختبار `test/chat_links_test.dart`. هذا نجاح CI مخصص للروابط والتحليل، وليس بناء APK أو اختبار جهاز حقيقي.

## متابعة إضافية — API وAndroid CI
- أضيف `.github/workflows/tomi-api.yml`: يشغل مجموعة اختبارات API كاملة على SQLite وPostgreSQL 17، ثم اختبار النسخ الاحتياطي المشفر والاستعادة في قاعدة CI مؤقتة. لا يستخدم قاعدة الإنتاج.
- أضيف `.github/workflows/tomi-android-smoke.yml`: يبني APK debug على Android runner دون اشتراط مفاتيح Firebase أو مفاتيح توقيع الإصدار، ويشغّل Flutter analyze والاختبارات وتجميع التشفير الأصلي. هذا artifact للاختبار الخاص فقط، وليس APK إصدار نهائي ولا يثبت عمل Push.
- تشغيل API workflow رقم `43328261086` على commit `36a34c20b7243bbd5b6f152f8ac5f71ddd969f7e` بدأ؛ مجموعة SQLite كانت قيد التنفيذ عند تحديث السجل.
- Security workflow رقم `43328261120` على commit `36a34c20b7243bbd5b6f152f8ac5f71ddd969f7e`: نجحت حتى الآن فحوص الأسرار والاعتماديات وتدقيق النوع/لوحة الإدارة، وكان تدقيق Rust/.NET قيد التنفيذ.
- Android smoke workflow رقم `43328411809` على commit `c1acb900bb60f43827c2855de2fb2b4ebe1daf63` بدأ؛ لا يوجد APK ناجح مثبت بعد.
- أرشيف المصدر على commit `36a34c20b7243bbd5b6f152f8ac5f71ddd969f7e` نجح في run `43328261011`.

## حدود إضافية
- Android smoke يختبر compilation والـ regression suite بإعداد Push غير مفعّل؛ لا يعد اختبارًا لتسليم الإشعارات على هاتف.
- لا تزال اختبارات الهاتفين، نشر Render، اختبار R2 الفعلي، اختبار الحمل، وMFA/FCM/LiveKit مع إعدادات الإنتاج تتطلب بيئة فعلية ومفاتيح المالك.

## متابعة 13 نوفمبر — إصلاح اختبار Android وتحسين جودة الفيديو
- فحص Android run 43328411809 كشف فشل اختبار test/e2ee42_test.dart بسبب أن عملية fixture لم تُخرج JSON على stdout. السبب أن الاختبار يشغّل API fixture يعتمد على node:sqlite، بينما workflow لم يجهّز Node 24 ولم يثبت اعتماديات server/.
- أضيف actions/setup-node@v6 مع Node 24 وnpm cache، ثم npm ci --ignore-scripts --no-audit --no-fund من مجلد server/ قبل اختبارات Flutter. commit الإصلاح الأول 620d73f3fa86fe1580d09f1a4a4867ec37e92ac1.
- أضيف server/** إلى مسارات تشغيل Android smoke حتى يعاد اختبار تكامل Flutter/API عند تغييرات الخادم.
- استكمال تحويل الفيديو: أضيفت rendition مجانية منخفضة الحجم بارتفاع 144px إلى جانب 540px و720px. worker ينتج الثلاثة، وعمليات التنظيف تحذف الثلاثة، واستعلامات/استجابات المنشورات والقصص والمحادثات والمجموعات تعرض المتاح منها. bitrate للـ144 هو 180k للفيديو مع AAC 96k.
- تحديث server/test/video_worker35.test.mjs ليختبر FFmpeg فعليًا على 144/540/720 ويتحقق من حفظ/تنظيف ثلاث نسخ.
- commits التنفيذ: c4fe94d4754b7b89d9fd07dbffd52b8a56e7127e, 59be6702b03a9e82d7138b194a6a5fb126f5acb1, dabfaa0c06d6d58838427c04719f0c390fb60d80, 16055110c75d97f0ecd5737fba1bd947ae60a224, d3b8138d1ab244e34dc908fed75d47ff4bba718d, f5157ead8391e30fd14209a295d25b2a6c6204d2, e823af24169230290b6316bb64cb0175eb3b7095, 480f627fe63fa95e244b101025935fc6d65c1cbe, 3fb7623fb643ac7321680389e1a090ad6f9db462.
- API + PostgreSQL + restore drill run 43328261086 اكتمل بنجاح على commit سابق.
- Android run 43330721909 على إصلاح Node 24 كان قيد التنفيذ عند آخر فحص. تشغيل أحدث يشمل تغييرات server بدأ/انتظر في run 43330949384 على commit 3fb7623fb643ac7321680389e1a090ad6f9db462.
- API run النهائي لتغييرات 144p هو 43330919985 على commit 480f627fe63fa95e244b101025935fc6d65c1cbe وكان قيد التنفيذ عند آخر فحص. لا تسجل نجاح التحويلات الجديدة قبل اكتماله.
- الألعاب لم تُعدّل؛ أصول C# الموجودة تُولد فقط كمتطلب لبناء Flutter.
- لم يثبت بعد اختبار R2 الفعلي، هاتفين، Push على جهاز، LiveKit/TURN إنتاجي، أو حمل إنتاجي. إضافة 144p تجعل النسخة المنخفضة متاحة من API عند اكتمال worker؛ لا تثبت وحدها اختيار العميل تلقائيًا لها أو نظام اشتراكات الجودة.
## متابعة إضافية — 13 نوفمبر 2026 (تصحيح بيئة تشفير Android)
- انتهى Android smoke run 43331150828 بالفشل في اختبار `test/e2ee42_test.dart`؛ السبب المؤكد من سجل CI أن الاختبار لم يجد `packages/tomi_secure/native/target/release/libtomi_secure.so` على Linux. الاختبار نفسه لم يُتجاوز.
- السبب: workflow كان يبني مكتبات Rust لأهداف Android فقط قبل Flutter tests، بينما تكامل FFI في اختبارات Flutter على Ubuntu يحتاج مكتبة host Linux.
- أضيف `python3 tool/build_secure_native.py --platform host` بعد بناء Android native وقبل Flutter analyze/tests. commit: 707fe90e8f588b90c08d1da1ac7055637e0acfc7.
- Android run الجديد 43416338162 وSecurity run 43416338019 على commit 707fe90e8f588b90c08d1da1ac7055637e0acfc7 كانا قيد التنفيذ عند تحديث هذه الملاحظة. لا تعلن نجاح Android قبل إتمام Flutter regression suite وdebug APK.
- source archive run 43416338228 اكتمل بنجاح على نفس commit.