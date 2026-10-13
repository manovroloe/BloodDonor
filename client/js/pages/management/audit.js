/** pages/management/audit: extracted from the working v22 flows. No build step is required. */
import { sb } from '../../core/client.js';
import { $, PAGE_SIZE, esc, fmtTime, statusLabel } from '../../core/dom.js';
import { renderPager } from '../../components/feedback.js';
let auditRows = [], auditNames = {}, auditPage = 1;
async function loadAudit() {
    const [a, p] = await Promise.all([sb.from('audit_logs').select('*').order('created_at', {
            ascending: false
        }).limit(1000), sb.from('staff_profiles').select('id,full_name,email')]);
    auditRows = a.data || [];
    auditNames = Object.fromEntries((p.data || []).map(x => [x.id, x.full_name || x.email]));
    renderAudit();
}
function renderAudit() {
    const q = ($('#auditSearch')?.value || '').toLowerCase(), entity = $('#auditEntityFilter')?.value || '';
    const rows = auditRows.filter(x => (!entity || x.entity_type === entity) && (!q || [x.action, x.entity_type, x.entity_id, auditNames[x.performed_by] || 'public'].join(' ').toLowerCase().includes(q)));
    const pages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
    auditPage = Math.min(auditPage, pages);
    const visible = rows.slice((auditPage - 1) * PAGE_SIZE, auditPage * PAGE_SIZE);
    $('#auditBody').innerHTML = visible.map(x => {
        let details = JSON.stringify(x.details || {});
        if (details.length > 160)
            details = details.slice(0, 157) + '…';
        return `<tr><td>${fmtTime(x.created_at)}</td><td><span class="tag">${esc(statusLabel(x.action))}</span></td><td>${esc(x.entity_type)}</td><td><code>${esc(x.entity_id || '—')}</code></td><td>${esc(auditNames[x.performed_by] || 'Public / system')}</td><td><small>${esc(details)}</small></td></tr>`;
    }).join('') || '<tr><td colspan="6">No audit records match this filter.</td></tr>';
    renderPager('#auditPagination', auditPage, pages, rows.length, p => {
        auditPage = p;
        renderAudit();
    });
}
export { loadAudit };
export function init() {
    $('#auditSearch')?.addEventListener('input', () => {
        auditPage = 1;
        renderAudit();
    });
    $('#auditEntityFilter')?.addEventListener('change', () => {
        auditPage = 1;
        renderAudit();
    });
}
