#!/usr/bin/env bash
set -euo pipefail

remote="${1:-${WORKSTATION_BRIDGE_REMOTE:-}}"
remote_port="${WORKSTATION_BRIDGE_REMOTE_PORT:-2222}"
local_port="${WORKSTATION_BRIDGE_LOCAL_PORT:-2222}"
local_user="${WORKSTATION_BRIDGE_LOCAL_USER:-$USER}"

if [[ -z "$remote" ]]; then
  cat >&2 <<'EOF'
No workstation bridge remote is configured.
Pass a host alias as the first argument, or set WORKSTATION_BRIDGE_REMOTE.
EOF
  exit 2
fi

echo "Local sshd:"
wsl.exe -d Debian -u root -- env WORKSTATION_BRIDGE_LOCAL_PORT="$local_port" bash -lc 'service ssh status || true; ss -ltnp | grep "${WORKSTATION_BRIDGE_LOCAL_PORT}" || true'
echo
echo "Local reverse tunnel tmux:"
tmux -L workstation-reverse ls 2>/dev/null || true
echo
echo "Remote workstation shell tmux:"
ssh "$remote" "tmux ls 2>/dev/null | grep '^workstation-shell:' || true"
echo
echo "Remote command test:"
ssh "$remote" "ssh -o BatchMode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p $remote_port $local_user@localhost hostname"
