/** pages/map: extracted from the working v22 flows. No build step is required. */
import { $, $$, esc } from '../core/dom.js';
import { sb } from '../core/client.js';
import { query } from '../core/routing.js';
function mapUrl(lat, lng) {
    const la = Number(lat), lo = Number(lng);
    if (!Number.isFinite(la) || !Number.isFinite(lo))
        return null;
    const pad = .02;
    return `https://www.openstreetmap.org/export/embed.html?bbox=${lo - pad}%2C${la - pad}%2C${lo + pad}%2C${la + pad}&layer=mapnik&marker=${la}%2C${lo}`;
}
let publicFacilityRows = [];
function openPublicFacility(id) {
    const x = publicFacilityRows.find(v => v.id === id);
    if (!x)
        return;
    let modal = $('#publicFacilityModal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'publicFacilityModal';
        modal.className = 'modal-backdrop';
        modal.hidden = true;
        document.body.append(modal);
    }
    const address = [x.address, x.barangay, x.municipality, x.province].filter(Boolean).join(', '), q = encodeURIComponent(x.id);
    modal.innerHTML = `<section class="modal-card facility-choice-modal" role="dialog" aria-modal="true" aria-labelledby="facilityChoiceTitle"><button class="modal-close" type="button" data-facility-close aria-label="Close">×</button><div class="facility-choice-head"><span class="tag">${esc(x.facility_type || 'Partner Facility')}</span><h2 id="facilityChoiceTitle">${esc(x.name)}</h2><p>${esc(address)}</p></div><div class="facility-choice-details">${x.operating_hours ? `<p><b>Operating Hours</b><span>${esc(x.operating_hours)}</span></p>` : ''}${x.phone ? `<p><b>Contact</b><span>${esc(x.phone)}</span></p>` : ''}${x.services ? `<p><b>Services</b><span>${esc(x.services)}</span></p>` : ''}</div><div class="facility-choice-prompt"><b>What would you like to do at this facility?</b><span>The selected facility will be carried into the next BloodCare service.</span></div><div class="facility-service-actions"><a class="facility-service-btn" href="request-blood.html?facility_id=${q}"><b>Request Blood</b><span>Request available blood from this facility</span></a><a class="facility-service-btn" href="donor-registration.html?facility_id=${q}"><b>Donate Blood</b><span>Start donor eligibility and registration</span></a><a class="facility-service-btn" href="blood-search.html?facility_id=${q}"><b>Search Blood</b><span>Check blood availability for this facility</span></a><a class="facility-service-btn" href="appointment.html?facility_id=${q}"><b>Book Appointment</b><span>Choose this facility as the donation location</span></a></div></section>`;
    modal.hidden = false;
    modal.querySelector('[data-facility-close]').onclick = () => modal.hidden = true;
    modal.onclick = e => {
        if (e.target === modal)
            modal.hidden = true;
    };
}
async function loadPublicFacilities() {
    const list = $('#facilityList'), preview = $('#homeFacilityPreview');
    if ((!list && !preview) || !sb)
        return;
    const { data, error } = await sb.from('facilities').select('*').eq('active', true).order('name');
    if (error) {
        if (list)
            list.innerHTML = `<div class="empty">${esc(error.message)}</div>`;
        if (preview)
            preview.innerHTML = `<div class="empty">${esc(error.message)}</div>`;
        return;
    }
    publicFacilityRows = data || [];
    if ($('#homeFacilityCount'))
        $('#homeFacilityCount').textContent = publicFacilityRows.length;
    if (preview) {
        const featured = [...publicFacilityRows].sort((a, b) => Number(!!b.is_main_branch) - Number(!!a.is_main_branch) || String(a.name || '').localeCompare(String(b.name || ''))).slice(0, 3);
        preview.innerHTML = featured.map(x => `<article class="home-facility-card" data-facility-open="${esc(x.id)}" tabindex="0" role="button" aria-label="Open ${esc(x.name)}"><div class="home-facility-card-head"><span class="tag">${esc(x.is_main_branch ? 'Main Branch' : (x.facility_type || 'Partner Facility'))}</span><span class="facility-active-dot">Active</span></div><h3>${esc(x.name)}</h3><p>${esc([x.address, x.barangay, x.municipality, x.province].filter(Boolean).join(', ') || 'Location available in facility details')}</p><small>View facility services →</small></article>`).join('') || '<div class="empty">No active partner facilities are currently published.</div>';
    }
    if (list) {
        list.innerHTML = publicFacilityRows.map(x => `<article class="facility-card clickable-facility" data-facility-open="${esc(x.id)}" data-facility-lat="${esc(x.latitude ?? '')}" data-facility-lng="${esc(x.longitude ?? '')}" data-facility-name="${esc(x.name)}" tabindex="0" role="button" aria-label="Focus ${esc(x.name)} on the map"><div class="facility-card-main"><span class="tag">${esc(x.facility_type)}</span><h3>${esc(x.name)}</h3><p>${esc([x.address, x.barangay, x.municipality, x.province].filter(Boolean).join(', '))}</p>${x.operating_hours ? `<small><b>Hours:</b> ${esc(x.operating_hours)}</small>` : ''}${x.services ? `<small><b>Services:</b> ${esc(x.services)}</small>` : ''}${x.phone ? `<small><b>Contact:</b> ${esc(x.phone)}</small>` : ''}</div><div class="facility-actions"><button class="primary-btn mini" type="button" data-facility-details="${esc(x.id)}">View Facility</button></div></article>`).join('') || '<div class="empty">No facilities are currently published.</div>';
    }
    const focusFacilityCard = card => {
        if (!list)
            return false;
        const u = mapUrl(card.dataset.facilityLat, card.dataset.facilityLng), map = $('#facilityMap');
        if (!u || !map)
            return false;
        map.src = u;
        if ($('#mapCaption'))
            $('#mapCaption').textContent = `Map focused on ${card.dataset.facilityName}.`;
        return true;
    };
    $$('[data-facility-open]').forEach(card => {
        card.addEventListener('click', e => {
            if (e.target.closest('button,a'))
                return;
            if (!focusFacilityCard(card))
                openPublicFacility(card.dataset.facilityOpen);
        });
        card.addEventListener('keydown', e => {
            if ((e.key === 'Enter' || e.key === ' ') && !e.target.closest('button,a')) {
                e.preventDefault();
                if (!focusFacilityCard(card))
                    openPublicFacility(card.dataset.facilityOpen);
            }
        });
    });
    $$('[data-facility-details]').forEach(b => b.onclick = e => {
        e.stopPropagation();
        openPublicFacility(b.dataset.facilityDetails);
    });
    const wanted = query.get('facility_id');
    if (list && wanted) {
        const selected = publicFacilityRows.find(x => x.id === wanted);
        if (selected) {
            const u = mapUrl(selected.latitude, selected.longitude), map = $('#facilityMap');
            if (u && map)
                map.src = u;
            if ($('#mapCaption'))
                $('#mapCaption').textContent = `Map focused on ${selected.name}.`;
            document.querySelector(`[data-facility-open="${CSS.escape(wanted)}"]`)?.scrollIntoView({
                behavior: 'smooth', block: 'center'
            });
        }
    }
}
export { mapUrl };
export function init() {
    loadPublicFacilities();
}
