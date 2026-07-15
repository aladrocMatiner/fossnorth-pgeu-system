# PGEU Authorization

This is the canonical operator reference for PGEU authorization through
Keycloak. It describes the repository-owned model, the approved structural
rollout, and the controls required before any person receives a scoped grant.

## Authority And Approved Production Scope

- Public Keycloak host: `auth.foss-north.se`
- Realm: `pgeu`
- OIDC issuer: `https://auth.foss-north.se/realms/pgeu`
- Client: `pgeu`
- Role claim: `pgeu_roles`
- Full group-path claim: `pgeu_groups`

Stop if OIDC discovery reports any other issuer. In particular,
`auth.foss-north.com` and the validation-era `sso.foss-north.org` endpoint are
not production substitutes.

The currently approved production operation is structural only:

- converge the 19 client roles and two protocol mappers;
- create canonical leaf groups for inventoried real PGEU resources;
- map `pgeu-user` plus exactly one matching scoped client role to each leaf
  group; and
- leave every new scoped leaf group with zero user memberships.

This authorization does **not** include adding a person to a scoped group,
directly assigning a scoped role, changing `pgeu-superadmin`, or changing any
existing user's roles. Those actions require separate explicit approval.

## Repository-Owned Sources

- `services/keycloak/realm-pgeu.tmpl.json` is the source of the role and mapper
  model for new realm imports.
- `scripts/sync-keycloak-role-model.sh` converges that model in an existing realm
  without depending on re-import.
- `services/keycloak/scoped-groups.example.json` is the secret-free manifest
  schema example; it intentionally declares no production groups.
- `services/keycloak/scoped-groups.foss-north-production.json` is the reviewed,
  secret-free production resource inventory: 56 leaf declarations covering two
  series and six roles for each of nine inventoried conferences. The manifest
  contains no membership data; live emptiness still requires the guard.
- `scripts/sync-keycloak-scoped-groups.sh` validates and converges only the leaf
  paths declared in an operator-reviewed manifest.
- `patches/pgeu/manifest.yaml` and `patches/pgeu/README.md` own the PGEU overlay
  baseline, scoped authorization patch, and wiki edit guard.
- `openspec/changes/map-pgeu-scoped-authorization/` records the design, safety
  gates, requirements, tasks, and implementation deviations.

The role-model script owns the 19 role definitions and the two mapper names
listed below. The scoped-group script creates missing path segments and
normalizes deployment-owned scoped role mappings on declared leaves. It never
adds or removes user memberships, never invents scope identifiers, and never
deletes groups. Production commands use `--require-empty-memberships`, which
checks direct member counts without printing identities and also requires every
managed leaf to have zero child groups. It fails on either condition, closing
both direct and inherited-membership rollout paths.

## Global Roles

These seven roles already form the coarse PGEU authorization model:

| Keycloak client role | PGEU result |
| --- | --- |
| `pgeu-user` | Allows normal PGEU login. |
| `pgeu-superadmin` | Allows login and maps to Django `is_staff` plus `is_superuser`. |
| `pgeu-invoice-manager` | Maps to Django group `Invoice managers`. |
| `pgeu-news-admin` | Maps to Django group `News administrators`. |
| `pgeu-membership-admin` | Maps to Django group `Membership administrators`. |
| `pgeu-election-admin` | Maps to Django group `Election administrators`. |
| `pgeu-accounting-manager` | Maps to Django group `Accounting managers`. |

The final overlay removes the authoritative global flags/groups on the next
authenticated callback. This includes a callback that is denied after
convergence because no accepted PGEU role remains. Unrelated local state stays
unchanged.

## Scoped Roles And Canonical Paths

A scoped PGEU object grant requires both conditions in the same login:

1. the matching fixed client role is present in `pgeu_roles`; and
2. the exact canonical full path is present in `pgeu_groups`.

Either condition alone grants no scoped object permission. A scoped client role
is nevertheless an accepted PGEU login role, so it can allow normal login
without a separate `pgeu-user`; the path is still mandatory for the object
grant. Canonical leaf groups map exactly their matching scoped role and no other
scoped role; they also map `pgeu-user` as the explicit login baseline.

