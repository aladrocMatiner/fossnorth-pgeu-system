# new.foss-north.se live state

Last audited: 2026-07-10.

This document records the changes that were applied directly on
`new.foss-north.se` during the PGEU/Keycloak migration and whether they are
covered by a repository.

## Covered in this repository

The `new-fossnorth-vps` branch already contains the nginx and Keycloak host
changes for:

- PGEU app host: `new.foss-north.se`
- Keycloak host: `auth.foss-north.se`
- Keycloak PGEU client callback:
  `https://new.foss-north.se/accounts/login/keycloak/*`

The branch tip observed during this audit was:

```text
d48e333 Fix Keycloak OAuth login in PGEU
```

## Live fn-web skin changes

The live `/srv/fn-web` checkout is on branch `prod` at upstream commit
`e2ae4c1`, with these local changes:

- `code/skin_urls.py` redirects `/pod/...` on `new.foss-north.se` to the
  original podcast tree at `https://foss-north.se/pod/...`.
- `template/oauthlogin/login.html` special-cases the Keycloak provider so it
  uses a provider-button PNG rather than the generic provider filename.

The exact text patch is stored in:

```text
patches/fn-web/new-foss-north-live-overlays.patch
```

The Keycloak button image used by the live site is stored in:

```text
assets/keycloak/btn_login_keycloak.png
```

Image metadata:

```text
PNG, 360 x 34
sha256: 81200b3a1d942f67ff2206a3b59c4b340c1790d9573657d0eda84b56aa3ae43c
```

The current live template references the image as:

```text
/media/img/misc/btn_login_keycloak.png
```

On the VPS that file currently lives in:

```text
/srv/pgeu-system/media/img/misc/btn_login_keycloak.png
```

`foss-north/fn-web` is not directly pushable from this GitHub account; current
permission observed with `gh repo view foss-north/fn-web` was `READ`. Until a
write-capable account pushes the patch to `foss-north/fn-web`, this repository
is the tracked source of the live overlay.

## Live compose stack changes

The live `/srv/compose-pgeu-system/current` checkout is a git repository with
no commits yet. It should be published separately before the deployment is
considered fully reproducible.

Important live changes applied there:

- `services/pgeu/render-local-settings.py` supports extra OAuth providers via:
  - `PGEU_EXTRA_OAUTH_PROVIDERS`
  - `PGEU_OAUTH_GITHUB_CLIENT_ID`
  - `PGEU_OAUTH_GITHUB_CLIENT_SECRET_FILE`
  - `PGEU_OAUTH_GOOGLE_CLIENT_ID`
  - `PGEU_OAUTH_GOOGLE_CLIENT_SECRET_FILE`
- `compose.yaml` passes those OAuth variables into PGEU and mounts
  `runtime/oauth-secrets` read-only at `/run/pgeu-oauth-secrets`.
- `.env` enables `github,google` as extra OAuth providers and points secrets at
  files under `runtime/oauth-secrets`.
- `services/pgeu/entrypoint.sh` builds a combined CA bundle from public system
  CAs plus the internal CA, then exports:
  - `REQUESTS_CA_BUNDLE=/tmp/pgeu-ca-bundle.crt`
  - `SSL_CERT_FILE=/tmp/pgeu-ca-bundle.crt`

The CA bundle change fixes PGEU OAuth callbacks to
`https://auth.foss-north.se`, which uses a public Let's Encrypt certificate.

Validation observed after the fix:

```text
status=200 issuer=https://auth.foss-north.se/realms/pgeu
```

## External dependencies

Google OAuth still requires the Google Cloud OAuth client allowlist to include:

```text
https://new.foss-north.se/accounts/login/google/
```

Without that external change, Google returns:

```text
Error 400: redirect_uri_mismatch
```
