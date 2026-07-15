## ADDED Requirements

### Requirement: Scoped authorization trusts one exact Keycloak authority

The deployment SHALL accept scoped PGEU authorization only from client `pgeu`
in the realm whose OIDC issuer is exactly
`https://auth.foss-north.se/realms/pgeu`.

#### Scenario: Exact production issuer is used

- **WHEN** scoped role generation, reconciliation, or validation targets production
- **THEN** discovery reports the exact issuer, realm `pgeu`, and client `pgeu` before any mutation proceeds

#### Scenario: Wrong authority is presented

- **WHEN** the issuer, realm, or client differs, including an `auth.foss-north.com` or legacy `sso.foss-north.org` issuer
- **THEN** scoped synchronization stops without adding, removing, or reclassifying a PGEU grant

### Requirement: Every supported scoped capability has a fixed client role and canonical group

The Keycloak `pgeu` client SHALL define `pgeu-series-admin`,
`pgeu-conference-admin`, `pgeu-conference-tester`,
`pgeu-conference-talkvoter`, `pgeu-conference-staff`,
`pgeu-conference-volunteer`, `pgeu-conference-checkin-processor`,
`pgeu-sponsor-manager`, `pgeu-meeting-admin`, `pgeu-wiki-viewer`,
`pgeu-wiki-editor`, and `pgeu-sponsor-badge-scanner`, while canonical full-path
groups SHALL carry the PGEU object scope.

#### Scenario: Canonical scoped group and role are assigned

- **WHEN** a subject has the fixed matching `pgeu-*` client role and one of the canonical full paths in `pgeu_groups`
- **THEN** PGEU can resolve exactly one allowlisted capability and object

#### Scenario: Role or path condition is missing

- **WHEN** a subject has only the scoped role, only the group path, a role/path mismatch, or a malformed or unknown path
- **THEN** the role grants no scoped PGEU object access and reconciliation records only a redacted diagnostic, even though an accepted scoped role may permit normal login

#### Scenario: Series path is canonical

- **WHEN** a series administrator grant is represented
- **THEN** its path is `/pgeu/series/<numeric-pk>/roles/admin`

#### Scenario: Conference path is canonical

- **WHEN** a conference admin, tester, talkvoter, staff, volunteer, or check-in-processor grant is represented
- **THEN** its path is `/pgeu/conferences/<urlname>/roles/<role>` using respectively `admin`, `tester`, `talkvoter`, `staff`, `volunteer`, or `checkin-processor`

#### Scenario: Wiki path is canonical

- **WHEN** a wiki viewer or editor grant is represented
- **THEN** its path is `/pgeu/conferences/<confurl>/wiki/<wikiurl>/roles/<role>` using `viewer` or `editor`

#### Scenario: Sponsor path is canonical

- **WHEN** a sponsor manager or badge-scanner grant is represented
- **THEN** its path is `/pgeu/sponsors/<numeric-pk>/roles/<role>` using `manager` or `badge-scanner`

#### Scenario: Meeting path is canonical

- **WHEN** a meeting administrator grant is represented
- **THEN** its path is `/pgeu/meetings/<numeric-pk>/roles/admin`

#### Scenario: Canonical leaf role mappings converge

- **WHEN** a declared scoped leaf group is synchronized
- **THEN** the leaf maps `pgeu-user` plus exactly its matching scoped client role and production synchronization adds no user membership

#### Scenario: Series administrator is mapped

- **WHEN** a valid `pgeu-series-admin` grant resolves to an existing series
- **THEN** PGEU manages the series administrator relation and relies on existing series inheritance without duplicating conference administrator rows

#### Scenario: Conference user role is mapped

- **WHEN** a valid conference admin, tester, talkvoter, or staff grant resolves to an existing conference
- **THEN** PGEU manages only the corresponding user-backed relation for that conference and never maps conference staff to Django `is_staff`

#### Scenario: Registration-backed conference role is mapped

- **WHEN** a valid volunteer or check-in-processor grant resolves to an eligible linked conference registration
- **THEN** PGEU manages only the matching registration-backed relation and does not expose registration or scanner tokens

#### Scenario: Sponsor, meeting, wiki, or scanner role is mapped

- **WHEN** a valid sponsor-manager, meeting-admin, wiki-viewer, wiki-editor, or sponsor-badge-scanner grant satisfies its documented prerequisite
- **THEN** PGEU manages only the allowlisted target relation for that object

### Requirement: Scoped grants bind to durable external identity

PGEU SHALL accept scoped grants only through the fixed `pgeu` client and SHALL
persist the exact OIDC issuer plus OIDC `sub` binding to one Django user. Email
MAY bootstrap that binding only from one unambiguous verified first-login
profile and SHALL NOT remain the grant provenance afterward.

