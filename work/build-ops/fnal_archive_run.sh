#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: fnal_archive_run.sh [run_root] [label]

Copies the current run logs and requested debug reports into the FNAL archive.

Environment:
  FNAL_ARCHIVE_REMOTE        SSH target. Default: marroyav@np04-srv-017.cern.ch
  FNAL_ARCHIVE_REMOTE_BASE   Remote base dir, relative to remote home. Default: fnal-sync
  FNAL_ARCHIVE_REMOTE_LOG    Remote event log, relative to remote home. Default: fnal.log
  FNAL_ARCHIVE_STATE_DIR     Local scratch dir. Default: /home/neutrino/work/build-ops/fnal-archive-state
  FNAL_SYNC_ROOT_FILE        Optional active-root file used when run_root is omitted
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REMOTE="${FNAL_ARCHIVE_REMOTE:-marroyav@np04-srv-017.cern.ch}"
REMOTE_BASE="${FNAL_ARCHIVE_REMOTE_BASE:-fnal-sync}"
REMOTE_LOG="${FNAL_ARCHIVE_REMOTE_LOG:-fnal.log}"
STATE_DIR="${FNAL_ARCHIVE_STATE_DIR:-/home/neutrino/work/build-ops/fnal-archive-state}"
SYNC_ROOT_FILE="${FNAL_SYNC_ROOT_FILE:-/home/neutrino/work/build-ops/fnal-sync-state/active-root.txt}"

mkdir -p "$STATE_DIR"

resolve_root_dir() {
  if [[ -n "${1:-}" ]]; then
    printf '%s\n' "$1"
    return 0
  fi

  if [[ -f "$SYNC_ROOT_FILE" ]]; then
    sed -n '1p' "$SYNC_ROOT_FILE"
    return 0
  fi

  printf '%s\n' "/mnt/c/w/d"
}

ROOT_DIR="$(resolve_root_dir "${1:-}")"
LABEL="${2:-${FNAL_ARCHIVE_LABEL:-manual}}"

timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}

ssh_remote() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" "$@"
}

append_remote_log() {
  local line="$1"
  printf '%s\n' "$line" | ssh_remote "cat >> \"$REMOTE_LOG\""
}

copy_if_present() {
  local source_path="$1"
  local remote_dir="$2"
  local remote_name="$3"

  if [[ -f "$source_path" ]]; then
    rsync -az "$source_path" "$REMOTE:$remote_dir/$remote_name"
    printf 'FOUND %s\n' "$source_path" >> "$MANIFEST_FILE"
    return 0
  fi

  printf 'MISSING %s\n' "$source_path" >> "$MANIFEST_FILE"
  return 1
}

extract_git_sha() {
  local log_path="$1"
  if [[ -f "$log_path" ]]; then
    rg -o 'DAPHNE_GIT_SHA=[0-9a-f]+' "$log_path" | head -n 1 | cut -d= -f2 || true
  fi
}

extract_first_block() {
  local log_path="$1"
  local pattern="$2"
  local output_path="$3"
  local line_no start_line end_line

  [[ -f "$log_path" ]] || return 1
  line_no="$(rg -n "$pattern" "$log_path" | head -n 1 | cut -d: -f1 || true)"
  [[ -n "$line_no" ]] || return 1

  start_line=$((line_no > 40 ? line_no - 40 : 1))
  end_line=$((line_no + 120))
  sed -n "${start_line},${end_line}p" "$log_path" > "$output_path"
}

RUN_TS="$(timestamp_utc)"
TMP_DIR="$(mktemp -d "$STATE_DIR/archive.XXXXXX")"
SUMMARY_FILE="$TMP_DIR/summary.txt"
MANIFEST_FILE="$TMP_DIR/manifest.txt"
PLACE_BLOCK_FILE="$TMP_DIR/first-place-30-716-block.txt"
trap 'rm -rf "$TMP_DIR"' EXIT

ROOT_VIVADO_LOG="$ROOT_DIR/vivado.log"
XILINX_VIVADO_LOG="$ROOT_DIR/xilinx/vivado.log"
PRIMARY_LOG="$XILINX_VIVADO_LOG"
if [[ ! -f "$PRIMARY_LOG" ]]; then
  PRIMARY_LOG="$ROOT_VIVADO_LOG"
fi

