/** pages/management/admin-dashboard: extracted from the working v22 flows. No build step is required. */
import { sb } from '../../core/client.js';
import { $, esc, fmtTime, loading, statusLabel, toast } from '../../core/dom.js';
import { query } from '../../core/routing.js';
import { managementProfile } from '../../components/navigation.js';
let adminInventoryChart = null, adminRequestChart = null;
async function loadAdminDashboard() {
    await sb.rpc('refresh_expired_units');
    const scope = $('#adminFacilityFilter');
    let facilities = [];
    if (scope && !scope.dataset.loaded) {
        const f = await sb.from('facilities').select('id,name,district,municipality,is_main_branch,active').eq('active', true).order('name');
        facilities = f.data || [];
        scope.innerHTML = '<option value="">All Facilities</option>' + facilities.map(x => `<option value="${x.id}">${x.is_main_branch ? '★ ' : ''}${esc(x.name)}${x.district ? ' — ' + esc(x.district) : ''}</option>`).join('');
        const initial = query.get('facility_id');
        if (initial && facilities.some(x => x.id === initial))
            scope.value = initial;
        scope.dataset.loaded = '1';
        scope.onchange = () => {
            const u = new URL(location.href);
            if (scope.value)
                u.searchParams.set('facility_id', scope.value);
            else
                u.searchParams.delete('facility_id');
            history.replaceState(null, '', u);
            loadAdminDashboard();
        };
        scope._facilities = facilities;
    }
    else
        facilities = scope ? scope._facilities || [] : [];
    const facilityId = scope?.value || '';
    const chosen = facilities.find(x => x.id === facilityId);
    const label = $('#adminDashboardScopeLabel');
    if (label)
        label.textContent = chosen ? `${chosen.is_main_branch ? 'Main Branch • ' : ''}${chosen.name} dashboard` : 'System-wide overview across all BloodCare facilities';
    let donorQ = sb.from('donors').select('id', {
        count: 'exact', head: true
    }), unitQ = sb.from('blood_units').select('blood_type,status,facility_id').eq('status', 'available'), reqQ = sb.from('blood_requests').select('id', {
        count: 'exact', head: true
    }).in('status', ['pending', 'under_review']), allReqQ = sb.from('blood_requests').select('status'), assignQ = sb.from('staff_facility_assignments').select('staff_id'), activeStaffQ = sb.from('staff_profiles').select('id').eq('active', true);
    if (facilityId) {
        donorQ = donorQ.eq('facility_id', facilityId);
        unitQ = unitQ.eq('facility_id', facilityId);
        reqQ = reqQ.eq('facility_id', facilityId);
        allReqQ = allReqQ.eq('facility_id', facilityId);
        assignQ = assignQ.eq('facility_id', facilityId);
    }
    const [donors, units, reqs, audit, allReq, settings, assignments, activeStaff] = await Promise.all([donorQ, unitQ, reqQ, sb.from('audit_logs').select('*').order('created_at', {
            ascending: false
        }).limit(8), allReqQ, sb.from('system_settings').select('*').eq('id', 1).maybeSingle(), assignQ, activeStaffQ]);
    const activeIds = new Set((activeStaff.data || []).map(x => x.id));
    const staffCount = facilityId ? new Set((assignments.data || []).filter(x => activeIds.has(x.staff_id)).map(x => x.staff_id)).size : activeIds.size;
    const counts = {};
    (units.data || []).forEach(x => counts[x.blood_type] = (counts[x.blood_type] || 0) + 1);
    const bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
    $('#adminStaffCount').textContent = staffCount;
    $('#adminDonorCount').textContent = donors.count || 0;
    $('#adminBagCount').textContent = (units.data || []).length;
    $('#adminRequestCount').textContent = reqs.count || 0;
    $('#adminRecentAudit').innerHTML = (audit.data || []).map(x => `<div class="activity-item"><span class="activity-dot"></span><div><b>${esc(statusLabel(x.action))} • ${esc(x.entity_type)}</b><p>${esc(x.entity_id || 'System record')}</p><small>${fmtTime(x.created_at)}</small></div></div>`).join('') || '<div class="empty">No activity logged yet.</div>';
    const settingsForm = $('#systemSettingsForm');
    if (settingsForm && settings.data) {
        settingsForm.elements.donation_interval_days.value = settings.data.donation_interval_days;
        settingsForm.elements.appointment_slot_limit.value = settings.data.appointment_slot_limit;
    }
    if (window.Chart) {
        adminInventoryChart?.destroy();
        adminRequestChart?.destroy();
        adminInventoryChart = new Chart($('#inventoryChart'), {
            type: 'bar', data: {
                labels: bloodTypes, datasets: [{
                        label: 'Available bags', data: bloodTypes.map(t => counts[t] || 0)
                    }]
            }, options: {
                responsive: true, maintainAspectRatio: false
            }
        });
        const rc = {};
        (allReq.data || []).forEach(x => rc[x.status] = (rc[x.status] || 0) + 1);
        adminRequestChart = new Chart($('#requestChart'), {
            type: 'doughnut', data: {
                labels: Object.keys(rc).map(statusLabel), datasets: [{
                        data: Object.values(rc)
                    }]
            }, options: {
                responsive: true, maintainAspectRatio: false
            }
        });
    }
}
export { loadAdminDashboard };
export function init() {
    $('#systemSettingsForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const f = Object.fromEntries(new FormData(e.target)), btn = e.submitter;
        loading(btn, true);
        const payload = {
            donation_interval_days: Number(f.donation_interval_days), appointment_slot_limit: Number(f.appointment_slot_limit), updated_at: new Date().toISOString(), updated_by: managementProfile?.id || null
        };
        const { error } = await sb.from('system_settings').update(payload).eq('id', 1);
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        toast('Operational settings saved.');
    });
}
