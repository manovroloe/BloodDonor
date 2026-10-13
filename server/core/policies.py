ALLOWED_TABLES = {
    "announcements", "appointments", "audit_logs", "blood_inventory", "blood_releases",
    "blood_requests", "blood_units", "contact_messages", "donations", "donors", "events", "facilities",
    "inventory_transactions", "staff_profiles", "staff_facility_assignments", "system_settings",
}
ALLOWED_RPCS = {
    "adjust_inventory", "adjust_facility_inventory", "admin_link_staff_by_email", "admin_move_blood_stock", "admin_set_staff_facilities", "admin_update_staff",
    "my_bloodcare_profile", "my_staff_facilities", "public_donation_history", "public_facility_inventory", "public_inventory",
    "public_stats", "public_track", "record_donation_v3", "refresh_expired_units", "register_donor",
    "donor_screening_policy", "update_my_profile_name",
    "release_blood_request", "set_blood_unit_facility", "set_donor_status", "set_my_donor_facility", "submit_appointment",
    "submit_blood_request", "update_appointment_status", "update_donor_contact", "update_request_status",
}
ALLOWED_BUCKETS = {"event-images"}


