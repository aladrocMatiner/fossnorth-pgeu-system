Keycloak SSO (OIDC) Integration
================================

This project includes a lightweight OAuth2/OpenID Connect login flow. You can
enable Keycloak SSO by configuring environment variables or via a settings
override file.

Prerequisites
- A Keycloak realm and a Confidential client for this site
- Redirect URI set to: `SITEBASE/accounts/login/keycloak/`
  - Example: if `SITEBASE=https://conf.example.org`, then
    `https://conf.example.org/accounts/login/keycloak/`

Quick Start (Docker Compose)
1. Edit `docker-compose/.env` and set:
   - `DJANGO_ENABLE_OAUTH_AUTH=true`
   - `DJANGO_SITE_BASE` to your public base URL
   - `KEYCLOAK_BASE_URL` = `https://keycloak.example.org/realms/<realm>`
   - `KEYCLOAK_CLIENT_ID` = your Keycloak client ID
   - `KEYCLOAK_CLIENT_SECRET` = your client secret
2. Rebuild and restart:
   ```bash
   docker compose up -d --build
   ```
3. Navigate to `/accounts/login/` to see the Keycloak button and sign in.
   - With the included dev realm (Docker), a demo user `fossnorth`/`fossnorth`
     is imported automatically.

What the container does
- The entrypoint generates `postgresqleu/local_settings.py` and, when
  `DJANGO_ENABLE_OAUTH_AUTH=true`, appends:
  ```python
  ENABLE_OAUTH_AUTH = True
  OAUTH = {
      'keycloak': {
          'clientid': '<from env>',
          'secret': '<from env>',
          'baseurl': '<from env>',
      }
  }
  ```
- The OAuth module uses standard OIDC endpoints under
  `<KEYCLOAK_BASE_URL>/protocol/openid-connect/` for `auth`, `token`, and
  `userinfo`. It reads `email`, `given_name`, and `family_name` claims.

Alternate: settings override file
If you prefer to avoid environment variables, create a
`pgeu_system_override_settings.py` on the Python path with:
```python
ENABLE_OAUTH_AUTH = True
SITEBASE = 'https://conf.example.org'
OAUTH = {
    'keycloak': {
        'clientid': '...',
        'secret': '...',
        'baseurl': 'https://keycloak.example.org/realms/<realm>',
    }
}
```
Then rebuild or restart the app.

Notes
- `/accounts/login/keycloak/` is served by the built-in Keycloak handler
  (no plugins required). If you see a 500 here, verify that `OAUTH` contains
  a `keycloak` entry and that the base URL is reachable.
- New users are auto-created based on the Keycloak email claim upon first
  login. If you need group/role mappings, extend the Keycloak handler to read
  additional claims and assign Django groups accordingly.
- Logout is local to Django. For full Single Logout, you can redirect to
  Keycloak's end-session endpoint after logging out of the app.
