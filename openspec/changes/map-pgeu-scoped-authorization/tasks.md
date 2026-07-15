## 1. Production Authority And Recovery Gates

- [x] 1.1 Verify discovery reports exactly `https://auth.foss-north.se/realms/pgeu` and record only issuer/status evidence.
- [x] 1.2 Verify the target realm is `pgeu`, the client is `pgeu`, and the existing seven-role inventory matches docs.
- [x] 1.3 Verify current Compose health, integrated smoke, and global role-sync smoke before scoped changes.
- [x] 1.4 Verify the deployed PGEU checkout matches the pinned patch-manifest baseline.
- [x] 1.5 Create mode-restricted Keycloak and PGEU database recovery artifacts outside Git.
- [x] 1.6 Perform and record a secret-safe restore-readiness check for both recovery artifacts.
- [ ] 1.7 Inventory all existing allowlisted PGEU target relations as local provenance before activation.

## 2. Desired-State And Identity Contract

- [x] 2.1 Add a secret-free resource schema for canonical scoped paths, numeric series/sponsor/meeting keys, and conference/wiki URL keys.
- [x] 2.2 Add an ignored, restrictive runtime location for disposable staging subject/group assignments.
- [x] 2.3 Add exact issuer/subject identity binding storage to the PGEU overlay while keeping the fixed `pgeu` client as an authority/configuration invariant.
- [x] 2.4 Reject missing/ambiguous subjects, duplicate verified-email matches, and conflicting issuer/subject/user bindings during scoped login reconciliation.
- [x] 2.5 Add prerequisite resolution for user-backed, registration-backed, member-backed, sponsor, meeting, wiki, and scanner targets.
- [x] 2.6 Make missing or ineligible prerequisites fail closed without creating business objects.

## 3. Wiki Write-Permission Blocker

- [x] 3.1 Add a dedicated overlay patch making `wikipage_edit()` request write permission.
- [x] 3.2 Add a viewer direct-GET regression test that expects denial.
- [x] 3.3 Add a viewer direct-POST regression test that proves content/history remain unchanged.
- [x] 3.4 Add explicit-editor GET, public-editor, and editor-registration-type positive regression tests.
- [x] 3.5 Record the wiki patch in `patches/pgeu/manifest.yaml` with provenance and removal criteria.
- [ ] 3.6 Add positive editor preview/commit and history/view non-regression coverage, and keep production wiki person assignment and consumption disabled until the deployed regression gate passes; disposable staging relation-lifecycle smoke remains permitted.

## 4. Keycloak Scoped Role And Group Model

- [x] 4.1 Add all twelve fixed scoped client roles to the Keycloak realm template.
- [x] 4.2 Add the full-path multivalued `pgeu_groups` OIDC mapper for the `pgeu` client.
- [x] 4.3 Add canonical group generation for series and conference user-backed capabilities.
- [x] 4.4 Add canonical group generation for conference registration-backed capabilities.
- [x] 4.5 Add canonical group generation for sponsor manager and badge-scanner capabilities.
- [x] 4.6 Add canonical group generation for meeting and wiki capabilities.
- [x] 4.7 Map each canonical leaf group to `pgeu-user` plus exactly its matching scoped client role without adding user memberships.
- [x] 4.8 Require the matching fixed `pgeu-*` role and canonical path, rejecting either condition alone and every malformed/mismatched path.
- [x] 4.9 Make existing-realm synchronization idempotent without deleting unrecognized realm state.
- [x] 4.10 Inventory real PGEU resources and render every canonical production leaf group with no membership.

## 5. PGEU Provenance And Reconciliation

- [x] 5.1 Add issuer-plus-subject identity binding and a scoped ledger with client role, group path, resource target, exact materialized relation target, exact scanner-row identity when applicable, ownership, timestamps, and declared unique/foreign database constraints.
- [x] 5.2 Preserve pre-existing local relations as local when an equivalent Keycloak grant appears.
- [x] 5.3 Materialize and record absent allowlisted user-backed relations transactionally.
- [x] 5.4 Materialize and record eligible registration/member-backed relations transactionally.
- [x] 5.5 Materialize and record eligible sponsor, wiki, meeting, and scanner relations transactionally.
- [x] 5.6 Make wiki editor imply effective view without rewriting public/regtype viewer state.
- [x] 5.7 Reconcile the current subject's complete scoped set on an authenticated Keycloak callback.
- [x] 5.8 Remove only Keycloak-owned relations for absent grants on the next callback, including a roleless callback denied after convergence, and preserve protected local collisions.
- [x] 5.9 Invalidate only the exact owned badge-scanner authorization/token while preserving scan history and a later local replacement row.
- [x] 5.10 Prove a second login reconciliation is idempotent.

