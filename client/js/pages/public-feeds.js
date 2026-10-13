/** pages/public-feeds: extracted from the working v22 flows. No build step is required. */
import { sb } from '../core/client.js';
import { $, $$, esc, loading, today } from '../core/dom.js';
import { publicEventCard, publicNewsCard } from './home.js';
import { query } from '../core/routing.js';
async function initPublicFeed() {
    const feed = document.body.dataset.publicFeed;
    if (!feed || !sb)
        return;
    const isNews = feed === 'news';
    const list = $(isNews ? '#latestNewsList' : '#eventsActivityList');
    const btn = $(isNews ? '#latestNewsViewMore' : '#eventsViewMore');
    const search = $('#publicFeedSearch');
    if (!list || !btn)
        return;
    const pageSize = 6;
    let offset = 0, busy = false, loaded = [], eventView = 'upcoming';
    function renderLoaded() {
        const term = String(search?.value || '').trim().toLowerCase();
        const rows = loaded.filter(x => !term || [x.title, x.body, x.description, x.location, x.contact_person].join(' ').toLowerCase().includes(term));
        list.innerHTML = rows.map(isNews ? publicNewsCard : publicEventCard).join('') || `<div class="empty">${term ? 'No loaded posts match your search.' : isNews ? 'No latest news has been published yet.' : eventView === 'upcoming' ? 'No upcoming events have been published yet.' : 'No past activities have been published yet.'}</div>`;
    }
    async function loadMore(reset = false) {
        if (busy)
            return;
        if (reset) {
            offset = 0;
            loaded = [];
            list.innerHTML = '<div class="empty">Loading…</div>';
        }
        busy = true;
        loading(btn, true);
        const end = offset + pageSize - 1;
        let request;
        if (isNews)
            request = sb.from('announcements').select('*', {
                count: 'exact'
            }).eq('published', true).eq('feed_type', 'news').order('created_at', {
                ascending: false
            }).range(offset, end);
        else {
            request = sb.from('events').select('*', {
                count: 'exact'
            }).eq('published', true);
            request = eventView === 'upcoming' ? request.gte('event_date', today()).order('event_date', {
                ascending: true
            }) : request.lt('event_date', today()).order('event_date', {
                ascending: false
            });
            request = request.order('created_at', {
                ascending: false
            }).range(offset, end);
        }
        const { data, error, count } = await request;
        loading(btn, false);
        busy = false;
        if (error) {
            list.innerHTML = `<div class="empty error-text">${esc(error.message)}</div>`;
            btn.hidden = true;
            return;
        }
        const rows = data || [];
        loaded.push(...rows);
        offset += rows.length;
        renderLoaded();
        btn.hidden = !(count == null ? rows.length === pageSize : offset < count);
    }
    search?.addEventListener('input', renderLoaded);
    $$('[data-event-view]').forEach(tab => tab.addEventListener('click', async () => {
        eventView = tab.dataset.eventView;
        $$('[data-event-view]').forEach(x => x.classList.toggle('active', x === tab));
        await loadMore(true);
    }));
    btn.addEventListener('click', () => loadMore(false));
    await loadMore(true);
}
async function initUnifiedPublicFeed() {
    if (document.body.dataset.publicFeed !== 'unified' || !sb)
        return;
    const list = $('#publicFeedList'), more = $('#publicFeedsViewMore'), search = $('#publicFeedSearch');
    if (!list || !more)
        return;
    let rows = [], visible = 6, filter = query.get('filter') || 'all';
    const [a, e] = await Promise.all([sb.from('announcements').select('*').eq('published', true).order('created_at', {
            ascending: false
        }).limit(150), sb.from('events').select('*').eq('published', true).order('created_at', {
            ascending: false
        }).limit(150)]);
    rows = [...(a.data || []).map(x => ({
            ...x, _kind: x.feed_type === 'announcement' ? 'announcements' : 'news', _date: x.created_at
        })), ...(e.data || []).map(x => ({
            ...x, _kind: 'events', _date: x.created_at || x.event_date
        }))].sort((x, y) => String(y._date || '').localeCompare(String(x._date || '')));
    function draw() {
        const term = String(search?.value || '').trim().toLowerCase();
        const filtered = rows.filter(x => (filter === 'all' || x._kind === filter) && (!term || [x.title, x.body, x.description, x.location].join(' ').toLowerCase().includes(term)));
        const shown = filtered.slice(0, visible);
        list.innerHTML = shown.map(x => x._kind === 'events' ? publicEventCard(x) : publicNewsCard(x)).join('') || '<div class="empty">No published items match this filter.</div>';
        more.hidden = shown.length >= filtered.length;
        $$('[data-feed-filter]').forEach(b => b.classList.toggle('active', b.dataset.feedFilter === filter));
    }
    $$('[data-feed-filter]').forEach(b => b.addEventListener('click', () => {
        filter = b.dataset.feedFilter;
        visible = 6;
        draw();
    }));
    search?.addEventListener('input', () => {
        visible = 6;
        draw();
    });
    more.addEventListener('click', () => {
        visible += 6;
        draw();
    });
    if (!['news', 'events', 'announcements', 'all'].includes(filter))
        filter = 'all';
    draw();
}
export function init() {
    initPublicFeed();
    initUnifiedPublicFeed();
}
