# Verification record - v23

Date: 2026-10-10. Source baseline: `BloodCareSystem_SearchFlowRefined_v22.zip`.

This record distinguishes local evidence from deployment checks that have not been performed. It is not a security certification or a claim that live hosting is already configured.

## Passed automated checks

Run `check.bat` or `./check.sh` after setup to repeat the included checks.

- Python syntax validation for the server, launch scripts, and tests.
- JavaScript syntax validation for every browser script/module using Node.js 22.16.0.
- **78 Python unit/integration-style tests passed** under Python 3.13.5 on Linux. The tests use FastAPI's test client, HTTPX mock transport, and synthetic accounts/data; they do not access the live database or send email.
- Original API routes retained; the new readiness route is additive.
- Original HTML markup retained except for the module script tag and theme stylesheet filename; original CSS/images and both Supabase SQL files match recorded v22 fingerprints.
- Original profile-PDF rendering functions retained by AST comparison. The PDF HTTP endpoint is tested with mocked PDF bytes, not a visual review of a newly rendered PDF.
- Local static asset links and native JavaScript module imports resolve.
- Authentication cookies, refresh failure behavior, logout, same-origin write checks, protected-page redirects, admin authorization, Supabase key separation, allowlists, pagination, upload constraints, and sanitized upstream failures are covered by mock-service tests.
- Setup tests confirm that an unchanged prepared environment skips package installation, normal startup never installs dependencies, explicit refresh installs the locked set, existing `.env` files are preserved, and a foreign/incomplete environment is not silently reused.
- Installed Linux runtime dependency versions match `requirements.txt`. Shell launchers pass shell syntax checks. Compose YAML parses successfully.

## Passed offline browser checks

Chromium executed the actual application modules against synthetic API responses at widths of 1440 and 390 CSS pixels. Due to this environment's browser navigation restrictions, HTML was loaded in memory, native ES modules used Blob URLs/import maps, and navigation destinations were asserted without navigating a public or local website.

**31 page/viewport smoke checks passed:** 26 non-legacy-redirect pages at desktop width, plus five phone-width checks. No unexpected JavaScript exceptions or horizontal page overflow were recorded. Role-specific pages used synthetic user, staff, or admin sessions.

The checks specifically confirmed that the Blood On-Lines quick form carries A+ and a selected facility into the Find Blood destination, and that Find Blood initializes the same selections and automatically displays the matching fixture result.

Seven v22/v23 screenshot pairs were compared. Six were pixel-identical. The phone-width Find Blood pair had 0.0388% changed pixels, confined to the same 'Change Facility' text bounds; image dimensions and visible content/layout were unchanged. This is not a guarantee of identical rendering on every browser or device.

The detailed browser results are in `docs/browser-verification.json`. External map frames were unavailable in this offline test, and Chart.js behavior was stubbed. These checks do not verify live map loading or actual chart rendering.

## Not verified in this environment

- A fresh online installation of the lock file: package-index DNS/network access was unavailable. The tests ran with matching dependencies already installed. Setup behavior was additionally tested with intercepted installer calls, not real downloads.
- Docker image build, Compose startup, or the systemd example: Docker is not installed here. Configuration is supplied for deployment testing, not marked as a successfully deployed image.
- Native Windows/macOS execution of their launchers; actual Android, iOS, Safari, or Firefox devices/browsers.
- Live Supabase authentication, deployed RPC/schema compatibility, real RLS enforcement, production inventory mutations, SMTP delivery, external maps/charts, and real PDF output.
- Public DNS, HTTPS certificates, reverse-proxy forwarding, uptime, backups, or hosting-provider configuration.

## Before switching a public website

Keep v22 and its private configuration for rollback. Use a staging deployment and controlled test accounts to verify actual login/refresh, facility restrictions, requests, appointments, inventory, email, PDF output, maps, and mobile browsers. Do not reset the database or rerun SQL for this cleanup. Review credentials previously shared outside the trusted team and rotate them where necessary.

## Packaging checks

The release packaging script excludes `.env`, local environment variants, installed environments, caches, logs, and prior ZIPs. The project source was checked against the populated key/password values from the supplied v22 `.env`; no matching secret values were found in the new deliverable. Only `.env.example` placeholders are included. Archive integrity and an extracted-copy test run are checked during final packaging.