## 6. Revocation And Session Controls

- [ ] 6.1 Add normal revocation evidence: group removal, next authenticated callback, session invalidation, and negative route check.
- [x] 6.2 Document emergency containment through user/session controls and the absence of out-of-band local reconciliation.
- [x] 6.3 Stop revocation on ambiguous provenance instead of deleting the target relation.
- [x] 6.4 Verify revocation in one scope preserves the same role in a sibling scope.
- [x] 6.5 Verify scoped revocation preserves accepted global roles and unrelated local assignments.

## 7. Disposable Functional Validation

- [x] 7.1 Create disposable series/conference fixtures covering all user-backed role families.
- [x] 7.2 Create disposable eligible registrations covering volunteer, check-in, wiki, and scanner roles.
- [x] 7.3 Create disposable sponsor/benefit, meeting/member, and wiki-page fixtures.
- [x] 7.4 Add positive grant-materialization checks for all twelve scoped roles; wiki editor preview/commit remains gated by 3.6.
- [x] 7.5 Add sibling-scope and no-group negative checks for all scoped role families.
- [x] 7.6 Add local-collision preservation and revoke/callback checks.
- [x] 7.7 Suppress tokens, cookies, OAuth values, credentials, emails, raw claims/rows, and scanner tokens in test output.
- [x] 7.8 Clean disposable assignments/fixtures and restore validation roles even when a test exits early.
- [x] 7.9 Run scoped/global grant and revoke tests only in staging, plus integrated and overlay validations from documented vantage points.
- [x] 7.10 Run a secret-marker scan over every changed artifact and redacted evidence summary.

## 8. Production Convergence At `auth.foss-north.se`

- [x] 8.1 Run and review production role/mapper/empty-group read-only checks against the exact issuer.
- [x] 8.2 Run `--require-empty-memberships` and confirm zero subject assignments, zero direct memberships, zero child groups below managed leaves, and zero superadmin changes.
- [x] 8.3 Apply the reviewed structural manifest with no user grants.
- [x] 8.4 Verify all inventoried real-resource leaf groups exist and every leaf has zero direct memberships and zero child groups.
- [x] 8.5 Rerun production read-only checks and require converged results.
- [x] 8.6 Run final non-mutating health, role/group inventory, global-role inventory non-regression, and integrated-stack checks.

## 9. Documentation And OpenSpec Evidence

- [x] 9.1 Create `docs/Areas/PGEU Authorization.md` with the canonical model and complete runbook.
- [x] 9.2 Update `docs/Areas/Operations.md` with concise gates, commands, vantage points, and canonical-doc link.
- [x] 9.3 Update `docs/Projects/PGEU Compose.md` with dated rollout state, deviations, results, and remaining risks.
- [x] 9.4 Update `docs/Areas/Auth Incident Template.md` with scoped provenance and session-revocation fields.
- [x] 9.5 Update `services/keycloak/README.md` with reproducible role/group/claim generation and safe inspection.
- [x] 9.6 Update `patches/pgeu/README.md` and manifest entries for scoped sync and the wiki guard.
- [x] 9.7 Update `deployment/proxmox/fossnorth-pgeu/RUNBOOK.md` with the disposable staging gate and a link to the canonical exact production check/apply/rollback flow.
- [x] 9.8 Record commands, vantage points, pass/fail summaries, skipped checks, deviations, and rollback state without sensitive output.
- [x] 9.9 Run `openspec validate map-pgeu-scoped-authorization --type change --strict`.
- [x] 9.10 Run `openspec status --change map-pgeu-scoped-authorization` and confirm all artifacts are apply-ready.
