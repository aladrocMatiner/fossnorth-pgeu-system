# Why

PGEU's existing Keycloak integration synchronizes login access, superadmin, and
five global Django groups, but conference, series, registration, sponsor,
meeting, and wiki permissions still have no central, scoped lifecycle. Operators
therefore cannot use Keycloak as the declared source of authorization intent for
those assignments, and removing a Keycloak role cannot revoke an equivalent
PGEU object relation safely.

The wiki edit route also checks read permission instead of write permission.
Until that defect is patched and regression-tested, a read-only wiki grant is
not a safe capability to provision from Keycloak.

The primary outcome of this change is a reproducible and reversible scoped
authorization contract in which the `pgeu` client in the `pgeu` realm at
`https://auth.foss-north.se/realms/pgeu` expresses every allowlisted PGEU scoped
role, while PGEU grants and revokes only the assignments proven to be owned by
that Keycloak source.

# What Changes

- Add fixed PGEU client-role definitions for series, conference, registration,
  sponsor, meeting, and wiki capabilities.
- Represent the object boundary with canonical Keycloak group paths using the
  final PGEU identifier for each resource family; authorization requires both
  the matching fixed `pgeu-*` client role and a valid group path.
- Add an OIDC group claim and a PGEU overlay lifecycle that binds users by the
  exact issuer plus OIDC `sub`, validates object prerequisites, records grant
  provenance, and reconciles additions and removals.
- Preserve local PGEU assignments and unrelated authorization state. Existing
  local relations are inventoried before activation and are never reclassified
  as Keycloak-owned merely because the same grant later appears in Keycloak.
- Add a blocking upstream-overlay fix and regression tests for direct wiki edit
  access so viewer and editor grants remain distinct.
- Add read-only structural production checks, staging-only grant/revoke tests,
  reconciliation, emergency revocation, rollback, and secret-safe functional
  validation for all scoped role families.
- Establish initial operational documentation for the exact production issuer,
  ownership, role/group grammar, assignment, revocation, evidence, incident,
  and rollback procedures.

# Capabilities

## New Capabilities

- `pgeu-scoped-authorization-sync`: Defines the fixed scoped-role inventory,
  Keycloak group grammar, identity binding, PGEU prerequisite checks,
  provenance, reconciliation, revocation, wiki safety gate, and operational
  evidence contract.

## Modified Capabilities

- `pgeu-keycloak-role-sync`: Replaces the blanket exclusion for object-level
  synchronization with a narrow allowlist governed by the new scoped
  authorization lifecycle; all other object-level assignments stay local.

# Dependencies

## Hard Prerequisites

- The production target SHALL resolve to an OIDC discovery document whose
  `issuer` is exactly `https://auth.foss-north.se/realms/pgeu`; neither
  `auth.foss-north.com` nor a legacy `sso.foss-north.org` issuer is an accepted
  substitute for this rollout.
- Operators SHALL have approved, secret-file-backed access to administer only
  the `pgeu` realm and `pgeu` client, plus restorable Keycloak and PGEU database
  snapshots stored outside Git with restrictive permissions.
- The deployed PGEU source SHALL match the pinned overlay baseline, and the
  existing global Keycloak role-sync validation SHALL pass in disposable
  staging before scoped production structure is changed.
- Every managed user SHALL have one persisted identity binding keyed by the
  exact issuer and OIDC `sub`; email alone is not sufficient grant provenance.
- A reviewed resource inventory SHALL resolve every group path to an existing
  PGEU object using the identifier required by its resource family. Any staging
  validation grant, or later separately authorized production grant, SHALL also
  resolve registration/member prerequisites.
- The wiki write-permission fix and its direct-URL negative regression test
  SHALL pass before any wiki viewer/editor group is assigned or synchronized.

## Optional References

- `openspec/specs/pgeu-keycloak-role-sync/spec.md`
- `openspec/specs/pgeu-auth-operational-evidence/spec.md`
- `openspec/changes/expand-pgeu-role-functional-validation/`
- The pinned upstream PGEU models and authorization checks named in the design.

