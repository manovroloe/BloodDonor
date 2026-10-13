/** pages/home: extracted from the working v22 flows. No build step is required. */
import { $, esc, excerpt, fmt, toast } from '../core/dom.js';
import { sb } from '../core/client.js';
const publicNewsCard = x => {
    const body = String(x.body || ''), long = body.length > 210, label = x.feed_type === 'announcement' ? 'Announcement' : 'News';
    return `<article class="mini-card feed-card news-feed-card">${x.image_url ? `<img class="feed-card-image" src="${esc(x.image_url)}" alt="${esc(x.title)}" loading="lazy">` : ''}<div class="feed-card-meta"><span class="tag">${label}</span><small>${fmt(x.created_at)}</small></div><h3>${esc(x.title)}</h3><p>${esc(long ? excerpt(body) : body)}</p>${long ? `<details class="feed-details"><summary>Read More</summary><p>${esc(body)}</p></details>` : ''}</article>`;
};
const publicEventCard = x => {
    const body = String(x.description || ''), long = body.length > 190;
    return `<article class="mini-card event feed-card event-feed-card">${x.image_url ? `<img class="feed-card-image" src="${esc(x.image_url)}" alt="${esc(x.title)}" loading="lazy">` : ''}<div class="feed-card-meta"><span class="tag">${fmt(x.event_date)}${x.event_time ? ' • ' + esc(String(x.event_time).slice(0, 5)) : ''}</span><small>${fmt(x.created_at)}</small></div><h3>${esc(x.title)}</h3>${body ? `<p>${esc(long ? excerpt(body, 190) : body)}</p>` : ''}${long ? `<details class="feed-details"><summary>Read More</summary><p>${esc(body)}</p></details>` : ''}<div class="event-feed-details"><span>${esc(x.location || 'Location to be announced')}</span>${x.contact_person ? `<small>Contact: ${esc(x.contact_person)}</small>` : ''}</div></article>`;
};
async function publicHome() {
    if (!document.querySelector("#homePublicFeed, #publicInventory, #publicInventoryPreview, #bloodOnlineQuickSearch, #homeDonors, #homeBags, #bloodOnlineTotal, #homeInventoryTotal")) return;
    if (!sb)
        return;
    const [ann, ev, stats, invRpc] = await Promise.all([
        sb.from('announcements').select('*').eq('published', true).order('created_at', {
            ascending: false
        }).limit(8),
        sb.from('events').select('*').eq('published', true).order('created_at', {
            ascending: false
        }).limit(8),
        sb.rpc('public_stats'), sb.rpc('public_inventory')
    ]);
    let inv = invRpc.data || [];
    if (invRpc.error) {
        const fallback = await sb.from('blood_inventory').select('*').order('blood_type');
        inv = fallback.data || [];
    }
    const inventoryTotal = stats.data?.available_bags ?? inv.reduce((a, x) => a + Number(x.bags_available || 0), 0);
    if ($('#homeDonors'))
        $('#homeDonors').textContent = stats.data?.registered_donors ?? '—';
    if ($('#homeBags'))
        $('#homeBags').textContent = inventoryTotal;
    if ($('#homeInventoryTotal'))
        $('#homeInventoryTotal').textContent = inventoryTotal;
    if ($('#bloodOnlineTotal'))
        $('#bloodOnlineTotal').textContent = inventoryTotal;
    const homeFeed = $('#homePublicFeed');
    if (homeFeed) {
        const mixed = [...(ann.data || []).map(x => ({
                kind: 'announcement', sortDate: x.created_at || '', row: x
            })), ...(ev.data || []).map(x => ({
                kind: 'event', sortDate: x.created_at || x.event_date || '', row: x
            }))].sort((a, b) => String(b.sortDate).localeCompare(String(a.sortDate))).slice(0, 3);
        homeFeed.innerHTML = mixed.map(x => x.kind === 'event' ? publicEventCard(x.row) : publicNewsCard(x.row)).join('') || '<div class="empty">No public updates have been published yet.</div>';
    }
    const inventoryMarkup = rows => rows.map(x => `<div class="blood-chip ${x.bags_available <= x.reorder_level ? 'low-stock' : ''}"><b>${esc(x.blood_type)}</b><span>${x.bags_available} bag${x.bags_available === 1 ? '' : 's'}</span></div>`).join('');
    const i = $('#publicInventory');
    if (i)
        i.innerHTML = inventoryMarkup(inv);
    const preview = $('#publicInventoryPreview');
    if (preview)
        preview.innerHTML = inventoryMarkup(inv.slice(0, 8));
    const quickType = $('#bloodQuickType');
    if (quickType) {
        const types = [...new Set(inv.map(x => String(x.blood_type || '').trim()).filter(Boolean))];
        quickType.innerHTML = '<option value="">Select blood type</option>' + types.map(t => `<option value="${esc(t)}">${esc(t)}</option>`).join('');
    }
    const quickFacility = $('#bloodQuickFacility');
    if (quickFacility) {
        const fq = await sb.from('facilities').select('id,name').eq('active', true).order('name');
        if (!fq.error)
            quickFacility.innerHTML = '<option value="">All partner facilities</option>' + (fq.data || []).map(f => `<option value="${esc(f.id)}">${esc(f.name)}</option>`).join('');
    }
    const quickForm = $('#bloodOnlineQuickSearch');
    if (quickForm && !quickForm.dataset.bound) {
        quickForm.dataset.bound = '1';
        quickForm.addEventListener('submit', e => {
            e.preventDefault();
            const type = $('#bloodQuickType')?.value || '', facility = $('#bloodQuickFacility')?.value || '';
            if (!type)
                return toast('Choose a blood type first.', 'err');
            const q = new URLSearchParams({
                blood_type: type
            });
            if (facility)
                q.set('facility_id', facility);
            window.location.href = `blood-search.html?${q.toString()}`;
        });
    }
}
export { publicEventCard, publicNewsCard };
export function init() {
    publicHome();
}
