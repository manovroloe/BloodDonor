/** components/feedback: extracted from the working v22 flows. No build step is required. */
import { $, $$, PAGE_SIZE, esc, fmt, fmtTime, loading, statusLabel, toast } from '../core/dom.js';
function renderPager(sel, page, pages, total, onPage) {
    const host = $(sel);
    if (!host)
        return;
    pages = Math.max(1, pages);
    page = Math.min(Math.max(1, page), pages);
    if (total <= PAGE_SIZE) {
        host.innerHTML = total ? `<span>Showing ${total} record${total === 1 ? '' : 's'}</span>` : '';
        return;
    }
    const prev = Math.max(1, page - 1), next = Math.min(pages, page + 1);
    host.innerHTML = `<span>Page ${page} of ${pages} • ${total} records</span><div><button class="small-btn pager-btn" data-page="${prev}" ${page === 1 ? 'disabled' : ''}>Previous</button><button class="small-btn pager-btn" data-page="${next}" ${page === pages ? 'disabled' : ''}>Next</button></div>`;
    $$('[data-page]', host).forEach(b => b.onclick = () => onPage(Number(b.dataset.page)));
}
function trackingTimeline(kind, status) {
    const steps = kind === 'Blood Request' ? ['pending', 'under_review', 'approved', 'ready_for_release', 'completed'] : kind === 'Appointment' ? ['requested', 'confirmed', 'checked_in', 'completed'] : ['pending', 'eligible'];
    const terminal = ['rejected', 'cancelled', 'no_show', 'deferred', 'inactive'].includes(status);
    let hit = false;
    return `<div class="status-timeline">${steps.map(step => {
        if (step === status)
            hit = true;
        const idx = steps.indexOf(step), cur = steps.indexOf(status), done = !terminal && cur >= idx;
        return `<div class="timeline-step ${done ? 'done' : ''} ${step === status ? 'current' : ''}"><span>${done ? '✓' : '○'}</span><b>${esc(statusLabel(step))}</b></div>`;
    }).join('')}${terminal ? `<div class="timeline-step terminal current"><span>!</span><b>${esc(statusLabel(status))}</b></div>` : ''}</div>`;
}
function storagePathFromUrl(url) {
    const text = String(url || '');
    for (const marker of ['/storage/v1/object/public/event-images/', '/api/storage/public/event-images/']) {
        const i = text.indexOf(marker);
        if (i >= 0)
            return decodeURIComponent(text.slice(i + marker.length));
    }
    return null;
}
function labelResponsiveTables() {
    document.querySelectorAll('.staff-layout .table-wrap table, .profile-table table').forEach(table => {
        const heads = [...table.querySelectorAll('thead th')].map(x => x.textContent.trim());
        table.querySelectorAll('tbody tr').forEach(row => [...row.children].forEach((cell, i) => {
            if (cell.tagName === 'TD' && heads[i])
                cell.dataset.label = heads[i];
        }));
    });
}
let tableLabelQueued = false;
const tableObserver = new MutationObserver(() => {
    if (tableLabelQueued)
        return;
    tableLabelQueued = true;
    requestAnimationFrame(() => {
        tableLabelQueued = false;
        labelResponsiveTables();
    });
});
async function confirmAction(title, message, confirmLabel = 'Confirm') {
    return new Promise(resolve => {
        const wrap = document.createElement('div');
        wrap.className = 'modal-backdrop bc-confirm';
        wrap.innerHTML = `<div class="modal-card confirm-card"><h2>${esc(title)}</h2><p class="muted-text">${esc(message)}</p><div class="modal-action-row"><button type="button" class="secondary-btn" data-no>Cancel</button><button type="button" class="primary-btn danger-confirm" data-yes>${esc(confirmLabel)}</button></div></div>`;
        document.body.append(wrap);
        const done = v => {
            wrap.remove();
            resolve(v);
        };
        wrap.querySelector('[data-no]').onclick = () => done(false);
        wrap.querySelector('[data-yes]').onclick = () => done(true);
        wrap.addEventListener('click', e => {
            if (e.target === wrap)
                done(false);
        });
    });
}
async function promptAction(title, label, initial = '', confirmLabel = 'Save') {
    return new Promise(resolve => {
        const wrap = document.createElement('div');
        wrap.className = 'modal-backdrop bc-confirm';
        wrap.innerHTML = `<div class="modal-card confirm-card"><h2>${esc(title)}</h2><div class="form-group"><label>${esc(label)}</label><textarea data-value rows=4>${esc(initial || '')}</textarea></div><div class="modal-action-row"><button type="button" class="secondary-btn" data-no>Cancel</button><button type="button" class="primary-btn" data-yes>${esc(confirmLabel)}</button></div></div>`;
        document.body.append(wrap);
        const field = wrap.querySelector('[data-value]');
        field.focus();
        const done = v => {
            wrap.remove();
            resolve(v);
        };
        wrap.querySelector('[data-no]').onclick = () => done(null);
        wrap.querySelector('[data-yes]').onclick = () => done(field.value);
        wrap.addEventListener('click', e => {
            if (e.target === wrap)
                done(null);
        });
    });
}
function showReceipt(el, title, code, text, track = true) {
    if (!el)
        return;
    el.hidden = false;
    el.innerHTML = `<b>${esc(title)}</b><strong>${esc(code)}</strong><p>${esc(text)}</p>${track ? '<a href="track-status.html" class="secondary-btn">Track Status</a>' : ''}`;
    el.scrollIntoView({
        behavior: 'smooth', block: 'center'
    });
}
export { confirmAction, promptAction, renderPager, showReceipt, storagePathFromUrl, trackingTimeline };
export function init() {
    window.BC = {
        $, $$, esc, fmt, fmtTime, toast, loading
    };
    tableObserver.observe(document.body, {
        subtree: true, childList: true
    });
    labelResponsiveTables();
}
