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
   The compose file attaches both services directly to the host
   network, so make sure nothing else is already bound to ports 8000
   (web) or 5432 (database) before running this command.
3. Once the containers settle, create an admin user:
   ```bash
   docker compose exec web python manage.py createsuperuser
   ```
   Follow the prompts for username/email and password—these credentials
   are what you'll use to access `/admin/` and the user dashboard.
4. Open <http://localhost:8000/> (or the hostname from `.env`) and log
   in with the account created in the previous step.

### Verify Repository Structure
Before running `docker compose`, double-check that the checkout has the
expected layout (the `pgeu-system` upstream repo must sit next to the
compose helpers). A quick sanity check:

```bash
tree -L 1
```

should at least show:

```
├── docker-compose
├── docker-compose.yml
├── pgeu-system
├── README.md
└── ...
```

If any of these are missing, revisit the clone instructions in
`docker-compose/README.md` before continuing.

Media uploads, collected static files, and database data are stored in
named Docker volumes (`web-media`, `web-static`, `pg-data`). Run
`docker compose down -v` to tear everything down and delete persisted
state.

### Troubleshooting
- **`SyntaxError: multiple exception types must be parenthesized` from `Cryptodome/Util/_raw_api.py`**  
  This means Docker reused an image layer with the legacy
  `pycryptodomex` (3.6.x) package. Rebuild without cache so the newer
  dependency versions install:
  ```bash
  docker compose down
  docker compose build --no-cache
  docker compose up -d
  ```
