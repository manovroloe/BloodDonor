/** pages/management/dashboard: extracted from the working v22 flows. No build step is required. */
import { $, esc, fmt, fmtTime, localDate, statusLabel, today } from '../../core/dom.js';
import { sb } from '../../core/client.js';
import { managementProfile } from '../../components/navigation.js';
async function loadDashboard() {
    const start = today(), soon = localDate(new Date(Date.now() + 5 * 86400000));
    await sb.rpc('refresh_expired_units');
    const [donors, reqs, appts, reorders, units, moves, dons, pendingDonors, expiring, reserved] = await Promise.all([
        sb.from('donors').select('id', {
            count: 'exact', head: true
        }), sb.from('blood_requests').select('id', {
            count: 'exact', head: true
        }).in('status', ['pending', 'under_review']), sb.from('appointments').select('id', {
            count: 'exact', head: true
        }).eq('appointment_date', start), sb.from('blood_inventory').select('blood_type,reorder_level').order('blood_type'), sb.from('blood_units').select('id,blood_type,status,expiry_date,facility_id').limit(2000), sb.from('inventory_transactions').select('*').order('created_at', {
            ascending: false
        }).limit(8), sb.from('donations').select('donation_date,bags').gte('donation_date', localDate(new Date(Date.now() - 6 * 86400000))).order('donation_date'), sb.from('donors').select('id', {
            count: 'exact', head: true
        }).eq('status', 'pending'), sb.from('blood_units').select('id,blood_type,expiry_date').eq('status', 'available').gte('expiry_date', start).lte('expiry_date', soon), sb.from('blood_units').select('id', {
            count: 'exact', head: true
        }).eq('status', 'reserved')
    ]);
    const available = (units.data || []).filter(x => x.status === 'available' && (!x.expiry_date || x.expiry_date >= start)), counts = {};
    available.forEach(x => counts[x.blood_type] = (counts[x.blood_type] || 0) + 1);
    const inv = (reorders.data || []).map(x => ({
        ...x, bags_available: counts[x.blood_type] || 0
    }));
    $('#donorCount').textContent = donors.count || 0;
    $('#requestCount').textContent = reqs.count || 0;
    $('#appointmentCount').textContent = appts.count || 0;
    $('#availableBags').textContent = available.length;
    const scope = $('#staffFacilityScope');
    if (scope) {
        const fs = managementProfile?.facilities || [], primary = managementProfile?.primary_facility;
        scope.innerHTML = fs.length ? `<b>${esc(primary?.name || fs[0].name)}</b><span>${fs.length === 1 ? 'Primary facility' : `${fs.length} assigned facilities • primary branch shown`}</span>` : '<b>No facility assigned</b><span>Ask an administrator to assign a branch before operating records.</span>';
    }
    $('#dashInventory').innerHTML = inv.map(x => `<div class="blood-chip ${x.bags_available <= x.reorder_level ? 'low-stock' : ''}"><b>${esc(x.blood_type)}</b><span>${x.bags_available} bags${x.bags_available <= x.reorder_level ? ' • LOW' : ''}</span></div>`).join('');
    $('#recentOperations').innerHTML = (moves.data || []).map(x => `<div class="activity-item"><span class="activity-dot"></span><div><b>${esc(statusLabel(x.transaction_type))} • ${esc(x.blood_type)}</b><p>${x.quantity_change > 0 ? '+' : ''}${x.quantity_change} bag(s) — ${esc(x.reason || 'Inventory movement')}</p><small>${fmtTime(x.created_at)}</small></div></div>`).join('') || '<div class="empty">No recent inventory activity for your assigned facility.</div>';
    const low = inv.filter(x => x.bags_available <= x.reorder_level), alerts = [];
    if (reqs.count)
        alerts.push(`<a href="staff-requests.html?status=pending"><b>${reqs.count} pending / under-review request${reqs.count === 1 ? '' : 's'}</b><span>Open branch blood request workflow</span></a>`);
    if (pendingDonors.count)
        alerts.push(`<a href="staff-donors.html?status=pending"><b>${pendingDonors.count} donor${pendingDonors.count === 1 ? '' : 's'} awaiting eligibility review</b><span>Review branch donor records</span></a>`);
    if ((expiring.data || []).length)
        alerts.push(`<a href="staff-inventory.html"><b>${expiring.data.length} unit${expiring.data.length === 1 ? '' : 's'} expiring within 5 days</b><span>Check branch blood units</span></a>`);
    if (low.length)
        alerts.push(`<a href="staff-inventory.html"><b>${low.map(x => x.blood_type).join(', ')} at or below reorder level</b><span>Review branch inventory</span></a>`);
    if (reserved.count)
        alerts.push(`<a href="staff-requests.html?status=approved"><b>${reserved.count} reserved blood unit${reserved.count === 1 ? '' : 's'}</b><span>Prepared for approved requests</span></a>`);
    if ($('#attentionRequired'))
        $('#attentionRequired').innerHTML = alerts.join('') || '<div class="attention-ok">No urgent operational alerts right now.</div>';
    if (window.Chart && $('#donationChart')) {
        const days = [...Array(7)].map((_, i) => localDate(new Date(Date.now() - (6 - i) * 86400000)));
        const sums = Object.fromEntries(days.map(d => [d, 0]));
        (dons.data || []).forEach(x => {
            if (x.donation_date in sums)
                sums[x.donation_date] += Number(x.bags || 0);
        });
        new Chart($('#donationChart'), {
            type: 'line', data: {
                labels: days.map(fmt), datasets: [{
                        label: 'Bags collected', data: days.map(d => sums[d]), tension: .35, fill: true
                    }]
            }, options: {
                responsive: true, maintainAspectRatio: false
            }
        });
    }
}
export { loadDashboard };
