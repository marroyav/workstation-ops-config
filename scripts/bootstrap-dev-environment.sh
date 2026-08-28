#!/usr/bin/env bash
set -euo pipefail

readonly NVIM_VERSION='v0.12.5'
readonly NVIM_SHA256='bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875'
readonly STARSHIP_VERSION='v1.26.0'
readonly STARSHIP_SHA256='321f0dd7af8340a5f2e6a8fec6538a04f617486f9ec70d878f91c09cd8deef22'
readonly EZA_VERSION='v0.23.5'
readonly EZA_SHA256='35c70c5c43c29108075e58b893234c67ef585f0b53a7eaf8e9e7d4eec9f339b4'
readonly DELTA_VERSION='0.19.2'
readonly DELTA_SHA256='8e695c5f586a8c53d6c3b01be0b4a422ed218bfed2a56191caebe373a1c18ab2'
readonly LAZYGIT_VERSION='v0.64.1'
readonly LAZYGIT_SHA256='f8ea237c41f194cd799b48505518bfdaae4edf5a2ad6bd3d898e939785ee4532'
readonly FZF_VERSION='0.74.3'
readonly FZF_SHA256='3501a595e4b5c40a6b047340a0e8f805c46fd4e61ef95ef8a136ba8c61cf6f22'

usage() {
  cat <<'EOF'
usage: scripts/bootstrap-dev-environment.sh [--skip-system]

Installs the Debian/WSL development toolchain used by this repository:
Brave, Neovim, terminal utilities, checksum-verified user binaries, Neovim
providers, and the Git presentation include.

Restore the repository's home/ tree first so the installed tools have their
matching configuration. Use --skip-system to omit APT and Brave repository
changes while installing only user-local tools and providers.
EOF
}

skip_system=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --skip-system)
      skip_system=1
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

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo 'This bootstrap currently supports x86_64 Linux only.' >&2
  exit 1
fi

if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
  echo 'Run this script as your normal user, without sudo.' >&2
  echo 'It obtains root access only for the package-installation steps.' >&2
  exit 1
fi

if [[ "$skip_system" -eq 0 ]]; then
  distro_id="$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | tr -d '"' | head -n 1)"
  if [[ "$distro_id" != debian ]]; then
    printf 'System installation supports Debian only (detected: %s).\n' \
      "${distro_id:-unknown}" >&2
    exit 1
  fi
fi

workstation_home="${HOME:?HOME must be set}"
bootstrap_cache="$workstation_home/.cache/workstation-ops/bootstrap"
user_bin_dir="$workstation_home/.local/bin"
user_opt_dir="$workstation_home/.local/opt"
mkdir -p "$bootstrap_cache" "$user_bin_dir" "$user_opt_dir"

run_as_root() {
  if [[ "$EUID" -eq 0 ]]; then
    "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo "$@"
    return
  fi

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v wsl.exe >/dev/null 2>&1; then
    wsl.exe -d "$WSL_DISTRO_NAME" -u root -- "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return
  fi

  echo 'Root access is required for system packages.' >&2
  return 1
}

install_system_tools() {
  run_as_root apt-get update
  run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl

  run_as_root install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
  run_as_root curl -fsSLo \
    /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  run_as_root curl -fsSLo \
    /etc/apt/sources.list.d/brave-browser-release.sources \
    https://brave-browser-apt-release.s3.brave.com/brave-browser.sources

  run_as_root apt-get update
  run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    bash-completion bat brave-browser btop build-essential desktop-file-utils \
    direnv fd-find fzf git jq less mesa-utils ncdu neovim python3-venv \
    ripgrep shellcheck tmux tree unzip vainfo wayland-utils wl-clipboard \
    xdg-utils zoxide
}

fetch_verified_archive() {
  local archive_path="$1"
  local archive_url="$2"
  local expected_sha256="$3"
  local partial_path="${archive_path}.part"

  if [[ -f "$archive_path" ]] &&
     printf '%s  %s\n' "$expected_sha256" "$archive_path" | sha256sum -c - >/dev/null 2>&1; then
    return
  fi

  curl -fL --retry 3 -o "$partial_path" "$archive_url"
  printf '%s  %s\n' "$expected_sha256" "$partial_path" | sha256sum -c -
  mv "$partial_path" "$archive_path"
}

install_binary_archive() {
  local binary_name="$1"
  local archive_path="$2"
  local archive_member="$3"
  local extraction_dir

  extraction_dir="$(mktemp -d "${TMPDIR:-/tmp}/workstation-ops-tool.XXXXXX")"
  tar -xzf "$archive_path" -C "$extraction_dir"
  install -m 0755 "$extraction_dir/$archive_member" "$user_bin_dir/$binary_name"
  rm -rf -- "$extraction_dir"
}

ensure_user_symlink() {
  local symlink_target="$1"
  local symlink_path="$2"

  if [[ -L "$symlink_path" ]]; then
    ln -sfn "$symlink_target" "$symlink_path"
  elif [[ -e "$symlink_path" ]]; then
    printf 'WARNING: preserving non-symlink at %s\n' "$symlink_path" >&2
  else
    ln -s "$symlink_target" "$symlink_path"
  fi
}

