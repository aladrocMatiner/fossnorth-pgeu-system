# Docker Compose Environment

This directory contains everything needed to run **pgeu-system** with
Docker Compose: a Python/Django container, a PostgreSQL database, and an
entrypoint that generates `local_settings.py`, runs migrations, and
collects static assets automatically.

## 1. Prerequisites

1. **Docker Engine + Compose plugin** (convenience script for Debian/Ubuntu):
   ```bash
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker "$USER"
   newgrp docker
   ```
   (Use the official docs for other distributions or if you need a locked-down install.)
2. **Git + curl** to clone the repositories and fetch the Docker install script:
   ```bash
   sudo apt-get update
   sudo apt-get install -y git curl
   ```

## 2. Directory Layout

```
fossnorth-pgeu-system/
├── docker-compose/        # Dockerfile, entrypoint, env template
├── docker-compose.yml     # Compose definition
└── pgeu-system/           # Upstream Django project (git clone)
```

Clone the helper repo, then fetch the application next to it:

```bash
git clone https://github.com/aladrocMatiner/fossnorth-pgeu-system.git
cd fossnorth-pgeu-system
git clone https://github.com/pgeu/pgeu-system.git
./scripts/patch-upstream.sh
tree -L 1
```

Make sure `docker-compose/`, `docker-compose.yml`, and `pgeu-system/`
all exist at the top level before proceeding. Missing directories mean
the helper files and upstream sources are not aligned correctly yet.

## 3. Configuration Flow

1. **Copy the env template and edit secrets/hosts**:
   ```bash
   cp docker-compose/.env.example docker-compose/.env
   $EDITOR docker-compose/.env
   ```
   - `POSTGRES_*`: database name/user/password seeded into the Postgres
     container and Django settings.
   - `DJANGO_SECRET_KEY`: set to a random string (fallback auto-generates one).
   - `DJANGO_ALLOWED_HOSTS`: comma-separated list for Django (e.g.,
     `localhost,conf.example.org`).
   - `DJANGO_SITE_BASE`: full base URL (e.g., `https://conf.example.org/`).
   - Toggle debug/redirect/cookie flags as needed.

2. **Build and start the stack**:
   ```bash
   docker compose up --build
   ```
   - `web` container installs dependencies, auto-migrates, collects
     static files, and serves Django on port 8000.
   - `db` container runs PostgreSQL 15 with data persisted in the
     `pg-data` volume.
   - Both services run on the host network, so keep ports 8000 (web)
     and 5432 (database) free on the host OS.

3. **Create an admin user** (run once after the containers come up):
   ```bash
   docker compose exec web python manage.py createsuperuser
   ```
   The command will prompt for username, email, and password. Use this
   account for logging in at `/admin/` and the main site.

4. **Access the site** at <http://localhost:8000/> (or the hostname you
   configured).

## 4. Preflight Script
Before building, you can run:
```bash
./scripts/preflight-check.sh
```
This validates that `docker`/`docker compose` are available, the repo
structure is correct, `.env` exists with `DJANGO_DEBUG=false`, and the
critical dependency pins (e.g., `pycryptodomex==3.19.1`) are present. A
non-zero exit means something needs fixing before `docker compose up`.

## 5. First-Run Checklist
1. Visit <http://localhost:8000/> and sign in with the superuser you
   just created.
2. Browse to `/admin/` to confirm admin access works.
3. If you see unexpected errors, check `docker compose logs web` before
   restarting the stack.

### Common Errors
- **`SyntaxError: multiple exception types must be parenthesized`** during
  startup indicates the old `pycryptodomex` wheel is still cached. Rebuild
  from scratch:
  ```bash
  docker compose down
  docker compose build --no-cache
  docker compose up -d
  ```
  After that, `docker compose exec web pip show pycryptodomex` should
  report `3.19.1`.

## 6. Persistence & Customizations
- `pg-data`: PostgreSQL data directory (`docker volume ls`).
- `web-media`: uploaded files (`/app/media` inside the container).
- `web-static`: collected static assets.
- To reset everything: `docker compose down -v`.
- To run alternative commands (e.g., tests) reuse the web container:
  `docker compose run --rm web ./manage.py test`.

## 7. Background Jobs & Production Notes
- The compose stack only runs the main web process. For full parity with
  production you may add services based on `tools/systemd/pgeu_jobs_runner.service`
  and `pgeu_media_poster.service`.
- Always disable `DJANGO_DEBUG` and enable secure cookies before exposing
  the stack to the internet behind a real reverse proxy.
