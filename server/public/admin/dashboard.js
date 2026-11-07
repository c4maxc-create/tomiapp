"use strict";
const form = document.querySelector('#login'), panel = document.querySelector('#panel'), content = document.querySelector('#content'), note = document.querySelector('#note');
let token = null, generation = 0, section = 'overview', controller = null;
const record = (v) => v && typeof v === 'object' && !Array.isArray(v) ? v : {};
const number = (v) => Number.isFinite(Number(v)) ? Number(v) : 0;
function element(tag, text, className) {
    const node = document.createElement(tag);
    node.textContent = text;
    if (className)
        node.className = className;
    return node;
}
class AdminResponseError extends Error {
    status;
    constructor(status, message) { super(message); this.status = status; }
}
async function request(path, body, auth = token, signal) {
    const r = await fetch(path, { method: body ? 'POST' : 'GET', headers: { accept: 'application/json', ...(body ? { 'content-type': 'application/json' } : {}), ...(auth ? { authorization: 'Bearer ' + auth } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}), signal, cache: 'no-store', redirect: 'error', credentials: 'omit' });
    const data = record(await r.json());
    if (!r.ok)
        throw new AdminResponseError(r.status, r.status === 403 ? 'حسابك لا يملك صلاحية هذا القسم.' : r.status === 401 ? 'انتهت الجلسة؛ سجّل الدخول مجددًا.' : String(record(data.error).message ?? 'تعذّر التحميل؛ أعد المحاولة.'));
    return data;
}
function cards(values) {
    const grid = element('div', '', 'grid');
    for (const [label, value] of Object.entries(values)) {
        const card = element('article', '', 'card');
        card.append(element('span', label), element('strong', String(value)));
        grid.append(card);
    }
    content.replaceChildren(grid);
}
async function refresh() {
    if (!token)
        return;
    const gen = ++generation;
    controller?.abort();
    controller = new AbortController();
    note.textContent = 'جارٍ التحديث…';
    try {
        if (section === 'reports') {
            const d = await request('/v1/admin/reports', undefined, token, controller.signal);
            if (gen !== generation)
                return;
            const rows = Array.isArray(d.items) ? d.items : Array.isArray(d.reports) ? d.reports : [];
            const list = element('div', '', 'list');
            for (const item of rows) {
                const r = record(item);
                list.append(element('article', `${String(r.reason ?? r.category ?? 'بلاغ')} • ${String(r.status ?? '')} • ${String(r.createdAt ?? '')}`, 'card'));
            }
            if (!rows.length)
                list.append(element('p', 'لا توجد بلاغات معروضة.'));
            content.replaceChildren(list);
        }
        else {
            const [d, h] = await Promise.all([request('/v1/admin/metrics', undefined, token, controller.signal), request('/health', undefined, token, controller.signal)]);
            if (gen !== generation)
                return;
            const db = record(d.database), r = record(d.requests), security = record(d.security), features = record(h.features);
            if (section === 'services')
                cards({ 'الإشعارات': features.phoneNotifications ? 'الإعداد موجود' : 'تحتاج إعدادًا', 'المكالمات': features.phoneCalls ? 'الإعداد موجود' : 'تحتاج TURN', 'الغرف': features.voiceRooms ? 'الإعداد موجود' : 'تحتاج LiveKit', 'البث': features.liveBroadcasts ? 'الإعداد موجود' : 'يحتاج LiveKit' });
            else {
                const metrics = Array.isArray(d.clientPerformance) ? d.clientPerformance.map(record) : [];
                cards({ 'تنبيه أمني': security.warning ? 'نشاط غير اعتيادي؛ راجع الحماية' : 'لا تنبيه حسب حدود الساعة', 'طلبات مرفوضة للصلاحيات': number(security.forbidden), 'طلبات محدودة السرعة': number(security.throttled), 'طلبات آخر ساعة': number(r.count), 'أخطاء الخادم': number(r.serverErrors), 'متوسط الاستجابة ms': number(r.averageMs), 'الحسابات': number(db.users), 'الغرف المفتوحة': number(db.open_rooms), 'مكالمات جارية': number(db.active_calls), 'بلاغات تنتظر': number(db.pending_reports), 'تقارير أخطاء اختيارية': metrics.filter(m => m.kind === 'flutter_error').reduce((n, m) => n + number(m.total), 0), 'تقارير بطء الرسم': metrics.filter(m => m.kind === 'slow_frame').reduce((n, m) => n + number(m.total), 0) });
            }
        }
        if (gen === generation)
            note.textContent = 'آخر تحديث: ' + new Date().toLocaleTimeString('ar-IQ');
    }
    catch (e) {
        if (gen === generation && e instanceof AdminResponseError && [401, 403].includes(e.status)) {
            content.replaceChildren();
            if (e.status === 401) {
                token = null;
                form.hidden = false;
                panel.hidden = true;
            }
        }
        if (gen === generation && !(e instanceof DOMException && e.name === 'AbortError'))
            note.textContent = e instanceof Error ? e.message : 'تعذّر التحميل.';
    }
}
form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const button = form.querySelector('button'), username = form.querySelector('#username'), password = form.querySelector('#password');
    button.disabled = true;
    try {
        const d = await request('/v1/auth/login', { username: username.value, password: password.value, mfaCode: form.querySelector('#mfa').value.trim() }, null);
        if (typeof d.token !== 'string')
            throw new Error('تعذّر تسجيل الدخول.');
        token = d.token;
        form.hidden = true;
        panel.hidden = false;
        password.value = '';
        form.querySelector('#mfa').value = '';
        await refresh();
    }
    catch (e) {
        note.textContent = e instanceof Error ? e.message : 'تعذّر تسجيل الدخول.';
    }
    finally {
        button.disabled = false;
        password.value = '';
        form.querySelector('#mfa').value = '';
    }
});
document.querySelector('#logout').addEventListener('click', () => {
    const old = token;
    token = null;
    generation++;
    controller?.abort();
    form.hidden = false;
    panel.hidden = true;
    content.replaceChildren();
    note.textContent = 'تم تسجيل الخروج.';
    if (old)
        void request('/v1/auth/logout', {}, old).catch(() => { note.textContent = 'خرجت من الصفحة؛ تعذّر تأكيد إنهاء الجلسة. راجع الأجهزة من التطبيق.'; });
});
document.querySelector('#refresh').addEventListener('click', () => void refresh());
for (const b of document.querySelectorAll('[data-section]'))
    b.addEventListener('click', () => {
        section = b.dataset.section ?? 'overview';
        for (const other of document.querySelectorAll('[data-section]'))
            other.setAttribute('aria-pressed', String(other === b));
        void refresh();
    });
window.setInterval(() => {
    if (!document.hidden && token)
        void refresh();
}, 30000);
