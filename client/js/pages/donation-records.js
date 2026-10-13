/** pages/donation-records: extracted from the working v22 flows. No build step is required. */
import { $, esc, fmt, toast } from '../core/dom.js';
import { sb } from '../core/client.js';
export function init() {
    $('#donationHistoryForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!sb)
            return toast('BloodCare API is unavailable.', 'err');
        const f = new FormData(e.target), body = $('#recordsBody');
        body.innerHTML = '<tr><td colspan="5">Loading…</td></tr>';
        const { data, error } = await sb.rpc('public_donation_history', {
            p_donor_code: f.get('donor_code'), p_email: f.get('email')
        });
        if (error)
            return body.innerHTML = `<tr><td colspan="5">${esc(error.message)}</td></tr>`;
        body.innerHTML = (data || []).map(x => `<tr><td>${esc(x.donation_code)}</td><td>${fmt(x.donation_date)}</td><td><span class="pill">${esc(x.blood_type)}</span></td><td>${x.bags}</td><td>${esc(x.donation_site)}</td></tr>`).join('') || '<tr><td colspan="5">No donation records matched this donor code and email.</td></tr>';
    });
}
