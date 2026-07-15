#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/patches/pgeu/manifest.yaml"
PATCH_ROOT="${ROOT_DIR}/patches/pgeu"

usage() {
  echo "usage: $0 PGEU_SOURCE_DIR" >&2
}

die() {
  echo "error: $*" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

TARGET="$1"

[[ -f "${MANIFEST}" ]] || die "manifest not found: ${MANIFEST}"
[[ -d "${TARGET}" ]] || die "target checkout not found: ${TARGET}"
git -C "${TARGET}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "target is not a Git checkout: ${TARGET}"

pinned_ref="$(awk -F': ' '/^[[:space:]]*pinned_ref:/ {print $2; exit}' "${MANIFEST}")"
repository="$(awk -F': ' '/^[[:space:]]*repository:/ {print $2; exit}' "${MANIFEST}")"

[[ -n "${pinned_ref}" ]] || die "manifest does not contain upstream.pinned_ref"
[[ -n "${repository}" ]] || die "manifest does not contain upstream.repository"

current_ref="$(git -C "${TARGET}" rev-parse HEAD)"
if [[ "${current_ref}" != "${pinned_ref}" ]]; then
  die "target checkout is at ${current_ref}, expected pinned ref ${pinned_ref}"
fi

echo "PGEU patch overlay"
echo "repository: ${repository}"
echo "pinned_ref: ${pinned_ref}"
echo "target: ${TARGET}"

mapfile -t patch_paths < <(
  awk '
    /^[[:space:]]*(path|patch_file):[[:space:]]*/ {
      value=$0
      sub(/^[[:space:]]*(path|patch_file):[[:space:]]*/, "", value)
      gsub(/^"|"$/, "", value)
      if (value != "" && value != "null") {
        print value
      }
    }
  ' "${MANIFEST}" | awk '!seen[$0]++'
)

mapfile -t helper_paths < <(
  awk '
    /^[[:space:]]*helper_script:[[:space:]]*/ {
      value=$0
      sub(/^[[:space:]]*helper_script:[[:space:]]*/, "", value)
      gsub(/^"|"$/, "", value)
      if (value != "" && value != "null") {
        print value
      }
    }
  ' "${MANIFEST}"
)

if [[ "${#patch_paths[@]}" -eq 0 && "${#helper_paths[@]}" -eq 0 ]]; then
  echo "patches: none"
fi

full_patches=()
affected_paths=()
applied_prefix=0

if [[ "${#patch_paths[@]}" -gt 0 ]]; then
  for patch_path in "${patch_paths[@]}"; do
    [[ "${patch_path}" == patches/* ]] || die "patch path must be relative to patches/pgeu/: ${patch_path}"
    full_patch="${PATCH_ROOT}/${patch_path#patches/pgeu/}"
    [[ -f "${full_patch}" ]] || die "patch file not found: ${full_patch}"
    full_patches+=("${full_patch}")
  done

  mapfile -t affected_paths < <(
    for full_patch in "${full_patches[@]}"; do
      git apply --numstat "${full_patch}"
    done | awk -F '\t' 'NF >= 3 { print $3 }' | sort -u
  )

  state_dir="$(mktemp -d "${TMPDIR:-/tmp}/pgeu-patch-state.XXXXXX")"
  trap 'rm -rf "${state_dir}"' EXIT
  worktree_index="${state_dir}/worktree.index"
  GIT_INDEX_FILE="${worktree_index}" git -C "${TARGET}" read-tree HEAD
  GIT_INDEX_FILE="${worktree_index}" git -C "${TARGET}" add -A

  applied_prefix=-1
  for ((candidate=${#full_patches[@]}; candidate >= 0; candidate--)); do
    candidate_index="${state_dir}/candidate-${candidate}.index"
    cp "${worktree_index}" "${candidate_index}"
    candidate_valid=true

    for ((patch_index=candidate - 1; patch_index >= 0; patch_index--)); do
      if ! GIT_INDEX_FILE="${candidate_index}" git -C "${TARGET}" apply --cached --reverse --check "${full_patches[$patch_index]}" >/dev/null 2>&1; then
        candidate_valid=false
        break
      fi
      GIT_INDEX_FILE="${candidate_index}" git -C "${TARGET}" apply --cached --reverse "${full_patches[$patch_index]}"
    done

    if [[ "${candidate_valid}" == "true" ]] && \
       GIT_INDEX_FILE="${candidate_index}" git -C "${TARGET}" diff --cached --quiet HEAD -- "${affected_paths[@]}"; then
      applied_prefix="${candidate}"
      break
    fi
  done

  if [[ "${applied_prefix}" -lt 0 ]]; then
    die "target patch paths do not match the baseline or a cumulative manifest patch prefix"
  fi

  echo "detected cumulative patch prefix: ${applied_prefix}/${#patch_paths[@]}"

  for ((patch_index=0; patch_index < ${#patch_paths[@]}; patch_index++)); do
    patch_path="${patch_paths[$patch_index]}"
    full_patch="${full_patches[$patch_index]}"

    echo "affected paths for ${patch_path}:"
    git apply --numstat "${full_patch}" | awk '{print "  - " $3}' || true

    if [[ "${patch_index}" -lt "${applied_prefix}" ]]; then
      echo "keep: ${patch_path} already applied in cumulative prefix"
    elif git -C "${TARGET}" apply --check "${full_patch}" >/dev/null 2>&1; then
      echo "apply: ${patch_path}"
      git -C "${TARGET}" apply "${full_patch}"
    else
      die "patch cannot be applied cleanly: ${patch_path}"
    fi
  done
fi

if [[ "${#helper_paths[@]}" -gt 0 ]]; then
  for helper_path in "${helper_paths[@]}"; do
    [[ "${helper_path}" == scripts/* ]] || die "helper path must be relative to patches/pgeu/: ${helper_path}"
    full_helper="${PATCH_ROOT}/${helper_path#patches/pgeu/}"
    [[ -f "${full_helper}" ]] || die "helper script not found: ${full_helper}"
    [[ -x "${full_helper}" ]] || die "helper script is not executable: ${helper_path}"
    echo "helper: ${helper_path}"
    "${full_helper}" "${TARGET}"
  done
fi

echo "diff stat:"
validation_index="$(mktemp "${state_dir:-${TMPDIR:-/tmp}}/validation-index.XXXXXX")"
rm -f "${validation_index}"
GIT_INDEX_FILE="${validation_index}" git -C "${TARGET}" read-tree HEAD
GIT_INDEX_FILE="${validation_index}" git -C "${TARGET}" add -A
GIT_INDEX_FILE="${validation_index}" git -C "${TARGET}" diff --cached --stat || true

echo "diff check:"
GIT_INDEX_FILE="${validation_index}" git -C "${TARGET}" diff --cached --check
echo "git diff --check passed"
