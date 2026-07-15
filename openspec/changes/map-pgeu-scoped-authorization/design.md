# Context

The accepted Keycloak role sync owns seven coarse client roles:
`pgeu-user`, `pgeu-superadmin`, `pgeu-invoice-manager`, `pgeu-news-admin`,
`pgeu-membership-admin`, `pgeu-election-admin`, and
`pgeu-accounting-manager`. It synchronizes Django flags/groups at login and
intentionally leaves PGEU object relations local.

PGEU implements the remaining roles through heterogeneous relations:

- `ConferenceSeries.administrators` and the user-backed conference
  `administrators`, `testers`, `talkvoters`, and `staff` relations;
- registration-backed conference `volunteers` and `checkinprocessors`;
- `Sponsor.managers`, `Meeting.meetingadmins`, wiki viewer/editor attendee
  relations, and `SponsorScanner` rows.

Those targets have different prerequisites and revocation behavior. A fixed
global client role is therefore not sufficient: the authorization must include
both a capability and an existing PGEU object. The design combines Keycloak
client roles (capability vocabulary) with Keycloak groups (scope instances),
then materializes only allowlisted relations in PGEU with explicit provenance.
The Keycloak and PGEU work is intentionally one change because neither side is a
safe or verifiable authorization outcome alone.

# Goals And Non-Goals

## Goals

- Express all identified scoped PGEU roles in a stable Keycloak vocabulary.
- Make scope explicit and machine-validated with the canonical identifier for
  each PGEU resource family.
- Bind external identity by exact issuer and OIDC subject, not mutable email.
- Preserve local grants while making Keycloak-owned grants reversible.
- Fail closed on malformed, unknown, ambiguous, or ineligible grants.
- Prove positive access, cross-scope denial, revocation, session clearing, and
  wiki viewer/editor separation without exposing secrets.
- Make `auth.foss-north.se`, realm `pgeu`, client `pgeu` operationally
  discoverable and reproducible from repository-owned inputs.

## Non-Goals

- The non-goals in `proposal.md` apply. In particular, scoped sync does not
  manufacture business prerequisites or make conference `staff` equivalent to
  Django `is_staff`.

# Decisions

## 1. Use fixed client roles plus canonical scope groups

The `pgeu` client SHALL add this fixed capability vocabulary:

| Keycloak client role | Canonical leaf path | PGEU target | Notes |
| --- | --- | --- | --- |
| `pgeu-series-admin` | `/pgeu/series/<numeric-pk>/roles/admin` | `ConferenceSeries.administrators` | Existing PGEU inheritance grants admin behavior for conferences in the series; do not duplicate conference rows. |
| `pgeu-conference-admin` | `/pgeu/conferences/<urlname>/roles/admin` | `Conference.administrators` | Conference-only administration. |
| `pgeu-conference-tester` | `/pgeu/conferences/<urlname>/roles/tester` | `Conference.testers` | Bypasses feature-open checks only where PGEU already permits it. |
| `pgeu-conference-talkvoter` | `/pgeu/conferences/<urlname>/roles/talkvoter` | `Conference.talkvoters` | Pre-approval talk review/voting/comment access. |
| `pgeu-conference-staff` | `/pgeu/conferences/<urlname>/roles/staff` | `Conference.staff` | Registration eligibility; never maps to Django `is_staff`. |
| `pgeu-conference-volunteer` | `/pgeu/conferences/<urlname>/roles/volunteer` | `Conference.volunteers` | Requires a valid registration; social publishing remains limited by the conference post policy. |
| `pgeu-conference-checkin-processor` | `/pgeu/conferences/<urlname>/roles/checkin-processor` | `Conference.checkinprocessors` | Requires a valid registration; does not expose registration/scanner tokens in claims or logs. |
| `pgeu-sponsor-manager` | `/pgeu/sponsors/<numeric-pk>/roles/manager` | `Sponsor.managers` | Does not create or approve a sponsorship. |
| `pgeu-meeting-admin` | `/pgeu/meetings/<numeric-pk>/roles/admin` | `Meeting.meetingadmins` | Requires the bound user to have a PGEU `Member` row. |
| `pgeu-wiki-viewer` | `/pgeu/conferences/<confurl>/wiki/<wikiurl>/roles/viewer` | `Wikipage.viewer_attendee` | Additive with public/regtype access and requires a valid registration. |
| `pgeu-wiki-editor` | `/pgeu/conferences/<confurl>/wiki/<wikiurl>/roles/editor` | `Wikipage.editor_attendee` | Implies effective viewing but does not rewrite public/regtype settings. Blocked until the edit guard is fixed. |
| `pgeu-sponsor-badge-scanner` | `/pgeu/sponsors/<numeric-pk>/roles/badge-scanner` | `SponsorScanner` | Requires eligible registration and confirmed scanning benefit; revocation invalidates only the owned scanner authorization/token and preserves scan history. |

