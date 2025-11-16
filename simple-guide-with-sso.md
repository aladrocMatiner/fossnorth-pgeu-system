# Simple Guide: Run pgeu-system with Docker + Keycloak SSO

This guide is written for non‑technical users. Copy/paste the commands as shown. It sets up Docker, builds the containers, starts everything, and tests login via Single Sign‑On (SSO) using an included Keycloak server.

Requirements
- A recent computer with Internet access
- Linux (Ubuntu/Debian). For macOS/Windows use Docker Desktop and run similar commands in a terminal.

1) Install Docker (Ubuntu/Debian)
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
newgrp docker
```

2) Get the project code
```bash
git clone https://github.com/aladrocMatiner/fossnorth-pgeu-system.git
cd fossnorth-pgeu-system
git clone https://github.com/pgeu/pgeu-system.git
./scripts/patch-upstream.sh
```

3) Create basic settings
```bash
cp docker-compose/.env.example docker-compose/.env
```

4) (Optional) Enable SSO (recommended)
Open the file `docker-compose/.env` in any text editor and ensure these lines exist (copy/paste if missing):
```
DJANGO_SITE_BASE=http://localhost:8000
DJANGO_ENABLE_OAUTH_AUTH=true
KEYCLOAK_BASE_URL=http://127.0.0.1:8080/realms/pgeu
KEYCLOAK_CLIENT_ID=pgeu
KEYCLOAK_CLIENT_SECRET=
```

5) Start everything (build + run)
This one command checks your setup, prepares SSO, builds, and starts all containers.
```bash
make sso-up
```
Notes:
- The first build can take several minutes (downloads images and Python packages).
- It starts 3 services: web (the site), db (database), keycloak (SSO server).

6) Watch logs (optional)
```bash
make sso-logs
```
Wait until you see messages like:
- Keycloak: “Listening on: http://0.0.0.0:8080 …”
- Web: “Starting development server at http://0.0.0.0:8000/”

7) Quick checks
```bash
./scripts/curl-check.sh     # basic pages reachable
./scripts/sso-check.sh      # SSO link + redirect looks correct
```
Both should finish with “completed successfully” or “OK” lines.
If `/accounts/login/keycloak/` ever shows a 500, re-run
`./scripts/generate-keycloak-realm.sh` and `make sso-up` to refresh the
Keycloak realm; the handler is built-in, no extra plugins needed.

8) Test full login automatically (SSO)
This script signs in with the demo Keycloak user (username: fossnorth, password: fossnorth) and confirms you’re logged in.
```bash
./scripts/sso-login.sh
```
Expected: it ends with “[OK] Authenticated access confirmed.”

9) Use it in your browser
- Open the site: http://localhost:8000
- Click “Your account” or go to http://localhost:8000/accounts/login/ and choose the Keycloak button
- Demo user: fossnorth / fossnorth
- (Optional admin) Create a local admin user for the site admin pages:
  ```bash
  docker compose exec web python manage.py createsuperuser
  ```

10) Stop or rebuild later
- Stop (keep data):
  ```bash
  make sso-down
  ```
- Rebuild from scratch:
  ```bash
  make sso-rebuild
  ```

Troubleshooting (common fixes)
- Port in use: Make sure ports 8000 (web), 5432 (db), 8080 (Keycloak) are free.
- “Invalid parameter: redirect_uri”: Run
  ```bash
  ./scripts/generate-keycloak-realm.sh
  make sso-up
  ```
  and ensure `DJANGO_SITE_BASE` in `.env` has no trailing slash (use `http://localhost:8000`).
- SSO health warnings: Give Keycloak 1–2 minutes on first start; then re-run `./scripts/sso-check.sh`.

Where things run
- Website: http://localhost:8000
- Keycloak Admin (SSO): http://127.0.0.1:8080 (admin / admin)

You’re done! If you need help or want this guide for macOS/Windows, ask and we’ll tailor it.
