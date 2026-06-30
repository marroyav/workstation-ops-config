#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: github_build_artifact_watcher.sh [--once] [--seed-current]

Watches for successful DAPHNE overlay zips under /w and /mnt/c/w and, when a
GitHub token is configured, uploads each new zip to a dedicated GitHub release
and upserts a commit comment that links to the asset.

Environment:
  DAPHNE_GITHUB_WATCH_ROOTS        Colon-separated roots to scan.
                                   Default: /w:/mnt/c/w
  DAPHNE_GITHUB_WATCH_INTERVAL_SEC Poll interval. Default: 120
  DAPHNE_GITHUB_STATE_DIR          State dir.
                                   Default: /home/neutrino/work/build-ops/github-build-state
  DAPHNE_GITHUB_REPO               Repo slug. Default: DUNE-DAQ/daphne-firmware
  DAPHNE_GITHUB_TOKEN_FILE         Token file path.
                                   Default: ~/.config/daphne-build-ops/github-token
  DAPHNE_GITHUB_RELEASE_TAG        Release tag used for uploaded zips.
                                   Default: daphne-build-artifacts
  DAPHNE_GITHUB_RELEASE_NAME       Release name.
                                   Default: DAPHNE Build Artifacts
EOF
}

ONCE=0
SEED_CURRENT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)
      ONCE=1
      shift
      ;;
    --seed-current)
      SEED_CURRENT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

WATCH_ROOTS="${DAPHNE_GITHUB_WATCH_ROOTS:-/w:/mnt/c/w}"
INTERVAL_SEC="${DAPHNE_GITHUB_WATCH_INTERVAL_SEC:-120}"
STATE_DIR="${DAPHNE_GITHUB_STATE_DIR:-/home/neutrino/work/build-ops/github-build-state}"
REPO_SLUG="${DAPHNE_GITHUB_REPO:-DUNE-DAQ/daphne-firmware}"
TOKEN_FILE="${DAPHNE_GITHUB_TOKEN_FILE:-$HOME/.config/daphne-build-ops/github-token}"
RELEASE_TAG="${DAPHNE_GITHUB_RELEASE_TAG:-daphne-build-artifacts}"
RELEASE_NAME="${DAPHNE_GITHUB_RELEASE_NAME:-DAPHNE Build Artifacts}"
PUBLISHER_PY="${DAPHNE_GITHUB_PUBLISHER_PY:-/home/neutrino/work/build-ops/github_commit_zip_publisher.py}"

mkdir -p "$STATE_DIR/seen"
STATUS_FILE="$STATE_DIR/status.txt"
LOG_FILE="$STATE_DIR/history.log"

timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

status() {
  local message="$1"
  printf '[%s] %s\n' "$(timestamp_utc)" "$message" | tee -a "$LOG_FILE" > "$STATUS_FILE"
}

have_token() {
  [[ -n "${DAPHNE_GITHUB_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-${GITHUB_PAT:-}}}}" ]] && return 0
  [[ -s "$TOKEN_FILE" ]]
}

iter_watch_roots() {
  local old_ifs="$IFS"
  IFS=':'
  for root in $WATCH_ROOTS; do
    [[ -d "$root" ]] && printf '%s\n' "$root"
  done
  IFS="$old_ifs"
}

find_overlay_zips() {
  local root
  while IFS= read -r root; do
    find "$root" -type f \( -name '*_ol_*.zip' -o -name '*_OL_*.zip' \) 2>/dev/null || true
  done < <(iter_watch_roots)
}

asset_commit_short() {
  local asset_name="$1"
  sed -nE 's/^.*_[oO][lL]_([0-9a-f]{7,40})\.zip$/\1/p' <<<"$asset_name"
}

asset_state_file() {
  local zip_path="$1"
  local key
  key="$(printf '%s' "$zip_path" | sha1sum | awk '{print $1}')"
  printf '%s/seen/%s.env\n' "$STATE_DIR" "$key"
}

