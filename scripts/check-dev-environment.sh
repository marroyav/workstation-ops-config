#!/usr/bin/env bash
set -uo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
check_failures=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  check_failures=$((check_failures + 1))
}

check_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "$command_name -> $(command -v "$command_name")"
  else
    fail "$command_name is not installed"
  fi
}

printf '%s\n' '== Commands =='
for command_name in \
  bat brave-browser btop delta direnv eza fd fzf git jq lazygit ncdu \
  nvim rg shellcheck starship tmux wl-copy zoxide; do
  check_command "$command_name"
done

printf '\n%s\n' '== Repository configuration =='
if bash -n \
    "$repository_root/home/.bashrc" \
    "$repository_root/home/.profile" \
    "$repository_root/home/.config/shell/wayland-wslg.sh" \
    "$repository_root/home/.config/shell/productivity.bash"; then
  pass 'Bash configuration syntax'
else
  fail 'Bash configuration syntax'
fi

if command -v shellcheck >/dev/null 2>&1 && shellcheck -x -S warning \
    "$repository_root/home/.config/shell/wayland-wslg.sh" \
    "$repository_root/home/.config/shell/productivity.bash" \
    "$repository_root/home/.local/bin/brave-browser" \
    "$repository_root/home/.local/bin/brave-x11" \
    "$repository_root/home/.local/bin/gui-wayland" \
    "$repository_root/home/.local/bin/gui-x11"; then
  pass 'ShellCheck'
else
  fail 'ShellCheck'
fi

if command -v desktop-file-validate >/dev/null 2>&1; then
  if desktop-file-validate \
      "$repository_root/home/.local/share/applications/brave-browser.desktop"; then
    pass 'Brave desktop entry'
  else
    fail 'Brave desktop entry'
  fi
else
  printf '%s\n' 'SKIP  desktop-file-validate is not installed'
fi

if command -v starship >/dev/null 2>&1 &&
   TERM=xterm-256color \
     STARSHIP_CONFIG="$repository_root/home/.config/starship.toml" \
     starship prompt >/dev/null; then
  pass 'Starship configuration'
else
  fail 'Starship configuration'
fi

printf '\n%s\n' '== Runtime =='
if command -v nvim >/dev/null 2>&1 &&
   timeout 30s nvim --headless '+qa!' >/dev/null 2>&1; then
  pass 'Neovim headless startup'
else
  fail 'Neovim headless startup'
fi

if command -v tmux >/dev/null 2>&1; then
  if tmux -L workstation-ops-check \
      -f "$repository_root/home/.tmux.conf" new-session -d -s config-check; then
    pass 'tmux configuration'
    tmux -L workstation-ops-check kill-server
  else
    fail 'tmux configuration'
  fi
fi

if [[ -n "${WAYLAND_DISPLAY:-}" ]] &&
   [[ -S "${XDG_RUNTIME_DIR:-/mnt/wslg/runtime-dir}/$WAYLAND_DISPLAY" ]]; then
  pass "Wayland socket $WAYLAND_DISPLAY"
else
  printf '%s\n' 'SKIP  no active Wayland socket in this session'
fi

if command -v glxinfo >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
  renderer_summary="$(glxinfo -B 2>&1)"
  if grep -Fq 'Accelerated: yes' <<<"$renderer_summary"; then
    pass "GPU acceleration: $(grep -F 'OpenGL renderer string:' <<<"$renderer_summary" | head -n 1)"
  else
    fail 'OpenGL is not hardware accelerated'
  fi
else
  printf '%s\n' 'SKIP  OpenGL check needs glxinfo and an active display'
fi

printf '\n'
if [[ "$check_failures" -eq 0 ]]; then
  printf '%s\n' 'All development-environment checks passed.'
  exit 0
fi

printf '%s\n' "$check_failures check(s) failed." >&2
exit 1
