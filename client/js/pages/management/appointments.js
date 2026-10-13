/** pages/management/appointments: extracted from the working v22 flows. No build step is required. */
import { sb } from '../../core/client.js';
import { $, $$, PAGE_SIZE, esc, fmt, statusClass, statusLabel, toast } from '../../core/dom.js';
import { query } from '../../core/routing.js';
import { promptAction, renderPager } from '../../components/feedback.js';
let appointmentRows = [], appointmentPage = 1;
async function loadAppointments() {
    const { data, error } = await sb.from('appointments').select('*,donors(donor_code)').order('appointment_date', {
        ascending: true
    });
    if (error)
        return toast(error.message, 'err');
    appointmentRows = data || [];
    const preset = query.get('status');
    if (preset && $('#appointmentStatusFilter'))
        $('#appointmentStatusFilter').value = preset;
    renderAppointments();
}
function renderAppointments() {
    const q = ($('#appointmentSearch')?.value || '').toLowerCase(), st = $('#appointmentStatusFilter')?.value || '';
    const rows = appointmentRows.filter(x => (!st || x.status === st) && (!q || [x.appointment_code, x.full_name, x.location, x.blood_type, x.donors?.donor_code].join(' ').toLowerCase().includes(q)));
    const pages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
    appointmentPage = Math.min(appointmentPage, pages);
    const visible = rows.slice((appointmentPage - 1) * PAGE_SIZE, appointmentPage * PAGE_SIZE);
    $('#staffAppointmentBody').innerHTML = visible.map(x => `<tr><td><b>${esc(x.appointment_code)}</b>${x.donors?.donor_code ? `<br><small>${esc(x.donors.donor_code)}</small>` : ''}</td><td>${esc(x.full_name)}<br><small>${esc(x.email)}</small></td><td><span class="pill">${esc(x.blood_type)}</span></td><td>${fmt(x.appointment_date)}<br><small>${esc(String(x.appointment_time || '').slice(0, 5))}</small></td><td>${esc(x.location)}</td><td><span class="status ${statusClass(x.status)}">${esc(statusLabel(x.status))}</span></td><td><div class="action-stack"><select data-appt-status="${x.id}">${['requested', 'confirmed', 'checked_in', 'completed', 'cancelled', 'no_show'].map(s => `<option value="${s}" ${s === x.status ? 'selected' : ''}>${statusLabel(s)}</option>`).join('')}</select>${x.status === 'checked_in' && x.donors?.donor_code ? `<a class="small-btn link-btn" href="staff-inventory.html?appointment=${x.id}&donor=${encodeURIComponent(x.donors.donor_code)}">Record Donation</a>` : ''}</div></td></tr>`).join('') || '<tr><td colspan="7">No appointments match this filter.</td></tr>';
    $$('[data-appt-status]').forEach(sel => sel.onchange = async () => {
        const current = appointmentRows.find(x => x.id === sel.dataset.apptStatus), notes = await promptAction('Update Appointment', 'Staff note (optional)', current?.staff_notes || '', 'Update Status');
        if (notes === null) {
            sel.value = current.status;
            return;
        }
        const { error } = await sb.rpc('update_appointment_status', {
            p_appointment_id: sel.dataset.apptStatus, p_status: sel.value, p_notes: notes || null
        });
        error ? toast(error.message, 'err') : (toast('Appointment updated.'), loadAppointments());
    });
    renderPager('#appointmentPagination', appointmentPage, pages, rows.length, p => {
        appointmentPage = p;
        renderAppointments();
    });
}
export { loadAppointments };
export function init() {
    $('#appointmentSearch')?.addEventListener('input', () => {
        appointmentPage = 1;
        renderAppointments();
    });
    $('#appointmentStatusFilter')?.addEventListener('change', () => {
        appointmentPage = 1;
        renderAppointments();
    });
}
