# Patch: example-short-name

## Purpose

Explain what this patch changes and why the compose integration needs it.

## Upstream Files Changed

- `path/in/pgeu-system`

## Patch Artifacts

- Patch file: `patches/pgeu/patches/NNN-short-name.patch`
- Optional helper script: `patches/pgeu/scripts/optional-helper.sh`
- Apply command: `scripts/apply-pgeu-patches.sh "${PGEU_SOURCE_DIR}"`

## Validation

```bash
scripts/apply-pgeu-patches.sh "${PGEU_SOURCE_DIR}"
git -C "${PGEU_SOURCE_DIR}" diff --stat
git -C "${PGEU_SOURCE_DIR}" diff --check
```

## Upstream Readiness

Classification: `temporary-local-only`, `plugin-candidate`, or
`pull-request-candidate`.

Record the intended plugin or pull-request path if applicable, and explain what
upstream change would make this patch smaller or removable.

## Removal Criteria

Describe when this patch can be removed safely.

## Upgrade Notes

Describe what must be rechecked when moving to a new upstream release, tag, or
commit.
