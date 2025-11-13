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
2. **Git** to clone both this helper repository and the upstream
   [`pgeu-system`](https://github.com/pgeu/pgeu-system) source:
   ```bash
   sudo apt-get update
   sudo apt-get install -y git
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
git clone https://github.com/aladroc/fossnorth-pgeu-system.git
cd fossnorth-pgeu-system
git clone https://github.com/pgeu/pgeu-system.git
```

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

3. **Create an admin user** (run once after the containers come up):
   ```bash
   docker compose exec web python manage.py createsuperuser
   ```

4. **Access the site** at <http://localhost:8000/> (or the hostname you
   configured).

## 4. Persistence & Customizations
- `pg-data`: PostgreSQL data directory (`docker volume ls`).
- `web-media`: uploaded files (`/app/media` inside the container).
- `web-static`: collected static assets.
- To reset everything: `docker compose down -v`.
- To run alternative commands (e.g., tests) reuse the web container:
  `docker compose run --rm web ./manage.py test`.

## 5. Background Jobs & Production Notes
- The compose stack only runs the main web process. For full parity with
  production you may add services based on `tools/systemd/pgeu_jobs_runner.service`
  and `pgeu_media_poster.service`.
- Always disable `DJANGO_DEBUG` and enable secure cookies before exposing
  the stack to the internet behind a real reverse proxy.
