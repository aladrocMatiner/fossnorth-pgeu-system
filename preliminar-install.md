# Preliminary Installation Plan – pgeu-system

## 1. Application Snapshot
- **Project**: [`pgeu-system`](https://github.com/pgeu/pgeu-system) – a Django-based platform for non-profit management plus a full conference administration suite covering registration, invoicing, membership, accounting, news, elections, and reporting.
- **Key Components**: Django web app (`manage.py`), PostgreSQL database, job runner/media poster background workers, optional skins for white-labelling, and integrations for payments, invoicing, and mail.

## 2. Target Environment & Assumptions
- **OS baseline**: Debian/Ubuntu LTS (systemd available); macOS possible for dev with Homebrew.
- **Python**: 3.11 recommended (virtualenv compatible with ≥3.7 per dev docs).
- **Database**: PostgreSQL 13+ reachable without password prompts (`.pgpass` or ident).
- **Web stack**: `uwsgi` (or equivalent WSGI server) fronted by nginx/Apache; HTTPS termination handled by the frontend.
- **File system**: Persistent directories for `media/` uploads, log files, and skin assets; backup strategy defined.
- **Email**: Outbound SMTP account for `SERVER_EMAIL` and notifications; SPF/DKIM handled outside scope.
- **DNS**: Application hostname decided ahead of time to populate `ALLOWED_HOSTS`/`SITEBASE`.

## 3. Prerequisites

### 3.1 System Packages
- Core build/deps: `build-essential`, `python3-dev`, `libffi-dev`, `libssl-dev`, `libjpeg-dev`, `libpng-dev`, `postgresql-client`, `postgresql-server-dev-*`, `virtualenv`, `uwsgi`, `uwsgi-plugin-python3`.
- Fonts for invoices/tickets: `fonts-dejavu-core` (Bullseye+) or `ttf-dejavu`.
- Optional tooling: `psql`, `git`, `nginx`, `certbot`, `redis` (if later needed for caching).

### 3.2 Python Dependencies
- Install via `pip install -r tools/devsetup/dev_requirements.txt` inside the project virtualenv; contains Django 4.2.x, psycopg2-binary, Pillow, Jinja2, ReportLab, JWT, OAuth, etc.
- For production pin versions via a dedicated `requirements.txt` generated from `pip freeze` after testing.

### 3.3 Accounts, Secrets, and Configuration
- PostgreSQL role/database for the app (UTF-8, timezone aware).
- `SECRET_KEY`, `SERVER_EMAIL`, optional `PGAUTH_*` values.
- Decide whether to enable skins (`SYSTEM_SKIN_DIRECTORY`) and any per-skin `skin_local_settings.py`.
- Mail transport, payment processor API keys, and accounting exports scheduled if required.

## 4. Installation Flow

### Step 1 – Fetch Source & Create Virtualenv
1. Ensure `git` is installed (`sudo apt-get install git`).
2. Pick a writable location (e.g., `/opt/pgeu-system` will require `sudo chown` or cloning as root).
3. `git clone https://github.com/pgeu/pgeu-system.git /opt/pgeu-system`.
4. `cd /opt/pgeu-system && virtualenv --python=python3 venv`.
5. `source venv/bin/activate` (or create helper shim similar to `tools/devsetup/dev_setup.sh`).

### Step 2 – Install Python Requirements
1. `pip install --upgrade pip`.
2. `pip install -r tools/devsetup/dev_requirements.txt`.
3. Capture a lock file for production deployment.

### Step 3 – Configure Settings
1. Copy `postgresqleu/local_settings.py.template` to `postgresqleu/local_settings.py`.
2. Populate at minimum:
   ```python
   DEBUG = False
   ALLOWED_HOSTS = ["conference.example.org"]
   SECRET_KEY = "<generated>"
   SERVER_EMAIL = "noreply@example.org"
   SITEBASE = "https://conference.example.org/"
   DATABASES = {
       "default": {
           "ENGINE": "django.db.backends.postgresql_psycopg2",
           "NAME": "pgeu",
           "USER": "pgeu",
           "PASSWORD": "<password>",
           "HOST": "127.0.0.1",
           "PORT": "5432",
       }
   }
   ```
3. Add any optional overrides (mail, payment, caching, skins). Use `pgeu_system_global_settings`/`_override_settings` modules if you prefer system-wide defaults.

### Step 4 – Database Prep & Migrations
1. Create DB/role: `sudo -u postgres createuser -P pgeu` and `createdb -O pgeu pgeu`.
2. Run migrations: `./venv/bin/python manage.py migrate`.
3. Create initial superuser: `./venv/bin/python manage.py createsuperuser`.
4. Load seed data as needed (currencies, countries) via Django admin or management commands.

### Step 5 – Static/Media Assets
- Decide on storage for uploaded files (`MEDIA_ROOT`). Ensure directory ownership matches the uwsgi user.
- Collect static assets if serving via Django: `./venv/bin/python manage.py collectstatic`.
- Configure web server to serve `/media/` and `/static/` either directly or via CDN.

### Step 6 – Application Server
1. Start with uwsgi: create `/etc/uwsgi/apps-available/pgeu.ini` similar to `tools/devsetup/devserver-uwsgi.ini.tmpl` but pointing at `/opt/pgeu-system/venv`.
2. Configure process manager (systemd unit) and socket, e.g.:
   ```
   [Unit]
   Description=pgeu-system uwsgi
   After=network.target

   [Service]
   Environment=DJANGO_SETTINGS_MODULE=postgresqleu.settings
   ExecStart=/usr/bin/uwsgi --ini /etc/uwsgi/apps-enabled/pgeu.ini
   Restart=always

   [Install]
   WantedBy=multi-user.target
   ```
3. Front with nginx/Apache to terminate TLS and forward to uwsgi socket.

### Step 7 – Background Jobs
- Copy `tools/systemd/pgeu_jobs_runner.service` and `pgeu_media_poster.service` to `/etc/systemd/system`, adjust paths/users, and enable them. They drive scheduled jobs and media posting.
- Ensure cron or systemd timers trigger any periodic scripts from `tools/` (mail queue, integrations) if required.

### Step 8 – Verification
- Smoke test via `./venv/bin/python manage.py runserver` on staging first.
- Validate:
  - Admin login
  - Conference creation, registration workflow
  - Invoice generation (requires DejaVu fonts + ReportLab)
  - Mail delivery (check job queue)
  - Background workers running (scheduler UI shows recent runs)
- Capture baseline monitoring/alerting (health endpoint, DB backups, log rotation).

## 5. Open Questions / Follow-ups
1. Confirm payment providers to enable (see `docs/invoices/payment.md`) and secure required API keys/certifications.
2. Decide on authentication strategy (local vs. PG community SSO via `PGAUTH_*`).
3. Determine skinning/theming requirements and whether to vendor a custom template under `template/`.
4. Plan data migration from legacy systems if any (import scripts not covered above).
5. Establish automated deployment/testing (CI pipeline, staging environment) before production go-live.

Once the above decisions are settled, turn this plan into an Ansible playbook or container build to ensure repeatable installs.
