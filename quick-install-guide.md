# Quick Install Guide (Docker + SSO)

Goal: get a working pgeu-system with Single Sign-On (Keycloak) in minutes.

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

3) Copy env and enable SSO (fast path)
```bash
cp docker-compose/.env.example docker-compose/.env
cat >> docker-compose/.env <<'EOF'
DJANGO_SITE_BASE=http://localhost:8000
DJANGO_ENABLE_OAUTH_AUTH=true
KEYCLOAK_BASE_URL=http://127.0.0.1:8080/realms/pgeu
KEYCLOAK_CLIENT_ID=pgeu
KEYCLOAK_CLIENT_SECRET=
EOF
```

4) One command: build + start everything
```bash
make sso-up
```
(First run may take several minutes.)

5) Quick checks (optional)
```bash
./scripts/curl-check.sh     # basic pages load
./scripts/sso-check.sh      # SSO link + redirect OK
```

6) Auto login test (demo user)
```bash
./scripts/sso-login.sh      # logs in fossnorth / fossnorth
```
Expect: "[OK] Authenticated access confirmed."

7) Use in browser
- Site: http://localhost:8000
- Login: http://localhost:8000/accounts/login/ → Keycloak button
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
- redirect_uri error: ensure `DJANGO_SITE_BASE=http://localhost:8000` (no trailing slash), then:
  ```bash
  ./scripts/generate-keycloak-realm.sh
  make sso-up
  ```
- Ports busy: free ports 8000 (web), 5432 (db), 8080 (Keycloak).
- First start slow: give Keycloak ~1–2 minutes on initial run.