The path grammar is closed: series, sponsors, and meetings use positive-decimal
PGEU primary keys; conference roles use `Conference.urlname`; wiki roles use the
containing conference `urlname` (`<confurl>`) plus `Wikipage.url`
(`<wikiurl>`). Paths are emitted in the multivalued `pgeu_groups` claim.

Authorization requires both the fixed client role and its one matching leaf
path. A role without a path, a path without the role, a role/path mismatch, an
invalid identifier, or any path outside the exact grammars grants nothing and
produces a redacted diagnostic. Canonical leaf groups receive `pgeu-user` plus
exactly their matching scoped client role; the same group membership supplies
the explicit login baseline, capability role, and full path.
Each scoped role belongs to the accepted PGEU login-role set, so a subject may
complete normal login without a separate `pgeu-user` role. The scoped role alone
still materializes no object grant without its matching `pgeu_groups` path.

Conference and wiki URL identifiers are existing PGEU routing keys. A rename is
treated as an explicit reviewed revoke/add operation; it cannot silently move a
grant. Human-readable Keycloak attributes remain informational only.

## 2. Treat the exact issuer and OIDC subject as identity provenance

The trusted authorization source is the tuple:

```text
(issuer=https://auth.foss-north.se/realms/pgeu, client_id=pgeu, sub=<oidc-subject>)
```

The PGEU provider configuration fixes `client_id=pgeu`; the persisted
`KeycloakIdentityBinding` therefore stores the exact issuer and `sub` and links
that pair to one Django user rather than duplicating the fixed client ID in each
row. On the first verified login, one normalized, verified email may bootstrap
the issuer/subject binding to one existing user or a newly created user. More
than one email match, a subject already bound to another user, or a user already
bound to another subject for the issuer fails closed. After that bootstrap,
authorization follows the issuer/subject binding, not an email-only match. A
subject change is a migration requiring operator review, not an automatic user
merge.

Generic templates remain environment-parameterized. The production runbook and
live safety check name the exact issuer; implementation SHALL not replace
environment configuration with a hard-coded hostname.

## 3. Validate prerequisites without creating business state

The reconciler resolves every scope against the PGEU database before mutation:

- user-backed roles require the bound active Django user;
- volunteer, check-in, wiki, and badge-scanner roles require a registration for
  the same conference, linked to that user, payment-confirmed and not cancelled;
- meeting admin requires a `Member` row for the bound user and the target
  meeting to exist;
- sponsor manager requires the sponsor to exist;
- badge scanner additionally requires a confirmed sponsor, badge scanning
  enabled for the conference, and a confirmed, non-declined badge-scanning
  sponsor benefit.

Missing or ambiguous prerequisites fail that grant closed. Reconciliation does
not create or alter the prerequisite object. Diagnostics report only non-secret
object types/IDs and anonymized subject identifiers.

## 4. Keep a grant-provenance ledger

