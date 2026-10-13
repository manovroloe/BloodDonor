/** pages/management/facilities: extracted from the working v22 flows. No build step is required. */
import { $, $$, esc, loading, toast } from '../../core/dom.js';
import { sb } from '../../core/client.js';
import { confirmAction } from '../../components/feedback.js';
import { mapUrl } from '../map.js';
import { managementProfile } from '../../components/navigation.js';
let facilityRows = [], adminFacilityUnits = [];
const BLOOD_TYPES = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
function renderAdminFacilityStock() {
    const body = $('#adminFacilityStockBody');
    if (!body)
        return;
    const active = facilityRows.filter(x => x.active), counts = {};
    for (const u of adminFacilityUnits) {
        if (u.status !== 'available')
            continue;
        const key = u.facility_id || 'unassigned';
        counts[key] ??= {};
        counts[key][u.blood_type] = (counts[key][u.blood_type] || 0) + 1;
    }
    const rows = [];
    const unassigned = counts.unassigned || {};
    if (Object.values(unassigned).some(Boolean))
        rows.push(`<tr><td><b>Unassigned stock</b></td><td>—</td><td>${BLOOD_TYPES.filter(t => unassigned[t]).map(t => `<span class="pill">${esc(t)} ${unassigned[t]}</span>`).join(' ')}</td></tr>`);
    for (const f of active) {
        const c = counts[f.id] || {};
        rows.push(`<tr><td>${esc(f.name)}</td><td>${esc(f.district || f.municipality || 'Not specified')}</td><td>${BLOOD_TYPES.filter(t => c[t]).map(t => `<span class="pill">${esc(t)} ${c[t]}</span>`).join(' ') || '<span class="muted-text">No available stock assigned</span>'}</td></tr>`);
    }
    body.innerHTML = rows.join('') || '<tr><td colspan="3">No facility stock records yet.</td></tr>';
    const source = $('#adminStockSource'), dest = $('#adminStockDestination');
    if (!source || !dest)
        return;
    const keepSource = source.value, keepDest = dest.value;
    const opts = active.map(f => `<option value="${f.id}">${esc(f.name)} — ${esc(f.district || f.municipality || 'Area not specified')}</option>`).join('');
    source.innerHTML = '<option value="">Unassigned stock</option>' + opts;
    dest.innerHTML = '<option value="">Select destination facility</option>' + opts;
    if ([...source.options].some(o => o.value === keepSource))
        source.value = keepSource;
    if ([...dest.options].some(o => o.value === keepDest))
        dest.value = keepDest;
    updateAdminStockHint();
}
function updateAdminStockHint() {
    const source = $('#adminStockSource'), dest = $('#adminStockDestination'), type = $('#adminStockBloodType'), hint = $('#adminStockAssignHint'), qty = $('#adminStockQuantity');
    if (!hint)
        return;
    const from = source?.value || null, to = dest?.value || '', blood = type?.value || '';
    if (!blood) {
        hint.textContent = 'Choose a blood type to see available source stock.';
        return;
    }
    const available = adminFacilityUnits.filter(u => u.status === 'available' && u.blood_type === blood && ((from && u.facility_id === from) || (!from && !u.facility_id))).length;
    if (qty)
        qty.max = String(Math.max(1, available));
    const sourceName = from ? (facilityRows.find(f => f.id === from)?.name || 'selected facility') : 'Unassigned stock';
    const destName = to ? (facilityRows.find(f => f.id === to)?.name || 'selected facility') : 'no destination selected';
    hint.className = 'stock-notice ' + (available > 0 && to && from !== to ? 'stock-ok' : '');
    hint.textContent = `${sourceName}: ${available} available ${blood} unit(s). Destination: ${destName}.`;
}
async function loadFacilities() {
    const [f, u] = await Promise.all([sb.from('facilities').select('*').order('name'), sb.from('blood_units').select('id,blood_type,status,facility_id,expiry_date').eq('status', 'available')]);
    if (f.error)
        return toast(f.error.message, 'err');
    if (u.error)
        return toast(u.error.message, 'err');
    facilityRows = f.data || [];
    adminFacilityUnits = u.data || [];
    $('#facilityAdminBody').innerHTML = facilityRows.map(x => `<tr><td><b>${esc(x.name)}</b></td><td>${x.is_main_branch ? '<span class="tag main-branch-tag">Main Branch</span>' : '<span class="muted-text">Partner Branch</span>'}</td><td>${esc(x.facility_type)}</td><td>${esc(x.district || x.municipality || '—')}</td><td>${esc([x.barangay, x.municipality, x.province].filter(Boolean).join(', ') || x.address)}</td><td>${esc(x.operating_hours || '—')}</td><td><span class="status ${x.active ? 'eligible' : 'inactive'}">${x.active ? 'Visible' : 'Hidden'}</span></td><td><div class="action-stack horizontal"><a class="small-btn link-btn" href="admin.html?facility_id=${encodeURIComponent(x.id)}">View Dashboard</a><button class="small-btn" data-assign-f="${x.id}" ${x.active ? '' : 'disabled'}>Assign Stock</button><button class="small-btn" data-edit-f="${x.id}">Edit</button><button class="small-btn danger" data-del-f="${x.id}" ${x.is_main_branch ? 'disabled title="Choose another main branch before deleting"' : ''}>Delete</button></div></td></tr>`).join('') || '<tr><td colspan="8">No facilities.</td></tr>';
    $$('[data-edit-f]').forEach(b => b.onclick = () => editFacility(b.dataset.editF));
    $$('[data-assign-f]').forEach(b => b.onclick = () => {
        const d = $('#adminStockDestination');
        if (d)
            d.value = b.dataset.assignF;
        updateAdminStockHint();
        $('#adminStockAssignForm')?.scrollIntoView({
            behavior: 'smooth', block: 'center'
        });
    });
    $$('[data-del-f]').forEach(b => b.onclick = async () => {
        if (b.disabled)
            return;
        if (!(await confirmAction('Delete Facility', 'This facility will be permanently removed from the system. Existing blood units will become unassigned.', 'Delete Facility')))
            return;
        const { error } = await sb.from('facilities').delete().eq('id', b.dataset.delF);
        error ? toast(error.message, 'err') : loadFacilities();
    });
    renderAdminFacilityStock();
}
function editFacility(id) {
    const x = facilityRows.find(v => v.id === id), f = $('#facilityForm');
    if (!x || !f)
        return;
    for (const k of ['id', 'name', 'facility_type', 'phone', 'address', 'barangay', 'municipality', 'province', 'district', 'operating_hours', 'latitude', 'longitude', 'services'])
        if (f.elements[k])
            f.elements[k].value = x[k] ?? '';
    f.elements.active.checked = x.active;
    if (f.elements.is_main_branch)
        f.elements.is_main_branch.checked = !!x.is_main_branch;
    const u = mapUrl(x.latitude, x.longitude);
    if (u)
        $('#adminFacilityMap').src = u;
    f.scrollIntoView({
        behavior: 'smooth'
    });
}
export { loadFacilities };
export function init() {
    $('#facilityForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const f = e.target, fd = new FormData(f), id = fd.get('id'), isMain = !!f.elements.is_main_branch?.checked;
        if (isMain && !f.elements.active.checked)
            return toast('The main branch must remain active and visible.', 'err');
        const payload = {
            name: fd.get('name'), facility_type: fd.get('facility_type'), phone: fd.get('phone') || null, address: fd.get('address'), barangay: fd.get('barangay') || null, municipality: fd.get('municipality') || null, province: fd.get('province') || null, district: fd.get('district') || null, operating_hours: fd.get('operating_hours') || null, latitude: fd.get('latitude') || null, longitude: fd.get('longitude') || null, services: fd.get('services') || null, is_main_branch: isMain, active: f.elements.active.checked, updated_at: new Date().toISOString()
        };
        const q = id ? sb.from('facilities').update(payload).eq('id', id) : sb.from('facilities').insert({
            ...payload, created_by: managementProfile.id
        });
        const { error } = await q;
        if (error)
            return toast(error.message, 'err');
        f.reset();
        f.elements.id.value = '';
        f.elements.active.checked = true;
        if (f.elements.is_main_branch)
            f.elements.is_main_branch.checked = false;
        toast('Facility saved.');
        loadFacilities();
    });
    $('#adminStockSource')?.addEventListener('change', updateAdminStockHint);
    $('#adminStockDestination')?.addEventListener('change', updateAdminStockHint);
    $('#adminStockBloodType')?.addEventListener('change', updateAdminStockHint);
    $('#adminStockQuantity')?.addEventListener('input', updateAdminStockHint);
    $('#adminStockAssignForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const fd = new FormData(e.target), from = String(fd.get('from_facility_id') || ''), to = String(fd.get('to_facility_id') || ''), blood = String(fd.get('blood_type') || ''), quantity = Number(fd.get('quantity') || 0);
        if (!to || !blood || quantity < 1)
            return toast('Choose source stock, blood type, quantity, and destination facility.', 'err');
        if (from && from === to)
            return toast('Source and destination facilities must be different.', 'err');
        const btn = e.submitter;
        loading(btn, true);
        const { data, error } = await sb.rpc('admin_move_blood_stock', {
            p_blood_type: blood, p_quantity: quantity, p_to_facility: to, p_from_facility: from || null
        });
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        toast(`${data || quantity} blood unit(s) assigned successfully.`);
        e.target.elements.quantity.value = '1';
        await loadFacilities();
    });
}
