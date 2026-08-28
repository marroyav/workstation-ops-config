# Restore Notes

This repository is intended as a source-controlled reference, not a blind
bootstrap bundle.

## Same-machine Restore

From the repository root:

```bash
rsync -av home/ /home/neutrino/
chmod 700 /home/neutrino/.ssh
chmod 600 /home/neutrino/.ssh/config /home/neutrino/.ssh/sshd_config_workstation
chmod 755 /home/neutrino/bin/*.sh /home/neutrino/.local/bin/vivado*
chmod 755 /home/neutrino/.local/bin/xilinx-2024.1-env
chmod 755 /home/neutrino/.local/bin/brave-browser /home/neutrino/.local/bin/brave-x11
chmod 755 /home/neutrino/.local/bin/gui-wayland /home/neutrino/.local/bin/gui-x11
chmod 755 /home/neutrino/.local/bin/tmux-codex
```

Then install the system packages, signed Brave repository, pinned user-local
binaries, Neovim providers, and Git productivity include:

```bash
scripts/bootstrap-dev-environment.sh
scripts/check-dev-environment.sh
```

Use `scripts/bootstrap-dev-environment.sh --skip-system` when the APT/Brave
packages are already managed separately. The bootstrap does not store or
restore downloaded binaries in Git.

Neovim uses `home/.config/nvim/init.vim` to load the shared workstation
`.vimrc` and then the Neovim-only `home/.config/nvim/custom.vim` layer. No
plugin installation step is required. The bootstrap creates
`~/.local/share/nvim/provider-venv`, installs the Python and optional Node
providers, and preserves `/usr/bin/nvim` as a fallback behind the user-local
current release.

JetBrains IDEs running on Windows read IdeaVim config from the Windows user
home, so copy `home/.ideavimrc` to `C:\Users\arroyave\.ideavimrc` after
restoring WSL files. Windows Terminal font settings live in the Windows profile
settings JSON, not under `/home/neutrino`; this workstation currently uses
JetBrains Mono installed as a per-user Windows font. WSL fontconfig uses
`home/.config/fontconfig/fonts.conf` to prefer JetBrains Mono for the generic
`monospace` family, but the TTF files themselves are external font assets and
are not stored in this repository.

Recreate the per-user Windows awake task from the repository root:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$PWD/windows/Install-KeepWindowsAwake.ps1")"
```

This deploys the runtime under `%LOCALAPPDATA%\WorkstationOps` and registers
`WorkstationOps Keep Windows Awake` to run at Windows sign-in. It prevents
automatic system sleep but does not keep the display on unless the installer
is run with `-KeepDisplayOn`.

Then restore SSH keys and tokens from their encrypted backup, not from this
repo.

The terminal tool walkthrough is in `docs/dev-environment-guide.md`; the
explanation of shell pipelines and the `nvim "$(fd --type f | fzf)"` command is
in `docs/shell-pipes.md`.

To enable automatic tmux/Codex snapshots after copying the user-systemd units:

```bash
systemctl --user daemon-reload
systemctl --user enable --now tmux-codex-snapshot.timer
systemctl --user enable --now tmux-codex-final-snapshot.service
```

See `docs/tmux-codex-sessions.md` for runtime-state backup requirements and
restore behavior.

## Files That Need Separate Secret Backup

- SSH private keys and `authorized_keys`
- GitHub token at `~/.config/daphne-build-ops/github-token`
- Any future Fermilab bridge key referenced by SSH config

## Machine-specific Assumptions

Several scripts assume:

- WSL distro name: `Debian`
- Workstation bridge Unix user: `marroyav` by default; it can be overridden
  with `WORKSTATION_BRIDGE_LOCAL_USER`
- Windows user path pieces such as `C:\Users\arroyave`
- CERN username: `marroyav`
- Xilinx/Vivado 2024.1 paths under `/opt/Xilinx`, `/home/neutrino/tools`, or
  `C:\Xilinx`

Review these before restoring onto a different workstation.

## System Config Reference

The repo includes:

- `system/etc/ssh/sshd_config.d/workstation-bridge.conf`

The bridge launcher installs and validates this drop-in. With systemd enabled
in WSL, `WORKSTATION_BRIDGE_INSTALL_WSL_BOOT=1` enables `ssh.service`; it
does not overwrite `/etc/wsl.conf`.
