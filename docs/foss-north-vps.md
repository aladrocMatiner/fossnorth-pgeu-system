## Foss-North VPS deployment (nginx + TLS)

Use this when deploying on a VPS with nginx fronting both the app and Keycloak (separate hosts).

1) Run the guided setup (creates/updates `.env` and nginx):
```bash
./scripts/setup-fossnorth.sh
```
- Defaults: app `new.foss-north.se`, Keycloak `auth.foss-north.se`.
- Prompts let you flip TLS verification (set false for self-signed) and choose whether to auto-generate test certs.
- Non-interactive example:
  ```bash
  NON_INTERACTIVE=1 APP_DOMAIN=new.foss-north.se KEYCLOAK_DOMAIN=auth.foss-north.se KEYCLOAK_SSL_VERIFY=true GENERATE_CERTS=0 ./scripts/setup-fossnorth.sh
  ```

2) Generate certs (or place real Let’s Encrypt certs):
```bash
./scripts/generate-selfsigned-cert.sh new.foss-north.se
./scripts/generate-selfsigned-cert.sh auth.foss-north.se
```
Place real cert/key in `certs/` with the same filenames when ready.

3) Regenerate Keycloak realm JSON and start (the setup script already ran the realm generation; re-running is safe):
```bash
./scripts/generate-keycloak-realm.sh
docker compose up -d --build
docker compose up -d nginx          # ensure nginx is running
```

4) Smoke test via nginx:
```bash
HOSTNAME_OVERRIDE=new.foss-north.se KC_HOST_OVERRIDE=auth.foss-north.se TARGET_IP=127.0.0.1 ./scripts/vps-check.sh
```
If testing remotely, set `TARGET_IP` to the VPS IP. The script hits HTTP/HTTPS homepage, login, Keycloak redirect, and the Keycloak OIDC config on the auth host.

Helpers for domains (non-interactive)
- For new.foss-north.se + auth.foss-north.se (production, verified certs): `./scripts/patch-domain-foss-north.sh`
- For the same hosts with self-signed testing: `./scripts/patch-domain-new-foss.sh` (disables Keycloak SSL verify)

Notes:
- nginx listens on 80/443; `new.foss-north.se` goes to the app (web:8000) and `auth.foss-north.se` goes to Keycloak (8080).
- For production TLS, replace the self-signed certs in `certs/` and restart nginx.
- Ensure DNS for `new.foss-north.se` and `auth.foss-north.se` points to the VPS and that `DJANGO_ALLOWED_HOSTS` includes the app host.