# Non-Goals

- Redesigning PGEU's full authorization system or replacing its existing local
  checks with a generic policy engine.
- Reworking the seven accepted global roles, granting superadmin, or assigning
  any production user. This rollout creates roles, the two deployment-owned
  mappers, and empty leaf groups only; production memberships require separate
  explicit authorization.
- Creating conferences, registrations, members, sponsors, meetings, wiki pages,
  sponsorship benefits, or attendee consent as a side effect of role sync.
- Mapping registration types, public wiki flags, attendee/member eligibility,
  scanner tokens, or business records into Keycloak.
- Adding SCIM, LDAP, identity brokering, event-listener extensions, or
  organization-wide HR lifecycle automation.
- Migrating DNS, TLS, the OIDC client secret, the OAuth flow, the realm name, or
  the public PGEU hostname.
- Treating Keycloak backups, realm exports, tokens, cookies, raw JWTs, scanner
  tokens, or database rows as committable evidence.

# Safety Gates And Stop Conditions

1. Stop if discovery does not report the exact production issuer, realm/client
   identifiers differ, backups are not restorable, or the current global-role
   smoke test fails.
2. Stop if the read-only structural check finds an unknown group shape, a missing PGEU object, an
   unclassified pre-existing local relation, a production subject assignment,
   a superadmin change, or any deletion not represented in the reviewed
   manifest and check result.
3. Stop all wiki activation until the read-only direct-edit regression test
   returns denial for both GET and POST and a valid editor can still publish.
4. Apply and validate disposable staging fixtures and users for every role
   family before production convergence. Production SHALL create the roles,
   two deployment-owned mappers, and real-resource leaf groups with zero user
   memberships.
5. Stop on unexpected privilege, failed revocation, stale session access,
   secret-bearing output, degraded service health, or post-apply state that
   differs from the reviewed manifest.

# Rollback Summary

Freeze assignments, disable scoped claim consumption, remove only
provenance-ledger grants created by this integration, restore pre-existing local
relations from the inventory, restore the pre-change realm/PGEU snapshots when
needed, invalidate affected Django and Keycloak sessions, and rerun negative
route checks. Existing global roles and unrelated local grants SHALL not be
removed. If ownership is ambiguous, stop rather than deleting the relation.

# Exact Documentation Targets

- `docs/Areas/PGEU Authorization.md`: canonical issuer/client, complete global
  and scoped role matrix, group grammar, prerequisites, ownership, assignment,
  reconciliation, revocation, emergency session clearing, wiki gate, rollback,
  and secret-handling runbook.
- `docs/Areas/Operations.md`: concise commands, safety gates, validation vantage
  points, and a link to the canonical authorization runbook.
- `docs/Projects/PGEU Compose.md`: dated rollout state, reviewed deviations,
  secret-safe validation results, remaining risks, and rollback result if used.
- `docs/Areas/Auth Incident Template.md`: scoped grant, provenance, object,
  reconciliation, and session-invalidation fields for privilege incidents.
- `services/keycloak/README.md`: reproducible role/group/claim generation source
  and the exact non-secret inspection procedure.
- `patches/pgeu/manifest.yaml` and `patches/pgeu/README.md`: scoped-sync and wiki
  guard patch provenance, affected upstream paths, readiness, validation, and
  removal criteria.
- `deployment/proxmox/fossnorth-pgeu/RUNBOOK.md`: disposable staging gate and a
  link to the canonical production check/apply/rollback sequence for
  `auth.foss-north.se` without embedding credentials.

# Impact

- Keycloak realm template and existing-realm synchronization logic.
- Deployment-owned PGEU overlay, patch manifest, and upstream regression tests.
- Resource inventory, structural check/apply commands, callback-time grant sync,
  session revocation limits, and scoped functional smoke validation.
- The exact documentation targets listed above.

No runtime code, template, script, realm, user, or live assignment is changed by
this proposal artifact itself.