The overlay SHALL maintain durable issuer-plus-OIDC-subject identity binding and
one ledger record per materialized scoped grant containing at least client role,
canonical group path, resource target, exact materialized relation target,
ownership status, creation time, and last-seen/reconciled time. Scanner grants
also persist the exact concrete scanner-row identity. The canonical claim path
is the group provenance identifier. Accepted global roles keep their existing
flag/group synchronization semantics outside this scoped ledger.

Before activation, an inventory classifies every existing target relation as
local. Reconciliation follows these rules:

1. If the desired relation is absent, create it and mark it Keycloak-owned.
2. If the relation pre-exists without a Keycloak-owned ledger entry, leave it
   local and record an observed/local collision; do not claim ownership.
3. If a desired Keycloak-owned relation remains present, update last-seen only.
4. If a Keycloak-owned grant disappears, remove the owned target relation and
   ledger row only when no recorded local ownership protects it.
5. Never remove unrelated Django groups, flags, public/regtype permissions,
   series inheritance, scan history, registrations, members, or business data.

Ambiguous ownership is a stop condition. An operator must use a documented,
auditable ownership-transfer procedure before a local fallback can replace a
Keycloak-owned relation or vice versa.

## 5. Reconcile scoped grants on the authenticated Keycloak callback

An authenticated Keycloak callback reconciles the current subject's valid
`pgeu_groups` set in one database transaction. With an accepted login role, the
normal binding/bootstrap and login path runs. With no accepted role, an inactive
bound user, or a verified-email conflict, an exact existing issuer/subject
binding is converged to empty global and scoped intent before the callback
returns `403`; no Django session, user, or binding is created. Only when no
exact binding exists, during the pre-binding migration window, may one
genuinely unbound existing user matching the verified email
case-insensitively have the authoritative global flags/groups converged to
empty. An unknown, ambiguous, or differently-bound fallback identity changes
nothing.
Invalid claims fail closed before new access is granted. This change does not
promise an out-of-band PGEU grant reconcile command, webhook, or Keycloak Admin
API credential in the application runtime.

Normal revocation is complete only after all of the following are true:

1. the subject is removed from the canonical Keycloak grant group;
2. the subject completes a new authenticated Keycloak callback so scoped
   reconciliation removes the Keycloak-owned PGEU relation, even when the
   callback is then denied because no accepted role remains;
3. affected Django/Keycloak sessions are explicitly invalidated when immediate
   session termination is required; and
4. a negative check proves the protected route is denied in the revoked scope.

Emergency containment disables the Keycloak user when appropriate and
invalidates sessions, but removing a group alone is not documented as immediate
local revocation because no out-of-band scoped reconcile command exists.
When possible, drive the authenticated roleless callback before disabling the
Keycloak account; disabling the account first can prevent the callback that
performs local convergence.

## 6. Make the wiki permission defect a hard activation blocker

At the pinned upstream baseline, `wikipage_edit()` calls
`_check_wiki_permissions(request, page)` and therefore accepts read-only access.
The overlay SHALL change that route to require write permission and add tests
covering both direct GET and commit POST:

- a viewer receives denial and cannot create a history entry or change content;
- an editor can preview and commit;
- public-edit and explicit editor-regtype behavior remain valid; and
- history/view access is unchanged.

The wiki patch needs a separate manifest entry with affected upstream path,
rationale, validation, readiness, and removal criteria. No production person
may be assigned to a wiki scope group, and no production wiki grant may be
consumed, until this gate passes in the deployed baseline. The disposable
staging smoke may create temporary wiki groups and materialize their relations
solely to prove claim mapping, revocation, and cleanup; it does not exercise or
claim the editor preview/commit workflow.

## 7. Use a reviewed desired-state manifest and staged convergence

The committed artifact contains schema/examples and object identifiers only.
Disposable staging subjects live in ignored, mode-restricted state. This change
does not authorize production subject assignments. The workflow is:

