#!/usr/bin/env bash
set -euo pipefail

distro="${WORKSTATION_BRIDGE_WSL_DISTRO:-Debian}"
legacy_pidfile="$HOME/.ssh/sshd_workstation.pid"
install_wsl_boot="${WORKSTATION_BRIDGE_INSTALL_WSL_BOOT:-0}"
local_port="${WORKSTATION_BRIDGE_LOCAL_PORT:-2222}"
local_user="${WORKSTATION_BRIDGE_LOCAL_USER:-$(id -un)}"

if [[ ! "$local_port" =~ ^[0-9]+$ ]] || (( local_port < 1 || local_port > 65535 )); then
  echo "invalid WORKSTATION_BRIDGE_LOCAL_PORT: $local_port" >&2
  exit 2
fi

if [[ ! "$local_user" =~ ^[a-z_][a-z0-9_-]*$ ]] || ! getent passwd "$local_user" >/dev/null; then
  echo "invalid WORKSTATION_BRIDGE_LOCAL_USER: $local_user" >&2
  exit 2
fi

if [[ "$install_wsl_boot" != "0" && "$install_wsl_boot" != "1" ]]; then
  echo "WORKSTATION_BRIDGE_INSTALL_WSL_BOOT must be 0 or 1" >&2
  exit 2
fi

if ! command -v wsl.exe >/dev/null 2>&1; then
  echo "wsl.exe not found; cannot manage root-owned sshd" >&2
  exit 1
fi

if [[ -f "$legacy_pidfile" ]]; then
  pid="$(cat "$legacy_pidfile" 2>/dev/null || true)"
  if [[ -n "${pid}" ]] && ps -p "$pid" -o args= 2>/dev/null | grep -q 'sshd_config_workstation'; then
    kill "$pid" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$legacy_pidfile"
fi

wsl.exe -d "$distro" -u root -e env \
  WORKSTATION_BRIDGE_INSTALL_WSL_BOOT="$install_wsl_boot" \
  WORKSTATION_BRIDGE_LOCAL_PORT="$local_port" \
  WORKSTATION_BRIDGE_LOCAL_USER="$local_user" \
  bash -lc '
set -euo pipefail

local_port="${WORKSTATION_BRIDGE_LOCAL_PORT}"
local_user="${WORKSTATION_BRIDGE_LOCAL_USER}"

mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/workstation-bridge.conf <<EOF
Port ${local_port}
ListenAddress 127.0.0.1
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitRootLogin no
AllowUsers ${local_user}
StrictModes yes
PrintMotd no
PrintLastLog no
X11Forwarding no
AllowTcpForwarding yes
AllowAgentForwarding no
GatewayPorts no
EOF

if ! command -v /usr/sbin/sshd >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends openssh-server
fi

ssh-keygen -A
install -d -m 0755 /run/sshd
/usr/sbin/sshd -t

if [[ -d /run/systemd/system ]]; then
  if [[ "${WORKSTATION_BRIDGE_INSTALL_WSL_BOOT:-0}" == "1" ]]; then
    systemctl enable ssh.service >/dev/null
  fi
  systemctl restart ssh.service
else
  if [[ "${WORKSTATION_BRIDGE_INSTALL_WSL_BOOT:-0}" == "1" ]]; then
    echo "cannot enable WSL boot autostart without systemd" >&2
    exit 1
  fi
  service ssh restart >/dev/null
fi

if ! ss -H -ltn | grep -F "127.0.0.1:${local_port}" >/dev/null; then
  echo "sshd did not bind to 127.0.0.1:${local_port}" >&2
  exit 1
fi
'

if [[ "$install_wsl_boot" == "1" ]]; then
  echo "ensured root-owned sshd on 127.0.0.1:${local_port} for ${local_user} with systemd autostart"
else
  echo "ensured root-owned sshd on 127.0.0.1:${local_port} for ${local_user}; autostart not modified"
fi