#### Scenario: Subject binding is unique

- **WHEN** a scoped claim from the fixed `pgeu` client is reconciled for a persisted unique issuer/subject binding
- **THEN** the grant is evaluated for the bound active PGEU user

#### Scenario: First verified login bootstraps a binding

- **WHEN** no issuer/subject binding exists and the verified Keycloak profile resolves to exactly one existing Django user or a new user
- **THEN** PGEU persists the unique issuer/subject/user binding before scoped grants are reconciled

#### Scenario: Identity is missing or ambiguous

- **WHEN** the subject is missing, multiple email users match, the subject is bound to another user, or the user is bound to another subject for the issuer
- **THEN** reconciliation fails closed before granting access and requires operator review

### Requirement: PGEU prerequisites are validated without side effects

Scoped reconciliation SHALL resolve existing PGEU objects and eligibility before
materializing authorization, and SHALL NOT create business prerequisites.

#### Scenario: User-backed prerequisite exists

- **WHEN** the bound active user and requested series, conference, or sponsor exist
- **THEN** an otherwise valid user-backed grant may be materialized

#### Scenario: Registration-backed prerequisite exists

- **WHEN** the same bound user has a linked, payment-confirmed, non-cancelled registration for the relevant conference
- **THEN** an otherwise valid volunteer, check-in, wiki, or scanner grant may be materialized

#### Scenario: Meeting prerequisite exists

- **WHEN** the meeting exists and the bound user has a PGEU member row
- **THEN** an otherwise valid meeting-admin grant may be materialized

#### Scenario: Badge-scanner prerequisite exists

- **WHEN** the sponsor is confirmed, conference badge scanning is enabled, the sponsor has a confirmed non-declined scanning benefit, and the registration is eligible
- **THEN** an otherwise valid sponsor-badge-scanner grant may be materialized

#### Scenario: Prerequisite is absent

- **WHEN** any required object, link, confirmation, benefit, or eligibility check is missing or ambiguous
- **THEN** the grant fails closed without creating or modifying that prerequisite

### Requirement: Keycloak-owned grant provenance is explicit

The integration SHALL record enough provenance to distinguish every
Keycloak-owned materialized relation from pre-existing or independently managed
local PGEU authorization.

#### Scenario: Sync creates a new relation

- **WHEN** a desired valid scoped relation is absent
- **THEN** sync creates it and records issuer/subject identity binding plus client role, canonical group path, resource target, exact materialized relation target, ownership, and timestamps, plus the exact concrete scanner-row identity when the relation is a badge scanner

#### Scenario: Equivalent local relation already exists

- **WHEN** the desired relation exists without Keycloak-owned provenance
- **THEN** sync preserves it as local, records a protected collision, and does not claim deletion ownership

#### Scenario: Provenance is ambiguous

- **WHEN** reconciliation cannot prove whether Keycloak owns a target relation
- **THEN** it stops rather than deleting or reclassifying the relation

### Requirement: Scoped additions and revocations reconcile deterministically

PGEU SHALL reconcile the complete valid scoped set transactionally on an
authenticated Keycloak callback. Global roles retain their authoritative
synchronization outside the scoped provenance ledger.

#### Scenario: Desired grant is added

- **WHEN** an authenticated Keycloak callback with an accepted login role carries a valid absent role/path grant
- **THEN** PGEU adds the relation once and a second reconciliation makes no change

#### Scenario: Keycloak-owned grant is removed

- **WHEN** canonical group membership is removed and the subject next completes an authenticated Keycloak callback
- **THEN** PGEU removes only the corresponding Keycloak-owned relation and ledger entry, including when the callback is subsequently denied because no accepted login role remains

#### Scenario: Unknown roleless identity reaches the callback

- **WHEN** a verified callback has no accepted login role and no exact binding or genuinely unbound, unique case-insensitive legacy email match
- **THEN** PGEU returns `403` without creating a user, binding, grant, or Django session and without changing an ambiguous user

#### Scenario: An exact bound identity is denied

- **WHEN** an exact issuer/subject binding reaches a callback with no accepted login role, an inactive bound user, or a verified-email conflict
- **THEN** PGEU converges that exact bound user's global and owned scoped intent to empty before returning `403`, without creating a user, binding, grant, or Django session

#### Scenario: Same role exists in another scope

- **WHEN** a subject loses a grant in one object but retains a canonical grant for a sibling object
- **THEN** access is revoked only in the removed scope

#### Scenario: Local or global authorization coexists

- **WHEN** scoped revocation runs for a subject with unrelated local assignments or accepted global roles
- **THEN** those unrelated permissions remain unchanged