| Client role | Required full group path | PGEU target |
| --- | --- | --- |
| `pgeu-series-admin` | `/pgeu/series/<numeric-pk>/roles/admin` | `ConferenceSeries.administrators` |
| `pgeu-conference-admin` | `/pgeu/conferences/<urlname>/roles/admin` | `Conference.administrators` |
| `pgeu-conference-tester` | `/pgeu/conferences/<urlname>/roles/tester` | `Conference.testers` |
| `pgeu-conference-talkvoter` | `/pgeu/conferences/<urlname>/roles/talkvoter` | `Conference.talkvoters` |
| `pgeu-conference-staff` | `/pgeu/conferences/<urlname>/roles/staff` | `Conference.staff` |
| `pgeu-conference-volunteer` | `/pgeu/conferences/<urlname>/roles/volunteer` | `Conference.volunteers` |
| `pgeu-conference-checkin-processor` | `/pgeu/conferences/<urlname>/roles/checkin-processor` | `Conference.checkinprocessors` |
| `pgeu-wiki-viewer` | `/pgeu/conferences/<confurl>/wiki/<wikiurl>/roles/viewer` | `Wikipage.viewer_attendee` |
| `pgeu-wiki-editor` | `/pgeu/conferences/<confurl>/wiki/<wikiurl>/roles/editor` | `Wikipage.editor_attendee` |
| `pgeu-sponsor-manager` | `/pgeu/sponsors/<numeric-pk>/roles/manager` | `Sponsor.managers` |
| `pgeu-sponsor-badge-scanner` | `/pgeu/sponsors/<numeric-pk>/roles/badge-scanner` | `SponsorScanner` |
| `pgeu-meeting-admin` | `/pgeu/meetings/<numeric-pk>/roles/admin` | `Meeting.meetingadmins` |

Conference identifiers use `Conference.urlname`; wiki identifiers use that
conference URL plus `Wikipage.url`. Series, sponsor, and meeting identifiers use
positive decimal PGEU primary keys. Treat a conference/wiki rename as a reviewed
revoke/add operation. Do not silently repoint an existing path.

`pgeu-conference-staff` is a conference registration capability and is not
Django `is_staff`. A volunteer's ability to publish social posts remains
limited by the conference's existing post policy; the scoped role does not
override that policy.

## Local Prerequisites And Fail-Closed Behavior

PGEU materializes only a matching role/path pair whose local object and
prerequisites already exist:

- series/conference user roles require the active Django user and target object;
- volunteer and check-in processor require a linked, confirmed, non-cancelled
  registration in the target conference;
- wiki viewer/editor require the same eligible registration in the conference
  containing the page;
- meeting admin requires a PGEU `Member` for the user;
- sponsor manager requires the sponsor;
- badge scanner requires a confirmed sponsor, an eligible registration,
  conference badge scanning, and a confirmed, non-declined badge-scanning
  sponsorship benefit.

Sync does not create conferences, registrations, members, sponsors, meetings,
wiki pages, benefits, or attendee consent. A malformed path, role/path mismatch,
missing object, or failed prerequisite grants nothing.

## Claims And Mapper Contract

The `pgeu` client owns exactly these protocol mappers:

- `pgeu-client-roles`: `oidc-usermodel-client-role-mapper` emitting the
  multivalued `pgeu_roles` claim.
- `pgeu-group-memberships`: `oidc-group-membership-mapper` emitting full paths
  in the multivalued `pgeu_groups` claim with `full.path=true`.

Both mappers emit into the ID token, access token, and userinfo response. Never
record those raw values as evidence. The scoped overlay consumes the claims
from the authenticated Keycloak userinfo response; it does not treat a locally
decoded, unverified access-token payload as its authorization source. Validate
mapper names/configuration or the resulting redacted PGEU state instead.

## Structural Production Rollout

Run these commands only on the Compose host whose Keycloak service is confirmed
to back the exact production issuer. The scripts read the Keycloak admin
password inside the container from `/run/secrets/keycloak_admin_password` and do
not print it.

### 1. Gate The Target And Recovery

Confirm discovery before contacting the admin API:

```bash
scripts/check-keycloak-oidc.sh --env-file .env
```

