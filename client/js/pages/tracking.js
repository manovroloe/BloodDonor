/** pages/tracking: extracted from the working v22 flows. No build step is required. */
import { $, esc, fmtTime, statusClass, statusLabel, toast } from '../core/dom.js';
import { sb } from '../core/client.js';
import { trackingTimeline } from '../components/feedback.js';
export function init() {
    $('#trackForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!sb)
            return toast('BloodCare API is unavailable.', 'err');
        const f = new FormData(e.target), out = $('#trackResult');
        out.innerHTML = '<div class="empty">Checking…</div>';
        const { data, error } = await sb.rpc('public_track', {
            p_reference: f.get('reference'), p_email: f.get('email')
        });
        if (error)
            return out.innerHTML = `<div class="empty error-text">${esc(error.message)}</div>`;
        const x = data?.[0];
        out.innerHTML = x ? `<div class="tracking-card"><span class="tag">${esc(x.kind)}</span><h2>${esc(x.reference)}</h2><div class="status ${statusClass(x.status)}">${esc(statusLabel(x.status))}</div><p>${esc(x.summary)}</p>${trackingTimeline(x.kind, x.status)}<small>Last updated ${fmtTime(x.updated_at)}</small></div>` : '<div class="empty">No matching record was found. Check the tracking number and email address.</div>';
    });
}
