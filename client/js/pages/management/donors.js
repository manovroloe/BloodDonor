/** pages/management/donors: extracted from the working v22 flows. No build step is required. */
import { sb } from '../../core/client.js';
import { $, $$, PAGE_SIZE, esc, fmt, fmtTime, loading, statusClass, statusLabel, toast } from '../../core/dom.js';
import { query } from '../../core/routing.js';
import { donorReviewLabels } from '../donor-registration.js';
import { renderPager } from '../../components/feedback.js';
let donorRows = [], donorPage = 1;
async function loadDonors() {
    const { data, error } = await sb.from('donors').select('*').order('created_at', {
        ascending: false
    });
    if (error)
        return toast(error.message, 'err');
    donorRows = data || [];
    const preset = query.get('status');
    if (preset && $('#donorStatusFilter'))
        $('#donorStatusFilter').value = preset;
    renderDonors();
}
const preScreenLabel = v => ({
    preliminarily_eligible: 'Preliminarily Eligible', temporarily_deferred: 'Temporarily Deferred', needs_review: 'Needs Review', not_eligible: 'Not Eligible Online'
})[v] || 'Legacy / Not Recorded';
function screeningListValues(values, labels) {
    return Array.isArray(values) && values.length ? values.map(x => labels[x] || statusLabel(x)).join(', ') : 'None reported';
}
function renderScreeningReview(d) {
    const s = d.screening_answers && typeof d.screening_answers === 'object' ? d.screening_answers : {}, reasons = Array.isArray(d.screening_reasons) ? d.screening_reasons : [];
    const pregnancy = ({
        not_applicable: 'Not applicable', no: 'No', pregnant: 'Currently pregnant', recent_birth: 'Recent childbirth'
    })[s.pregnancy_status] || 'Not recorded';
    return `<div class="profile-panel screening-review"><div class="panel-head"><div><h3>Detailed Online Pre-screen</h3><p class="muted-text">Online screening supports staff review and is not the final medical decision.</p></div><span class="status ${d.screening_outcome === 'preliminarily_eligible' ? 'eligible' : d.screening_outcome === 'temporarily_deferred' ? 'deferred' : 'pending'}">${esc(preScreenLabel(d.screening_outcome))}</span></div><div class="screening-review-grid"><p><b>Weight:</b> ${esc(d.weight_kg ?? '—')} kg</p><p><b>Current illness:</b> ${s.current_illness ? 'Yes' : 'No'}</p><p><b>Antibiotics:</b> ${s.on_antibiotics ? 'Yes' : 'No'}</p><p><b>Medical review conditions:</b> ${esc(screeningListValues(s.review_conditions, donorReviewLabels))}</p><p><b>Medication:</b> ${s.medication_current ? esc(s.medication_details || 'Yes') : 'None reported'}</p><p><b>Tattoo:</b> ${d.has_tattoo ? 'Yes — ' + fmt(d.tattoo_date) : 'No'}</p><p><b>Piercing:</b> ${d.has_piercing ? 'Yes — ' + fmt(d.piercing_date) : 'No'}</p><p><b>Acupuncture:</b> ${s.has_acupuncture === 'true' ? 'Yes — ' + fmt(s.acupuncture_date) : 'No'}</p><p><b>Pregnancy / postpartum:</b> ${esc(pregnancy)}</p><p><b>Breastfeeding:</b> ${s.breastfeeding ? 'Yes' : 'No'}</p><p><b>Alcohol in prior 24h:</b> ${s.alcohol_last_24h ? 'Yes' : 'No'}</p><p><b>Smoking / vaping:</b> ${s.smokes ? 'Yes' : 'No'}</p><p><b>Previous donation:</b> ${s.donated_before ? fmt(s.last_donation_date) : 'None reported'}</p><p><b>Other lifestyle note:</b> ${esc(s.other_habits || 'None')}</p></div>${reasons.length ? `<div class="screening-reasons"><b>Automated pre-screen findings</b><ul>${reasons.map(x => `<li>${esc(x)}</li>`).join('')}</ul>${d.screening_next_eligible_at ? `<small>Estimated next eligible time from automatic rules: ${esc(fmtTime(d.screening_next_eligible_at))}</small>` : ''}</div>` : ''}</div>`;
}
function renderDonors() {
    const q = ($('#donorSearch')?.value || '').toLowerCase(), st = $('#donorStatusFilter')?.value || '';
    const rows = donorRows.filter(x => (!st || x.status === st) && (!q || [x.donor_code, x.first_name, x.last_name, x.email, x.phone, x.municipality, x.barangay, x.screening_outcome].join(' ').toLowerCase().includes(q)));
    const pages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
    donorPage = Math.min(donorPage, pages);
    const visible = rows.slice((donorPage - 1) * PAGE_SIZE, donorPage * PAGE_SIZE);
    $('#donorBody').innerHTML = visible.map(x => `<tr><td><b>${esc(x.donor_code)}</b><br>${esc(x.first_name + ' ' + x.last_name)}<br><small>${esc(x.email)}</small></td><td><span class="pill">${esc(x.blood_type)}</span></td><td>${esc([x.street, x.barangay, x.municipality, x.province].filter(Boolean).join(', '))}</td><td><span class="status ${statusClass(x.status)}">${esc(statusLabel(x.status))}</span><br><small>Pre-screen: ${esc(preScreenLabel(x.screening_outcome))}</small></td><td>${fmt(x.last_donation_date)}</td><td><button class="small-btn" data-donor-view="${x.id}">View / Edit</button></td></tr>`).join('') || '<tr><td colspan="6">No donors match this filter.</td></tr>';
    $$('[data-donor-view]').forEach(b => b.onclick = () => openDonor(b.dataset.donorView));
    renderPager('#donorPagination', donorPage, pages, rows.length, p => {
        donorPage = p;
        renderDonors();
    });
}
async function openDonor(id) {
    const d = donorRows.find(x => x.id === id);
    if (!d)
        return;
    const [dons, appts] = await Promise.all([sb.from('donations').select('*').eq('donor_id', id).order('donation_date', {
            ascending: false
        }).limit(10), sb.from('appointments').select('*').eq('donor_id', id).order('appointment_date', {
            ascending: false
        }).limit(10)]);
    const c = $('#donorDetailContent');
    c.innerHTML = `<div class="modal-title"><span class="tag">${esc(d.donor_code)}</span><h2>${esc(d.first_name + ' ' + d.last_name)}</h2><p>${esc(d.email)} • ${esc(d.phone)}</p></div><form id="donorEditForm" class="form-grid"><input type="hidden" name="id" value="${d.id}"><div class="form-group"><label>Email</label><input name="email" type="email" value="${esc(d.email)}" required></div><div class="form-group"><label>Phone</label><input name="phone" value="${esc(d.phone)}" required></div><div class="form-group"><label>Street / Purok / Sitio</label><input name="street" value="${esc(d.street)}" required></div><div class="form-group"><label>Barangay</label><input name="barangay" value="${esc(d.barangay)}" required></div><div class="form-group"><label>Municipality</label><input name="municipality" value="${esc(d.municipality)}" required></div><div class="form-group"><label>Province</label><input name="province" value="${esc(d.province)}" required></div><div class="form-group"><label>Eligibility Status</label><select name="status">${['pending', 'eligible', 'deferred', 'inactive'].map(s => `<option value="${s}" ${s === d.status ? 'selected' : ''}>${statusLabel(s)}</option>`).join('')}</select></div><div class="form-group"><label>Review Notes</label><input name="review_notes" value="${esc(d.review_notes || '')}"></div><div class="form-group full"><button class="primary-btn">Save Donor</button></div></form>${renderScreeningReview(d)}<div class="grid-2 detail-grids"><div><h3>Donation History</h3>${(dons.data || []).map(x => `<div class="record-line"><b>${esc(x.donation_code)}</b><span>${fmt(x.donation_date)} • ${x.bags} bag(s)</span></div>`).join('') || '<p class="muted-text">No donations yet.</p>'}</div><div><h3>Appointments</h3>${(appts.data || []).map(x => `<div class="record-line"><b>${esc(x.appointment_code)}</b><span>${fmt(x.appointment_date)} • ${esc(statusLabel(x.status))}</span></div>`).join('') || '<p class="muted-text">No linked appointments.</p>'}</div></div>`;
    $('#donorDetail').hidden = false;
    $('#donorEditForm').onsubmit = async (e) => {
        e.preventDefault();
        const f = Object.fromEntries(new FormData(e.target)), btn = e.submitter;
        loading(btn, true);
        const { error: e1 } = await sb.rpc('update_donor_contact', {
            p_donor_id: f.id, p_data: {
                email: f.email, phone: f.phone, street: f.street, barangay: f.barangay, municipality: f.municipality, province: f.province
            }
        });
        if (e1) {
            loading(btn, false);
            return toast(e1.message, 'err');
        }
        const { error: e2 } = await sb.rpc('set_donor_status', {
            p_donor_id: f.id, p_status: f.status, p_notes: f.review_notes || null
        });
        loading(btn, false);
        if (e2)
            return toast(e2.message, 'err');
        toast('Donor updated.');
        $('#donorDetail').hidden = true;
        loadDonors();
    };
}
export { loadDonors };
export function init() {
    $('#donorSearch')?.addEventListener('input', () => {
        donorPage = 1;
        renderDonors();
    });
    $('#donorStatusFilter')?.addEventListener('change', () => {
        donorPage = 1;
        renderDonors();
    });
}