write_state() {
  local state_file="$1"
  local zip_path="$2"
  local digest="$3"
  local commit_sha="$4"
  local state_kind="${5:-published}"
  cat >"$state_file" <<EOF
zip_path=$zip_path
digest=$digest
commit=$commit_sha
state=$state_kind
updated_at=$(timestamp_utc)
EOF
}

read_state_digest() {
  local state_file="$1"
  [[ -f "$state_file" ]] || return 0
  sed -n 's/^digest=//p' "$state_file" | head -n 1
}

read_state_kind() {
  local state_file="$1"
  [[ -f "$state_file" ]] || return 0
  sed -n 's/^state=//p' "$state_file" | head -n 1
}

resolve_full_commit() {
  local short_sha="$1"
  local candidate full_sha
  declare -A seen=()

  while IFS= read -r root; do
    while IFS= read -r candidate; do
      [[ -d "$candidate" ]] || continue
      if full_sha="$(git -C "$candidate" rev-parse --verify "${short_sha}^{commit}" 2>/dev/null)"; then
        seen["$full_sha"]=1
      fi
    done < <(find "$root" -maxdepth 1 -mindepth 1 -type d -print 2>/dev/null)
  done < <(iter_watch_roots)

  if [[ ${#seen[@]} -eq 1 ]]; then
    for full_sha in "${!seen[@]}"; do
      printf '%s\n' "$full_sha"
      return 0
    done
  fi

  printf '%s\n' "$short_sha"
}

process_zip() {
  local zip_path="$1"
  local asset_name short_sha digest state_file previous_digest previous_kind full_sha

  asset_name="$(basename "$zip_path")"
  short_sha="$(asset_commit_short "$asset_name")"
  [[ -n "$short_sha" ]] || return 0

  [[ -f "$(dirname "$zip_path")/SHA256SUMS" ]] || return 0

  digest="$(sha256sum "$zip_path" | awk '{print $1}')"
  state_file="$(asset_state_file "$zip_path")"
  previous_digest="$(read_state_digest "$state_file")"
  previous_kind="$(read_state_kind "$state_file")"

  if [[ "$digest" == "$previous_digest" && "$previous_kind" != "pending" ]]; then
    return 0
  fi

  if [[ "$SEED_CURRENT" == "1" ]]; then
    write_state "$state_file" "$zip_path" "$digest" "$short_sha" "seeded"
    status "seeded existing artifact: $zip_path"
    return 0
  fi

  if ! have_token; then
    if [[ "$digest" != "$previous_digest" || "$previous_kind" != "pending" ]]; then
      write_state "$state_file" "$zip_path" "$digest" "$short_sha" "pending"
      status "waiting for GitHub token before publishing: $zip_path"
    fi
    return 0
  fi

  full_sha="$(resolve_full_commit "$short_sha")"
  status "publishing artifact for commit=$full_sha zip=$zip_path"
  if python3 "$PUBLISHER_PY" \
      --repo "$REPO_SLUG" \
      --commit "$full_sha" \
      --zip "$zip_path" \
      --token-file "$TOKEN_FILE" \
      --release-tag "$RELEASE_TAG" \
      --release-name "$RELEASE_NAME" \
      >"$STATE_DIR/last-publish.json"; then
    write_state "$state_file" "$zip_path" "$digest" "$full_sha" "published"
    status "published artifact for commit=$full_sha zip=$zip_path"
    return 0
  fi

  status "publish failed for zip=$zip_path"
  return 1
}

scan_once() {
  local zip_path
  while IFS= read -r zip_path; do
    [[ -n "$zip_path" ]] || continue
    process_zip "$zip_path"
  done < <(find_overlay_zips | sort -u)
}

status "watcher starting"

while true; do
  scan_once
  if [[ "$ONCE" == "1" ]]; then
    status "watcher finished single pass"
    exit 0
  fi
  sleep "$INTERVAL_SEC"
done
