# Quick Install Guide (Docker + SSO)

Goal: get a working pgeu-system with Single Sign-On (Keycloak) behind nginx in minutes (local/test or VPS).

0) Requirements
- Ubuntu/Debian system with Internet
- Git and curl installed (step 1 installs Docker)

1) Install Docker (Ubuntu/Debian)
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER" && newgrp docker
```

2) Clone repos and patch upstream deps
```bash
git clone https://github.com/aladrocMatiner/fossnorth-pgeu-system.git
 cd fossnorth-pgeu-system
 git clone https://github.com/pgeu/pgeu-system.git
 ./scripts/patch-upstream.sh
```

3) Configure hosts (fast path)
```bash
./scripts/setup-fossnorth.sh
```
- Defaults: app `https://new.foss-north.se`, Keycloak `https://auth.foss-north.se`.
- Prompts let you change hosts, toggle TLS verification, and optionally generate self-signed certs for both hosts.
- Non-interactive example:
  ```bash
  NON_INTERACTIVE=1 APP_DOMAIN=new.foss-north.se KEYCLOAK_DOMAIN=auth.foss-north.se KEYCLOAK_SSL_VERIFY=true GENERATE_CERTS=0 ./scripts/setup-fossnorth.sh
  ```
If you only need local testing on 127.0.0.1, you can still `cp docker-compose/.env.example docker-compose/.env` and keep `DJANGO_SITE_BASE=http://localhost:8000`.

4) Generate realm and start
```bash
./scripts/generate-keycloak-realm.sh
docker compose up -d --build
docker compose up -d nginx
```
(If you already ran `setup-fossnorth.sh`, the realm was regenerated there—running it again is safe.)

5) Quick checks
```bash
./scripts/curl-check.sh          # basic pages load (direct to app)
./scripts/sso-check.sh           # SSO link + redirect OK
HOSTNAME_OVERRIDE=<your-host> KC_HOST_OVERRIDE=<keycloak-host> TARGET_IP=<ip> ./scripts/vps-check.sh   # via nginx/proxy
```

6) Auto login test (demo user)
```bash
./scripts/sso-login.sh      # logs in fossnorth / fossnorth
```
Expect: "[OK] Authenticated access confirmed."
Notes: Keycloak login is built-in; the dev realm imported at startup already
contains the demo user above.

7) Use in browser (adjust host/https)
- Site: http(s)://<your-host>/
- Login: http(s)://<your-host>/accounts/login/ → Keycloak button
- Demo SSO user: fossnorth / fossnorth
- Create local admin (optional):
  ```bash
  docker compose exec web python manage.py createsuperuser
  ```

8) Stop / Rebuild
```bash
make sso-down           # stop containers (keep data)
make sso-rebuild        # full rebuild and restart
```

Troubleshooting (30‑second fixes)
- redirect_uri error: ensure `DJANGO_SITE_BASE` matches the URL you visit (no trailing slash) and regenerate:
  ```bash
  ./scripts/generate-keycloak-realm.sh
  make sso-up
  ```
- Self-signed Keycloak: set `KEYCLOAK_SSL_VERIFY=false` (test only) or use a trusted cert and set it to true.
- Ports busy: free ports 80/443 (nginx), 8000 (web), 5432 (db), 8080 (Keycloak).
- First start slow: give Keycloak ~1–2 minutes on initial run.