1. verify exact discovery issuer and service health;
2. create restorable Keycloak/PGEU snapshots outside Git;
3. inventory and classify existing local relations;
4. run the real read-only `check` modes and review the resource manifest,
   confirming exactly zero subject assignments or superadmin changes;
5. validate all role families with disposable staging objects/users;
6. create the roles, mapper, and empty leaf groups for inventoried real PGEU
   resources in production;
7. verify every created production leaf has zero direct memberships and zero
   child groups;
8. rerun health, inventory, global-role, and no-op convergence checks; and
9. update durable, redacted documentation evidence.

The structural apply SHALL run only after exact-issuer confirmation, manifest
review, read-only checks, backup, and explicit operator confirmation. Stop if
the reviewed inputs or live target change, or if any production membership,
subject, or superadmin mutation appears.

# Safety Gates

- Discovery issuer, realm, and client must match exactly.
- Current integrated, global-role, backup, and service-health checks must pass.
- The PGEU overlay baseline and patch preflight must match.
- Backups must exist outside Git with restrictive modes and a documented restore
  check; realm exports that may contain secrets are never durable Git evidence.
- All subject bindings, PGEU scopes, prerequisites, ownership classifications,
  and planned removals must be unambiguous.
- The wiki guard tests must pass before any wiki activation.
- Staging grant/revoke tests must pass before structural production apply.
- The reviewed production manifest/apply scope must contain zero subject assignments, memberships, and
  superadmin changes; every created leaf group must remain empty and pass the
  secret-safe `--require-empty-memberships` direct-member and child-group
  counts.
- Stop on unexpected access, failed denial/revocation, stale-session access,
  drift from the reviewed manifest/check result, secret-bearing output, or
  unhealthy dependencies.

# Secret-Safe Validation Design

Grant/revoke validation uses disposable users and fixtures exclusively in
staging. It SHALL prove each role's positive route/workflow, denial in a sibling scope,
revocation after reconciliation, preservation of a same-shaped local grant, and
idempotent second reconciliation. The test harness SHALL redact or suppress
passwords, client/admin secrets, access/ID/refresh tokens, cookies, OAuth state
and codes, raw JWTs/claims, full redirect query strings, scanner tokens, email
addresses, and raw database rows.

Allowed durable evidence is limited to command name, vantage point, issuer,
role/group name, PGEU object type/ID, anonymized subject label, expected/actual
status or page marker, add/keep/remove counts, backup identifier without path
contents, and pass/fail summary.

Planned validation commands, from the place stated:

1. Local patch workspace: `scripts/apply-pgeu-patches.sh "${PGEU_SOURCE_DIR}"`
   followed by `git -C "${PGEU_SOURCE_DIR}" diff --check`, Django migrations,
   and `python manage.py djangoconstraints_apply` in the disposable database.
2. Staging Compose host: `docker compose config --quiet`.
3. Staging Compose host: `scripts/preflight-integrated-stack.sh --patch-mode patched`.
4. Disposable staging public Traefik/Keycloak route plus PGEU container checks:
   `PGEU_SCOPED_SMOKE_CONFIRM=disposable-staging
   scripts/smoke-keycloak-scoped-authorization.sh --target-ip 127.0.0.1`.
5. Staging Compose host: `scripts/smoke-keycloak-role-sync.sh --target-ip 127.0.0.1`
   to prove existing global mappings did not regress.
6. Production Compose/public-route host:
   `scripts/smoke-integrated-stack.sh --patch-mode patched --target-ip 127.0.0.1`
   using only its non-credentialed health/discovery/redirect checks.
7. Local repository: a documented secret-marker scan limited to changed
   OpenSpec, docs, templates, patch metadata, patches, and validation scripts.

OpenSpec readiness is checked separately with
`openspec validate map-pgeu-scoped-authorization --type change --strict` and
`openspec status --change map-pgeu-scoped-authorization`.

# Rollback And Recovery

