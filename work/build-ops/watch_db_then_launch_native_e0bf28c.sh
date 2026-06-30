#!/usr/bin/env bash
set -euo pipefail

db_pid="${1:-}"
if [[ -z "${db_pid}" ]]; then
  db_pid="$(pgrep -f 'scripts/wsl/run_manual_vivado_pushd.sh all' | head -n 1 || true)"
fi

if [[ -z "${db_pid}" ]]; then
  echo "No active db build wrapper process found." >&2
  exit 1
fi

db_root="/home/neutrino/work/db"
db_vivado_log="${db_root}/xilinx/vivado.log"
native_launcher_windows='C:\Users\arroyave\work\daphne-native-build-e0bf28c.ps1'
ops_root="/home/neutrino/work/build-ops"
run_log="${ops_root}/watch_db_then_launch_native_e0bf28c.log"

mkdir -p "${ops_root}"

stamp() {
  date '+%Y-%m-%d %H:%M:%S %z'
}

log() {
  printf '[%s] %s\n' "$(stamp)" "$*" | tee -a "${run_log}"
}

artifact_summary() {
  local output_dir="${db_root}/xilinx/output-88cd864"
  if [[ -d "${output_dir}" ]]; then
    find "${output_dir}" -maxdepth 3 -type f \
      \( -name '*.bit' -o -name '*.bin' -o -name '*.xsa' -o -name '*.dcp' -o -name '*.rpt' \) \
      -printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' | sort | tee -a "${run_log}" >/dev/null
  else
    log "No output directory yet at ${output_dir}."
  fi
}

log "Watching db build wrapper pid=${db_pid}."
if [[ -f "${db_vivado_log}" ]]; then
  log "Initial vivado.log state: $(stat -c '%y %s %n' "${db_vivado_log}")"
fi

while kill -0 "${db_pid}" 2>/dev/null; do
  if [[ -f "${db_vivado_log}" ]]; then
    log "db build still active; vivado.log: $(stat -c '%y %s %n' "${db_vivado_log}")"
  else
    log "db build still active; vivado.log not present yet."
  fi
  sleep 60
done

log "db build wrapper pid=${db_pid} exited."
if [[ -f "${db_vivado_log}" ]]; then
  log "Final vivado.log state: $(stat -c '%y %s %n' "${db_vivado_log}")"
  tail -n 80 "${db_vivado_log}" | sed 's/\r$//' | tee -a "${run_log}" >/dev/null
fi
artifact_summary

log "Launching native Windows build via ${native_launcher_windows}."
cmd.exe /c powershell -ExecutionPolicy Bypass -File "${native_launcher_windows}" 2>&1 \
  | sed 's/\r$//' | tee -a "${run_log}"

log "Native Windows build launcher returned."
