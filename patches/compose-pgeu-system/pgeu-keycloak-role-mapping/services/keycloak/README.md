# Keycloak SSO Service

Keycloak is routed through Traefik at `KEYCLOAK_HOST` and keeps its database,
admin credentials, and PGEU OIDC client secret in runtime secret files.

## Files

- `compose.yaml` - Keycloak and Keycloak database Compose fragment.
- `entrypoint.sh` - secret-file bridge for Keycloak admin and database
  passwords.
- `realm-pgeu.tmpl.json` - realm/client template with variable placeholders
  only.
- `scoped-groups.example.json` - empty, secret-free schema example for a scoped
  group inventory; it is not a production resource manifest.
- `scoped-groups.foss-north-production.json` - reviewed, secret-free production
  resource inventory with 56 leaf declarations for two series and nine
  conferences; it contains no users, subjects, credentials, memberships,
  sponsors, meetings, or wiki pages. Live emptiness is verified separately.
- `generated/` - ignored realm import output when `KEYCLOAK_REALM_IMPORT_FILE`
  uses the default path.

## Realm Generation

Generate the realm import before first startup:

```bash
scripts/generate-keycloak-realm.sh --env-file .env
```

The generator requires a runtime client secret file through
`PGEU_KEYCLOAK_CLIENT_SECRET_FILE` or `KEYCLOAK_CLIENT_SECRET_FILE`. It writes
the generated realm only under ignored `services/keycloak/generated/` or
`runtime/` paths and does not print the secret value.

Keep `PGEU_KEYCLOAK_CLIENT_SECRET_FILE` and any `KEYCLOAK_CLIENT_SECRET_FILE`
override pointed at the same runtime secret unless a later change introduces
explicit secret synchronization.

## Existing-Realm Role And Mapper Sync

`realm-pgeu.tmpl.json` defines 19 PGEU client roles and two deployment-owned
protocol mappers:

- `pgeu-client-roles` emits client roles in multivalued `pgeu_roles`.
- `pgeu-group-memberships` emits full group paths in multivalued
  `pgeu_groups` with `full.path=true`.

Both claims are enabled for ID tokens, access tokens, and userinfo. Do not log
the raw tokens or claims.

Validate the template without contacting Keycloak, then check or converge the
existing realm:

```bash
scripts/sync-keycloak-role-model.sh --env-file .env validate
scripts/sync-keycloak-role-model.sh --env-file .env check
scripts/sync-keycloak-role-model.sh --env-file .env apply
```

The script reads the admin password only inside the Keycloak container. It
creates/updates the 19 owned role definitions, creates/updates the two named
mappers, removes duplicate instances of those owned mapper names, and verifies
the result. It does not synchronize user role assignments.

## Scoped Group Sync

The scoped group inventory has this exact shape:

```json
{
  "version": 1,
  "groups": [
    {
      "path": "/pgeu/conferences/example/roles/admin",
      "client_role": "pgeu-conference-admin"
    }
  ]
}
```

Use ignored/restricted runtime storage for staging or private inventories. The
approved production structure uses the committed secret-free inventory.
Validate it, inspect the existing realm without mutation, then apply:

```bash
scripts/sync-keycloak-scoped-groups.sh \
  --env-file .env \
  --manifest services/keycloak/scoped-groups.foss-north-production.json \
  validate
scripts/sync-keycloak-scoped-groups.sh \
  --env-file .env \
  --manifest services/keycloak/scoped-groups.foss-north-production.json \
  --require-empty-memberships \
  check
scripts/sync-keycloak-scoped-groups.sh \
  --env-file .env \
  --manifest services/keycloak/scoped-groups.foss-north-production.json \
  --require-empty-memberships \
  apply
```

The command accepts only the canonical series, conference, conference-wiki,
sponsor, and meeting path grammars documented in
[`docs/Areas/PGEU Authorization.md`](../../docs/Areas/PGEU%20Authorization.md).
It creates missing path segments and maps `pgeu-user` plus exactly one matching
scoped client role to each declared leaf. It does not add/remove user
memberships, invent object identifiers, or delete groups.

For the approved production rollout at
`https://auth.foss-north.se/realms/pgeu`, every declared scoped leaf must have
zero direct members and zero child groups before and after apply. The script
deliberately leaves membership untouched; `--require-empty-memberships` makes
check/apply fail on a non-zero direct-member count without printing identities,
and also fails if a managed
leaf contains any child group. This blocks an inherited-membership path without
changing hierarchy. Any production membership or `pgeu-superadmin` change
requires separate authorization.

## Startup Prerequisites

Before starting `keycloak-db` and `keycloak`, create these runtime-only files:

- `KEYCLOAK_DB_PASSWORD_FILE`
- `KEYCLOAK_ADMIN_PASSWORD_FILE`
- `PGEU_KEYCLOAK_CLIENT_SECRET_FILE`
- `KEYCLOAK_REALM_IMPORT_FILE`

The PGEU redirect URI is generated with the Django OAuth handler path:

```text
/accounts/login/keycloak/
```

Public OIDC validation additionally requires the Traefik route and Step CA
certificate workflow from their own changes.

## Validation

After Step CA certificates and Traefik are available, validate discovery
through the public route:

```bash
scripts/check-keycloak-oidc.sh --env-file .env --cacert "${STEPCA_ROOT_CERT}"
```

For production, successful discovery must report exactly
`https://auth.foss-north.se/realms/pgeu`. Run role/group `check` again after
apply and require idempotent results before closing the change.

Do not print admin passwords, database passwords, cookies, access tokens, or
client secret values in validation logs. Realm exports and recovery artifacts
are secret-bearing runtime data and must remain outside Git.