COMMIT_SHA="$(extract_git_sha "$PRIMARY_LOG")"
if [[ -z "$COMMIT_SHA" && -e "$ROOT_DIR/.git" ]]; then
  COMMIT_SHA="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || true)"
fi
: "${COMMIT_SHA:=unknown}"

BRANCH_NAME="unknown"
if [[ -e "$ROOT_DIR/.git" ]]; then
  BRANCH_NAME="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi

ARCHIVE_ID="${RUN_TS}-${COMMIT_SHA}-${LABEL}"
REMOTE_DIR="${REMOTE_BASE}/archive/${ARCHIVE_ID}"

{
  printf 'archived_at_utc=%s\n' "$RUN_TS"
  printf 'root_dir=%s\n' "$ROOT_DIR"
  printf 'branch=%s\n' "$BRANCH_NAME"
  printf 'commit=%s\n' "$COMMIT_SHA"
  printf 'label=%s\n' "$LABEL"
  if [[ -f "$PRIMARY_LOG" ]]; then
    printf 'primary_log=%s\n' "$PRIMARY_LOG"
    printf 'primary_log_size=%s\n' "$(stat -c '%s' "$PRIMARY_LOG" 2>/dev/null || true)"
    printf 'primary_log_mtime=%s\n' "$(stat -c '%y' "$PRIMARY_LOG" 2>/dev/null || true)"
  fi
} > "$SUMMARY_FILE"

{
  printf 'archive_id=%s\n' "$ARCHIVE_ID"
  printf 'root_dir=%s\n' "$ROOT_DIR"
  printf 'branch=%s\n' "$BRANCH_NAME"
  printf 'commit=%s\n' "$COMMIT_SHA"
  printf 'label=%s\n' "$LABEL"
} > "$MANIFEST_FILE"

ssh_remote "mkdir -p \"$REMOTE_DIR\""

copy_if_present "$ROOT_VIVADO_LOG" "$REMOTE_DIR" "root-vivado.log" || true
copy_if_present "$XILINX_VIVADO_LOG" "$REMOTE_DIR" "xilinx-vivado.log" || true

DEBUG_ROOT=""
for candidate in \
  "$ROOT_DIR/xilinx/output-$COMMIT_SHA/debug" \
  "$ROOT_DIR/output-$COMMIT_SHA/debug"
do
  if [[ -d "$candidate" ]]; then
    DEBUG_ROOT="$candidate"
    break
  fi
done

if [[ -n "$DEBUG_ROOT" ]]; then
  printf 'DEBUG_ROOT %s\n' "$DEBUG_ROOT" >> "$MANIFEST_FILE"
  copy_if_present "$DEBUG_ROOT/post_synth_clocks_pre_constraints.rpt" "$REMOTE_DIR" "post_synth_clocks_pre_constraints.rpt" || true
  copy_if_present "$DEBUG_ROOT/endpoint_pins_pre_constraints.txt" "$REMOTE_DIR" "endpoint_pins_pre_constraints.txt" || true
  copy_if_present "$DEBUG_ROOT/endpoint_nets_pre_constraints.txt" "$REMOTE_DIR" "endpoint_nets_pre_constraints.txt" || true
else
  printf 'MISSING_DEBUG_ROOT %s\n' "$ROOT_DIR/xilinx/output-$COMMIT_SHA/debug" >> "$MANIFEST_FILE"
  printf 'MISSING_DEBUG_ROOT %s\n' "$ROOT_DIR/output-$COMMIT_SHA/debug" >> "$MANIFEST_FILE"
fi

if extract_first_block "$PRIMARY_LOG" 'Place 30-716' "$PLACE_BLOCK_FILE"; then
  rsync -az "$PLACE_BLOCK_FILE" "$REMOTE:$REMOTE_DIR/first-place-30-716-block.txt"
  printf 'FOUND first Place 30-716 block in %s\n' "$PRIMARY_LOG" >> "$MANIFEST_FILE"
else
  printf 'MISSING first Place 30-716 block in %s\n' "$PRIMARY_LOG" >> "$MANIFEST_FILE"
fi

rsync -az "$SUMMARY_FILE" "$REMOTE:$REMOTE_DIR/summary.txt"
rsync -az "$MANIFEST_FILE" "$REMOTE:$REMOTE_DIR/manifest.txt"

append_remote_log "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] note=archived path=~/$REMOTE_DIR commit=$COMMIT_SHA branch=$BRANCH_NAME label=$LABEL"
printf '%s\n' "$REMOTE_DIR"