#### Scenario: Emergency revocation is required

- **WHEN** access must end before the subject's next authenticated callback
- **THEN** operators remove group membership, drive a callback when possible, contain access through account/session controls, and document that local object revocation remains incomplete until callback reconciliation because no out-of-band local reconcile exists

#### Scenario: Badge scanner is revoked

- **WHEN** a Keycloak-owned sponsor-badge-scanner grant is removed
- **THEN** its exact recorded scanner row and authorization/token become unusable while existing scan history, attendee consent, and any later local replacement scanner row remain intact

### Requirement: Wiki viewer and editor authorization is least-privilege

The deployed PGEU baseline SHALL require write permission for the direct wiki
edit route before any Keycloak wiki grant is activated for a production person.

#### Scenario: Viewer requests edit route

- **WHEN** a user has only viewer access and sends either GET or commit POST directly to the wiki edit route
- **THEN** PGEU denies the request and does not change page content or history

#### Scenario: Editor requests edit route

- **WHEN** a user has an effective editor grant and all registration prerequisites hold
- **THEN** PGEU permits the existing preview/commit workflow

#### Scenario: Wiki fix is not proven

- **WHEN** the deployed baseline lacks the write-check patch or its negative regression test fails
- **THEN** production person assignment and consumption of wiki viewer/editor scope groups remain blocked

#### Scenario: Disposable staging validates wiki relation lifecycle

- **WHEN** the confirmed staging-only smoke creates temporary wiki groups and relations for disposable fixtures and users
- **THEN** it may validate claim mapping, revocation, and cleanup without authorizing production membership or claiming editor preview/commit workflow coverage

### Requirement: Production convergence uses reviewed safety gates

Production mutation SHALL require exact-authority preflight, restorable recovery
artifacts, local-provenance inventory, reviewed read-only checks, and
disposable staging validation. This rollout SHALL create only roles, the two
deployment-owned mappers, and empty canonical leaf groups for real PGEU
resources in production.

#### Scenario: Preflight or read-only check is unsafe

- **WHEN** health, backup, baseline, identity, object, eligibility, provenance, wiki, manifest-drift, or deletion checks fail
- **THEN** apply stops without continuing to later production batches

#### Scenario: Production structural manifest is safe

- **WHEN** the reviewed manifest and read-only checks contain zero subject assignments, zero group memberships, zero managed-leaf child groups, and zero superadmin changes
- **THEN** roles, the `pgeu_roles` and `pgeu_groups` mappers, and empty real-resource leaf groups may be applied

#### Scenario: Production leaf inventory converges

- **WHEN** structural production apply completes
- **THEN** every expected real-resource leaf exists, every leaf passes secret-safe zero-direct-member and zero-child-group guards, non-mutating health/global-role inventory checks pass, and repeated checks report convergence

#### Scenario: Production assignment is proposed

- **WHEN** the reviewed production manifest or apply scope contains any user, subject, membership, or superadmin mutation
- **THEN** apply stops pending separate explicit authorization

#### Scenario: Rollback is required

- **WHEN** scoped rollout produces unexpected access or cannot reconcile safely
- **THEN** operators disable scoped consumption, reverse only provenance-owned grants or restore recovery artifacts, invalidate sessions, and preserve global/local authorization and business data

### Requirement: Scoped authorization evidence is secret-safe and operationally documented

The deployment SHALL validate every scoped role family and record the final
operational model in the exact repository documentation targets without
committing reusable authentication material or private business data.

#### Scenario: Functional validation runs in staging

- **WHEN** scoped validation executes against disposable staging fixtures and users
- **THEN** it proves positive access, sibling-scope denial, revocation, local-collision preservation, session clearing, and idempotence for all twelve scoped roles

#### Scenario: Validation produces durable evidence

- **WHEN** results are summarized in docs or final reports
- **THEN** evidence contains commands, vantage points, issuer, non-secret role/scope identifiers, redacted counts/statuses, pass/fail results, deviations, and remaining risks only

#### Scenario: Output may contain secrets or private identifiers

- **WHEN** a command can emit credentials, tokens, cookies, OAuth values, raw JWTs/claims, redirect query strings, email addresses, scanner tokens, realm exports, or raw database rows
- **THEN** that output stays out of Git and the durable summary is generated from redacted or filtered output by design

#### Scenario: Operator needs the final authorization model

- **WHEN** an operator opens `docs/Areas/PGEU Authorization.md`
- **THEN** it identifies the exact issuer/client, complete global/scoped matrix, group grammar, prerequisites, provenance, assignment, reconciliation, revocation/session clearing, wiki gate, rollback, evidence rules, and links to implementation sources
