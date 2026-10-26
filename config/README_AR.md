# إعداد إشعارات Android

لإصدار accounts يلزم إعداد Firebase لتطبيق Android ذي الحزمة `com.tomi.tomi_app`.

المسار الموصى به: احفظ محتوى `google-services.json` في GitHub Actions Secret باسم `TOMI_GOOGLE_SERVICES_JSON`.
ويمكن بدلًا منه وضع ملف إعداد العميل في `config/google-services.json`؛ أداة البناء تنقله إلى Android بعد توليد ملفات المنصة. لا توجد قيم تجريبية مرفقة في الحزمة.

ملف خدمة الخادم الخاص يبقى في متغير `FCM_SERVICE_ACCOUNT_JSON` داخل Render. راجع `FIX_NOTIFICATIONS_ROOMS_1.3.2_AR.md` للخطوات الكاملة.
