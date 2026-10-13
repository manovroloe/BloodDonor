/** components/facility-context: extracted from the working v22 flows. No build step is required. */
import { query } from '../core/routing.js';
import { sb } from '../core/client.js';
import { $, esc, today } from '../core/dom.js';
import { donorAge } from '../pages/donor-registration.js';
import { loadRequestFacilities, syncRequestFor } from '../pages/blood-request.js';
import { currentProfile, currentUser } from '../core/session.js';
async function initSelectedFacilityContext() {
    const facilityId = query.get('facility_id');
    if (!facilityId || !sb)
        return;
    const page = location.pathname.split('/').pop() || 'index.html';
    if (!['request-blood.html', 'blood-search.html', 'donor-registration.html', 'appointment.html'].includes(page))
        return;
    const { data, error } = await sb.from('facilities').select('id,name,facility_type,address,municipality,province').eq('id', facilityId).eq('active', true).maybeSingle();
    if (error || !data)
        return;
    const title = $('.page-title');
    if (!title)
        return;
    const note = document.createElement('div');
    note.className = 'selected-facility-context';
    note.innerHTML = `<span class="tag">Selected Partner Facility</span><div><b>${esc(data.name)}</b><small>${esc([data.address, data.municipality, data.province].filter(Boolean).join(', '))}</small></div><a href="map.html">Change Facility</a>`;
    title.insertAdjacentElement('afterend', note);
}
async function initPublicFormSafety() {
    const max = today();
    const birth = $('#donorBirthDate'), last = $('#donorLastDonation'), apptDate = $('#appointmentDate'), need = $('#requestDateNeeded'), tattoo = $('#tattooDate'), piercing = $('#piercingDate'), pickup = $('#pickupDate');
    if (birth)
        birth.max = max;
    if (last)
        last.max = max;
    if (tattoo)
        tattoo.max = max;
    if (piercing)
        piercing.max = max;
    if (apptDate)
        apptDate.min = max;
    if (need)
        need.min = max;
    if (pickup)
        pickup.min = max;
    birth?.addEventListener('change', () => {
        const hint = $('#donorAgeHint'), age = donorAge(birth.value);
        if (hint)
            hint.textContent = age === null ? 'Required age: 18–65.' : `Age: ${age} • ${age >= 18 && age <= 65 ? 'Within basic standard' : 'Outside 18–65 standard'}`;
    });
    const loc = $('#appointmentLocation');
    if (loc && sb) {
        const { data, error } = await sb.from('facilities').select('id,name,address,municipality,province,district').eq('active', true).order('name');
        if (error) {
            loc.innerHTML = '<option value="">Unable to load facilities</option>';
        }
        else {
            loc.innerHTML = '<option value="">Select an active facility</option>' + (data || []).map(x => `<option value="${esc(x.id)}" data-name="${esc(x.name)}">${esc(x.name)} — ${esc(x.district || [x.municipality, x.province].filter(Boolean).join(', ') || x.address)}</option>`).join('');
            const wanted = query.get('facility_id');
            if (wanted) {
                loc.value = wanted;
                if (loc.value !== wanted)
                    loc.value = '';
            }
            const syncLocation = () => {
                const hidden = $('#appointmentForm')?.elements.location;
                if (hidden)
                    hidden.value = loc.selectedOptions[0]?.dataset.name || '';
            };
            loc.addEventListener('change', syncLocation);
            syncLocation();
        }
    }
    if ($('#requestBloodType')) {
        const type = query.get('blood_type');
        if (type)
            $('#requestBloodType').value = type;
        if (query.get('schedule') === '1') {
            $('#scheduleBloodRequest').checked = true;
            $('#pickupScheduleFields').hidden = false;
            $('#pickupDate').required = true;
            $('#pickupTime').required = true;
        }
        syncRequestFor();
        if (type)
            await loadRequestFacilities();
    }
    if (sb && $('.profile-btn')) {
        const u = await currentUser(), btn = $('.profile-btn'), span = $('span', btn);
        let staff = null;
        if (u)
            staff = await currentProfile();
        if (staff) {
            btn.href = staff.role === 'admin' ? 'admin.html' : 'staff.html';
            btn.setAttribute('aria-label', staff.role === 'admin' ? 'Return to Admin Portal' : 'Return to Staff Portal');
            if (span)
                span.textContent = staff.role === 'admin' ? 'Admin Portal' : 'Staff Portal';
        }
        else {
            btn.href = u ? 'profile.html' : 'login.html';
            const accountName = String(u?.user_metadata?.full_name || u?.user_metadata?.name || '').trim() || String(u?.email || '').split('@')[0] || 'My Account';
            btn.setAttribute('aria-label', u ? `Open ${accountName}'s BloodCare profile` : 'Log in to BloodCare');
            if (span)
                span.textContent = u ? accountName : 'Log In';
            btn.title = u ? accountName : 'Log In';
        }
    }
}
export function init() {
    initSelectedFacilityContext();
    initPublicFormSafety();
}
