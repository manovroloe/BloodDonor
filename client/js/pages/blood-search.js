/** pages/blood-search: extracted from the working v22 flows. No build step is required. */
import { $, esc, toast } from '../core/dom.js';
import { sb } from '../core/client.js';
import { query } from '../core/routing.js';
const bloodSearchForm = $('#bloodSearchForm'), prefilledBloodType = query.get('blood_type');
export function init() {
    $('#bloodSearchForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!sb)
            return toast('BloodCare API is unavailable.', 'err');
        const type = new FormData(e.target).get('blood_type'), out = $('#bloodSearchResult');
        out.innerHTML = '<div class="empty">Checking current stock and partner facilities…</div>';
        const [q, fac] = await Promise.all([sb.rpc('public_inventory'), sb.rpc('public_facility_inventory', {
                p_blood_type: type
            })]);
        let row = !q.error ? (q.data || []).find(x => x.blood_type === type) : null;
        if (q.error) {
            const fallback = await sb.from('blood_inventory').select('*').eq('blood_type', type).single();
            row = fallback.data;
        }
        if (!row)
            return out.innerHTML = '<div class="empty">No inventory record found.</div>';
        const allFacilities = fac.error ? [] : (fac.data || []), wantedFacility = query.get('facility_id'), facilities = wantedFacility ? allFacilities.filter(x => x.facility_id === wantedFacility) : allFacilities, total = Number(row.bags_available || 0), requestable = facilities.reduce((n, x) => n + Number(x.bags_available || 0), 0), first = facilities[0];
        const primary = first ? `<a class="primary-btn request-blood-cta" href="request-blood.html?blood_type=${encodeURIComponent(type)}&facility_id=${encodeURIComponent(first.facility_id)}">Request Blood</a>` : '<button class="primary-btn request-blood-cta unavailable" type="button" disabled>Request Blood</button>';
        const facilityCards = facilities.map(x => `<article class="stock-facility-card"><div><span class="tag">${esc(x.facility_type || 'Partner Facility')}</span><h3>${esc(x.facility_name)}</h3><p><b>${esc(x.district || 'District not specified')}</b><br>${esc([x.address, x.barangay, x.municipality, x.province].filter(Boolean).join(', '))}</p></div><div class="facility-stock-count"><strong>${x.bags_available}</strong><span>bag${x.bags_available === 1 ? '' : 's'} available</span></div><div class="facility-request-actions"><a class="primary-btn" href="request-blood.html?blood_type=${encodeURIComponent(type)}&facility_id=${encodeURIComponent(x.facility_id)}">Request Blood</a><a class="secondary-btn" href="request-blood.html?blood_type=${encodeURIComponent(type)}&facility_id=${encodeURIComponent(x.facility_id)}&schedule=1">Schedule Request</a></div></article>`).join('');
        const contextNote = wantedFacility ? '<div class="stock-notice">Showing availability for the partner facility you selected. Choose another facility from Find Partner Facilities to change it.</div>' : '', displayTotal = wantedFacility ? requestable : total;
        out.innerHTML = `${contextNote}<div class="result-card blood-result-summary"><div class="drop">${esc(type)}</div><div><h3>${displayTotal} bag${displayTotal === 1 ? '' : 's'} ${wantedFacility ? 'available at selected facility' : 'recorded available'}</h3><p>${requestable ? `${requestable} bag(s) are available at the ${wantedFacility ? 'selected partner facility' : 'listed partner facilities'} and can be requested online.` : wantedFacility ? 'The selected partner facility currently has no requestable stock for this blood type.' : total ? 'Stock exists but has not yet been assigned to a partner facility. Staff must assign its facility before online requests can be submitted.' : 'No available stock is currently recorded.'}</p></div><div>${primary}</div></div><div class="facility-stock-list">${facilityCards || '<div class="empty">No partner facility currently has requestable stock for this blood type.</div>'}</div>`;
    });
    if (bloodSearchForm && prefilledBloodType) {
        const select = bloodSearchForm.elements.blood_type;
        if (select) {
            select.value = prefilledBloodType;
            if (select.value !== prefilledBloodType) {
                const option = document.createElement('option');
                option.value = prefilledBloodType;
                option.textContent = prefilledBloodType;
                select.append(option);
                select.value = prefilledBloodType;
            }
        }
        bloodSearchForm.classList.add('search-prefilled');
        queueMicrotask(() => bloodSearchForm.requestSubmit());
    }
}
