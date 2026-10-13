/** pages/management/staff: extracted from the working v22 flows. No build step is required. */
import { apiRequest, sb } from '../../core/client.js';
import { $, $$, esc, fmt, loading, toast } from '../../core/dom.js';
async function setStaffPassword(id, name) {
    if (!apiRequest)
        return toast('BloodCare API is unavailable.', 'err');
    const wrap = document.createElement('div');
    wrap.className = 'modal-backdrop bc-confirm';
    wrap.innerHTML = `<form class="modal-card confirm-card" data-staff-password-form><h2>Set Password</h2><p class="muted-text">Set a new login password for <b>${esc(name || 'this staff account')}</b>. The password is saved only in Supabase Authentication.</p><div class="form-group"><label>New Password</label><input name="password" type="password" minlength="8" autocomplete="new-password" required placeholder="At least 8 characters"></div><div class="form-group"><label>Confirm Password</label><input name="confirm_password" type="password" minlength="8" autocomplete="new-password" required placeholder="Repeat password"></div><div class="modal-action-row"><button type="button" class="secondary-btn" data-no>Cancel</button><button type="submit" class="primary-btn">Update Password</button></div></form>`;
    document.body.append(wrap);
    const form = wrap.querySelector('[data-staff-password-form]');
    wrap.querySelector('[data-no]').onclick = () => wrap.remove();
    wrap.addEventListener('click', e => {
        if (e.target === wrap)
            wrap.remove();
    });
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const f = Object.fromEntries(new FormData(form));
        if (f.password !== f.confirm_password)
            return toast('Password and confirmation do not match.', 'err');
        const btn = e.submitter;
        loading(btn, true);
        const { error } = await apiRequest(`/api/admin/staff/${encodeURIComponent(id)}/password`, 'POST', f);
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        toast('Staff password updated.');
        wrap.remove();
    });
    form.elements.password.focus();
}
let staffFacilityRows = [], staffAssignmentRows = [];
function staffAssignmentsFor(id) {
    return staffAssignmentRows.filter(x => x.staff_id === id);
}
async function manageStaffFacilities(id, name) {
    if (!staffFacilityRows.length)
        return toast('Create an active facility first.', 'err');
    const current = staffAssignmentsFor(id), selected = new Set(current.map(x => x.facility_id)), primary = current.find(x => x.is_primary)?.facility_id || current[0]?.facility_id || staffFacilityRows.find(x => x.is_main_branch)?.id || staffFacilityRows[0].id;
    const wrap = document.createElement('div');
    wrap.className = 'modal-backdrop bc-confirm';
    wrap.innerHTML = `<form class="modal-card staff-facility-modal" data-staff-facility-form><h2>Manage Facilities</h2><p class="muted-text">Choose which branches <b>${esc(name || 'this staff account')}</b> can manage. One branch must be primary.</p><div class="staff-facility-choice-list">${staffFacilityRows.map(f => `<label class="staff-facility-choice"><input type="checkbox" name="facility_ids" value="${f.id}" ${selected.has(f.id) ? 'checked' : ''}><span><b>${f.is_main_branch ? '★ ' : ''}${esc(f.name)}</b><small>${esc(f.district || f.municipality || 'Area not specified')}</small></span><input type="radio" name="primary_facility" value="${f.id}" ${primary === f.id ? 'checked' : ''} aria-label="Set ${esc(f.name)} as primary"><em>Primary</em></label>`).join('')}</div><div class="modal-action-row"><button type="button" class="secondary-btn" data-no>Cancel</button><button type="submit" class="primary-btn">Save Facility Access</button></div></form>`;
    document.body.append(wrap);
    const form = wrap.querySelector('[data-staff-facility-form]');
    const sync = () => {
        const checked = new Set([...form.querySelectorAll('input[name="facility_ids"]:checked')].map(x => x.value));
        form.querySelectorAll('input[name="primary_facility"]').forEach(r => {
            r.disabled = !checked.has(r.value);
            if (r.checked && !checked.has(r.value))
                r.checked = false;
        });
        if (!form.querySelector('input[name="primary_facility"]:checked')) {
            const first = form.querySelector('input[name="facility_ids"]:checked');
            if (first)
                form.querySelector(`input[name="primary_facility"][value="${first.value}"]`).checked = true;
        }
    };
    form.querySelectorAll('input[name="facility_ids"]').forEach(x => x.addEventListener('change', sync));
    sync();
    wrap.querySelector('[data-no]').onclick = () => wrap.remove();
    wrap.addEventListener('click', e => {
        if (e.target === wrap)
            wrap.remove();
    });
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const ids = [...form.querySelectorAll('input[name="facility_ids"]:checked')].map(x => x.value), primaryId = form.querySelector('input[name="primary_facility"]:checked')?.value;
        if (!ids.length || !primaryId)
            return toast('Assign at least one facility and choose a primary branch.', 'err');
        const btn = e.submitter;
        loading(btn, true);
        const { error } = await sb.rpc('admin_set_staff_facilities', {
            p_staff_id: id, p_facility_ids: ids, p_primary_facility: primaryId
        });
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        toast('Staff facility access updated.');
        wrap.remove();
        loadStaffAccounts();
    });
}
async function loadStaffAccounts() {
    const [staff, facilities, assignments] = await Promise.all([sb.from('staff_profiles').select('*').order('created_at'), sb.from('facilities').select('id,name,district,municipality,is_main_branch,active').eq('active', true).order('name'), sb.from('staff_facility_assignments').select('*')]);
    if (staff.error)
        return toast(staff.error.message, 'err');
    if (facilities.error)
        return toast(facilities.error.message, 'err');
    if (assignments.error)
        return toast(assignments.error.message, 'err');
    staffFacilityRows = facilities.data || [];
    staffAssignmentRows = assignments.data || [];
    const primarySel = $('#staffPrimaryFacility');
    if (primarySel) {
        const main = staffFacilityRows.find(x => x.is_main_branch);
        primarySel.innerHTML = '<option value="">Select primary facility</option>' + staffFacilityRows.map(x => `<option value="${x.id}">${x.is_main_branch ? '★ ' : ''}${esc(x.name)} — ${esc(x.district || x.municipality || 'Area not specified')}</option>`).join('');
        if (main)
            primarySel.value = main.id;
    }
    $('#staffAccountsBody').innerHTML = (staff.data || []).map(x => {
        const assigned = staffAssignmentsFor(x.id), primary = assigned.find(a => a.is_primary), names = assigned.map(a => {
            const f = staffFacilityRows.find(v => v.id === a.facility_id);
            return f ? `${a.is_primary ? '★ ' : ''}${f.name}` : 'Unknown facility';
        });
        return `<tr><td>${esc(x.full_name)}</td><td>${esc(x.email || 'Not stored')}</td><td><select data-staff-role="${x.id}"><option value="staff" ${x.role === 'staff' ? 'selected' : ''}>Staff</option><option value="admin" ${x.role === 'admin' ? 'selected' : ''}>Administrator</option></select></td><td><div class="staff-assignment-cell">${names.length ? names.map(n => `<span class="tag">${esc(n)}</span>`).join(' ') : '<span class="muted-text">No facility assigned</span>'}<button class="small-btn" data-staff-facilities="${x.id}" data-staff-name="${esc(x.full_name)}">Manage Facilities</button></div></td><td><label class="inline-toggle"><input type="checkbox" data-staff-active="${x.id}" ${x.active ? 'checked' : ''}> ${x.active ? 'Active' : 'Disabled'}</label></td><td>${fmt(x.created_at)}</td><td><div class="action-stack horizontal"><button class="small-btn" data-staff-save="${x.id}">Save</button><button class="small-btn" data-staff-password="${x.id}" data-staff-name="${esc(x.full_name)}">Set Password</button></div></td></tr>`;
    }).join('') || '<tr><td colspan="7">No staff accounts.</td></tr>';
    $$('[data-staff-save]').forEach(b => b.onclick = async () => {
        const role = $(`[data-staff-role="${b.dataset.staffSave}"]`).value, active = $(`[data-staff-active="${b.dataset.staffSave}"]`).checked;
        const { error } = await sb.rpc('admin_update_staff', {
            p_id: b.dataset.staffSave, p_role: role, p_active: active
        });
        error ? toast(error.message, 'err') : (toast('Staff account updated.'), loadStaffAccounts());
    });
    $$('[data-staff-password]').forEach(b => b.onclick = () => setStaffPassword(b.dataset.staffPassword, b.dataset.staffName));
    $$('[data-staff-facilities]').forEach(b => b.onclick = () => manageStaffFacilities(b.dataset.staffFacilities, b.dataset.staffName));
    if (apiRequest) {
        const cfg = await apiRequest('/api/admin/config');
        const notice = $('#staffAuthConfigNotice');
        if (notice) {
            const ready = !!cfg.data?.staff_auth_ready;
            notice.className = 'stock-notice ' + (ready ? 'stock-ok' : '');
            notice.textContent = ready ? 'Supabase administrator auth is configured. New staff can log in immediately after creation.' : 'Add SUPABASE_SERVICE_ROLE_KEY to the server .env before creating or resetting staff passwords.';
        }
    }
}
export { loadStaffAccounts };
export function init() {
    $('#linkStaffForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!apiRequest)
            return toast('BloodCare API is unavailable.', 'err');
        const f = Object.fromEntries(new FormData(e.target)), btn = e.submitter;
        if (f.password !== f.confirm_password)
            return toast('Password and confirmation do not match.', 'err');
        loading(btn, true);
        const { error } = await apiRequest('/api/admin/staff', 'POST', f);
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        e.target.reset();
        toast('Staff login created and authorized.');
        loadStaffAccounts();
    });
}
