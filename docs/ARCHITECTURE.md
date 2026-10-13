# Architecture

## One website, not a distributed rewrite

The browser requests pages and `/api/*` from the same origin. FastAPI serves `client/` and connects to the existing Supabase project. This is a modular single-server application, not a set of microservices and not an executable desktop application.

The architecture is pragmatic rather than a claim of perfectly framework-independent domain code: services use the existing HTTP error contract, and the main data rules remain in the existing Supabase functions and Row Level Security policies.

## Backend responsibilities

`server/main.py` composes the application, registers routes, starts/stops the shared outbound HTTP client, and mounts the frontend. It does not contain blood-request workflows or execute schema changes.

`server/api/` is the HTTP boundary. Routes obtain a repository through FastAPI dependency injection, read cookies and validated request objects, call a service, and return the existing response format. Cookie creation and deletion remain at this boundary.

`server/services/` contains the coordinated workflows. Auth handles sessions and active staff checks. Admin verifies an active admin profile before using privileged Auth operations. Database preserves allowlisted tables/RPCs. Contact handles public submissions; email is an explicit server-side adapter. Profile coordinates the existing PDF renderer. Storage validates bucket/path and upload-size limits.

`server/repositories/supabase.py` owns Supabase endpoints and authorization headers. Ordinary table queries, RPCs, and storage writes use the public API key plus the current user's access token. Privileged keys are used only for administrator-managed Auth operations after permission checks. New-style publishable/secret API key aliases are supported without treating those keys as JWT bearer tokens.

`server/schemas/` preserves the existing JSON payloads and validates inputs. Range checks now reject a reversed range and ranges larger than the existing 5,000-record limit.

`server/core/` owns settings, authorization policy allowlists, cookie helpers, and browser-boundary middleware. Real settings stay in the root `.env` or the host's environment/secret store. Server environment values override `.env`. A `*_FILE` value can point to a mounted secret file.

## Frontend responsibilities

`client/js/api.js` is the compatibility API client used by the existing UI. It provides the query-builder, auth, storage, and RPC interface; it contains no Supabase credentials. Mutating requests carry `X-BloodCare-Request: 1`; session refresh is shared across concurrent requests. A legitimate `data: null` response stays null, and network errors do not tell visitors to install or start a server.

`client/js/app.js` initializes the modules. `core/` contains client access, DOM helpers, routing/session helpers, and management startup. `components/` contains shared navigation, dialogs/table labels, and facility context. `pages/` contains public page behavior and `pages/management/` contains staff/admin behavior. Imports/exports make dependencies explicit; shared profile state is an object rather than an illegally reassigned module import.

`ui.js` keeps theme switching, contact-modal behavior, and the existing presentation interactions. CSS is retained byte-for-byte. The active theme is now named `theme.css`, not `preview-theme.css`. The existing cascade is deliberately retained; deleting apparent duplicate rules without redesign-specific regression work would risk changing the working appearance.

## Security and operational boundaries

The page-cookie gate is only a navigation convenience. It does not establish that a token is valid and never substitutes for API authorization or Supabase RLS. Admin endpoints independently resolve the user and verify an active admin role. Do not disable RLS or replace ordinary user operations with a service-role key.

State-changing requests must match the website origin. When Origin/Referer are absent, a custom request header is required; cross-origin CORS is not enabled. Native same-origin logout forms remain supported. Cross-site navigation to the legacy GET logout route is rejected when identified by browser fetch metadata/Origin. For strict deployments, prefer the POST logout flow; the legacy GET route remains for v22 compatibility.

API and account responses are not cached. HTML, JavaScript, and CSS revalidate, reducing stale-code problems after deployment. Baseline headers prevent object embedding and framing; a complete script/style CSP is deliberately not asserted because v22 still has inline code, a chart CDN, and map content.

This is not a complete security certification. Before real-world use, review RLS policies, abuse/rate controls, file-content handling, retention/backups, monitoring, and role/facility permissions with the actual deployment and test accounts. No eligibility rules, clinical logic, or medical policy was changed by this cleanup.

## Database preservation

No DDL, seed, clear, or migration is performed by the application or launch scripts. Existing table/RPC allowlists and response paths are retained. The two SQL files are preserved as reference/installation material. The deployment must continue using your existing correctly configured Supabase project.
