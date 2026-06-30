#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: fnal_sync_watcher.sh [--once] [repo_root]

Pushes lightweight build status plus Vivado logs to the CERN host.

Environment:
  FNAL_SYNC_INTERVAL_SEC   Poll interval in seconds. Default: 120
  FNAL_SYNC_REMOTE         SSH target. Default: marroyav@np04-srv-017.cern.ch
  FNAL_SYNC_REMOTE_BASE    Remote base dir, relative to remote home. Default: fnal-sync
  FNAL_SYNC_REMOTE_LOG     Remote summary log, relative to remote home. Default: fnal.log
  FNAL_SYNC_STATE_DIR      Local state dir. Default: /home/neutrino/work/build-ops/fnal-sync-state
  FNAL_SYNC_ROOT_FILE      Optional file whose contents override repo_root on
                           each poll. Useful when another controller switches
                           between dedicated build worktrees.
EOF
}

ONCE=0
if [[ "${1:-}" == "--once" ]]; then
  ONCE=1
  shift
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DEFAULT_ROOT_DIR="${1:-${ROOT_DIR:-/mnt/c/w/d}}"
INTERVAL="${FNAL_SYNC_INTERVAL_SEC:-120}"
REMOTE="${FNAL_SYNC_REMOTE:-marroyav@np04-srv-017.cern.ch}"
REMOTE_BASE="${FNAL_SYNC_REMOTE_BASE:-fnal-sync}"
REMOTE_LOG="${FNAL_SYNC_REMOTE_LOG:-fnal.log}"
STATE_DIR="${FNAL_SYNC_STATE_DIR:-/home/neutrino/work/build-ops/fnal-sync-state}"
ROOT_FILE="${FNAL_SYNC_ROOT_FILE:-$STATE_DIR/active-root.txt}"

mkdir -p "$STATE_DIR"

STATUS_FILE="$STATE_DIR/status.txt"
TAIL_FILE="$STATE_DIR/vivado.tail.txt"
SUMMARY_FILE="$STATE_DIR/summary.txt"
LAST_SUMMARY_FILE="$STATE_DIR/last-summary.txt"
LAST_SUMMARY_KEY_FILE="$STATE_DIR/last-summary-key.txt"
EMPTY_REPORTS_DIR="$STATE_DIR/empty-reports"
REPORTS_MANIFEST_FILE="$STATE_DIR/reports-manifest.txt"

mkdir -p "$EMPTY_REPORTS_DIR"

resolve_root_dir() {
  local candidate=""

  if [[ -f "$ROOT_FILE" ]]; then
    candidate="$(sed -n '1p' "$ROOT_FILE" 2>/dev/null || true)"
  fi

  if [[ -n "$candidate" && -d "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  printf '%s\n' "$DEFAULT_ROOT_DIR"
}

log_has_re() {
  local log_path="$1"
  local pattern="$2"
  [[ -n "$log_path" && -f "$log_path" ]] || return 1
  grep -aEq "$pattern" "$log_path"
}

collect_milestones() {
  local log_path="$1"
  local artifacts="$2"
  local -a milestones=()
  local artifact

  # If the generated project/control TCL exists, FuseSoC setup succeeded and
  # the packaged-IP preflight plus native graph audit have already completed.
  if find "$ROOT_DIR/build" -maxdepth 3 -type f \( -name 'k26c_comp.tcl' -o -name 'k26c_mod.tcl' -o -name 'k26c_legacy.tcl' \) 2>/dev/null | grep -q .; then
    milestones+=("preflight-passed")
    milestones+=("graph-ready")
  fi

  if log_has_re "$log_path" 'Starting synth_design|Waiting for synth_1 to finish|Command: synth_design'; then
    milestones+=("synth-started")
  fi

  if log_has_re "$log_path" 'Done setting XDC timing constraints'; then
    milestones+=("constraints-done")
  fi
  if log_has_re "$log_path" 'synth_design completed successfully|synth_1 finished'; then
    milestones+=("synth-passed")
  fi
  if log_has_re "$log_path" 'Running DRC as a precondition to command opt_design|Command: opt_design|opt_design -directive'; then
    milestones+=("opt-started")
  fi
  if log_has_re "$log_path" 'place_design'; then
    milestones+=("place-started")
  fi
  if log_has_re "$log_path" 'route_design|post_route|write_checkpoint -force .*post_route'; then
    milestones+=("route-started")
  fi
  if log_has_re "$log_path" 'write_bitstream'; then
    milestones+=("bitstream-started")
  fi
  if log_has_re "$log_path" 'write_hw_platform'; then
    milestones+=("xsa-started")
  fi
  if log_has_re "$log_path" 'ERROR:|failed due to earlier errors|Failed runs\(s\)|opt_design failed|place_design failed|route_design failed'; then
    milestones+=("run-failed")
  fi

  while IFS= read -r artifact; do
    [[ -n "$artifact" ]] || continue
    case "$artifact" in
      *.bit) milestones+=("bit-ready") ;;
      *.bin) milestones+=("bin-ready") ;;
      *.xsa) milestones+=("xsa-ready") ;;
    esac
  done <<< "$artifacts"

  printf '%s\n' "${milestones[@]}" | awk 'NF' | sort -u
}