The successful output must be exactly the `.se` issuer above. Also confirm
service health and create mode-restricted, restorable production recovery
artifacts for both the Keycloak and PGEU databases using the service owner's
approved backup process. Perform a secret-safe `pg_restore` catalog check for
both artifacts. Do not use `scripts/restore-compose-state.sh` for production;
that command is explicitly for the disposable validation stack.

Stop if the issuer differs, Keycloak is degraded, either recovery artifact or
catalog check is unavailable, the PGEU overlay baseline differs, or the current
global role inventory is unexpected.

### 2. Build And Review The Resource Manifest

Inventory real series, conferences, wiki pages, sponsors, and meetings in PGEU.
The reviewed 2026-07-15 inventory is committed as
`services/keycloak/scoped-groups.foss-north-production.json`. It contains 56
leaves: two series-admin leaves and six conference-role leaves for each of nine
conferences. No wiki, sponsor, or meeting object was included in that reviewed
inventory. A manifest has this shape:

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

The example identifier above is illustrative, not a production assignment.
Every entry must contain exactly `path` and `client_role`. Review the real
manifest for correct PGEU identifiers and confirm it contains no users,
subjects, emails, memberships, credentials, or superadmin changes.

### 3. Validate And Check Without Mutation

```bash
scripts/sync-keycloak-role-model.sh --env-file .env validate
scripts/sync-keycloak-scoped-groups.sh \
  --env-file .env \
  --manifest services/keycloak/scoped-groups.foss-north-production.json \
  validate
scripts/sync-keycloak-role-model.sh --env-file .env check
scripts/sync-keycloak-scoped-groups.sh \
  --env-file .env \
  --manifest services/keycloak/scoped-groups.foss-north-production.json \
  --require-empty-memberships \
  check
```

`validate` checks local source/manifest structure without contacting Keycloak.
`check` is read-only against the existing realm. Before the first apply, a
non-zero `check` may be the expected proof that roles, mappers, or groups are
missing; review every reported difference. `check` verifies current state but
does not produce a separately approved mutation plan.

The required-empty guard queries only direct-member and child-group counts for
declared leaves and does not print identities. Stop on either non-zero count;
do not export or log member records.

### 4. Apply Structure In Dependency Order

```bash
scripts/sync-keycloak-role-model.sh --env-file .env apply
scripts/sync-keycloak-scoped-groups.sh \
  --env-file .env \
  --manifest services/keycloak/scoped-groups.foss-north-production.json \
  --require-empty-memberships \
  apply
```

The role model must exist before group-role mappings. The group command may
create intermediate/leaf groups and normalize only the 12 deployment-owned
scoped role mappings on declared leaves. It does not delete groups or touch user
membership.

Stop immediately if output mentions the wrong realm/client, an unknown path,
role/path mismatch, missing client role, duplicate group, unexpected scoped
role, or any user-membership operation.

### 5. Verify No-Grant Convergence

```bash
scripts/sync-keycloak-role-model.sh --env-file .env check
scripts/sync-keycloak-scoped-groups.sh \
  --env-file .env \
  --manifest services/keycloak/scoped-groups.foss-north-production.json \
  --require-empty-memberships \
  check
scripts/check-keycloak-oidc.sh --env-file .env
```

The required-empty check proves every declared production leaf still has zero
direct members and zero child groups, so no inherited-member path sits below a
managed leaf. Rerun both `apply` commands only to prove idempotence when the
change window allows; the second run must report successful convergence without
membership or hierarchy changes. Record counts and pass/fail summaries, not raw
Admin API responses.

### 6. Completion Record — 2026-07-15

The structural rollout completed from `foss-north-2026` against exact issuer
`https://auth.foss-north.se/realms/pgeu`. The accepted mode-`0700` recovery
artifact was
`/srv/compose-pgeu-backups/compose-state-20260715T113502Z`; both Keycloak and
PGEU `pg_restore` catalog checks passed. The earlier `20260715T113420Z` attempt
was partial because of runtime permissions and was not used.

Preflight, the `util.0009` migration, `manage.py check`, the reviewed role/group
applies, and both post-apply checks passed. Final state was 19 client roles, two
mappers, 56 declared leaves, 81 realm group rows, and 112 group-role mappings,
with zero realm group memberships, zero direct members or child groups on every
declared leaf, and zero direct assignments across all twelve scoped roles.
Existing global direct-assignment counts and all recorded PGEU authorization
aggregates remained unchanged; PGEU retained zero identity bindings and zero
scoped-grant ledger rows.

