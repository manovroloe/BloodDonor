/** pages/management/requests: extracted from the working v22 flows. No build step is required. */
import { sb } from '../../core/client.js';
import { query } from '../../core/routing.js';
import { $, $$, PAGE_SIZE, esc, fmt, fmtTime, statusClass, statusLabel, toast } from '../../core/dom.js';
import { confirmAction, promptAction, renderPager } from '../../components/feedback.js';
let requestRows = [], requestInventory = {}, requestReserved = {}, requestPage = 1;
async function loadRequests() {
    await sb.rpc('refresh_expired_units');
    const [r, u] = await Promise.all([sb.from('blood_requests').select('*,facilities(name,district,municipality)').order('created_at', {
            ascending: false
        }), sb.from('blood_units').select('request_id,blood_type,facility_id,status').in('status', ['available', 'reserved'])]);
    requestRows = r.data || [];
    requestInventory = {};
    requestReserved = {};
    (u.data || []).forEach(x => {
        if (x.status === 'available') {
            const k = (x.facility_id || 'all') + '|' + x.blood_type;
            requestInventory[k] = (requestInventory[k] || 0) + 1;
        }
        if (x.status === 'reserved' && x.request_id)
            requestReserved[x.request_id] = (requestReserved[x.request_id] || 0) + 1;
    });
    const preset = query.get('status');
    if (preset && $('#requestStatusFilter'))
        $('#requestStatusFilter').value = preset;
    renderRequests();
}
function requestAvailableFor(x) {
    return requestInventory[(x.facility_id || 'all') + '|' + x.blood_type] || 0;
}
function renderRequests() {
    const q = ($('#requestSearch')?.value || '').toLowerCase(), st = $('#requestStatusFilter')?.value || '';
    const rows = requestRows.filter(x => (!st || x.status === st) && (!q || [x.request_code, x.patient_name, x.requester_name, x.hospital, x.blood_type, x.facilities?.name, x.relationship].join(' ').toLowerCase().includes(q)));
    const pages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
    requestPage = Math.min(requestPage, pages);
    const visible = rows.slice((requestPage - 1) * PAGE_SIZE, requestPage * PAGE_SIZE);
    $('#staffRequestBody').innerHTML = visible.map(x => `<tr><td><b>${esc(x.request_code)}</b><br><small>${fmtTime(x.created_at)}</small></td><td>${esc(x.patient_name)}<br><small>${esc(x.requester_name)}</small></td><td><span class="pill">${esc(x.blood_type)}</span><br><small>${requestReserved[x.id] || 0} reserved • ${requestAvailableFor(x)} available</small></td><td>${x.bags} bag(s)<br><small>${fmt(x.date_needed)}</small></td><td>${esc(x.hospital)}<br><small>${esc(x.facilities?.name || 'Facility not assigned')}${x.facilities?.district ? ' • ' + esc(x.facilities.district) : ''}<br>${esc(x.request_for === 'self' ? 'For self' : ('For ' + (x.relationship || 'another person')))}${x.pickup_date ? '<br>Pickup: ' + fmt(x.pickup_date) + (x.pickup_time ? ' ' + esc(String(x.pickup_time).slice(0, 5)) : '') : ''}</small></td><td><span class="status ${statusClass(x.status)}">${esc(statusLabel(x.status))}</span></td><td><div class="action-stack">${x.status !== 'completed' ? `<select data-request-status="${x.id}">${['pending', 'under_review', 'approved', 'ready_for_release', 'rejected', 'cancelled'].map(s => `<option value="${s}" ${s === x.status ? 'selected' : ''}>${statusLabel(s)}</option>`).join('')}</select>` : ''}${['approved', 'ready_for_release'].includes(x.status) ? `<button class="small-btn" data-release="${x.id}">Release Blood</button>` : ''}</div></td></tr>`).join('') || '<tr><td colspan="7">No requests match this filter.</td></tr>';
    $$('[data-request-status]').forEach(sel => sel.onchange = async () => {
        const current = requestRows.find(x => x.id === sel.dataset.requestStatus), notes = await promptAction('Update Request Status', 'Staff note (optional)', current?.staff_notes || '', 'Update Status');
        if (notes === null) {
            sel.value = current.status;
            return;
        }
        const { error } = await sb.rpc('update_request_status', {
            p_request_id: sel.dataset.requestStatus, p_status: sel.value, p_notes: notes || null
        });
        error ? toast(error.message, 'err') : (toast(['approved', 'ready_for_release'].includes(sel.value) ? 'Request updated and blood units reserved.' : 'Request status updated.'), loadRequests());
    });
    $$('[data-release]').forEach(b => b.onclick = async () => {
        if (!(await confirmAction('Release Blood', 'Release the reserved blood now and complete this request? This action completes the request.', 'Release Blood')))
            return;
        const notes = await promptAction('Release Notes', 'Release note (optional)', '', 'Release Blood');
        if (notes === null)
            return;
        const { data, error } = await sb.rpc('release_blood_request', {
            p_request_id: b.dataset.release, p_notes: notes || null
        });
        error ? toast(error.message, 'err') : (toast(`Blood released successfully (${data}).`), loadRequests());
    });
    renderPager('#requestPagination', requestPage, pages, rows.length, p => {
        requestPage = p;
        renderRequests();
    });
}
export { loadRequests };
export function init() {
    $('#requestSearch')?.addEventListener('input', () => {
        requestPage = 1;
        renderRequests();
    });
    $('#requestStatusFilter')?.addEventListener('change', () => {
        requestPage = 1;
        renderRequests();
    });
}