find_last_error_line() {
  local log_path="$1"
  [[ -n "$log_path" && -f "$log_path" ]] || return 0
  grep -a 'ERROR:' "$log_path" | tail -n 1 | tr '\r' ' ' | tr '\n' ' ' || true
}

join_lines_csv() {
  awk 'NF { out = out (out ? "," : "") $0 } END { print out }'
}

find_vivado_log() {
  local candidate
  for candidate in \
    "$ROOT_DIR/build/k26c_comp/impl/vivado.log" \
    "$ROOT_DIR/build/k26c_mod/impl/vivado.log" \
    "$ROOT_DIR/build/k26c_legacy/impl/vivado.log" \
    "$ROOT_DIR/vivado.log" \
    "$ROOT_DIR/xilinx/vivado.log"
  do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  find "$ROOT_DIR/build" -type f -name vivado.log 2>/dev/null | sort | head -n 1 || true
}

find_artifacts() {
  {
    find "$ROOT_DIR/build" -type f \( -name '*.bit' -o -name '*.bin' -o -name '*.xsa' \) 2>/dev/null
    find "$ROOT_DIR/xilinx" -type f \( -name '*.bit' -o -name '*.bin' -o -name '*.xsa' \) 2>/dev/null
  } | sort -u || true
}

find_report_root() {
  local commit="$1"
  local candidate latest=""

  for candidate in \
    "$ROOT_DIR/xilinx/output-$commit" \
    "$ROOT_DIR/output-$commit" \
    "$ROOT_DIR/xilinx/output" \
    "$ROOT_DIR/output"
  do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  latest="$(
    {
      find "$ROOT_DIR/xilinx" -maxdepth 1 -mindepth 1 -type d -name 'output-*' -printf '%T@ %p\n' 2>/dev/null || true
      find "$ROOT_DIR" -maxdepth 1 -mindepth 1 -type d -name 'output-*' -printf '%T@ %p\n' 2>/dev/null || true
    } | sort -nr | head -n 1 | cut -d' ' -f2-
  )"

  printf '%s\n' "$latest"
}

find_report_files() {
  local report_root="$1"

  [[ -n "$report_root" && -d "$report_root" ]] || return 0
  find "$report_root" -type f -name '*.rpt' | sort || true
}

write_report_manifest() {
  local report_root="$1"
  local report_path rel_path

  : > "$REPORTS_MANIFEST_FILE"

  while IFS= read -r report_path; do
    [[ -n "$report_path" ]] || continue
    rel_path="${report_path#$report_root/}"
    printf '%s\n' "$rel_path" >> "$REPORTS_MANIFEST_FILE"
  done < <(find_report_files "$report_root")
}