install_neovim() {
  local nvim_archive="$bootstrap_cache/nvim-linux-x86_64-$NVIM_VERSION.tar.gz"
  local nvim_install_dir="$user_opt_dir/nvim-$NVIM_VERSION"
  local nvim_stage_dir

  fetch_verified_archive \
    "$nvim_archive" \
    "https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" \
    "$NVIM_SHA256"

  if [[ ! -x "$nvim_install_dir/bin/nvim" ]]; then
    if [[ -e "$nvim_install_dir" ]]; then
      printf 'Refusing to overwrite incomplete Neovim directory: %s\n' "$nvim_install_dir" >&2
      return 1
    fi
    nvim_stage_dir="$(mktemp -d "$user_opt_dir/.nvim-$NVIM_VERSION.XXXXXX")"
    tar -xzf "$nvim_archive" --strip-components=1 -C "$nvim_stage_dir"
    mv "$nvim_stage_dir" "$nvim_install_dir"
  fi

  ensure_user_symlink "$nvim_install_dir" "$user_opt_dir/nvim"
  ensure_user_symlink "$user_opt_dir/nvim/bin/nvim" "$user_bin_dir/nvim"
}

install_user_tools() {
  local starship_archive="$bootstrap_cache/starship-$STARSHIP_VERSION.tar.gz"
  local eza_archive="$bootstrap_cache/eza-$EZA_VERSION.tar.gz"
  local delta_archive="$bootstrap_cache/delta-$DELTA_VERSION.tar.gz"
  local lazygit_archive="$bootstrap_cache/lazygit-$LAZYGIT_VERSION.tar.gz"
  local fzf_archive="$bootstrap_cache/fzf-$FZF_VERSION.tar.gz"

  fetch_verified_archive "$starship_archive" \
    "https://github.com/starship/starship/releases/download/$STARSHIP_VERSION/starship-x86_64-unknown-linux-gnu.tar.gz" \
    "$STARSHIP_SHA256"
  install_binary_archive starship "$starship_archive" starship

  fetch_verified_archive "$eza_archive" \
    "https://github.com/eza-community/eza/releases/download/$EZA_VERSION/eza_x86_64-unknown-linux-gnu.tar.gz" \
    "$EZA_SHA256"
  install_binary_archive eza "$eza_archive" eza

  fetch_verified_archive "$delta_archive" \
    "https://github.com/dandavison/delta/releases/download/$DELTA_VERSION/delta-$DELTA_VERSION-x86_64-unknown-linux-gnu.tar.gz" \
    "$DELTA_SHA256"
  install_binary_archive delta "$delta_archive" \
    "delta-$DELTA_VERSION-x86_64-unknown-linux-gnu/delta"

  fetch_verified_archive "$lazygit_archive" \
    "https://github.com/jesseduffield/lazygit/releases/download/$LAZYGIT_VERSION/lazygit_${LAZYGIT_VERSION#v}_linux_x86_64.tar.gz" \
    "$LAZYGIT_SHA256"
  install_binary_archive lazygit "$lazygit_archive" lazygit

  fetch_verified_archive "$fzf_archive" \
    "https://github.com/junegunn/fzf/releases/download/v$FZF_VERSION/fzf-$FZF_VERSION-linux_amd64.tar.gz" \
    "$FZF_SHA256"
  install_binary_archive fzf "$fzf_archive" fzf

  if [[ -x /usr/bin/batcat ]]; then
    ensure_user_symlink /usr/bin/batcat "$user_bin_dir/bat"
  fi
  if [[ -x /usr/bin/fdfind ]]; then
    ensure_user_symlink /usr/bin/fdfind "$user_bin_dir/fd"
  fi
}

install_neovim_providers() {
  local provider_venv="$workstation_home/.local/share/nvim/provider-venv"
  mkdir -p "$workstation_home/.local/state/nvim/undo"

  if [[ ! -x "$provider_venv/bin/python" ]]; then
    python3 -m venv "$provider_venv"
  fi
  "$provider_venv/bin/python" -m pip install --disable-pip-version-check \
    'pynvim==0.6.0'

  if command -v npm >/dev/null 2>&1; then
    npm install --global --prefix "$workstation_home/.local" 'neovim@5.4.0'
  else
    echo 'WARNING: npm is unavailable; the optional Neovim Node provider was skipped.' >&2
  fi
}

configure_user_environment() {
  local git_fragment="$workstation_home/.config/git/productivity.gitconfig"

  if [[ -f "$git_fragment" ]]; then
    if ! git config --global --get-all include.path 2>/dev/null |
         grep -Fqx "$git_fragment"; then
      git config --global --add include.path "$git_fragment"
    fi
  else
    printf 'WARNING: restore %s before configuring Git.\n' "$git_fragment" >&2
  fi

  if command -v update-desktop-database >/dev/null 2>&1 &&
     [[ -d "$workstation_home/.local/share/applications" ]]; then
    update-desktop-database "$workstation_home/.local/share/applications"
  fi
  if command -v xdg-settings >/dev/null 2>&1 &&
     [[ -f "$workstation_home/.local/share/applications/brave-browser.desktop" ]]; then
    xdg-settings set default-web-browser brave-browser.desktop || true
    xdg-mime default brave-browser.desktop x-scheme-handler/http || true
    xdg-mime default brave-browser.desktop x-scheme-handler/https || true
  fi
}

if [[ "$skip_system" -eq 0 ]]; then
  install_system_tools
fi

for prerequisite in curl git install mktemp python3 sha256sum tar; do
  if ! command -v "$prerequisite" >/dev/null 2>&1; then
    printf 'Required command is missing: %s\n' "$prerequisite" >&2
    exit 1
  fi
done

install_neovim
install_user_tools
install_neovim_providers
configure_user_environment

cat <<EOF

Development environment bootstrap complete.

Open a new terminal or run:
  source "$workstation_home/.bashrc"

Then read:
  docs/dev-environment-guide.md
EOF
