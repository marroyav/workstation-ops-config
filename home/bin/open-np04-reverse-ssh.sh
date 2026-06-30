#!/usr/bin/env bash
set -euo pipefail

remote="${1:-${WORKSTATION_BRIDGE_REMOTE:-}}"
remote_port="${WORKSTATION_BRIDGE_REMOTE_PORT:-2222}"
local_port="${WORKSTATION_BRIDGE_LOCAL_PORT:-2222}"

if [[ -z "$remote" ]]; then
  cat >&2 <<'EOF'
No workstation bridge remote is configured.
Pass a host alias as the first argument, or set WORKSTATION_BRIDGE_REMOTE.
Example: WORKSTATION_BRIDGE_REMOTE=fnal-workstation-bridge
EOF
  exit 2
fi

exec ssh \
  -NT \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o ConnectionAttempts=1 \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=60 \
  -o ServerAliveCountMax=3 \
  -R "${remote_port}:127.0.0.1:${local_port}" \
  "$remote"
