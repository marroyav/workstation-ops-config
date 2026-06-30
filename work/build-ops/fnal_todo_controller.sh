#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: fnal_todo_controller.sh [--once] [--seed-current-failed]

Polls fnal.todo on srv17, keeps a remote control status file, and launches
local builds from a dedicated reusable worktree after cleaning it between runs.

Environment:
  FNAL_CONTROL_INTERVAL_SEC   Poll interval in seconds. Default: 120
  FNAL_CONTROL_REMOTE         SSH target. Default: marroyav@np04-srv-017.cern.ch
  FNAL_CONTROL_REMOTE_BASE    Remote base dir. Default: fnal-sync
  FNAL_CONTROL_REMOTE_LOG     Remote event log. Default: fnal.log
  FNAL_CONTROL_STATE_DIR      Local state dir. Default: /home/neutrino/work/build-ops/fnal-control-state
  FNAL_CONTROL_SOURCE_REPO    Git source repo. Default: /home/neutrino/work/daphne-firmware
  FNAL_CONTROL_BUILD_ROOT     Reused clean build root. Default: /mnt/c/w/archive/fnal-build-live
  FNAL_CONTROL_DEFAULT_ROOT   Default status root when idle. Default: /mnt/c/w/d
  FNAL_SYNC_ROOT_FILE         Shared active-root file for fnal_sync_watcher.sh
EOF
}

ONCE=0
SEED_CURRENT_FAILED=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --once)
      ONCE=1
      ;;
    --seed-current-failed)
      SEED_CURRENT_FAILED=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

INTERVAL="${FNAL_CONTROL_INTERVAL_SEC:-120}"
REMOTE="${FNAL_CONTROL_REMOTE:-marroyav@np04-srv-017.cern.ch}"
REMOTE_BASE="${FNAL_CONTROL_REMOTE_BASE:-fnal-sync}"
REMOTE_LOG="${FNAL_CONTROL_REMOTE_LOG:-fnal.log}"
STATE_DIR="${FNAL_CONTROL_STATE_DIR:-/home/neutrino/work/build-ops/fnal-control-state}"
SOURCE_REPO="${FNAL_CONTROL_SOURCE_REPO:-/home/neutrino/work/daphne-firmware}"
BUILD_ROOT="${FNAL_CONTROL_BUILD_ROOT:-/mnt/c/w/archive/fnal-build-live}"
DEFAULT_ROOT="${FNAL_CONTROL_DEFAULT_ROOT:-/mnt/c/w/d}"
SYNC_STATE_DIR="${FNAL_SYNC_STATE_DIR:-/home/neutrino/work/build-ops/fnal-sync-state}"
ROOT_FILE="${FNAL_SYNC_ROOT_FILE:-$SYNC_STATE_DIR/active-root.txt}"
SYNC_WATCHER="${FNAL_CONTROL_SYNC_WATCHER:-/home/neutrino/work/build-ops/fnal_sync_watcher.sh}"
ARCHIVER="${FNAL_CONTROL_ARCHIVER:-/home/neutrino/work/build-ops/fnal_archive_run.sh}"

mkdir -p "$STATE_DIR" "$SYNC_STATE_DIR"

STATUS_FILE="$STATE_DIR/control.txt"
LAST_FILE="$STATE_DIR/last.env"
ACTIVE_FILE="$STATE_DIR/active.env"
LOG_FILE="$STATE_DIR/controller.log"
HISTORY_FILE="$STATE_DIR/history.log"
LAST_REMOTE_KEY_FILE="$STATE_DIR/last-remote-key.txt"

timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

log_info() {
  printf '%s INFO: %s\n' "$(timestamp)" "$*" | tee -a "$LOG_FILE" >/dev/null
}

log_warn() {
  printf '%s WARNING: %s\n' "$(timestamp)" "$*" | tee -a "$LOG_FILE" >/dev/null
}

ssh_remote() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" "$@"
}

kv_line() {
  local key="$1"
  local value="${2-}"
  printf '%s=%q' "$key" "$value"
}

write_env_file() {
  local path="$1"
  shift
  local tmp
  tmp="$(mktemp "$STATE_DIR/.env.XXXXXX")"
  {
    while [[ "$#" -gt 0 ]]; do
      printf '%s\n' "$1"
      shift
    done
  } > "$tmp"
  mv "$tmp" "$path"
}

