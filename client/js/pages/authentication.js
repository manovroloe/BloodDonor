/** pages/authentication: extracted from the working v22 flows. No build step is required. */
import { $, $$, loading, toast } from '../core/dom.js';
import { sb } from '../core/client.js';
import { currentProfile, currentUser } from '../core/session.js';
import { query, safeAccountNext } from '../core/routing.js';
async function redirectLoggedInFromLogin() {
    if (!$('#loginForm') || query.get('reauth') === '1')
        return;
    const u = await currentUser();
    if (!u)
        return;
    const p = await currentProfile();
    location.replace(p ? (p.role === 'admin' ? 'admin.html' : 'staff.html') : (safeAccountNext() || 'profile.html'));
}
export function init() {
    $('#loginForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!sb)
            return toast('BloodCare API is unavailable.', 'err');
        const btn = e.submitter;
        loading(btn, true);
        const f = new FormData(e.target);
        const { error } = await sb.auth.signInWithPassword({
            email: String(f.get('email')).trim().toLowerCase(), password: String(f.get('password'))
        });
        if (error) {
            loading(btn, false);
            return toast(error.message, 'err');
        }
        const p = await currentProfile();
        loading(btn, false);
        location.href = p ? (p.role === 'admin' ? 'admin.html' : 'staff.html') : (safeAccountNext() || 'profile.html');
    });
    $('#signupForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!sb)
            return toast('BloodCare API is unavailable.', 'err');
        const btn = e.submitter, f = new FormData(e.target), email = String(f.get('email')).trim().toLowerCase(), password = String(f.get('password')), fullName = String(f.get('full_name')).trim(), msg = $('#authMessage');
        if (password.length < 8)
            return toast('Password must be at least 8 characters.', 'err');
        loading(btn, true);
        const { data, error } = await sb.auth.signUp({
            email, password, options: {
                data: {
                    full_name: fullName
                }
            }
        });
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        if (data.session) {
            location.href = safeAccountNext() || 'profile.html';
            return;
        }
        if (msg)
            msg.textContent = 'Account created. Check your email if Supabase email confirmation is enabled, then log in.';
        e.target.reset();
    });
    $$('[data-auth-tab]').forEach(tab => tab.addEventListener('click', () => {
        const login = tab.dataset.authTab === 'login';
        $$('[data-auth-tab]').forEach(x => x.classList.toggle('active', x === tab));
        if ($('#loginForm'))
            $('#loginForm').hidden = !login;
        if ($('#signupForm'))
            $('#signupForm').hidden = login;
    }));
    redirectLoggedInFromLogin();
}
