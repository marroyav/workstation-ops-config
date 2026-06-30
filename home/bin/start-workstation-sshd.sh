#!/usr/bin/env bash
set -euo pipefail

distro="Debian"
legacy_pidfile="$HOME/.ssh/sshd_workstation.pid"
install_wsl_boot="${WORKSTATION_BRIDGE_INSTALL_WSL_BOOT:-0}"

if ! command -v wsl.exe >/dev/null 2>&1; then
  echo "wsl.exe not found; cannot manage root-owned sshd" >&2
  exit 1
fi

if [[ -f "$legacy_pidfile" ]]; then
  pid="$(cat "$legacy_pidfile" 2>/dev/null || true)"
  if [[ -n "${pid}" ]] && ps -p "$pid" -o args= 2>/dev/null | grep -q '/usr/sbin/sshd -f /home/neutrino/.ssh/sshd_config_workstation'; then
    kill "$pid" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$legacy_pidfile"
fi

wsl.exe -d "$distro" -u root -- env WORKSTATION_BRIDGE_INSTALL_WSL_BOOT="$install_wsl_boot" bash -lc '
set -euo pipefail

mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/workstation-bridge.conf <<'"'"'EOF'"'"'
Port 2222
ListenAddress 127.0.0.1
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers neutrino
PrintMotd no
PrintLastLog no
X11Forwarding no
AllowTcpForwarding yes
GatewayPorts no
EOF

if [[ "${WORKSTATION_BRIDGE_INSTALL_WSL_BOOT:-0}" == "1" ]]; then
cat > /etc/wsl.conf <<'"'"'EOF'"'"'
[boot]
command=service ssh start
EOF
fi

if service ssh status >/dev/null 2>&1 && ss -ltn | grep -q "127.0.0.1:2222"; then
  exit 0
fi

service ssh restart >/dev/null 2>&1 || service ssh start >/dev/null 2>&1
'

if [[ "$install_wsl_boot" == "1" ]]; then
  echo "ensured root-owned sshd on 127.0.0.1:2222 and WSL boot autostart"
else
  echo "ensured root-owned sshd on 127.0.0.1:2222; WSL boot autostart not modified"
fi
