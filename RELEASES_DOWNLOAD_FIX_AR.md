# حل فشل رفع APK بسبب حصة Artifacts

التطبيق في صور التشغيل 42 وصل إلى رفع ملف APK، لكن GitHub رفض إنشاء Artifact برسالة Artifact storage quota has been hit. الإعادة المرسلة لاحقًا أكدت 403 وinsufficient usage to create artifact. الحل في هذه الحزمة يجعل التنزيل من **Releases** داخل المستودع نفسه.

## الخطوات لنسختك الحالية

يكفي تبديل ملف واحد، لأن المصدر الحالي اجتاز الفحوص والبناء:

1. نزّل **tomi-android.yml** المرفق في الرد.
2. افتح مستودع **ToLo10/tomiapp** على GitHub، واختر فرع **main**.
3. من **Code** ادخل مجلد **.github** ثم **workflows**.
4. اختر **Add file → Upload files** وارفع الملف ليحل محل الموجود بالاسم نفسه. المسار النهائي يجب أن يكون `.github/workflows/tomi-android.yml`.
5. اضغط **Commit changes** واحفظ التعديل على main.
6. افتح **Actions → TOMI 1.4.0-beta.1 Android → Run workflow**، واختر **main / accounts / debug** وعنوان الخادم الحالي، ثم ابدأ تشغيلًا جديدًا. هذا التعديل يحتاج تشغيلًا على الكوميت الجديد؛ إعادة التشغيل السابق تستخدم ملفه القديم.
7. بعد نجاح التشغيل افتح https://github.com/ToLo10/tomiapp/releases . افتح نسخة TOMI الجديدة، ووسّع **Assets**، ونزّل **TOMI-1.4.0-beta.1.apk**.

ستجد أيضًا رابط **Open APK/AAB downloads** في ملخص التشغيل. ملفات Source code التي يعرضها GitHub تخص المصدر؛ ملف التثبيت ينتهي بـ.apk.

## ما الذي تغير

ملف workflow يحفظ النسخة التجريبية مع بصماتها في Release له رقم تشغيل ومحاولة فريدان، ويربطه بكوميت البناء. يبدأ الحفظ كمسودة، ثم يتحقق من الملفات المرفوعة وأحجامها وبصماتها إن وفّرها الخادم، وبعدها ينشره كـPrerelease. إخفاق الرفع أو التحقق يبقي الوظيفة فاشلة والمسودة غير منشورة.

يستعمل رمز GitHub التلقائي، مع صلاحية contents:write لوظيفة Android وحدها. صلاحيات قراءة المستودع تحدد من يصل إلى النسخة. لا يحذف هذا التعديل نسخك القديمة أو يغير ظهور المستودع أو خطة الحساب. خدمة Render وقاعدة البيانات وإعداد Firebase الحالي تُستعمل كما هي. كل فحوص API والتطبيق والتوقيع والتنظيف السابقة محفوظة.

الحزمة **TOMI-1.4-releases-fix.zip** تتضمن المصدر الكامل أيضًا. التقرير **VALIDATION-1.4-RELEASES-FIX.md** وسجل الاستكمال **TOMI-PROGRESS.md**.

المراجع الرسمية: https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases وhttps://cli.github.com/manual/gh_release_create وhttps://docs.github.com/en/actions/tutorials/authenticate-with-github_token .