1. Freeze Keycloak group and desired-state changes and save the failed
   check/apply summary without secret-bearing output.
2. Disable scoped claim consumption/reconciliation while leaving the accepted
   global role sync active.
3. On a later authenticated callback, use provenance to remove only relations
   created by scoped sync and preserve local ownership. Stop on ambiguity; no
   out-of-band reconcile command is claimed by this change.
4. Restore the pre-change Keycloak realm/PGEU database snapshots when a safe
   corrective change cannot be proven; never commit or print their contents.
5. Invalidate affected Django and Keycloak sessions, then prove negative access
   for all changed subjects/scopes and rerun existing global-role smoke tests.
6. Record the reason, commands, result, deviations, and follow-up in the exact
   documentation targets.

Rollback SHALL preserve unrelated local assignments, existing global roles,
registrations, members, sponsors, meetings, wiki content/history, attendee
consent, scan history, and other business data.

# Documentation Outcome

The implementation is not complete until every exact target in `proposal.md`
describes the final rather than intended state. `docs/Areas/PGEU Authorization.md`
is canonical; the other targets link to it and record environment-specific
commands/evidence, patch provenance, or incident fields. Any role name, group
grammar, issuer, prerequisite, sync behavior, validation user strategy, or file
location that differs from this design must be recorded as a reviewed deviation
before production apply.

# Implementation Deviations And Remaining Gates

Repository implementation inspected on 2026-07-15 is sufficient for the
authorized structural-only production rollout, but it does not yet satisfy the
full person-assignment lifecycle in this design:

- The overlay now persists issuer-plus-subject identity binding and scoped
  role/path/resource-target/exact-relation-target/ownership/timestamps from the
  authenticated Keycloak userinfo claims. Scanner grants additionally persist
  the exact concrete `SponsorScanner` row. The fixed `pgeu` client remains an
  authority/configuration invariant rather than a repeated database field.
- Database-backed tests prove exact owned revocation after registration
  detachment, exact scanner-row revocation, scan-history preservation, and
  preservation of a later local replacement scanner row.
- Scoped reconciliation runs only on the subject's next authenticated Keycloak
  callback. A denied callback for an exact existing binding revokes global and
  owned scoped intent before returning `403`, including inactive-user and
  verified-email-conflict paths, but there is no out-of-band operator reconcile
  command and active Django sessions are not automatically invalidated.
- `sync-keycloak-role-model.sh` and `sync-keycloak-scoped-groups.sh` provide
  local `validate`, read-only `check`, and structural `apply` modes only.
- The wiki patch enforces `readwrite=True`; tests cover viewer GET denial,
  viewer commit-POST denial without content/history mutation, explicit-editor
  GET, and the public-editor/editor-registration-type write checks. A positive
  editor preview-and-commit regression and a history/view non-regression test
  remain incomplete.

These gaps block production user memberships. The approved live scope therefore
creates only roles, mappers, and empty real-resource leaf groups, verifies zero
memberships, and leaves grant/revoke testing in disposable staging. Do not mark
the remaining session, wiki-test, or person-assignment tasks complete until the
stronger controls exist and pass.

# Risks And Trade-Offs

- Group paths are operator-visible and rename-sensitive. Canonical generation,
  path provenance, strict parsing, and reviewed check/apply gates make a rename
  a reviewed revoke/add instead of an implicit privilege move.
- Materializing external grants into heterogeneous PGEU relations is more
  complex than checking a claim at request time, but it preserves existing PGEU
  authorization behavior and avoids patching every protected view.
- Callback-time sync alone is insufficient for urgent revocation when no
  callback occurs. The explicit callback and session invalidation procedure are
  mandatory controls.
- Existing local and external grants can collide. Preserving local ownership is
  safer than deleting access automatically, though it requires an explicit
  ownership-transfer workflow.
- Badge-scanner revocation must invalidate the owned scanner token without
  deleting scan history. Functional tests must prove this separately.
