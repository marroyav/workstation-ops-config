#!/usr/bin/env bash
set -euo pipefail

remote="${1:-${WORKSTATION_BRIDGE_REMOTE:-}}"
local_socket="${WORKSTATION_BRIDGE_LOCAL_SOCKET:-workstation-reverse}"
local_session="${WORKSTATION_BRIDGE_LOCAL_SESSION:-workstation-reverse-ssh}"
remote_session="${WORKSTATION_BRIDGE_REMOTE_SESSION:-workstation-shell}"
remote_port="${WORKSTATION_BRIDGE_REMOTE_PORT:-2222}"
local_user="${WORKSTATION_BRIDGE_LOCAL_USER:-$USER}"
remote_identity="${WORKSTATION_BRIDGE_REMOTE_IDENTITY:-}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

remote_identity_args=""
if [[ -n "$remote_identity" ]]; then
  if [[ ! "$remote_identity" =~ ^[A-Za-z0-9_./~-]+$ ]]; then
    echo "WORKSTATION_BRIDGE_REMOTE_IDENTITY contains unsupported characters" >&2
    exit 2
  fi
  remote_identity_args="-i $remote_identity -o IdentitiesOnly=yes "
fi

if [[ -z "$remote" ]]; then
  cat >&2 <<'EOF'
The retired CERN workstation bridge no longer has a default remote.
For a future Fermilab bridge, add an SSH host alias and run with:
  WORKSTATION_BRIDGE_REMOTE=fnal-workstation-bridge
EOF
  exit 2
fi

"$script_dir/start-workstation-sshd.sh"

if ! tmux -L "$local_socket" has-session -t "$local_session" 2>/dev/null; then
  tmux -L "$local_socket" new-session -d -s "$local_session" \
    "bash -lc 'while true; do \"$script_dir/open-np04-reverse-ssh.sh\" \"$remote\"; echo \"[reverse tunnel exited, retrying in 5s]\"; sleep 5; done'"
  tmux -L "$local_socket" set-option -t "$local_session" prefix C-g
  tmux -L "$local_socket" unbind-key -T prefix C-b 2>/dev/null || true
  tmux -L "$local_socket" bind-key -T prefix C-g send-prefix
fi

ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o ConnectionAttempts=1 \
  "$remote" \
  "if ! tmux has-session -t $remote_session 2>/dev/null; then \
     tmux new-session -d -s $remote_session \"bash -lc 'while true; do ssh -tt ${remote_identity_args}-o BatchMode=yes -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p $remote_port $local_user@localhost; echo; echo [workstation shell exited, retrying in 5s]; sleep 5; done'\"; \
   fi; \
   tmux set-option -t $remote_session prefix C-\\\\; \
   tmux unbind-key -T prefix C-b 2>/dev/null || true; \
   tmux bind-key -T prefix C-\\\\ send-prefix"

cat <<EOF
Workstation bridge is up.

From $remote:
  tmux attach -t $remote_session

Local tunnel inspection:
  tmux -L $local_socket attach -t $local_session
EOF