All nine services were healthy, integrated smoke passed, and the external auth
and site endpoints returned HTTP `200`. No credentialed production role smoke,
person assignment, production focused suite, or idempotent re-apply was run;
post-check proved convergence and staging had already proved idempotence.
ShellCheck was unavailable. Rollback was not invoked, and the accepted backup
was retained. The detailed secret-safe metrics and deviations are recorded in
[`PGEU Compose`](../Projects/PGEU%20Compose.md).

## Person Assignments Are A Separate Change

Do not use this rollout to grant a person access. A future assignment requires
separate approval and must identify the subject, exact leaf, local prerequisite,
owner, expiry/review date, positive check, sibling-scope denial, and revocation
test. Prefer group membership over direct client-role assignment so role and
path stay paired.

Grant/revoke behavior must first be exercised with disposable staging users.
Never test a temporary revoke by changing a production person's roles without
explicit authorization.

Run the end-to-end scoped gate only on the disposable staging host, where
`127.0.0.1` is the explicit private Traefik target:

```bash
PGEU_SCOPED_SMOKE_CONFIRM=disposable-staging \
  scripts/smoke-keycloak-scoped-authorization.sh \
  --target-ip 127.0.0.1
```

The script hard-refuses the production issuer, exercises all 12 scoped role
families with real callback-time grant/revoke convergence, and removes its
memberships, groups, fixtures, binding state, and direct-role changes.
Temporary wiki groups and relations in this disposable test validate only
claim-to-relation materialization, revocation, and cleanup. They do not exercise
the editor preview/commit workflow or authorize a production wiki membership.

## Provenance And Revocation

`KeycloakIdentityBinding` binds one Django user to the exact OIDC issuer and
`sub`, with creation/last-seen timestamps and uniqueness for issuer+subject and
issuer+user. The `pgeu` client is fixed by the provider configuration and is not
repeated in each binding row. Initial account association occurs only after
Keycloak returns a non-empty normalized email with `email_verified=true`: one
case-insensitive matching user is bound, or a new user is created. Duplicate
email matches or a conflicting issuer/subject/user binding fail closed. Later
scoped provenance uses the persisted issuer/subject binding rather than email
alone.

`KeycloakRoleGrant` references that binding and records client role, canonical
group path, grant type, resource `target`, exact materialized
`relation_target`, optional exact scanner-row `relation_record`, `owned`, and
creation/last-seen timestamps. `relation_target` is the concrete user,
registration, or member relation used by that grant; `relation_record` is set
only for a concrete `SponsorScanner` row. The ledger is scoped-only. Existing
global flags/groups retain authoritative callback-time behavior outside this
ledger.

The stored identities allow owned revocation after a registration is detached
from its user and allow scanner revocation to delete only the exact owned
scanner row. `ScannedAttendee` history remains. If a local scanner row replaces
the recorded one, it is treated as unowned and preserved. These cases are
covered by database-backed regression tests; production person assignments are
still blocked by the separate callback/session lifecycle gates below.

Before accepting a Keycloak callback on a checkout containing this overlay, run
the Django migration and `python manage.py djangoconstraints_apply`. The patch
adds the three expected uniqueness constraints (issuer/subject, issuer/user,
and binding/client-role/group-path) plus the two expected foreign keys (binding
to user and grant to binding) to PGEU's constraint inventories. A patched
preflight or isolated database validation must fail if those declarations are
missing. The inventory CSVs belong to this pinned deployment overlay and must
be regenerated and revalidated whenever the upstream baseline moves. The
current upstream auditor also emits 48 PostgreSQL-catalog false positives and
38 inherited application-inventory mismatches; none names these five new
constraints, so the global audit must not be reported as clean.

When a relation already exists locally, sync records it as not owned and will
not delete it later. This conservative rule also applies on the first login
after upgrading: a pre-existing relation is treated as local even if an older
sync may historically have created it without provenance. When the new sync
creates a relation, it records it as owned and may remove only that owned
relation after the matching grant disappears. It does not remove unrelated
local assignments, accepted global groups/flags, registrations, members, wiki
content/history, attendee consent, or scan history.

