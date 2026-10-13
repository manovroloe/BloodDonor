/** pages/management/inventory: extracted from the working v22 flows. No build step is required. */
import { $, $$, esc, fmt, fmtTime, loading, statusClass, statusLabel, toast, today } from '../../core/dom.js';
import { sb } from '../../core/client.js';
import { query } from '../../core/routing.js';
import { managementProfile } from '../../components/navigation.js';
import { showReceipt } from '../../components/feedback.js';
async function lookupDonationDonor() {
    const code = $('#donationDonorCode')?.value.trim();
    if (!code || !sb)
        return;
    const { data } = await sb.from('donors').select('id,donor_code,blood_type,status,first_name,last_name').eq('donor_code', code.toUpperCase()).maybeSingle();
    $('#donationBloodType').value = data ? `${data.blood_type} — ${data.first_name} ${data.last_name} (${statusLabel(data.status)})` : 'Donor not found';
}
const donationDate = $('#donationDate'), donationExpiry = $('#donationExpiry');
async function loadDonationAppointments() {
    const sel = $('#donationAppointment');
    if (!sel)
        return;
    const { data } = await sb.from('appointments').select('id,appointment_code,full_name,appointment_date,donors(donor_code)').in('status', ['confirmed', 'checked_in']).order('appointment_date');
    sel.innerHTML = '<option value="">Not linked to an appointment</option>' + (data || []).map(x => `<option value="${x.id}">${esc(x.appointment_code)} — ${esc(x.full_name)} — ${fmt(x.appointment_date)}</option>`).join('');
    const appt = query.get('appointment'), donor = query.get('donor');
    if (appt)
        sel.value = appt;
    if (donor) {
        $('#donationDonorCode').value = donor;
        lookupDonationDonor();
    }
}
let managementFacilities = [];
async function loadManagementFacilities() {
    let data = [];
    if (managementProfile?.role === 'admin') {
        const r = await sb.from('facilities').select('id,name,district,municipality,active,is_main_branch').eq('active', true).order('name');
        data = r.data || [];
    }
    else {
        const r = await sb.rpc('my_staff_facilities');
        data = (r.data || []).map(x => ({
            id: x.facility_id, name: x.name, district: x.district, municipality: x.municipality, active: true, is_main_branch: x.is_main_branch, is_primary: x.is_primary
        }));
    }
    managementFacilities = data || [];
    const options = managementFacilities.map(x => `<option value="${x.id}">${x.is_main_branch ? '★ ' : ''}${esc(x.name)} — ${esc(x.district || x.municipality || 'District not specified')}</option>`).join('');
    const sel = $('#donationFacility');
    if (sel) {
        sel.innerHTML = '<option value="">Select assigned facility</option>' + options;
        const primary = managementFacilities.find(x => x.is_primary) || managementFacilities[0];
        if (primary && managementProfile?.role !== 'admin')
            sel.value = primary.id;
    }
    const adjust = $('#adjustFacility');
    if (adjust) {
        adjust.innerHTML = '<option value="">Select assigned facility</option>' + options;
        const primary = managementFacilities.find(x => x.is_primary) || managementFacilities[0];
        if (primary)
            adjust.value = primary.id;
    }
}
async function chooseUnitFacility(unitId) {
    if (!managementFacilities.length)
        await loadManagementFacilities();
    return new Promise(resolve => {
        const wrap = document.createElement('div');
        wrap.className = 'modal-backdrop bc-confirm';
        wrap.innerHTML = `<div class="modal-card confirm-card"><h2>Assign Blood Unit Facility</h2><div class="form-group"><label>Partner Facility</label><select data-facility><option value="">Select facility</option>${managementFacilities.map(x => `<option value="${x.id}">${esc(x.name)} — ${esc(x.district || x.municipality || '')}</option>`).join('')}</select></div><div class="modal-action-row"><button class="secondary-btn" type="button" data-no>Cancel</button><button class="primary-btn" type="button" data-yes>Assign</button></div></div>`;
        document.body.append(wrap);
        const done = v => {
            wrap.remove();
            resolve(v);
        };
        wrap.querySelector('[data-no]').onclick = () => done(null);
        wrap.querySelector('[data-yes]').onclick = () => done(wrap.querySelector('[data-facility]').value || null);
    });
}
function facilityAvailableCount(facilityId, bloodType) {
    return (window._unitRows || []).filter(x => x.status === 'available' && x.facility_id === facilityId && x.blood_type === bloodType && (!x.expiry_date || x.expiry_date >= today())).length;
}
function syncInventoryAdjustment() {
    const f = $('#inventoryAdjustForm'), facility = $('#adjustFacility');
    if (!f || !facility)
        return;
    const type = f.elements.blood_type.value, current = facilityAvailableCount(facility.value, type);
    $('#adjustCurrent').value = String(current);
    f.elements.new_quantity.value = String(current);
}
async function loadInventory() {
    await sb.rpc('refresh_expired_units');
    const [reorders, units, moves] = await Promise.all([sb.from('blood_inventory').select('blood_type,reorder_level,updated_at').order('blood_type'), sb.from('blood_units').select('*,facilities(id,name,district,municipality)').order('created_at', {
            ascending: false
        }).limit(1000), sb.from('inventory_transactions').select('*').order('created_at', {
            ascending: false
        }).limit(120)]);
    const allUnits = units.data || [], available = allUnits.filter(x => x.status === 'available' && (!x.expiry_date || x.expiry_date >= today())), counts = {};
    available.forEach(x => counts[x.blood_type] = (counts[x.blood_type] || 0) + 1);
    const rows = (reorders.data || []).map(x => ({
        ...x, bags_available: counts[x.blood_type] || 0
    })), reserved = {};
    allUnits.filter(x => x.status === 'reserved').forEach(x => reserved[x.blood_type] = (reserved[x.blood_type] || 0) + 1);
    if ($('#inventoryCards'))
        $('#inventoryCards').innerHTML = rows.map(x => `<div class="blood-chip ${x.bags_available <= x.reorder_level ? 'low-stock' : ''}"><b>${esc(x.blood_type)}</b><span>${x.bags_available} available${reserved[x.blood_type] ? ` • ${reserved[x.blood_type]} reserved` : ''}</span></div>`).join('');
    if ($('#inventoryBody'))
        $('#inventoryBody').innerHTML = rows.map(x => `<tr><td><span class="pill">${esc(x.blood_type)}</span></td><td>${x.bags_available}</td><td>${x.reorder_level}</td><td>${fmtTime(x.updated_at)}</td><td><button class="small-btn" data-stock="${esc(x.blood_type)}">Adjust Branch Stock</button></td></tr>`).join('');
    window._unitRows = allUnits;
    $$('[data-stock]').forEach(b => b.onclick = () => {
        const m = $('#inventoryAdjustModal'), f = $('#inventoryAdjustForm');
        if (!m || !f)
            return;
        f.elements.blood_type.value = b.dataset.stock;
        f.elements.reason.value = '';
        $('#adjustBloodType').value = b.dataset.stock;
        const primary = managementFacilities.find(x => x.is_primary) || managementFacilities[0];
        if (primary && $('#adjustFacility'))
            $('#adjustFacility').value = primary.id;
        syncInventoryAdjustment();
        m.hidden = false;
    });
    renderUnits();
    if ($('#facilityStockBody')) {
        const types = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
        const facilitySets = await Promise.all(types.map(t => sb.rpc('public_facility_inventory', {
            p_blood_type: t
        })));
        let stockRows = facilitySets.flatMap((r, i) => (r.data || []).map(x => ({
            ...x, blood_type: types[i]
        })));
        if (managementProfile?.role !== 'admin') {
            const allowed = new Set(managementFacilities.map(x => x.id));
            stockRows = stockRows.filter(x => allowed.has(x.facility_id));
        }
        $('#facilityStockBody').innerHTML = stockRows.map(x => `<tr><td>${esc(x.facility_name)}</td><td>${esc(x.district || x.municipality || '—')}</td><td><span class="pill">${esc(x.blood_type)}</span></td><td>${x.bags_available}</td></tr>`).join('') || '<tr><td colspan="4">No stock is assigned to your facilities yet.</td></tr>';
    }
    if ($('#movementBody'))
        $('#movementBody').innerHTML = (moves.data || []).map(x => `<tr><td>${fmtTime(x.created_at)}</td><td>${esc(statusLabel(x.transaction_type))}<br><small>${esc(x.blood_type)}</small></td><td class="${x.quantity_change > 0 ? 'positive' : x.quantity_change < 0 ? 'negative' : ''}">${x.quantity_change > 0 ? '+' : ''}${x.quantity_change}</td><td>${x.balance_after}</td><td>${esc(x.reason || '—')}</td></tr>`).join('') || '<tr><td colspan="5">No inventory history for your assigned facility.</td></tr>';
}
function renderUnits() {
    const st = $('#unitStatusFilter')?.value || '', term = today();
    const rows = (window._unitRows || []).filter(x => !st || x.status === st);
    if ($('#unitBody'))
        $('#unitBody').innerHTML = rows.map(x => `<tr class="${x.status === 'available' && x.expiry_date && x.expiry_date <= term ? 'unit-expiry-warning' : ''}"><td>${esc(x.unit_code)}</td><td><span class="pill">${esc(x.blood_type)}</span></td><td>${fmt(x.collection_date)}</td><td>${fmt(x.expiry_date)}</td><td>${esc(x.facilities?.name || 'Unassigned')}${x.facilities?.district ? `<br><small>${esc(x.facilities.district)}</small>` : ''}</td><td><span class="status ${statusClass(x.status)}">${esc(statusLabel(x.status))}</span>${x.request_id && x.status === 'reserved' ? '<br><small>Reserved for request</small>' : ''}</td><td>${x.status === 'available' ? `<button class="small-btn" data-unit-facility="${x.id}">${x.facility_id ? 'Change' : 'Assign'}</button>` : '—'}</td></tr>`).join('') || '<tr><td colspan="7">No blood units match this filter.</td></tr>';
    $$('[data-unit-facility]').forEach(b => b.onclick = async () => {
        const facilityId = await chooseUnitFacility(b.dataset.unitFacility);
        if (!facilityId)
            return;
        const { error } = await sb.rpc('set_blood_unit_facility', {
            p_unit_id: b.dataset.unitFacility, p_facility_id: facilityId
        });
        error ? toast(error.message, 'err') : (toast('Blood unit facility updated.'), loadInventory());
    });
}
export { loadDonationAppointments, loadInventory, loadManagementFacilities };
export function init() {
    $('#donationDonorCode')?.addEventListener('blur', lookupDonationDonor);
    if (donationDate) {
        donationDate.max = today();
        if (!donationDate.value)
            donationDate.value = today();
        donationDate.addEventListener('change', () => {
            if (donationExpiry) {
                donationExpiry.min = donationDate.value || '';
                if (donationExpiry.value && donationExpiry.value < donationDate.value)
                    donationExpiry.value = '';
            }
        });
    }
    if (donationExpiry && donationDate?.value)
        donationExpiry.min = donationDate.value;
    $('#donationStaffForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const f = Object.fromEntries(new FormData(e.target)), btn = e.submitter;
        loading(btn, true);
        const { data, error } = await sb.rpc('record_donation_v3', {
            p_donor_code: f.donor_code, p_bags: Number(f.bags), p_donation_date: f.donation_date, p_facility_id: f.facility_id, p_appointment_id: f.appointment_id || null, p_expiry_date: f.expiry_date || null
        });
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        e.target.reset();
        $('#donationBloodType').value = '';
        showReceipt($('#donationReceipt'), 'Donation recorded', data, 'Inventory and blood-unit records were updated automatically.', false);
        loadInventory();
        loadDonationAppointments();
    });
    $('#adjustFacility')?.addEventListener('change', syncInventoryAdjustment);
    $('#inventoryAdjustForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const f = Object.fromEntries(new FormData(e.target)), v = Number(f.new_quantity), btn = e.submitter;
        if (!f.facility_id)
            return toast('Select an assigned facility.', 'err');
        if (!Number.isInteger(v) || v < 0)
            return toast('Enter a valid whole number.', 'err');
        loading(btn, true);
        const { error } = await sb.rpc('adjust_facility_inventory', {
            p_facility_id: f.facility_id, p_blood_type: f.blood_type, p_new_quantity: v, p_reason: f.reason
        });
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        $('#inventoryAdjustModal').hidden = true;
        toast('Facility inventory adjusted and logged.');
        loadInventory();
    });
    $('#unitStatusFilter')?.addEventListener('change', renderUnits);
}
