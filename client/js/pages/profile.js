/** pages/profile: extracted from the working v22 flows. No build step is required. */
import { $, $$, esc, fmt, loading, statusClass, statusLabel, toast } from '../core/dom.js';
import { sb } from '../core/client.js';
import { currentProfile, currentUser } from '../core/session.js';
import { ACCOUNT_ONLY_PAGES } from '../core/routing.js';
import { syncRequestFor } from './blood-request.js';
function profileInitials(p) {
    const n = p?.first_name && p?.last_name ? `${p.first_name.charAt(0)}${p.last_name.charAt(0)}` : String(p?.full_name || p?.email || 'BC').slice(0, 2);
    return n.toUpperCase();
}
function splitProfileName(payload) {
    const p = payload?.profile, a = payload?.account || {};
    if (p)
        return {
            first: String(p.first_name || '').trim(), last: String(p.last_name || '').trim()
        };
    const full = String(a.full_name || '').trim().replace(/\s+/g, ' '), parts = full ? full.split(' ') : [];
    return {
        first: parts.shift() || '', last: parts.join(' ')
    };
}
function bindProfileNameEditor(payload) {
    const trigger = $('[data-edit-profile-name]');
    if (!trigger)
        return;
    trigger.onclick = () => {
        const current = splitProfileName(payload), wrap = document.createElement('div');
        wrap.className = 'modal-backdrop profile-edit-modal';
        wrap.innerHTML = `<div class="modal-card profile-edit-card"><div class="modal-header"><div><span class="section-label">PROFILE</span><h2>Edit your name</h2><p>Updating your name also updates the name shown in the BloodCare navigation.</p></div><button type="button" class="modal-close" data-profile-edit-close aria-label="Close">×</button></div><form id="profileNameForm" class="form-grid"><div class="form-group"><label>First Name</label><input name="first_name" maxlength="80" value="${esc(current.first)}" required autocomplete="given-name"></div><div class="form-group"><label>Last Name</label><input name="last_name" maxlength="80" value="${esc(current.last)}" autocomplete="family-name"></div><div class="form-group full modal-action-row"><button type="button" class="secondary-btn" data-profile-edit-close>Cancel</button><button class="primary-btn" type="submit">Save Name</button></div></form></div>`;
        document.body.append(wrap);
        const close = () => wrap.remove();
        $$('[data-profile-edit-close]', wrap).forEach(b => b.onclick = close);
        wrap.addEventListener('click', e => {
            if (e.target === wrap)
                close();
        });
        const form = $('#profileNameForm', wrap);
        form?.addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(form), first = String(fd.get('first_name') || '').trim(), last = String(fd.get('last_name') || '').trim();
            if (first.length < 1)
                return toast('Enter your first name.', 'err');
            const btn = e.submitter;
            loading(btn, true);
            const { data, error } = await sb.rpc('update_my_profile_name', {
                p_first_name: first, p_last_name: last
            });
            loading(btn, false);
            if (error)
                return toast(error.message, 'err');
            close();
            profileState.payload = null;
            toast('Profile name updated.');
            await loadMyBloodCareProfile();
            const navSpan = $('.profile-btn span');
            if (navSpan)
                navSpan.textContent = String(data?.full_name || `${first} ${last}`).trim();
        });
        form?.elements.first_name?.focus();
    };
}
function renderBloodCareProfile(payload) {
    const host = $('#profileDashboard'), access = $('#profileAccessCard');
    if (!host || !payload?.account)
        return;
    const a = payload.account, p = payload.profile, dons = Array.isArray(payload.donations) ? payload.donations : [], appts = Array.isArray(payload.appointments) ? payload.appointments : [], reqs = Array.isArray(payload.requests) ? payload.requests : [];
    const displayName = String(a.full_name || '').trim() || (p ? `${p.first_name} ${p.last_name}` : a.email);
    const donationRows = dons.map(x => `<tr><td><b>${esc(x.donation_code)}</b></td><td>${fmt(x.donation_date)}</td><td><span class="pill">${esc(x.blood_type)}</span></td><td>${Number(x.bags || 0)}</td><td>${esc(x.donation_site || '—')}</td></tr>`).join('');
    const appointmentRows = appts.map(x => `<tr><td><b>${esc(x.appointment_code)}</b></td><td>${fmt(x.appointment_date)}<br><small>${esc(String(x.appointment_time || '').slice(0, 5))}</small></td><td>${esc(x.location || '—')}</td><td><span class="status ${statusClass(x.status)}">${esc(statusLabel(x.status))}</span></td></tr>`).join('');
    const requestRows = reqs.map(x => `<tr><td><b>${esc(x.request_code)}</b></td><td>${esc(x.patient_name || '—')}</td><td><span class="pill">${esc(x.blood_type)}</span> • ${Number(x.bags || 0)} bag(s)</td><td>${fmt(x.date_needed)}</td><td><span class="status ${statusClass(x.status)}">${esc(statusLabel(x.status))}</span></td></tr>`).join('');
    const donorCard = p ? `<div class="profile-details-grid"><article class="profile-panel"><h3>Donor Details</h3><div class="detail-grid"><div class="detail-item"><span>Donor Code</span><b>${esc(p.donor_code)}</b></div><div class="detail-item"><span>Blood Type</span><b>${esc(p.blood_type)}</b></div><div class="detail-item"><span>Weight</span><b>${esc(p.weight_kg ?? '—')} kg</b></div><div class="detail-item"><span>Birth Date</span><b>${fmt(p.birth_date)}</b></div><div class="detail-item"><span>Last Donation</span><b>${fmt(p.last_donation_date)}</b></div><div class="detail-item"><span>Estimated Next Eligibility</span><b>${fmt(p.next_eligible_date)}</b><small>Staff screening remains final.</small></div></div></article><article class="profile-panel profile-summary"><h3>Donor Summary</h3><div class="blood-type-badge"><b>${esc(p.blood_type)}</b></div><p><b>${dons.length}</b> verified donation record${dons.length === 1 ? '' : 's'}<br><b>${appts.length}</b> appointment record${appts.length === 1 ? '' : 's'}</p><span class="profile-status">${esc(statusLabel(p.status))}</span></article></div>` : `<article class="profile-panel non-donor-card"><div class="non-donor-copy"><h3>You are not registered as a donor</h3><p>Your BloodCare account can still request blood, track requests, and manage appointments. If you want to donate, complete the donor pre-screen and registration.</p></div><div class="non-donor-actions"><a class="primary-btn" href="donor-registration.html">Become a Donor</a></div></article>`;
    host.innerHTML = `<div class="profile-top-card"><div class="profile-avatar">${esc(profileInitials(p || a))}</div><div class="profile-identity"><h2>${esc(displayName)}</h2><p>${esc(a.email)}${p ? ' • ' + esc(p.donor_code) : ' • BloodCare Account'}</p>${p ? `<span class="profile-status">${esc(statusLabel(p.status))}</span>` : ''}</div><div class="profile-top-actions"><button class="profile-edit-btn" type="button" data-edit-profile-name aria-label="Edit profile name"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20h4l10.5-10.5a2.8 2.8 0 0 0-4-4L4 16v4Zm9-13 4 4" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg><span>Edit Name</span></button><a class="profile-download-btn" href="/api/profile/ticket.pdf" aria-label="Download profile details as PDF"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12m0 0 4-4m-4 4-4-4M5 19h14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg><span>Download Details</span></a></div></div>${donorCard}<article class="profile-panel"><h3>Blood Requests</h3><div class="profile-table"><table><thead><tr><th>Reference</th><th>Patient</th><th>Blood</th><th>Needed</th><th>Status</th></tr></thead><tbody>${requestRows || '<tr><td colspan="5" class="profile-empty">No blood requests on this account.</td></tr>'}</tbody></table></div></article><article class="profile-panel"><h3>Appointments</h3><div class="profile-table"><table><thead><tr><th>Reference</th><th>Schedule</th><th>Location</th><th>Status</th></tr></thead><tbody>${appointmentRows || '<tr><td colspan="4" class="profile-empty">No appointments on this account.</td></tr>'}</tbody></table></div></article>${p ? `<article class="profile-panel"><h3>Verified Donation History</h3><div class="profile-table"><table><thead><tr><th>Donation ID</th><th>Date</th><th>Blood Type</th><th>Bags</th><th>Site</th></tr></thead><tbody>${donationRows || '<tr><td colspan="5" class="profile-empty">No completed donations have been recorded yet.</td></tr>'}</tbody></table></div></article>` : ''}`;
    bindProfileNameEditor(payload);
    if (access)
        access.hidden = true;
    host.hidden = false;
}
const profileState = {
    payload: null
};
async function loadMyBloodCareProfile() {
    if (!sb)
        return null;
    const u = await currentUser();
    if (!u)
        return null;
    const { data, error } = await sb.rpc('my_bloodcare_profile');
    if (error) {
        toast(error.message, 'err');
        const host = $('#profileDashboard');
        if (host) {
            host.innerHTML = `<article class="profile-panel profile-load-error"><h3>Unable to load your profile</h3><p>${esc(error.message || 'BloodCare could not load your profile details.')}</p><button class="primary-btn" type="button" onclick="location.reload()">Try Again</button></article>`;
            host.hidden = false;
        }
        return null;
    }
    profileState.payload = data;
    return data;
}
async function initPublicProfile() {
    if (!sb)
        return;
    const isProfile = !!$('#profileDashboard'), u = await currentUser(), pageName = location.pathname.split('/').pop() || 'index.html';
    if (ACCOUNT_ONLY_PAGES.has(pageName) && !u) {
        const next = location.pathname + location.search;
        location.replace('/login.html?next=' + encodeURIComponent(next));
        return;
    }
    // Staff/admin accounts are management identities, never donor/user identities.
    // This prevents the public website from exposing or auto-linking any donor profile.
    const staffAccount = u ? await currentProfile() : null;
    if (staffAccount) {
        if (isProfile || ACCOUNT_ONLY_PAGES.has(pageName)) {
            location.replace(staffAccount.role === 'admin' ? 'admin.html' : 'staff.html');
        }
        return;
    }
    if (isProfile) {
        if (!u) {
            const access = $('#profileAccessCard');
            if (access) {
                access.hidden = false;
                $('#profileDashboard').hidden = true;
            }
            else {
                location.replace('login.html?next=profile.html');
            }
            return;
        }
        const data = await loadMyBloodCareProfile();
        if (data)
            renderBloodCareProfile(data);
    }
    if (!u)
        return;
    const data = profileState.payload || await loadMyBloodCareProfile();
    if (!data)
        return;
    const a = data.account || {}, p = data.profile;
    const appt = $('#appointmentForm'), request = $('#requestForm'), donor = $('#donorForm'), track = $('#trackForm');
    if (donor && p) {
        const quiz = $('#donorEligibilityQuiz'), result = $('#donorQuizResult'), registration = $('#donorRegistrationSection');
        if (quiz)
            quiz.hidden = true;
        if (registration)
            registration.hidden = true;
        if (result) {
            result.hidden = false;
            result.className = 'glass-card donor-quiz-result qualified';
            result.innerHTML = `<div class="quiz-result-icon">✓</div><span class="section-label">DONOR ACCOUNT FOUND</span><h2>You are already registered as a blood donor.</h2><p>Your donor record <b>${esc(p.donor_code)}</b> is already linked to this BloodCare account. You do not need to register again.</p><div class="quiz-nav-actions"><a class="primary-btn" href="profile.html">Open My Profile</a><a class="secondary-btn" href="appointment.html">Book Donation Appointment</a></div>`;
        }
    }
    else if (donor && a.email) {
        donor.elements.email.value = a.email;
    }
    if (appt) {
        if (a.email)
            appt.elements.email.value = a.email;
        if (p) {
            appt.elements.donor_code.value = p.donor_code;
            appt.elements.full_name.value = `${p.first_name} ${p.last_name}`;
            appt.elements.phone.value = p.phone;
            appt.elements.blood_type.value = p.blood_type;
        }
        else if (a.full_name)
            appt.elements.full_name.value = a.full_name;
    }
    if (request) {
        if (a.email)
            request.elements.email.value = a.email;
        if (p) {
            request.elements.requester_name.value = `${p.first_name} ${p.last_name}`;
            request.elements.phone.value = p.phone;
        }
        else if (a.full_name)
            request.elements.requester_name.value = a.full_name;
        syncRequestFor();
    }
    if (track && a.email)
        track.elements.email.value = a.email;
}
export { profileState };
export function init() {
    initPublicProfile();
}
