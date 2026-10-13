/** BloodCare website entry point. Native browser modules; no npm/build step. */
import { init as initializeClient } from './core/client.js';
import { init as initializeSharedFeedback } from './components/feedback.js';
import { init as initializeNavigation } from './components/navigation.js';
import { init as initializeAuthentication } from './pages/authentication.js';
import { init as initializeDonorRegistration } from './pages/donor-registration.js';
import { init as initializeBloodRequest } from './pages/blood-request.js';
import { init as initializeAppointment } from './pages/appointment.js';
import { init as initializeTracking } from './pages/tracking.js';
import { init as initializeDonationRecords } from './pages/donation-records.js';
import { init as initializeBloodSearch } from './pages/blood-search.js';
import { init as initializeHome } from './pages/home.js';
import { init as initializePublicFeeds } from './pages/public-feeds.js';
import { init as initializeMap } from './pages/map.js';
import { init as initializeFacilityContext } from './components/facility-context.js';
import { init as initializeAdminDashboardEvents } from './pages/management/admin-dashboard.js';
import { init as initializeDonorManagementEvents } from './pages/management/donors.js';
import { init as initializeRequestManagementEvents } from './pages/management/requests.js';
import { init as initializeAppointmentManagementEvents } from './pages/management/appointments.js';
import { init as initializeInventoryEvents } from './pages/management/inventory.js';
import { init as initializeContentEvents } from './pages/management/content.js';
import { init as initializeReportEvents } from './pages/management/reports.js';
import { init as initializeStaffAccountEvents } from './pages/management/staff.js';
import { init as initializeContactManagementEvents } from './pages/management/contacts.js';
import { init as initializeAuditEvents } from './pages/management/audit.js';
import { init as initializeFacilityManagementEvents } from './pages/management/facilities.js';
import { init as initializeProfile } from './pages/profile.js';
import { init as initializeManagementData } from './core/management.js';
import { toast } from './core/dom.js';
function startFeature(initialize) {
    try {
        initialize();
    }
    catch (error) {
        console.error("BloodCare page initialization failed", error);
        toast("This page could not finish loading. Please refresh and try again.", "err");
    }
}
startFeature(initializeClient); // core/client
startFeature(initializeSharedFeedback); // components/feedback
startFeature(initializeNavigation); // components/navigation
startFeature(initializeAuthentication); // pages/authentication
startFeature(initializeDonorRegistration); // pages/donor-registration
startFeature(initializeBloodRequest); // pages/blood-request
startFeature(initializeAppointment); // pages/appointment
startFeature(initializeTracking); // pages/tracking
startFeature(initializeDonationRecords); // pages/donation-records
startFeature(initializeBloodSearch); // pages/blood-search
startFeature(initializeHome); // pages/home
startFeature(initializePublicFeeds); // pages/public-feeds
startFeature(initializeMap); // pages/map
startFeature(initializeFacilityContext); // components/facility-context
startFeature(initializeAdminDashboardEvents); // pages/management/admin-dashboard
startFeature(initializeDonorManagementEvents); // pages/management/donors
startFeature(initializeRequestManagementEvents); // pages/management/requests
startFeature(initializeAppointmentManagementEvents); // pages/management/appointments
startFeature(initializeInventoryEvents); // pages/management/inventory
startFeature(initializeContentEvents); // pages/management/content
startFeature(initializeReportEvents); // pages/management/reports
startFeature(initializeStaffAccountEvents); // pages/management/staff
startFeature(initializeContactManagementEvents); // pages/management/contacts
startFeature(initializeAuditEvents); // pages/management/audit
startFeature(initializeFacilityManagementEvents); // pages/management/facilities
startFeature(initializeProfile); // pages/profile
startFeature(initializeManagementData); // core/management
window.dispatchEvent(new Event("bloodcare:ready"));
