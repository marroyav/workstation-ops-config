#!/usr/bin/env bash
set -euo pipefail

remote="${1:-${WORKSTATION_BRIDGE_REMOTE:-}}"
local_socket="${WORKSTATION_BRIDGE_LOCAL_SOCKET:-workstation-reverse}"
local_session="${WORKSTATION_BRIDGE_LOCAL_SESSION:-workstation-reverse-ssh}"
remote_session="${WORKSTATION_BRIDGE_REMOTE_SESSION:-workstation-shell}"
remote_port="${WORKSTATION_BRIDGE_REMOTE_PORT:-2222}"
local_port="${WORKSTATION_BRIDGE_LOCAL_PORT:-2222}"
local_user="${WORKSTATION_BRIDGE_LOCAL_USER:-$USER}"
remote_identity="${WORKSTATION_BRIDGE_REMOTE_IDENTITY:-}"
remote_known_hosts="${WORKSTATION_BRIDGE_REMOTE_KNOWN_HOSTS:-/dev/null}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

shell_quote() {
  printf "%q" "$1"
}

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
  bridge_loop="while true; do WORKSTATION_BRIDGE_REMOTE_PORT=$(shell_quote "$remote_port") WORKSTATION_BRIDGE_LOCAL_PORT=$(shell_quote "$local_port") $(shell_quote "$script_dir/open-np04-reverse-ssh.sh") $(shell_quote "$remote"); echo '[reverse tunnel exited, retrying in 5s]'; sleep 5; done"
  tmux -L "$local_socket" new-session -d -s "$local_session" \
    "bash -lc $(shell_quote "$bridge_loop")"
  tmux -L "$local_socket" set-option -t "$local_session" prefix C-g
  tmux -L "$local_socket" unbind-key -T prefix C-b 2>/dev/null || true
  tmux -L "$local_socket" bind-key -T prefix C-g send-prefix
fi

remote_attach_args=(ssh -tt)
if [[ -n "$remote_identity" ]]; then
  remote_attach_args+=(-i "$remote_identity" -o IdentitiesOnly=yes)
fi
remote_attach_args+=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o "UserKnownHostsFile=$remote_known_hosts"
  -o StrictHostKeyChecking=no
  -p "$remote_port"
  "$local_user@localhost"
)
printf -v remote_attach_cmd "%q " "${remote_attach_args[@]}"
remote_attach_cmd="${remote_attach_cmd% }"
remote_loop="while true; do $remote_attach_cmd; echo; echo '[workstation shell exited, retrying in 5s]'; sleep 5; done"
remote_tmux_command="bash -lc $(shell_quote "$remote_loop")"
remote_session_q="$(shell_quote "$remote_session")"
remote_tmux_command_q="$(shell_quote "$remote_tmux_command")"

ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o ConnectionAttempts=1 \
  "$remote" \
  "if ! tmux has-session -t $remote_session_q 2>/dev/null; then \
     tmux new-session -d -s $remote_session_q $remote_tmux_command_q; \
   fi; \
   tmux set-option -t $remote_session_q prefix C-\\\\; \
   tmux unbind-key -T prefix C-b 2>/dev/null || true; \
   tmux bind-key -T prefix C-\\\\ send-prefix"

cat <<EOF
Workstation bridge is up.

From $remote:
  tmux attach -t $remote_session

Directly from $remote:
  $remote_attach_cmd

Local tunnel inspection:
  tmux -L $local_socket attach -t $local_session
EOF