push_control_file() {
  ssh_remote "mkdir -p \"$REMOTE_BASE/current\" && cat > \"$REMOTE_BASE/current/control.txt\"" < "$STATUS_FILE"
}

append_remote_log_if_changed() {
  local key="$1"
  local line="$2"
  if [[ -f "$LAST_REMOTE_KEY_FILE" && "$key" == "$(cat "$LAST_REMOTE_KEY_FILE")" ]]; then
    return 0
  fi
  printf '%s\n' "$key" > "$LAST_REMOTE_KEY_FILE"
  printf '%s\n' "$line" | ssh_remote "cat >> \"$REMOTE_LOG\""
}

set_state() {
  local state="$1"
  local reason="$2"
  local details="${3-}"

  write_env_file "$STATUS_FILE" \
    "$(kv_line control_state "$state")" \
    "$(kv_line control_reason "$reason")" \
    "$(kv_line control_updated_at "$(timestamp_utc)")" \
    "$(kv_line control_remote "$REMOTE")" \
    "$(kv_line control_build_root "$BUILD_ROOT")" \
    "$(kv_line control_default_root "$DEFAULT_ROOT")" \
    "$(kv_line control_last_todo_checksum "${last_todo_checksum:-}")" \
    "$(kv_line control_last_outcome "${last_outcome:-}")" \
    "$(kv_line control_active_pid "${active_pid:-}")" \
    "$(kv_line control_active_build_root "${active_build_root:-}")" \
    "$(kv_line control_active_commit "${active_commit:-}")" \
    "$(kv_line control_active_branch "${active_branch:-}")" \
    "$(kv_line control_active_target "${active_target:-}")" \
    "$(kv_line control_pending_checksum "${todo_checksum:-}")" \
    "$(kv_line control_requested_entrypoint "${todo_entrypoint:-}")" \
    "$(kv_line control_requested_path "${todo_path_win:-}")" \
    "$(kv_line control_details "$details")"

  push_control_file || true
  printf '%s\tstate=%s\treason=%s\tdetails=%s\n' "$(timestamp_utc)" "$state" "$reason" "$details" >> "$HISTORY_FILE"
  append_remote_log_if_changed \
    "control=$state reason=$reason checksum=${todo_checksum:-none} active_pid=${active_pid:-none}" \
    "[$(timestamp_utc)] control=$state reason=$reason checksum=${todo_checksum:-none} active_pid=${active_pid:-none} details=$details" || true
}

fetch_remote_todo() {
  ssh_remote "cat ~/fnal.todo 2>/dev/null || true"
}

todo_has_work() {
  printf '%s\n' "$1" | grep -Eq '^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*.+$'
}

checksum_for_text() {
  printf '%s' "$1" | cksum | awk '{print $1 ":" $2}'
}

parse_todo() {
  local content="$1"
  local line key value

  todo_action=""
  todo_entrypoint=""
  todo_path_win=""
  todo_target=""
  todo_notes=""
  todo_branch=""
  todo_commit=""

  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    key="${line%%:*}"
    value="${line#*:}"
    key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g')"
    value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//')"
    case "$key" in
      action) todo_action="$value" ;;
      entrypoint) todo_entrypoint="$value" ;;
      path) todo_path_win="$value" ;;
      target) todo_target="$value" ;;
      notes) todo_notes="$value" ;;
    esac
  done <<< "$content"

  if [[ "$todo_entrypoint" == *"@"* ]]; then
    todo_branch="${todo_entrypoint%@*}"
    todo_commit="${todo_entrypoint##*@}"
  else
    todo_commit="$todo_entrypoint"
  fi
}

write_last_file() {
  write_env_file "$LAST_FILE" \
    "$(kv_line last_todo_checksum "${last_todo_checksum:-}")" \
    "$(kv_line last_outcome "${last_outcome:-}")" \
    "$(kv_line last_handled_at "${last_handled_at:-}")" \
    "$(kv_line last_entrypoint "${last_entrypoint:-}")"
}

write_active_file() {
  write_env_file "$ACTIVE_FILE" \
    "$(kv_line active_pid "${active_pid:-}")" \
    "$(kv_line active_checksum "${active_checksum:-}")" \
    "$(kv_line active_build_root "${active_build_root:-}")" \
    "$(kv_line active_commit "${active_commit:-}")" \
    "$(kv_line active_branch "${active_branch:-}")" \
    "$(kv_line active_target "${active_target:-}")" \
    "$(kv_line active_started_at "${active_started_at:-}")" \
    "$(kv_line active_launch_log "${active_launch_log:-}")"
}

