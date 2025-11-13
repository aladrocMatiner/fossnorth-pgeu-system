# fossnorth-pgeu-system
Documentation &amp; goodies from the install of the pgeu-system

## Docker Compose Stack

A self-contained Docker setup lives in `docker-compose/` (see the
dedicated [README](docker-compose/README.md) for full details). The high
level flow is:

### Prerequisites
- Install Docker Engine + Compose plugin (Debian/Ubuntu snippet provided
  in `docker-compose/README.md`).
- Clone this helper repo *and* the upstream
  [`pgeu-system`](https://github.com/pgeu/pgeu-system) project so it sits
  under `./pgeu-system`.

### Bring-up Steps
1. Copy the environment template and edit secrets/hosts:
   ```bash
   cp docker-compose/.env.example docker-compose/.env
   ```
2. Build and start the stack:
   ```bash
   docker compose up --build
   ```
3. Once the containers settle, create an admin user:
   ```bash
   docker compose exec web python manage.py createsuperuser
   ```
4. Open <http://localhost:8000/> (or the hostname from `.env`).

Media uploads, collected static files, and database data are stored in
named Docker volumes (`web-media`, `web-static`, `pg-data`). Run
`docker compose down -v` to tear everything down and delete persisted
state.
