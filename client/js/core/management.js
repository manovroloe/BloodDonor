/** core/management: extracted from the working v22 flows. No build step is required. */
import { guardManagement } from '../components/navigation.js';
import { loadDashboard } from '../pages/management/dashboard.js';
import { loadAdminDashboard } from '../pages/management/admin-dashboard.js';
import { loadDonors } from '../pages/management/donors.js';
import { loadRequests } from '../pages/management/requests.js';
import { loadAppointments } from '../pages/management/appointments.js';
import { loadDonationAppointments, loadInventory, loadManagementFacilities } from '../pages/management/inventory.js';
import { loadContent } from '../pages/management/content.js';
import { runReport } from '../pages/management/reports.js';
import { loadStaffAccounts } from '../pages/management/staff.js';
import { loadAdminContacts } from '../pages/management/contacts.js';
import { loadAudit } from '../pages/management/audit.js';
import { loadFacilities } from '../pages/management/facilities.js';
async function initManagement() {
    const p = await guardManagement();
    if (!p)
        return;
    const page = document.body.dataset.page;
    if (page === 'dashboard')
        await loadDashboard();
    if (page === 'admin-dashboard')
        await loadAdminDashboard();
    if (page === 'donors')
        await loadDonors();
    if (page === 'requests')
        await loadRequests();
    if (page === 'appointments')
        await loadAppointments();
    if (page === 'inventory') {
        await loadManagementFacilities();
        await Promise.all([loadInventory(), loadDonationAppointments()]);
    }
    if (page === 'content')
        await loadContent();
    if (page === 'reports')
        await runReport();
    if (page === 'admin-staff')
        await loadStaffAccounts();
    if (page === 'admin-contacts')
        await loadAdminContacts();
    if (page === 'admin-audit')
        await loadAudit();
    if (page === 'admin-facilities')
        await loadFacilities();
}
export function init() {
    initManagement();
}
