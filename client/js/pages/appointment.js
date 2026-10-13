/** pages/appointment: extracted from the working v22 flows. No build step is required. */
import { $, loading, normalizePhone, toast, today } from '../core/dom.js';
import { sb } from '../core/client.js';
import { showReceipt } from '../components/feedback.js';
export function init() {
    $('#appointmentForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!sb)
            return toast('BloodCare API is unavailable.', 'err');
        const btn = e.submitter;
        const data = Object.fromEntries(new FormData(e.target));
        data.email = String(data.email || '').trim().toLowerCase();
        data.phone = normalizePhone(data.phone);
        const loc = $('#appointmentLocation');
        if (loc?.selectedOptions?.[0])
            data.location = loc.selectedOptions[0].dataset.name || loc.selectedOptions[0].textContent || '';
        if (data.appointment_date < today())
            return toast('Appointment date cannot be in the past.', 'err');
        loading(btn, true);
        const { data: code, error } = await sb.rpc('submit_appointment', {
            p_data: data
        });
        loading(btn, false);
        if (error)
            return toast(error.message, 'err');
        e.target.reset();
        showReceipt($('#appointmentReceipt'), 'Appointment request received', code, 'Save this appointment number. Staff will confirm or update the schedule.');
    });
}
