/** core/session: extracted from the working v22 flows. No build step is required. */
import { sb } from './client.js';
import { toast } from './dom.js';
async function signOutAndRedirect(btn = null) {
    if (btn) {
        btn.disabled = true;
        btn.dataset.logoutText = btn.textContent;
        btn.textContent = 'Signing out…';
    }
    if (!sb) {
        location.replace('login.html?logged_out=1');
        return;
    }
    const { error } = await sb.auth.signOut();
    if (error) {
        if (btn) {
            btn.disabled = false;
            btn.textContent = btn.dataset.logoutText || 'Sign Out';
        }
        toast(error.message || 'Unable to sign out. Please try again.', 'err');
        return;
    }
    // Replace the current history entry so Back does not reopen an authenticated page.
    location.replace('login.html?logged_out=1');
}
async function currentUser() {
    if (!sb)
        return null;
    const { data: sessionData } = await sb.auth.getSession();
    if (sessionData?.session?.user)
        return sessionData.session.user;
    const { data } = await sb.auth.getUser();
    return data.user || null;
}
async function currentProfile() {
    const u = await currentUser();
    if (!u)
        return null;
    const { data, error } = await sb.from('staff_profiles').select('id,email,full_name,role,active,created_at').eq('id', u.id).maybeSingle();
    if (error || !data || !data.active)
        return null;
    if (!data.email)
        data.email = u.email;
    const facilities = await sb.rpc('my_staff_facilities');
    data.facilities = facilities.error ? [] : (facilities.data || []);
    data.primary_facility = data.facilities.find(x => x.is_primary) || data.facilities[0] || null;
    return data;
}
export { currentProfile, currentUser };
