/** core/client: extracted from the working v22 flows. No build step is required. */
const sb = window.BloodCareAPI?.createClient?.() || null;
const apiRequest = window.BloodCareAPI?.request || null;
const configured = !!sb;
export { apiRequest, configured, sb };
export function init() {
    window.BloodCare = {
        sb, configured
    };
}
