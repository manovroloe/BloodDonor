/** core/routing: extracted from the working v22 flows. No build step is required. */
const query = new URLSearchParams(location.search);
const ACCOUNT_ONLY_PAGES = new Set(['blood-search.html', 'request-blood.html', 'donor-registration.html', 'appointment.html', 'donations.html', 'donation-records.html', 'profile.html', 'inventory.html', 'requests.html', 'user.html']);
function safeAccountNext() {
    const raw = query.get('next');
    if (!raw)
        return '';
    try {
        const u = new URL(raw, location.origin), file = u.pathname.split('/').pop();
        if (u.origin !== location.origin || !ACCOUNT_ONLY_PAGES.has(file))
            return '';
        return u.pathname + u.search + u.hash;
    }
    catch (_e) {
        return '';
    }
}
export { ACCOUNT_ONLY_PAGES, query, safeAccountNext };