active_pid_running() {
  [[ -n "${active_pid:-}" ]] || return 1
  kill -0 "$active_pid" 2>/dev/null
}

trigger_sync_once() {
  if [[ -x "$SYNC_WATCHER" ]]; then
    FNAL_SYNC_ROOT_FILE="$ROOT_FILE" "$SYNC_WATCHER" --once >/dev/null 2>&1 || true
  fi
}

detect_outcome() {
  local root="$1"
  local commit="$2"
  local log_path=""

  for candidate in "$root/xilinx/vivado.log" "$root/vivado.log"; do
    if [[ -f "$candidate" ]]; then
      log_path="$candidate"
      break
    fi
  done

  if find "$root" -type f \( -name '*.bit' -o -name '*.bin' -o -name '*.xsa' \) 2>/dev/null | grep -q .; then
    printf '%s\n' "succeeded"
    return 0
  fi

  if [[ -n "$log_path" ]] && rg -q 'ERROR:|failed due to earlier errors|Exiting Vivado' "$log_path"; then
    printf '%s\n' "failed"
    return 0
  fi

  printf '%s\n' "stopped"
}

ensure_commit_available() {
  if git -C "$SOURCE_REPO" rev-parse --verify "${todo_commit}^{commit}" >/dev/null 2>&1; then
    return 0
  fi

  if [[ -n "$todo_branch" ]]; then
    git -C "$SOURCE_REPO" fetch --prune origin "$todo_branch"
  else
    git -C "$SOURCE_REPO" fetch --prune origin
  fi

  git -C "$SOURCE_REPO" rev-parse --verify "${todo_commit}^{commit}" >/dev/null 2>&1
}

prepare_build_root() {
  mkdir -p "$(dirname "$BUILD_ROOT")"

  if [[ -e "$BUILD_ROOT/.git" ]]; then
    git -C "$BUILD_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1
    git -C "$BUILD_ROOT" reset --hard HEAD
    git -C "$BUILD_ROOT" clean -fdx
    git -C "$BUILD_ROOT" checkout --detach "$todo_commit"
    return 0
  fi

  git -C "$SOURCE_REPO" worktree add --force --detach "$BUILD_ROOT" "$todo_commit"
}

launch_build() {
  local launch_log target stop_after_synth launch_cmd pid

  ensure_commit_available || {
    set_state blocked missing_commit "commit_not_available:$todo_entrypoint"
    return 1
  }

  prepare_build_root || {
    set_state failed prepare_failed "prepare_build_root_failed:$BUILD_ROOT"
    return 1
  }

  printf '%s\n' "$BUILD_ROOT" > "$ROOT_FILE"
  trigger_sync_once

  target="${todo_target:-impl}"
  stop_after_synth=0
  if [[ "$todo_action" == "synth" || "$todo_notes" == *"DAPHNE_STOP_AFTER_SYNTH=1"* ]]; then
    stop_after_synth=1
  fi

  launch_log="$STATE_DIR/run-${todo_commit}-$(date +%Y%m%d-%H%M%S).log"
  launch_cmd="cd '$BUILD_ROOT' && export DAPHNE_GIT_SHA='$todo_commit' && unset DAPHNE_PLATFORM_CORE DAPHNE_PLATFORM_TARGET DAPHNE_BD_NAME DAPHNE_BD_WRAPPER_NAME && if [ '$stop_after_synth' = '1' ]; then export DAPHNE_STOP_AFTER_SYNTH=1; else unset DAPHNE_STOP_AFTER_SYNTH; fi && ./scripts/fusesoc/build_platform.sh --composable --target '$target'"

  pid="$(bash -lc "nohup bash -lc $(printf '%q' "$launch_cmd") > $(printf '%q' "$launch_log") 2>&1 & echo \$!")"

  active_pid="$pid"
  active_checksum="$todo_checksum"
  active_build_root="$BUILD_ROOT"
  active_commit="$todo_commit"
  active_branch="$todo_branch"
  active_target="$target"
  active_started_at="$(timestamp_utc)"
  active_launch_log="$launch_log"
  write_active_file

  set_state launching launch_started "commit=$todo_commit target=$target pid=$pid build_root=$BUILD_ROOT"
  append_remote_log_if_changed \
    "launch=$todo_checksum commit=$todo_commit target=$target pid=$pid" \
    "[$(timestamp_utc)] status=launching commit=$todo_commit branch=${todo_branch:-detached} root=$BUILD_ROOT target=$target note=fnal.todo" || true
  set_state running active_build "commit=$todo_commit target=$target pid=$pid"
  return 0
}

