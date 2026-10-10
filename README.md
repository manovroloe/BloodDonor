# BloodCare website - v23

A cleanup of `BloodCareSystem_SearchFlowRefined_v22.zip`, retaining the working website design, page URLs, API routes, and Supabase database scripts. It remains HTML/CSS/JavaScript + FastAPI + Supabase.

## Start here

Keep your old v22 folder. Extract this release into a new folder, then copy your private **root `.env`** from v22 next to `run.py`. Real credentials are intentionally absent from this ZIP.

On the **developer/server computer**, with Python 3.12 or 3.13 installed:

```bat
setup.bat
start.bat
```

Run `setup.bat` once. On later starts, run only `start.bat`. The default address is `http://127.0.0.1:8000` (or your configured port). Keep the terminal open for local development; Ctrl+C stops the website server.

On macOS/Linux:

```sh
chmod +x setup.sh start.sh check.sh
./setup.sh
./start.sh
```

Setup creates `.venv` and installs the exact dependency versions in `requirements.txt`. It does not overwrite an existing `.env`. When the lock file is unchanged and dependencies are already present, running setup again skips installation. `setup.bat --refresh` / `./setup.sh --refresh` explicitly rechecks/reinstalls the pinned set when needed.

**Website visitors do none of this.** After deployment, they open your HTTPS website link on a supported browser. Their phones and computers do not install Python or project requirements.

## What changed

The backend is split into API routes, request schemas, services, and a Supabase repository. The former all-in-one page script is split into browser-native modules with explicit imports. There is no npm install or frontend compilation step.

Startup and setup are separate. Production configuration includes secure cookies, same-origin write checks, restricted hosts, safe error messages, request IDs, and separate liveness/readiness endpoints. Docker, Compose, and optional native-server examples are included.

`preview-theme.css` was renamed to `theme.css`; the CSS content was not changed. Existing v22 markup is preserved except for that reference and the module script tag. The 45%/55% Donation Map, facility-aware Find Blood search, four service CTAs, and responsive styles are retained.

**No database migration is required.** The original `supabase/schema.sql` and `supabase/upgrade.sql` are unchanged and are never executed at startup. Do not rerun them on an existing working database for this release.

## Project layout

```text
client/          Existing pages and assets; js/core, js/components, js/pages
server/api/      HTTP routes and dependency injection
server/schemas/  Validated request payloads
server/services/ Authentication, admin, contacts, profile, storage, data workflows
server/repositories/  Supabase transport and query translation
server/core/     Configuration, sessions, policies, request middleware
supabase/        Existing SQL reference scripts, unchanged
scripts/         One-time setup, normal startup, checks, safe source packaging
tests/           Offline API and preservation tests; synthetic data only
deploy/          Optional reverse-proxy and native-service examples
docs/            Architecture, hosting, testing, and change notes
```

## Check the release

```bat
check.bat
```

Or `./check.sh`. The checks require only the installed runtime Python packages and Python's standard-library test runner. Node.js, when already installed, adds a JavaScript syntax check; Node is not required to serve or use BloodCare.

`tests/v22_baseline.json` records the supplied v22 routes and file fingerprints so accidental visual/schema changes fail tests. Update that baseline only when intentionally changing those files in a later feature release.

## Host the website

See [Deployment](docs/DEPLOYMENT.md). Build dependencies belong to the server build, not to the normal startup command. The provided Docker build installs them once into the image; container restarts reuse that image.

See [Architecture](docs/ARCHITECTURE.md), [Change notes](docs/CHANGELOG.md), and [Verification](docs/VERIFICATION.md). The ZIP is source plus deployment configuration, **not a claim that the website is already hosted or that live Supabase/SMTP access has been tested**.
