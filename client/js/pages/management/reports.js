/** pages/management/reports: extracted from the working v22 flows. No build step is required. */
import { $, esc, fmt, fmtTime, localDate, statusLabel, toast, today } from '../../core/dom.js';
import { sb } from '../../core/client.js';
let reportExportRows = [];
async function runReport() {
    if (!$('#reportBody'))
        return;
    const from = $('#reportFrom')?.value || null, to = $('#reportTo')?.value || null;
    let dq = sb.from('donations').select('*').order('donation_date', {
        ascending: false
    });
    let rq = sb.from('blood_releases').select('*').order('released_at', {
        ascending: false
    });
    let donorQ = sb.from('donors').select('id,created_at');
    let apptQ = sb.from('appointments').select('id,status,appointment_date');
    let reqQ = sb.from('blood_requests').select('id,status,updated_at');
    let moveQ = sb.from('inventory_transactions').select('*').order('created_at', {
        ascending: false
    });
    if (from) {
        dq = dq.gte('donation_date', from);
        rq = rq.gte('released_at', `${from}T00:00:00`);
        donorQ = donorQ.gte('created_at', `${from}T00:00:00`);
        apptQ = apptQ.gte('appointment_date', from);
        reqQ = reqQ.gte('updated_at', `${from}T00:00:00`);
        moveQ = moveQ.gte('created_at', `${from}T00:00:00`);
    }
    if (to) {
        dq = dq.lte('donation_date', to);
        rq = rq.lte('released_at', `${to}T23:59:59`);
        donorQ = donorQ.lte('created_at', `${to}T23:59:59`);
        apptQ = apptQ.lte('appointment_date', to);
        reqQ = reqQ.lte('updated_at', `${to}T23:59:59`);
        moveQ = moveQ.lte('created_at', `${to}T23:59:59`);
    }
    const [dons, rels, donors, appts, reqs, moves, reorders, units] = await Promise.all([dq, rq, donorQ, apptQ, reqQ, moveQ, sb.from('blood_inventory').select('blood_type,reorder_level'), sb.from('blood_units').select('blood_type,status').eq('status', 'available')]);
    const dr = dons.data || [], mr = moves.data || [], availableCounts = {};
    (units.data || []).forEach(x => availableCounts[x.blood_type] = (availableCounts[x.blood_type] || 0) + 1);
    $('#reportDonations').textContent = dr.length;
    $('#reportCollected').textContent = dr.reduce((a, x) => a + Number(x.bags || 0), 0);
    $('#reportReleased').textContent = (rels.data || []).reduce((a, x) => a + Number(x.bags || 0), 0);
    $('#reportCompletedRequests').textContent = (reqs.data || []).filter(x => x.status === 'completed').length;
    $('#reportDonors').textContent = (donors.data || []).length;
    $('#reportAppointments').textContent = (appts.data || []).length;
    $('#reportCancelled').textContent = (appts.data || []).filter(x => ['cancelled', 'no_show'].includes(x.status)).length;
    $('#reportLowStock').textContent = (reorders.data || []).filter(x => (availableCounts[x.blood_type] || 0) <= x.reorder_level).length;
    $('#reportBody').innerHTML = dr.map(x => `<tr><td>${fmt(x.donation_date)}</td><td>${esc(x.donation_code)}</td><td>${esc(x.donor_code)}</td><td>${esc(x.blood_type)}</td><td>${x.bags}</td><td>${esc(x.donation_site)}</td></tr>`).join('') || '<tr><td colspan="6">No donation records for this period.</td></tr>';
    $('#reportMovementBody').innerHTML = mr.map(x => `<tr><td>${fmtTime(x.created_at)}</td><td>${esc(x.blood_type)}</td><td>${esc(statusLabel(x.transaction_type))}</td><td>${x.quantity_change > 0 ? '+' : ''}${x.quantity_change}</td><td>${x.balance_after}</td><td>${esc(x.reason || '—')}</td></tr>`).join('') || '<tr><td colspan="6">No inventory movement for this period.</td></tr>';
    reportExportRows = [['Record Type', 'Date', 'Reference', 'Blood Type', 'Quantity', 'Details'], ...dr.map(x => ['Donation', x.donation_date, x.donation_code, x.blood_type, x.bags, x.donation_site]), ...mr.map(x => ['Inventory Movement', x.created_at, x.transaction_type, x.blood_type, x.quantity_change, x.reason || ''])];
}
export { runReport };
export function init() {
    $('#reportFilter')?.addEventListener('submit', e => {
        e.preventDefault();
        runReport();
    });
    $('#reportPreset')?.addEventListener('change', e => {
        const d = new Date();
        let from;
        if (e.target.value === 'day')
            from = d;
        else if (e.target.value === 'month')
            from = new Date(d.getFullYear(), d.getMonth(), 1);
        else if (e.target.value === 'year')
            from = new Date(d.getFullYear(), 0, 1);
        else
            return;
        $('#reportFrom').value = localDate(from);
        $('#reportTo').value = today();
        runReport();
    });
    $('#exportCsv')?.addEventListener('click', () => {
        if (reportExportRows.length < 2)
            return toast('No report data to export.', 'err');
        const csv = reportExportRows.map(r => r.map(v => `"${String(v ?? '').replaceAll('"', '""')}"`).join(',')).join('\n');
        const blob = new Blob([csv], {
            type: 'text/csv'
        }), a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = `bloodcare-report-${today()}.csv`;
        a.click();
        URL.revokeObjectURL(a.href);
    });
}