Normal synchronization occurs on the next authenticated Keycloak callback. If
an exact existing issuer/subject binding exists, a roleless callback, inactive
bound user, or verified-email identity conflict converges that exact user's
global and scoped intent to empty transactionally before returning `403`; no
Django login, user, or binding is created. During the pre-binding migration
window, and only when no exact binding exists, a denied callback may clear only
global intent for exactly one genuinely unbound existing user matched
case-insensitively by the verified email. Unknown, ambiguous, and
differently-bound fallback identities are denied without mutation.

Removing a Keycloak group membership alone is still not immediate revocation:
an existing Django session and materialized relation can remain until a new
callback and explicit session handling complete. There is no out-of-band scoped
reconcile command. Before any production person assignment is authorized, the
procedure must prove both accepted-role and roleless callback revocation and
must cover Keycloak and Django session invalidation. When possible, drive the
callback before disabling the Keycloak account; disabling the account first can
prevent the callback that removes the PGEU relation. Disabling the account
contains new SSO but does not itself prove local convergence.

For an owned badge-scanner grant, revocation removes only the exact recorded
`SponsorScanner` authorization/token. Existing `ScannedAttendee` history and a
locally created replacement scanner row are preserved.

## Wiki Activation Gate

At the pinned upstream baseline, the direct wiki edit route used the read check
instead of the write check. The scoped overlay must include the dedicated wiki
authorization patch that calls the check with `readwrite=True`.

The current patch proves viewer denial for direct GET and commit POST, with no
form/history creation and unchanged content. It also proves that an explicit
editor can open the edit view and that public-editor and editor-registration-
type paths pass the existing write-permission helper. A positive editor
preview-and-commit regression and a history/view non-regression test remain an
active OpenSpec gate rather than completed evidence.

Do not assign a production person to, or activate production consumption of, a
wiki viewer/editor grant unless regression tests prove all of the following:

- a viewer is denied on direct edit GET;
- a viewer is denied on commit POST and content/history do not change;
- an editor can preview and commit;
- existing public-editor and editor-registration-type behavior remains valid.

Production leaf creation is safe only while leaves are empty; the wiki gate is
mandatory before any future production membership. The confirmed disposable
staging smoke may continue to create temporary wiki mappings solely to validate
the scoped relation lifecycle and cleanup described above.

## Rollback And Recovery

The structural rollout deliberately creates no scoped person grants. If health
or issuer validation fails after apply:

1. stop further changes and preserve only a redacted command/result summary;
2. leave empty groups dormant unless the reviewed rollback explicitly owns
   their removal;
3. restore the appropriate production Keycloak and/or PGEU database recovery
   artifacts if mapper/role state cannot be safely corrected in place;
4. redeploy the previous known-good PGEU overlay revision if application login
   regresses; and
5. rerun issuer, health, global-role inventory, role-model check, and zero-member
   verification.

There is no automatic group-delete rollback in
`sync-keycloak-scoped-groups.sh`. Never delete an existing `/pgeu` hierarchy
without proving that the affected leaves were created by this rollout and have
zero direct members and zero child groups. Never remove the seven existing
global roles as part of scoped rollback.

## Secret-Safe Evidence

Durable evidence may contain:

- date, environment, exact issuer, realm, and client;
- repository revision and PGEU overlay baseline;
- command names and validation vantage points;
- the 19-role/two-mapper count and canonical group paths;
- zero-member counts, add/verify summaries, and pass/fail status;
- skipped checks, deviations, rollback, and remaining risks.

Do not commit or paste `.env` values, passwords, client/admin secrets, tokens,
cookies, OAuth state/codes, raw JWTs or claims, full redirect query strings,
scanner tokens, member exports, raw database rows, realm exports, backups, or
private keys. Store any necessary raw diagnostic material only under ignored,
mode-restricted runtime storage and summarize it after filtering.

Use `docs/Areas/Auth Incident Template.md` for unexpected privilege, failed
revocation, wrong-issuer, or authorization availability incidents. Record the
dated structural rollout result and deviations in
`docs/Projects/PGEU Compose.md`.
