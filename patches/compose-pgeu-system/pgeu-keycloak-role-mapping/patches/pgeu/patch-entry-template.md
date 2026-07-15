# PGEU Patch Entry Template

Copy this shape into `patches/pgeu/manifest.yaml` when adding a local upstream
patch. Keep the patch note short enough that an operator can understand the
local delta without reading the whole upstream repository.

```yaml
patches:
  - id: keycloak-oauth-handler
    apply_order: 10
    purpose: Add the smallest required Keycloak/OIDC integration point.
    upstream_files_changed:
      - postgresqleu/oauthlogin/oauthclient.py
    affected_paths:
      - postgresqleu/oauthlogin/oauthclient.py
    patch_file: patches/keycloak-oauth-handler.patch
    path: patches/keycloak-oauth-handler.patch
    helper_script: null
    apply_command: scripts/apply-pgeu-patches.sh "${PGEU_SOURCE_DIR}"
    validation:
      - git -C "${PGEU_SOURCE_DIR}" diff --stat
      - git -C "${PGEU_SOURCE_DIR}" diff --check
      - Run the relevant SSO smoke check with redirect parameters redacted.
    readiness:
      class: plugin_candidate
      rationale: Prefer a PGEU extension point if upstream exposes one.
      upstream_path: Describe what would need to change before proposing this.
    removal_criteria: Remove when upstream or a plugin provides equivalent behavior.
    upgrade_notes: Re-check the touched upstream files whenever the baseline moves.
```

Use `helper_script` only when a patch file cannot express the change clearly.
The helper script must be idempotent, documented in the manifest, and leave a
reviewable diff.
