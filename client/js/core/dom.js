/** core/dom: extracted from the working v22 flows. No build step is required. */
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
}[c]));
const fmt = d => d ? new Date(`${String(d).slice(0, 10)}T00:00:00`).toLocaleDateString(undefined, {
    year: 'numeric', month: 'short', day: 'numeric'
}) : '—';
const fmtTime = d => d ? new Date(d).toLocaleString(undefined, {
    year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'
}) : '—';
const localDate = d => {
    const n = d || new Date(), y = n.getFullYear(), m = String(n.getMonth() + 1).padStart(2, '0'), day = String(n.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
};
const today = () => localDate(new Date());
const toast = (msg, type = 'ok') => {
    const x = document.createElement('div');
    x.className = 'toast ' + type;
    x.textContent = msg;
    document.body.append(x);
    setTimeout(() => x.remove(), 4200);
};
const loading = (btn, on) => {
    if (!btn)
        return;
    if (on) {
        btn.dataset.t = btn.textContent;
        btn.disabled = true;
        btn.textContent = 'Please wait…';
    }
    else {
        btn.disabled = false;
        btn.textContent = btn.dataset.t || btn.textContent;
    }
};
const statusLabel = s => String(s || '').replaceAll('_', ' ').replace(/\b\w/g, m => m.toUpperCase());
const statusClass = s => String(s || '').replace(/[^a-z0-9_-]/gi, '-');
const PAGE_SIZE = 25;
const normalizePhone = v => {
    const raw = String(v || '').trim().replace(/[^0-9+]/g, '');
    return raw.startsWith('09') ? '+63' + raw.slice(1) : raw;
};
const excerpt = (v, n = 210) => {
    const t = String(v || '').trim();
    return t.length > n ? t.slice(0, n).trimEnd() + '…' : t;
};
export { $, $$, PAGE_SIZE, esc, excerpt, fmt, fmtTime, loading, localDate, normalizePhone, statusClass, statusLabel, toast, today };
