# PGEU Keycloak role mapping

The reviewed, secret-free publication bundle is available at
[`patches/compose-pgeu-system/pgeu-keycloak-role-mapping/`](../patches/compose-pgeu-system/pgeu-keycloak-role-mapping/README.md).
It contains the exact Keycloak sources, synchronization and smoke scripts,
pinned six-patch PGEU overlay, production group inventory, checksums, and
canonical authorization runbook needed to reproduce the implementation.

Production authority is limited to issuer
`https://auth.foss-north.se/realms/pgeu`, realm `pgeu`, and client `pgeu`.
`auth.foss-north.com` and the former validation issuer are not accepted
production substitutes.

## Production outcome — 2026-07-15

The structural rollout completed against exact issuer
`https://auth.foss-north.se/realms/pgeu` with 19 client roles, two mappers, 56
declared leaves, and 112 group-role mappings. Final evidence showed zero realm
group memberships, zero direct members and child groups on every declared
leaf, zero direct assignments across all twelve scoped roles, and zero PGEU
identity bindings or scoped-grant ledger rows. Global direct-assignment and
PGEU authorization counts remained unchanged.

All nine services were healthy, integrated smoke passed, and the external auth
and site endpoints returned HTTP `200`. The accepted recovery backup was
retained, rollback was not invoked, and no production person assignment was
made.

## Role inventory

The `pgeu` client defines 19 roles:

- Global: `pgeu-user`, `pgeu-superadmin`, `pgeu-invoice-manager`,
  `pgeu-news-admin`, `pgeu-membership-admin`, `pgeu-election-admin`, and
  `pgeu-accounting-manager`.
- Scoped: `pgeu-series-admin`, `pgeu-conference-admin`,
  `pgeu-conference-tester`, `pgeu-conference-talkvoter`,
  `pgeu-conference-staff`, `pgeu-conference-volunteer`,
  `pgeu-conference-checkin-processor`, `pgeu-sponsor-manager`,
  `pgeu-sponsor-badge-scanner`, `pgeu-meeting-admin`, `pgeu-wiki-viewer`, and
  `pgeu-wiki-editor`.

Global roles map login, Django staff/superuser flags, or the five
deployment-owned Django manager groups. A scoped object permission requires
both the matching role in `pgeu_roles` and its exact canonical full path in
`pgeu_groups`; either claim alone grants no object permission.

The complete role-to-path-to-PGEU matrix, prerequisites, ownership and
revocation behavior, production check/apply gates, rollback, and evidence rules
are in the exact
[`PGEU Authorization` runbook](../patches/compose-pgeu-system/pgeu-keycloak-role-mapping/runbook/PGEU%20Authorization.md).

## Safety boundary

The published production manifest contains 56 structural leaf declarations
and no users, subjects, emails, credentials, or memberships. Applying the
structure is not authorization to assign a person, alter `pgeu-superadmin`, or
change an existing user's roles. Production commands must use the runbook's
issuer, recovery, read-only check, and empty-membership gates.

The destructive scoped functional smoke is staging-only. It refuses the
production issuer, requires an explicit private target and confirmation, and
must stop if cleanup cannot prove full convergence.

Design and implementation status are recorded in
[`openspec/changes/map-pgeu-scoped-authorization/`](../openspec/changes/map-pgeu-scoped-authorization/).
