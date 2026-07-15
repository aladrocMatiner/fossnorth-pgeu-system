# PGEU Service Assets

This directory contains deployment-owned assets for running the external
`pgeu-system` checkout in the integrated Compose stack.

## Boundary

- Keep upstream source outside this repository.
- Configure the checkout path with `PGEU_SOURCE_DIR`.
- Do not copy live `.env` files, generated `local_settings.py`, certificate
  keys, database files, or client secrets into Git.

The image built from `services/pgeu/Dockerfile` does not vendor application
source. Compose mounts `PGEU_SOURCE_DIR` at `/app`, then `entrypoint.sh`
generates `/app/postgresqleu/local_settings.py` from runtime variables and
secret files.

`pgeu-web`, `pgeu-scheduler`, and `pgeu-mailqueue` use this same image and
external checkout. The web service owns migrations, static collection, and venv
preparation; the worker services depend on web health and override only the
runtime command.

## Files

- `compose.yaml` - PGEU web/database compose fragment for later inclusion in
  the root stack.
- `Dockerfile` - base runtime image with system dependencies and deployment
  scripts only.
- `entrypoint.sh` - startup flow for settings generation, dependency install,
  database wait, migrations, and static collection.
- `render-local-settings.py` - secret-file aware Django settings renderer.
- `bin/preflight.sh` - external checkout and patch marker validation.

## Preflight

Run from the deployment repo:

```bash
PGEU_SOURCE_DIR=/path/to/pgeu-system services/pgeu/bin/preflight.sh --baseline
```

After the documented patch overlay is applied:

```bash
PGEU_SOURCE_DIR=/path/to/pgeu-system services/pgeu/bin/preflight.sh --patched
```

The preflight checks object names, file presence, baseline commit and patch
markers only. It does not print credential values.

## Current Patch Gate

The manifest baseline `b0f05c327012e41a34ad9b25d64b7918839461c4` still needs
the local dependency/OIDC overlay for this deployment. A clean shallow clone of
that baseline shows `pycryptodomex==3.6.1` and no `oauth_login_keycloak`
handler, so `services/pgeu/bin/preflight.sh --patched` is expected to pass only
after `scripts/apply-pgeu-patches.sh "${PGEU_SOURCE_DIR}"` applies the manifest
overlay.

The same overlay also adapts `/accounts/logout` for Django 5 and Keycloak. It
stores the Keycloak ID token in the Django session, logs out the local Django
session, redirects the browser through Keycloak's OIDC end-session endpoint with
`id_token_hint`, and then returns to `PGEU_SITE_BASE`; otherwise a later login
can silently reuse the existing Keycloak SSO cookie or stop on a Keycloak logout
confirmation page.

Do not work around that by editing the external checkout manually. Maintain the
reviewable patch under `patches/pgeu/` and re-run the preflight against a fresh
checkout after any baseline move.
