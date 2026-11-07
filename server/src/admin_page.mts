import { readFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
export async function adminPage(req: IncomingMessage, res: ServerResponse, url: URL): Promise<boolean> {
    if (req.method !== 'GET' || !['/admin', '/admin/', '/admin/assets/dashboard.js'].includes(url.pathname))
        return false;
    const nonce = randomBytes(16).toString('base64');
    res.setHeader('cache-control', 'no-store');
    res.setHeader('x-content-type-options', 'nosniff');
    res.setHeader('referrer-policy', 'no-referrer');
    res.setHeader('x-frame-options', 'DENY');
    if (url.pathname.endsWith('.js')) {
        res.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8' });
        res.end(await readFile(new URL('../public/admin/dashboard.js', import.meta.url), 'utf8'));
        return true;
    }
    res.setHeader('content-security-policy', `default-src 'none'; script-src 'self'; style-src 'nonce-${nonce}'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'`);
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(`<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>TOMI | الإدارة</title><style nonce="${nonce}">*{box-sizing:border-box}body{margin:0;background:#0c1421;color:#f3f1fa;font-family:system-ui,sans-serif}main{max-width:1120px;margin:auto;padding:24px}header{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:24px 0}h1{margin:0}p,small,.card span{color:#a1a8c0;line-height:1.8}form,.card{padding:22px;background:#142333;border:1px solid #30465a;border-radius:20px}form{max-width:460px;margin:40px auto}label{display:block;margin:14px 0}input{display:block;width:100%;padding:14px;border:1px solid #30465a;border-radius:12px;background:#203246;color:white;font:inherit;margin-top:8px}button{font:inherit;cursor:pointer;border:1px solid #30465a;border-radius:14px;padding:12px 18px;background:#203246;color:#f3f1fa;margin:4px}button[type=submit],button[aria-pressed=true]{background:#77decf;color:#0c1421}button:disabled{opacity:.5;cursor:wait}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px;margin:24px 0}.card strong{display:block;font-size:30px;margin-top:12px;overflow-wrap:anywhere}nav{display:flex;gap:8px;flex-wrap:wrap}.list{display:grid;gap:12px;margin-top:20px}[hidden]{display:none!important}@media(max-width:700px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}main{padding:16px}}@media(max-width:400px){.grid{grid-template-columns:1fr}}</style><main><header><div><h1>TOMI</h1><small>مركز الإدارة والمتابعة</small></div></header><p id="note" role="status" aria-live="polite">تسجيل الدخول بحساب يملك صلاحيات الإدارة. تحتاج تسجيل الدخول مجددًا بعد إغلاق الصفحة.</p><form id="login"><h2>أهلًا بعودتك</h2><label>اليوزر<input id="username" autocomplete="username" required maxlength="20"></label><label>كلمة المرور<input id="password" type="password" autocomplete="current-password" required maxlength="128"></label><label>رمز المصادقة إن كان مفعّلاً<input id="mfa" autocomplete="one-time-code" maxlength="32"></label><button type="submit">دخول آمن</button></form><section id="panel" hidden><nav><button data-section="overview" aria-pressed="true">نظرة عامة</button><button data-section="reports" aria-pressed="false">البلاغات</button><button data-section="services" aria-pressed="false">حالة الخدمات</button><button id="refresh">تحديث</button><button id="logout">تسجيل خروج</button></nav><p>مؤشرات الخادم الحالي وتقارير الأداء الاختيارية. إجراءات الإشراف التفصيلية متاحة من قسم الإدارة داخل التطبيق.</p><div id="content"></div></section></main><script type="module" src="/admin/assets/dashboard.js"></script></html>`);
    return true;
}
