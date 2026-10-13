# v23 - Clean architecture and website deployment preparation

Source baseline: `BloodCareSystem_SearchFlowRefined_v22.zip`.

## Preserved

All original API routes; existing public/account/staff/admin page URLs; HTML layout except the JavaScript-module tag and theme filename; CSS and image content; v22 Donation Map proportions/buttons; facility-aware automatic blood search; service CTAs without arrows; and Supabase schema/upgrade scripts. The existing profile PDF renderer is unchanged.

## Reorganized

The 1,005-line backend entry module was separated into configuration/security, payload schemas, API routes, services, and Supabase repository modules. The former all-in-one page script was split into 31 feature/shared modules and a small browser-native entry point. The active `preview-theme.css` was renamed to `theme.css`, not removed.

Duplicate server requirements and Python cache files were removed. A single exact production dependency lock, one-time setup commands, install-free normal startup commands, an offline check command, deployment examples, and current documentation were added.

## Behavior/safety corrections

Rejected refresh sessions now actually clear cookies on the returned error response. A temporary upstream refresh outage does not deliberately wipe the existing cookies. Concurrent frontend requests share a refresh attempt. Disabled staff accounts are still rejected; sign-in now fails closed when account access cannot be verified. A successful API result with `data: null` remains null instead of becoming an unexpected wrapper object.

Admin operations continue to verify admin identity before privileged Auth calls, and failed staff provisioning attempts a compensating Auth-user cleanup. Email errors are not exposed as raw SMTP exception text. Uploads have a configurable size limit (default 10 MB), storage paths reject traversal, and malformed pagination ranges are rejected.

Same-origin protection, host validation, production configuration checks, privacy-conscious logs, cache controls, and separate health/readiness routes were added. Pages do not instruct ordinary visitors to start FastAPI. Unrelated pages no longer load the homepage inventory/feed unnecessarily.

## Not performed

No live database migration, reset, backup, or data change; no real SMTP message; no domain/DNS/hosting change; no replacement of the database or framework; no clinical-rule change; and no native application build. See VERIFICATION.md for the actual test scope and remaining deployment checks.