find_relevant_processes() {
  local win_root=""
  if command -v wslpath >/dev/null 2>&1; then
    win_root="$(wslpath -w "$ROOT_DIR" 2>/dev/null || true)"
  fi

  if [[ -n "$win_root" ]]; then
    ps -eo pid,etimes,%cpu,%mem,cmd \
      | rg -F -e "$ROOT_DIR" -e "$win_root" \
      | rg -v 'fnal_sync_watcher|rg -F' || true
  else
    ps -eo pid,etimes,%cpu,%mem,cmd \
      | rg -F "$ROOT_DIR" \
      | rg -v 'fnal_sync_watcher|rg -F' || true
  fi
}

detect_stage() {
  local log_path="$1"
  local process_lines="$2"
  local artifacts="$3"
  local tail_text=""

  if [[ -n "$artifacts" ]]; then
    printf '%s\n' "bit-ready"
    return 0
  fi

  if [[ -n "$log_path" && -f "$log_path" ]]; then
    tail_text="$(tail -n 120 "$log_path" 2>/dev/null || true)"
    if [[ -z "$process_lines" ]] && printf '%s' "$tail_text" | rg -q 'ERROR:|failed due to earlier errors|Failed runs\(s\)|Exiting Vivado'; then
      printf '%s\n' "failed"
      return 0
    fi
    if [[ -z "$process_lines" ]]; then
      printf '%s\n' "idle"
      return 0
    fi
    if printf '%s' "$tail_text" | rg -q 'write_bitstream|write_hw_platform|write_hw_platform -fixed'; then
      printf '%s\n' "bitstream"
      return 0
    fi
    if printf '%s' "$tail_text" | rg -q 'route_design|post_route|write_checkpoint -force .*post_route'; then
      printf '%s\n' "route"
      return 0
    fi
    if printf '%s' "$tail_text" | rg -q 'place_design|opt_design|phys_opt_design'; then
      printf '%s\n' "impl"
      return 0
    fi
    if printf '%s' "$tail_text" | rg -q 'Starting synth_design|synth_design completed successfully|RTL Elaboration|\[Synth [0-9]'; then
      printf '%s\n' "synth"
      return 0
    fi
    if printf '%s' "$tail_text" | rg -q 'ERROR:|failed|permission denied|Exiting Vivado'; then
      printf '%s\n' "failed"
      return 0
    fi
  fi

  if printf '%s' "$process_lines" | rg -q 'vivado'; then
    printf '%s\n' "vivado"
    return 0
  fi

  if printf '%s' "$process_lines" | rg -q 'fusesoc|build_platform.sh|check_native_impl_graph.sh'; then
    printf '%s\n' "fusesoc-setup"
    return 0
  fi

  printf '%s\n' "idle"
}

push_remote_files() {
  local log_path="$1"
  local report_root="$2"

  ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" "mkdir -p \"$REMOTE_BASE/current/reports\"" >/dev/null
  rsync -az "$STATUS_FILE" "$REMOTE:$REMOTE_BASE/current/status.txt"

  if [[ -s "$TAIL_FILE" ]]; then
    rsync -az "$TAIL_FILE" "$REMOTE:$REMOTE_BASE/current/vivado.tail.txt"
  fi

  if [[ -n "$log_path" && -f "$log_path" ]]; then
    rsync -az "$log_path" "$REMOTE:$REMOTE_BASE/current/vivado.log"
  fi

  rsync -az "$REPORTS_MANIFEST_FILE" "$REMOTE:$REMOTE_BASE/current/reports-manifest.txt"

  if [[ -n "$report_root" && -d "$report_root" ]]; then
    rsync -az --delete --prune-empty-dirs \
      --include '*/' \
      --include '*.rpt' \
      --exclude '*' \
      "$report_root/" "$REMOTE:$REMOTE_BASE/current/reports/"
  else
    rsync -az --delete "$EMPTY_REPORTS_DIR/" "$REMOTE:$REMOTE_BASE/current/reports/"
  fi
}

