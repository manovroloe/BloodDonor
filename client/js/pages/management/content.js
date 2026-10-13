/** pages/management/content: extracted from the working v22 flows. No build step is required. */
import { sb } from '../../core/client.js';
import { $, $$, esc, fmt, loading, statusLabel, toast } from '../../core/dom.js';
import { confirmAction, storagePathFromUrl } from '../../components/feedback.js';
import { managementProfile } from '../../components/navigation.js';
let announcements = [], events = [];
async function loadContent() {
    const [a, e] = await Promise.all([sb.from('announcements').select('*').order('created_at', {
            ascending: false
        }), sb.from('events').select('*').order('event_date', {
            ascending: false
        })]);
    announcements = a.data || [];
    events = e.data || [];
    $('#announcementAdmin').innerHTML = announcements.map(x => `<tr><td>${x.image_url ? `<img class="thumb" src="${esc(x.image_url)}" alt="">` : ''}${esc(x.title)}<br><small>${esc(statusLabel(x.feed_type || 'news'))}</small></td><td>${x.published ? 'Published' : 'Draft'}</td><td>${fmt(x.created_at)}</td><td><div class="action-stack horizontal"><button class="small-btn" data-edit-a="${x.id}">Edit</button><button class="small-btn danger" data-del-a="${x.id}">Delete</button></div></td></tr>`).join('') || '<tr><td colspan="4">No latest news posts.</td></tr>';
    $('#eventAdmin').innerHTML = events.map(x => `<tr><td>${x.image_url ? `<img class="thumb" src="${esc(x.image_url)}" alt="">` : ''}${esc(x.title)}</td><td>${fmt(x.event_date)}</td><td>${esc(x.location)}</td><td><div class="action-stack horizontal"><button class="small-btn" data-edit-e="${x.id}">Edit</button><button class="small-btn danger" data-del-e="${x.id}">Delete</button></div></td></tr>`).join('') || '<tr><td colspan="4">No events or activities.</td></tr>';
    $$('[data-edit-a]').forEach(b => b.onclick = () => {
        const x = announcements.find(v => v.id === b.dataset.editA), f = $('#announcementForm');
        f.elements.id.value = x.id;
        f.elements.feed_type.value = x.feed_type || 'news';
        f.elements.title.value = x.title;
        f.elements.body.value = x.body;
        f.elements.published.checked = x.published;
        f.dataset.imageUrl = x.image_url || '';
        f.scrollIntoView({
            behavior: 'smooth'
        });
    });
    $$('[data-del-a]').forEach(b => b.onclick = async () => {
        if (!(await confirmAction('Delete News Post', 'This public news post will be permanently deleted.', 'Delete')))
            return;
        const x = announcements.find(v => v.id === b.dataset.delA), { error } = await sb.from('announcements').delete().eq('id', b.dataset.delA);
        if (error)
            return toast(error.message, 'err');
        const oldPath = storagePathFromUrl(x?.image_url);
        if (oldPath)
            await sb.storage.from('event-images').remove([oldPath]);
        toast('Public feed post deleted.');
        loadContent();
    });
    $$('[data-edit-e]').forEach(b => b.onclick = () => {
        const x = events.find(v => v.id === b.dataset.editE), f = $('#eventForm');
        f.elements.id.value = x.id;
        f.elements.title.value = x.title;
        f.elements.event_date.value = x.event_date;
        f.elements.event_time.value = x.event_time || '';
        f.elements.location.value = x.location;
        f.elements.contact_person.value = x.contact_person || '';
        f.elements.latitude.value = x.latitude || '';
        f.elements.longitude.value = x.longitude || '';
        f.elements.description.value = x.description || '';
        f.elements.published.checked = x.published;
        f.dataset.imageUrl = x.image_url || '';
        f.scrollIntoView({
            behavior: 'smooth'
        });
    });
    $$('[data-del-e]').forEach(b => b.onclick = async () => {
        const x = events.find(v => v.id === b.dataset.delE);
        if (!(await confirmAction('Delete Event / Activity', 'This event and its stored image will be permanently deleted.', 'Delete')))
            return;
        const { error } = await sb.from('events').delete().eq('id', b.dataset.delE);
        if (error)
            return toast(error.message, 'err');
        const oldPath = storagePathFromUrl(x?.image_url);
        if (oldPath)
            await sb.storage.from('event-images').remove([oldPath]);
        toast('Event deleted.');
        loadContent();
    });
}
export { loadContent };
export function init() {
    $('#announcementForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const f = e.target, fd = new FormData(f), btn = e.submitter;
        loading(btn, true);
        const oldUrl = f.dataset.imageUrl || null;
        let imageUrl = oldUrl, file = fd.get('image_file'), newPath = null;
        if (file?.size) {
            if (file.size > 5 * 1024 * 1024) {
                loading(btn, false);
                return toast('Post image must be 5 MB or smaller.', 'err');
            }
            const safe = file.name.replace(/[^a-zA-Z0-9._-]/g, '-'), path = `feed-${Date.now()}-${safe}`;
            const up = await sb.storage.from('event-images').upload(path, file, {
                upsert: false
            });
            if (up.error) {
                loading(btn, false);
                return toast(up.error.message, 'err');
            }
            newPath = path;
            imageUrl = sb.storage.from('event-images').getPublicUrl(path).data.publicUrl;
        }
        const id = fd.get('id'), payload = {
            feed_type: fd.get('feed_type') || 'news', title: String(fd.get('title')).trim(), body: String(fd.get('body')).trim(), image_url: imageUrl, published: f.elements.published.checked, updated_at: new Date().toISOString()
        };
        const q = id ? sb.from('announcements').update(payload).eq('id', id) : sb.from('announcements').insert({
            ...payload, created_by: managementProfile.id
        });
        const { error } = await q;
        loading(btn, false);
        if (error) {
            if (newPath)
                await sb.storage.from('event-images').remove([newPath]);
            return toast(error.message, 'err');
        }
        if (newPath && oldUrl) {
            const oldPath = storagePathFromUrl(oldUrl);
            if (oldPath)
                await sb.storage.from('event-images').remove([oldPath]);
        }
        f.reset();
        f.elements.id.value = '';
        f.dataset.imageUrl = '';
        toast('Public feed post saved.');
        loadContent();
    });
    $('#eventForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const f = e.target, fd = new FormData(f), btn = e.submitter;
        loading(btn, true);
        const oldUrl = f.dataset.imageUrl || null;
        let imageUrl = oldUrl, file = fd.get('image_file'), newPath = null;
        if (file?.size) {
            if (file.size > 5 * 1024 * 1024) {
                loading(btn, false);
                return toast('Event image must be 5 MB or smaller.', 'err');
            }
            const safe = file.name.replace(/[^a-zA-Z0-9._-]/g, '-'), path = `${Date.now()}-${safe}`;
            const up = await sb.storage.from('event-images').upload(path, file, {
                upsert: false
            });
            if (up.error) {
                loading(btn, false);
                return toast(up.error.message, 'err');
            }
            newPath = path;
            imageUrl = sb.storage.from('event-images').getPublicUrl(path).data.publicUrl;
        }
        const id = fd.get('id'), payload = {
            title: String(fd.get('title')).trim(), event_date: fd.get('event_date'), event_time: fd.get('event_time') || null, location: String(fd.get('location')).trim(), contact_person: fd.get('contact_person') || null, latitude: fd.get('latitude') || null, longitude: fd.get('longitude') || null, description: fd.get('description') || null, image_url: imageUrl, published: f.elements.published.checked, updated_at: new Date().toISOString()
        };
        const q = id ? sb.from('events').update(payload).eq('id', id) : sb.from('events').insert({
            ...payload, created_by: managementProfile.id
        });
        const { error } = await q;
        loading(btn, false);
        if (error) {
            if (newPath)
                await sb.storage.from('event-images').remove([newPath]);
            return toast(error.message, 'err');
        }
        if (newPath && oldUrl) {
            const oldPath = storagePathFromUrl(oldUrl);
            if (oldPath)
                await sb.storage.from('event-images').remove([oldPath]);
        }
        f.reset();
        f.elements.id.value = '';
        f.dataset.imageUrl = '';
        toast('Event / activity saved.');
        loadContent();
    });
}
