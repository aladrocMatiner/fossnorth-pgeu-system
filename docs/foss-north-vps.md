## Foss-North VPS deployment (nginx + TLS)

Use this when deploying on a VPS with nginx fronting both the app and Keycloak.

1) Copy the VPS env example:
```bash
cp docker-compose/.env.foss-north.example docker-compose/.env
```
This sets `DJANGO_SITE_BASE=https://foss-north.aladroc.io`, allows that host, and points Keycloak to the proxied URL (`/auth/realms/pgeu`).

2) Generate certs (replace with real Let’s Encrypt later):
```bash
./scripts/generate-selfsigned-cert.sh    # writes certs/foss-north.aladroc.io.{crt,key}
```
Place real cert/key in `certs/` with the same filenames when ready.

3) Regenerate Keycloak realm JSON and start:
```bash
./scripts/generate-keycloak-realm.sh
docker compose up -d --build
docker compose up -d nginx          # ensure nginx is running
```

4) Smoke test via nginx:
```bash
HOSTNAME_OVERRIDE=foss-north.aladroc.io TARGET_IP=127.0.0.1 ./scripts/vps-check.sh
```
If testing remotely, set `TARGET_IP` to the VPS IP. The script hits HTTP/HTTPS homepage, login, Keycloak redirect, and OIDC config via `/auth/`.

Notes:
- nginx listens on 80/443 and proxies `/` to the app (web:8000) and `/auth/` to Keycloak (8080).
- For production TLS, replace the self-signed certs in `certs/` and restart nginx.
- Ensure DNS for `foss-north.aladroc.io` points to the VPS and that `DJANGO_ALLOWED_HOSTS` includes it.