append_remote_summary_if_changed() {
  local summary="$1"
  local summary_key="$2"

  if [[ -f "$LAST_SUMMARY_KEY_FILE" ]] && [[ "$summary_key" == "$(cat "$LAST_SUMMARY_KEY_FILE")" ]]; then
    return 0
  fi

  printf '%s\n' "$summary" > "$LAST_SUMMARY_FILE"
  printf '%s\n' "$summary_key" > "$LAST_SUMMARY_KEY_FILE"
  printf '%s\n' "$summary" > "$SUMMARY_FILE"
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" "cat >> \"$REMOTE_LOG\"" < "$SUMMARY_FILE"
}

run_once() {
  local ts_utc commit branch log_path process_lines artifacts report_root reports stage log_mtime log_size last_log_line last_error_line milestones milestones_csv summary summary_key

  ROOT_DIR="$(resolve_root_dir)"
  ts_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -d "$ROOT_DIR/.git" ]]; then
    commit="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || true)"
    branch="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  else
    commit="${DAPHNE_GIT_SHA:-unknown}"
    branch="snapshot"
  fi

  log_path="$(find_vivado_log)"
  process_lines="$(find_relevant_processes)"
  artifacts="$(find_artifacts)"
  report_root="$(find_report_root "$commit")"
  reports="$(find_report_files "$report_root")"
  stage="$(detect_stage "$log_path" "$process_lines" "$artifacts")"
  milestones="$(collect_milestones "$log_path" "$artifacts")"
  milestones_csv="$(printf '%s\n' "$milestones" | join_lines_csv)"
  last_error_line="$(find_last_error_line "$log_path")"

  if [[ -n "$log_path" && -f "$log_path" ]]; then
    log_mtime="$(stat -c '%y' "$log_path" 2>/dev/null || true)"
    log_size="$(stat -c '%s' "$log_path" 2>/dev/null || true)"
    last_log_line="$(tail -n 1 "$log_path" 2>/dev/null | tr '\r' ' ' | tr '\n' ' ' || true)"
    tail -n 120 "$log_path" > "$TAIL_FILE" 2>/dev/null || true
  else
    log_mtime=""
    log_size=""
    last_log_line=""
    : > "$TAIL_FILE"
  fi

  {
    printf 'timestamp_utc=%s\n' "$ts_utc"
    printf 'root_dir=%s\n' "$ROOT_DIR"
    printf 'commit=%s\n' "$commit"
    printf 'branch=%s\n' "$branch"
    printf 'stage=%s\n' "$stage"
    printf 'milestones=%s\n' "$milestones_csv"
    printf 'log_path=%s\n' "$log_path"
    printf 'log_mtime=%s\n' "$log_mtime"
    printf 'log_size=%s\n' "$log_size"
    printf 'last_log_line=%s\n' "$last_log_line"
    printf 'last_error_line=%s\n' "$last_error_line"
    printf 'milestones_begin\n'
    printf '%s\n' "$milestones"
    printf 'milestones_end\n'
    printf 'artifacts_begin\n'
    printf '%s\n' "$artifacts"
    printf 'artifacts_end\n'
    printf 'report_root=%s\n' "$report_root"
    printf 'reports_begin\n'
    printf '%s\n' "$reports"
    printf 'reports_end\n'
    printf 'processes_begin\n'
    printf '%s\n' "$process_lines"
    printf 'processes_end\n'
  } > "$STATUS_FILE"

  write_report_manifest "$report_root"
  push_remote_files "$log_path" "$report_root"

  summary_key="status=$stage commit=$commit branch=$branch root=$ROOT_DIR milestones=${milestones_csv:-none}"
  if [[ -n "$last_error_line" ]]; then
    summary_key="$summary_key last_error=$(printf '%s' "$last_error_line" | sed 's/[[:space:]]\\+/ /g')"
  fi
  summary="[$ts_utc] $summary_key"
  append_remote_summary_if_changed "$summary" "$summary_key"
}

while true; do
  run_once
  if [[ "$ONCE" -eq 1 ]]; then
    exit 0
  fi
  sleep "$INTERVAL"
done
