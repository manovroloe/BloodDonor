/** pages/blood-request: extracted from the working v22 flows. No build step is required. */
import { $, esc, loading, normalizePhone, toast, today } from '../core/dom.js';
import { sb } from '../core/client.js';
import { query } from '../core/routing.js';
import { showReceipt } from '../components/feedback.js';
let requestFacilityStocks = {};
async function loadRequestFacilities() {
    const type = $('#requestBloodType')?.value, sel = $('#requestFacility'), submit = $('#requestSubmitBtn'), hint = $('#requestFacilityHint');
    if (!sel)
        return;
    if (!type || !sb) {
        sel.innerHTML = '<option value="">Select a blood type first</option>';
        if (submit)
            submit.disabled = true;
        return;
    }
    sel.innerHTML = '<option value="">Checking facility stock…</option>';
    if (submit)
        submit.disabled = true;
    const { data, error } = await sb.rpc('public_facility_inventory', {
        p_blood_type: type
    });
    if (error) {
        sel.innerHTML = '<option value="">Unable to load stock</option>';
        if (hint)
            hint.textContent = error.message;
        return;
    }
    requestFacilityStocks = Object.fromEntries((data || []).map(x => [x.facility_id, x]));
    sel.innerHTML = '<option value="">Select a facility with stock</option>' + (data || []).map(x => `<option value="${x.facility_id}">${esc(x.facility_name)} — ${x.bags_available} bag${x.bags_available === 1 ? '' : 's'} • ${esc(x.district || x.municipality || 'District not specified')}</option>`).join('');
    const wanted = query.get('facility_id');
    if (wanted && requestFacilityStocks[wanted])
        sel.value = wanted;
    if (hint)
        hint.textContent = (data || []).length ? 'Only facilities with available stock are listed.' : 'No partner facility currently has this blood type available.';
    validateRequestStock();
}
function validateRequestStock() {
    const sel = $('#requestFacility'), bags = Number($('#requestBags')?.value || 0), submit = $('#requestSubmitBtn'), notice = $('#requestStockNotice'), stock = requestFacilityStocks[sel?.value];
    const ok = !!stock && bags > 0 && bags <= Number(stock.bags_available || 0);
    if (submit)
        submit.disabled = !ok;
    if (notice) {
        notice.className = 'stock-notice ' + (ok ? 'stock-ok' : '');
        notice.textContent = stock ? (ok ? `${stock.facility_name} currently shows ${stock.bags_available} available bag(s). You may submit this request.` : `Only ${stock.bags_available} bag(s) are currently available at ${stock.facility_name}.`) : 'Choose a blood type and partner facility with available stock.';
    }
    return ok;
}
function syncRequestFor() {
    const f = $('#requestForm');
    if (!f)
        return;
    const self = f.elements.request_for.value === 'self', wrap = $('#relationshipWrap'), rel = $('#requestRelationship');
    if (wrap)
        wrap.hidden = self;
    if (rel) {
        rel.required = !self;
        if (self)
            rel.value = 'Self';
        else if (rel.value === 'Self')
            rel.value = '';
    }
    if (self && f.elements.requester_name.value)
        f.elements.patient_name.value = f.elements.requester_name.value;
}
export { loadRequestFacilities, syncRequestFor };
export function init() {
    $('#requestBloodType')?.addEventListener('change', loadRequestFacilities);
    $('#requestFacility')?.addEventListener('change', validateRequestStock);
    $('#requestBags')?.addEventListener('input', validateRequestStock);
    $('#requestFor')?.addEventListener('change', syncRequestFor);
    $('#requestForm')?.elements?.requester_name?.addEventListener('input', () => {
        if ($('#requestFor')?.value === 'self')
            $('#requestPatientName').value = $('#requestForm').elements.requester_name.value;
    });
    $('#scheduleBloodRequest')?.addEventListener('change', e => {
        const on = e.target.checked;
        $('#pickupScheduleFields').hidden = !on;
        $('#pickupDate').required = on;
        $('#pickupTime').required = on;
    });
    $('#requestForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!sb)
            return toast('BloodCare API is unavailable.', 'err');
        if (!validateRequestStock())
            return toast('Choose a facility with enough available stock.', 'err');
        const btn = e.submitter;
        const data = Object.fromEntries(new FormData(e.target));
        data.email = String(data.email || '').trim().toLowerCase();
        data.phone = normalizePhone(data.phone);
        if (data.request_for === 'self')
            data.relationship = 'Self';
        if (!$('#scheduleBloodRequest')?.checked) {
            data.pickup_date = '';
            data.pickup_time = '';
        }
        if (data.date_needed < today())
            return toast('Date needed cannot be in the past.', 'err');
        loading(btn, true);
        const { data: code, error } = await sb.rpc('submit_blood_request', {
            p_data: data
        });
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        e.target.reset();
        requestFacilityStocks = {};
        $('#requestFacility').innerHTML = '<option value="">Select a blood type first</option>';
        $('#requestSubmitBtn').disabled = true;
        $('#pickupScheduleFields').hidden = true;
        syncRequestFor();
        showReceipt($('#requestReceipt'), 'Blood request received', code, 'Save this request number. Staff will review the request and the selected facility stock before release.');
    });
}
