/** components/navigation: extracted from the working v22 flows. No build step is required. */
import { $, $$, esc } from '../core/dom.js';
import { configured, sb } from '../core/client.js';
import { currentProfile } from '../core/session.js';
const currentPublicPage = location.pathname.split('/').pop() || 'index.html';
function sidebar(profile) {
    const side = $('#managementSidebar');
    if (!side)
        return;
    const here = location.pathname.split('/').pop() || 'staff.html';
    const linkHtml = ([href, label]) => `<a class="${href === here ? 'active' : ''}" href="${href}">${esc(label)}</a>`;
    const staffLinks = [
        ['staff.html', 'Dashboard'], ['staff-donors.html', 'Donors'], ['staff-requests.html', 'Blood Requests'], ['staff-inventory.html', 'Donations & Inventory'], ['staff-appointments.html', 'Appointments'], ['staff-content.html', 'Public Feeds'], ['staff-reports.html', 'Reports']
    ];
    const adminGroups = [
        ['Overview', [
                ['admin.html', 'Dashboard']
            ]],
        ['Management', [
                ['staff-donors.html', 'Donors'],
                ['admin-staff.html', 'Staff Accounts'],
                ['admin-facilities.html', 'Facilities']
            ]],
        ['Operations', [
                ['staff-requests.html', 'Blood Requests'],
                ['staff-inventory.html', 'Donations & Inventory'],
                ['staff-appointments.html', 'Appointments']
            ]],
        ['Communications', [
                ['admin-contacts.html', 'Messages'],
                ['staff-content.html', 'Public Feeds']
            ]],
        ['System & Logs', [
                ['admin-audit.html', 'Audit Log'],
                ['staff-reports.html', 'Reports']
            ]]
    ];
    const navHtml = profile.role === 'admin'
        ? `<nav class="management-nav admin-management-nav">${adminGroups.map(([group, links]) => `<section class="management-nav-group"><div class="management-nav-label">${esc(group)}</div><div class="management-nav-links">${links.map(linkHtml).join('')}</div></section>`).join('')}<div class="management-nav-utility"><a href="index.html?public=1">Public Website</a></div></nav>`
        : `<nav class="management-nav staff-management-nav">${staffLinks.map(linkHtml).join('')}<div class="management-nav-utility"><a href="index.html?public=1">Public Website</a></div></nav>`;
    const primaryFacility = profile.primary_facility?.name || '';
    const roleContext = profile.role === 'admin' ? (primaryFacility ? `Administrator • ${primaryFacility}` : 'Administrator') : (primaryFacility ? `Staff • ${primaryFacility}` : 'Staff • No facility assigned');
    side.innerHTML = `<div class="staff-brand-row"><div class="staff-brand"><img class="brand-logo-icon staff-brand-icon" src="images/favicon.svg" alt="" aria-hidden="true"><span>BloodCare <small>${profile.role === 'admin' ? 'Admin' : 'Staff'}</small></span></div><button class="theme-toggle staff-theme-toggle" type="button" aria-label="Switch color theme" title="Switch theme"><svg class="theme-icon theme-icon-sun" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="3.6" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12 2.5v2M12 19.5v2M4.6 4.6 6 6M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg><svg class="theme-icon theme-icon-moon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 15.1A8.4 8.4 0 0 1 8.9 4a8.5 8.5 0 1 0 11.1 11.1Z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg></button></div>${navHtml}<div class="staff-user"><b class="staff-name">${esc(profile.full_name)}</b><span class="staff-role">${esc(roleContext)}</span><form class="logout-form staff-logout-form" action="/logout" method="post"><button id="logoutBtn" class="staff-signout" type="submit" data-logout>Sign Out</button></form></div>`;
}
let managementProfile = null;
async function guardManagement() {
    if (!document.body.dataset.staff)
        return null;
    if (!sb) {
        location.href = 'login.html';
        return null;
    }
    const p = await currentProfile();
    if (!p) {
        location.href = 'profile.html';
        return null;
    }
    if (document.body.dataset.admin && p.role !== 'admin') {
        location.href = 'staff.html';
        return null;
    }
    managementProfile = p;
    sidebar(p);
    return p;
}
export { guardManagement, managementProfile };
export function init() {
    $('.menu-btn')?.addEventListener('click', e => {
        const n = $('.nav-links');
        if (!n)
            return;
        n.classList.toggle('open');
        e.currentTarget.setAttribute('aria-expanded', n.classList.contains('open') ? 'true' : 'false');
    });
    $$('.nav-dropdown-toggle').forEach(btn => btn.addEventListener('click', e => {
        e.stopPropagation();
        const item = btn.closest('.nav-dropdown');
        if (!item)
            return;
        const willOpen = !item.classList.contains('open');
        $$('.nav-dropdown.open').forEach(x => {
            if (x !== item) {
                x.classList.remove('open');
                x.querySelector('.nav-dropdown-toggle')?.setAttribute('aria-expanded', 'false');
            }
        });
        item.classList.toggle('open', willOpen);
        btn.setAttribute('aria-expanded', willOpen ? 'true' : 'false');
    }));
    document.addEventListener('click', e => {
        if (!e.target.closest('.nav-dropdown'))
            $$('.nav-dropdown.open').forEach(x => {
                x.classList.remove('open');
                x.querySelector('.nav-dropdown-toggle')?.setAttribute('aria-expanded', 'false');
            });
    });
    $$('.nav-links a').forEach(a => a.addEventListener('click', () => {
        const n = $('.nav-links');
        n?.classList.remove('open');
        $('.menu-btn')?.setAttribute('aria-expanded', 'false');
        $$('.nav-dropdown.open').forEach(x => {
            x.classList.remove('open');
            x.querySelector('.nav-dropdown-toggle')?.setAttribute('aria-expanded', 'false');
        });
    }));
    if (currentPublicPage === 'public-feeds.html')
        $('.nav-links a[href="public-feeds.html"]')?.classList.add('active');
    if (currentPublicPage === 'donor-registration.html')
        $('.nav-links a[href="donor-registration.html"]')?.classList.add('active');
    if (currentPublicPage === 'blood-search.html')
        $('.nav-links a[href="blood-search.html"]')?.classList.add('active');
    if (currentPublicPage === 'index.html')
        $('.nav-links a[href="index.html"]')?.classList.add('active');
    if (!configured) {
        const b = $('#configBanner');
        if (b)
            b.hidden = false;
    }
    if (location.protocol === 'file:') {
        const w = document.createElement('div');
        w.className = 'file-protocol-banner';
        w.innerHTML = '<b>Open the website:</b> Use your BloodCare website address instead of opening this HTML file directly.';
        document.body.append(w);
    }
    $$('[data-close-modal]').forEach(b => b.addEventListener('click', () => b.closest('.modal-backdrop').hidden = true));
    $$('.modal-backdrop').forEach(m => m.addEventListener('click', e => {
        if (e.target === m)
            m.hidden = true;
    }));
    document.addEventListener('click', async (e) => {
        const btn = e.target.closest?.('[data-logout]');
        if (!btn)
            return;
        e.preventDefault();
        e.stopPropagation();
        if (btn.dataset.logoutBusy === '1')
            return;
        btn.dataset.logoutBusy = '1';
        const original = btn.textContent;
        btn.textContent = 'Signing out…';
        btn.disabled = true;
        try {
            await fetch('/api/auth/sign-out', {
                method: 'POST', credentials: 'same-origin', cache: 'no-store', headers: {
                    'Cache-Control': 'no-store'
                }
            });
        }
        catch (_err) {
            // The POST /logout fallback below still clears the same cookies.
            try {
                btn.closest('form')?.submit();
                return;
            }
            catch (_ignored) {
            }
        }
        location.replace('/login.html?logged_out=1&_=' + Date.now());
    }, true);
}