finalize_active_if_needed() {
  local outcome

  if active_pid_running; then
    set_state running active_build "commit=${active_commit:-} pid=${active_pid:-}"
    return 0
  fi

  [[ -n "${active_checksum:-}" ]] || return 0

  trigger_sync_once
  outcome="$(detect_outcome "${active_build_root:-$BUILD_ROOT}" "${active_commit:-unknown}")"
  if [[ -x "$ARCHIVER" ]]; then
    "$ARCHIVER" "${active_build_root:-$BUILD_ROOT}" "$outcome" >> "$LOG_FILE" 2>&1 || true
  fi

  last_todo_checksum="$active_checksum"
  last_outcome="$outcome"
  last_handled_at="$(timestamp_utc)"
  last_entrypoint="${active_branch:+$active_branch@}${active_commit:-}"
  write_last_file

  append_remote_log_if_changed \
    "finish=$active_checksum outcome=$outcome commit=${active_commit:-}" \
    "[$(timestamp_utc)] status=$outcome commit=${active_commit:-unknown} branch=${active_branch:-detached} root=${active_build_root:-$BUILD_ROOT} target=${active_target:-unknown}" || true

  set_state "$outcome" run_finished "commit=${active_commit:-} outcome=$outcome"

  active_pid=""
  active_checksum=""
  active_build_root=""
  active_commit=""
  active_branch=""
  active_target=""
  active_started_at=""
  active_launch_log=""
  write_active_file
}

seed_current_failure() {
  local content
  content="$(fetch_remote_todo)"
  todo_checksum=""
  if todo_has_work "$content"; then
    todo_checksum="$(checksum_for_text "$content")"
    parse_todo "$content"
    last_todo_checksum="$todo_checksum"
    last_outcome="failed"
    last_handled_at="$(timestamp_utc)"
    last_entrypoint="$todo_entrypoint"
    write_last_file
    set_state idle seeded_current_failure "checksum=$todo_checksum entrypoint=$todo_entrypoint"
  fi
}

validate_interval() {
  case "$INTERVAL" in
    ''|*[!0-9]*)
      echo "ERROR: FNAL_CONTROL_INTERVAL_SEC must be a positive integer." >&2
      exit 2
      ;;
    0)
      echo "ERROR: FNAL_CONTROL_INTERVAL_SEC must be greater than zero." >&2
      exit 2
      ;;
  esac
}

last_todo_checksum=""
last_outcome=""
last_handled_at=""
last_entrypoint=""
active_pid=""
active_checksum=""
active_build_root=""
active_commit=""
active_branch=""
active_target=""
active_started_at=""
active_launch_log=""
todo_checksum=""
todo_action=""
todo_entrypoint=""
todo_path_win=""
todo_target=""
todo_notes=""
todo_branch=""
todo_commit=""

if [[ -f "$LAST_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$LAST_FILE"
fi

if [[ -f "$ACTIVE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ACTIVE_FILE"
fi

validate_interval
printf '%s\n' "$DEFAULT_ROOT" > "$ROOT_FILE"

if [[ "$SEED_CURRENT_FAILED" -eq 1 ]]; then
  seed_current_failure
fi

while true; do
  finalize_active_if_needed

  todo_content="$(fetch_remote_todo || true)"
  if ! todo_has_work "$todo_content"; then
    todo_checksum=""
    set_state idle no_todo "remote_todo_empty"
  else
    todo_checksum="$(checksum_for_text "$todo_content")"
    parse_todo "$todo_content"

    if active_pid_running; then
      if [[ "$todo_checksum" != "${active_checksum:-}" ]]; then
        set_state blocked active_build "new_todo_waiting checksum=$todo_checksum"
      else
        set_state running active_build "same_todo_still_running checksum=$todo_checksum"
      fi
    elif [[ "$todo_checksum" == "${last_todo_checksum:-}" ]]; then
      set_state idle already_handled "checksum=$todo_checksum outcome=${last_outcome:-unknown}"
    else
      set_state acknowledged new_todo "checksum=$todo_checksum entrypoint=$todo_entrypoint"
      launch_build || true
    fi
  fi

  if [[ "$ONCE" -eq 1 ]]; then
    exit 0
  fi
  sleep "$INTERVAL"
done
