# Deploying BloodCare as a website

## Before publishing

Keep the working v22 release and the current private server configuration. Establish a database backup/recovery procedure through your Supabase administration process before any future database work. This cleanup does not create a database backup and does not require a schema change.

Use the same existing Supabase project. Set its keys on the server only, through a private root `.env`, the hosting provider's environment settings, or mounted secret files. Do not place `.env` in `client/`, publish it in Git, copy it into an image, or include it in a shared ZIP. Rotate real credentials that were shared outside the trusted team.

Configure the public release explicitly:

```dotenv
APP_ENV=production
PUBLIC_ORIGIN=https://your-real-bloodcare-domain.example
COOKIE_SECURE=true
ALLOWED_HOSTS=your-real-bloodcare-domain.example,localhost,127.0.0.1
SUPABASE_URL=https://YOUR_PROJECT_ID.supabase.co
SUPABASE_ANON_KEY=YOUR_EXISTING_PUBLIC_KEY
```

Use real values before deployment. Keep your existing server-only service-role/secret key for staff login administration and SMTP settings for email replies. They are optional for base startup but required for those features. The old environment variable names continue to work.

Production startup fails early when required Supabase configuration, HTTPS origin, or secure-cookie settings are missing. That does not create an HTTPS certificate: HTTPS must be provided by your hosting platform, existing proxy, or tunnel.

## Option A: Docker on the server

Docker/Compose are installed on the **server**, not on visitor devices. From the project root, after preparing `.env`:

```sh
docker compose build
docker compose up -d
```

The image build installs the locked dependencies. Ordinary starts/restarts do not:

```sh
docker compose restart website
docker compose logs --tail=100 website
```

The host port is loopback-only by default: `127.0.0.1:8000`. Put your existing HTTPS reverse proxy or tunnel in front of it. `deploy/Caddyfile.example` illustrates a same-host proxy, but it is not installed or activated automatically. Keep one canonical hostname equal to `PUBLIC_ORIGIN`; redirect alternate hostnames at the proxy.

The provided Compose service runs as a non-root user, drops Linux capabilities, uses a read-only application filesystem with temporary storage, rotates container logs, and restarts after process failure. Its healthcheck tests process liveness; an unhealthy healthcheck alone is not an automatic Docker restart mechanism. Monitor database readiness separately.

The Dockerfile defaults to the Python 3.13 slim image. For a release-controlled production build, override `PYTHON_IMAGE` with an approved image digest and retain the resulting BloodCare image. The default base-image tag can move to a new patch release; it is not a bit-for-bit reproducible base-image pin.

To run a local Docker preview over HTTP instead, use `APP_ENV=development`, `COOKIE_SECURE=false`, and leave `PUBLIC_ORIGIN` blank in the local `.env`. Do not use that configuration as the public production deployment.

## Option B: Native Python hosting

On the server, create the environment once with `setup.sh` or `setup.bat`. Your platform's build hook can instead create a virtual environment and run:

```sh
python -m pip install --no-deps -r requirements.txt
python -m pip check
```

Its start command should be only:

```sh
python run.py
```

Use the virtual-environment interpreter or the hosting platform's prepared runtime. Never put `pip install` into the start command. Set `HOST=0.0.0.0` only when needed by your hosting network; restrict backend access appropriately. `PORT` is configurable. `WORKERS` defaults to one.

`deploy/bloodcare.service.example` is an optional native Linux service template. Review its installation path and account before enabling it. Do not run both a native service and Docker on the same port.

## Existing reverse proxy or tunnel

Keep the domain you already use. Forward `/` and `/api/*` to the same FastAPI process. Preserve the original Host header and forward the website over HTTPS. `PUBLIC_ORIGIN` must exactly match the public scheme/hostname/port used by browsers.

Trust forwarded headers only from your actual proxy addresses using `FORWARDED_ALLOW_IPS`. Do not use `*` on an exposed server. The default trusts localhost; a container-network proxy may have a different address. An explicit public origin also keeps same-origin validation independent of an internal HTTP connection.

Review your existing Supabase Site URL and permitted redirects against the real production domain. Do not invent or change project credentials to match this example.

## Health and acceptance checks

`GET /api/health` verifies that the process runs. `GET /api/ready` makes a read-only request to the existing facilities table using the public key, reporting 200 when reachable and 503 when unavailable. Results are cached for ten seconds. Readiness does not test every RPC, RLS rule, email delivery, or full schema compatibility.

Verify the staged site through its HTTPS address with controlled test accounts: public browsing; login/logout/refresh; staff versus admin restrictions; facility assignments; A+ plus Facility A quick search and automatic results; requests and appointments; image operations; PDF download; and a controlled contact-reply email. Check desktop and actual mobile browsers. Avoid touching real patient records just to test deployment.

The map provider and versioned Chart.js CDN are retained from v22. They, Supabase, and SMTP need their normal network access. Dependency packaging does not make the website offline.

## Updates and rollback

Build and test a new release separately. Retain the currently running image before switching. With the current default image name, an example is:

```sh
docker image tag bloodcare:23.0.0 bloodcare:rollback-before-update
```

Then build/start the new release and check liveness, readiness, and the real workflows. To roll back, stop the faulty release and redeploy the saved image or the intact v22 source with its private configuration. Do not delete/recreate the Supabase database. No schema rollback is needed for this cleanup because SQL was not changed.

Deploy complete releases rather than copying only selected JS files; the frontend now has module dependencies. Keep HTML/JS/CSS revalidation enabled and perform a hard refresh on any browser that still has an old release cached.

## Documentation references

The deployment choices were checked against the official FastAPI container/deployment guidance, pip's repeatable-install guidance, Docker Compose secret guidance, and Supabase API-key guidance. These are implementation references, not evidence that this specific deployment has passed a live integration test.

- https://fastapi.tiangolo.com/deployment/docker/
- https://fastapi.tiangolo.com/deployment/concepts/
- https://pip.pypa.io/en/stable/topics/repeatable-installs/
- https://docs.docker.com/compose/how-tos/use-secrets/
- https://supabase.com/docs/guides/getting-started/api-keys
