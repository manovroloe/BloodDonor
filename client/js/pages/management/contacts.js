/** pages/management/contacts: extracted from the working v22 flows. No build step is required. */
import { apiRequest, sb } from '../../core/client.js';
import { $, $$, PAGE_SIZE, esc, excerpt, fmtTime, loading, statusClass, statusLabel, toast } from '../../core/dom.js';
import { renderPager } from '../../components/feedback.js';
let contactRows = [], contactPage = 1, contactEmailReady = false;
async function loadAdminContacts() {
    const [messages, cfg] = await Promise.all([sb.from('contact_messages').select('*').order('created_at', {
            ascending: false
        }).limit(1000), apiRequest ? apiRequest('/api/admin/config') : Promise.resolve({
            data: null, error: null
        })]);
    if (messages.error)
        return toast(messages.error.message, 'err');
    contactRows = messages.data || [];
    contactEmailReady = !!cfg.data?.email_reply_ready;
    const notice = $('#contactEmailConfigNotice');
    if (notice) {
        notice.className = 'stock-notice ' + (contactEmailReady ? 'stock-ok' : '');
        notice.textContent = contactEmailReady ? 'Outgoing email is configured. Admin replies will be delivered to the sender email address.' : 'Messages are being received, but email replies need SMTP settings in the server .env. For Gmail, use smtp.gmail.com with a Gmail App Password.';
    }
    renderAdminContacts();
}
function renderAdminContacts() {
    const term = String($('#contactAdminSearch')?.value || '').trim().toLowerCase(), status = $('#contactAdminStatus')?.value || '', sender = $('#contactAdminSender')?.value || '';
    const rows = contactRows.filter(x => (!status || x.status === status) && (!sender || (sender === 'user' ? !!x.auth_user_id : !x.auth_user_id)) && (!term || [x.full_name, x.email, x.phone, x.inquiry_type, x.message, x.source_page].join(' ').toLowerCase().includes(term)));
    const pages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
    contactPage = Math.min(contactPage, pages);
    const visible = rows.slice((contactPage - 1) * PAGE_SIZE, contactPage * PAGE_SIZE);
    const body = $('#contactMessageBody');
    if (!body)
        return;
    body.innerHTML = visible.map(x => `<tr class="${x.status === 'new' ? 'contact-row-new' : ''}"><td><b>${esc(x.full_name)}</b><br><small>${esc(x.email)}</small><br><span class="tag">${x.auth_user_id ? 'Registered User' : 'Visitor'}</span></td><td>${esc(statusLabel(x.inquiry_type))}<br><small>${esc(x.phone || '—')}</small></td><td><div class="contact-message-preview">${esc(excerpt(x.message, 120))}</div></td><td>${fmtTime(x.created_at)}</td><td><span class="status ${statusClass(x.status)}">${esc(statusLabel(x.status))}</span></td><td><button class="small-btn" data-contact-view="${x.id}">${x.status === 'new' ? 'Open' : 'View'}</button></td></tr>`).join('') || '<tr><td colspan="6">No contact messages match this filter.</td></tr>';
    $$('[data-contact-view]').forEach(b => b.onclick = () => openAdminContact(b.dataset.contactView));
    renderPager('#contactAdminPagination', contactPage, pages, rows.length, p => {
        contactPage = p;
        renderAdminContacts();
    });
}
async function openAdminContact(id) {
    const x = contactRows.find(v => v.id === id);
    if (!x)
        return;
    const modal = $('#contactDetailModal'), host = $('#contactDetailContent');
    if (!modal || !host)
        return;
    if (x.status === 'new') {
        const { error } = await sb.from('contact_messages').update({
            status: 'read', updated_at: new Date().toISOString()
        }).eq('id', x.id);
        if (!error) {
            x.status = 'read';
            renderAdminContacts();
        }
    }
    const linked = !!x.auth_user_id;
    host.innerHTML = `<div class="modal-title"><span class="tag">${linked ? 'Registered User' : 'Visitor'}</span><h2 id="contactDetailTitle">${esc(x.full_name)}</h2><p>${esc(x.email)} • ${esc(x.phone || 'No phone')}</p></div><div class="contact-admin-meta"><div><small>Inquiry</small><b>${esc(statusLabel(x.inquiry_type))}</b></div><div><small>Received</small><b>${esc(fmtTime(x.created_at))}</b></div><div><small>Source</small><b>${esc(x.source_page || 'Public contact form')}</b></div><div><small>Sender Type</small><b>${linked ? 'Registered User' : 'Visitor / Guest'}</b></div></div><div class="contact-admin-message"><small>MESSAGE</small><p>${esc(x.message)}</p></div>${x.reply_message ? `<div class="contact-admin-reply-history"><small>LAST ADMIN REPLY</small><p>${esc(x.reply_message)}</p><span>${esc(fmtTime(x.replied_at))}${x.email_delivery_status ? ' • Email ' + esc(statusLabel(x.email_delivery_status)) : ''}</span></div>` : ''}<div class="form-grid contact-admin-controls"><div class="form-group"><label>Status</label><select id="contactDetailStatus">${['new', 'read', 'replied', 'resolved'].map(s => `<option value="${s}" ${x.status === s ? 'selected' : ''}>${statusLabel(s)}</option>`).join('')}</select></div><div class="form-group contact-status-action"><label>&nbsp;</label><button id="saveContactStatus" class="secondary-btn" type="button">Save Status</button></div></div><form id="contactReplyForm" class="contact-reply-form"><div class="form-group"><label>Reply by Email</label><textarea name="message" rows="6" minlength="2" maxlength="5000" required placeholder="Write the BloodCare reply that will be emailed to ${esc(x.email)}..."></textarea><small>${linked ? 'This account-linked message will be replied to using the account email address.' : 'This visitor has no BloodCare inbox. The reply will be sent to the email/Gmail address they entered.'}</small></div><button class="primary-btn" type="submit" ${contactEmailReady ? '' : 'disabled'}>${contactEmailReady ? 'Send Email Reply' : 'Email Not Configured'}</button></form>`;
    modal.hidden = false;
    $('#saveContactStatus')?.addEventListener('click', async (e) => {
        const status = $('#contactDetailStatus')?.value || 'read', btn = e.currentTarget;
        loading(btn, true);
        const { error } = await sb.from('contact_messages').update({
            status, updated_at: new Date().toISOString()
        }).eq('id', x.id);
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        x.status = status;
        toast('Message status updated.');
        renderAdminContacts();
    });
    $('#contactReplyForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!apiRequest)
            return toast('BloodCare API is unavailable.', 'err');
        const btn = e.submitter, values = Object.fromEntries(new FormData(e.target));
        loading(btn, true);
        const { error } = await apiRequest(`/api/admin/contact/${encodeURIComponent(x.id)}/reply`, 'POST', values);
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        toast('Reply sent to ' + x.email + '.');
        modal.hidden = true;
        await loadAdminContacts();
    });
}
export { loadAdminContacts };
export function init() {
    $('#contactAdminSearch')?.addEventListener('input', () => {
        contactPage = 1;
        renderAdminContacts();
    });
    $('#contactAdminStatus')?.addEventListener('change', () => {
        contactPage = 1;
        renderAdminContacts();
    });
    $('#contactAdminSender')?.addEventListener('change', () => {
        contactPage = 1;
        renderAdminContacts();
    });
    $('#refreshContacts')?.addEventListener('click', loadAdminContacts);
}
