# Workstation Ops Config

Personal workstation configuration, SSH routing notes, and local automation
scripts for this WSL/Debian environment.

This repo intentionally stores configuration and source scripts only. It does
not store private SSH keys, authorized keys, tokens, command histories, runtime
state, logs, browser state, generated caches, or large local binaries.

## Layout

- `home/` mirrors selected files under `/home/neutrino`.
- `home/.ssh/` stores SSH client/server config and historical config backups,
  but no keys, sockets, logs, or known-host material.
- `home/bin/` stores workstation SSH bridge helpers.
- `home/.local/bin/` stores small wrapper scripts, including the Brave/Wayland
  launchers, but not downloaded binaries.
- `home/.config/` stores selected application, XDG, and user-systemd configs.
- `home/.config/fontconfig/fonts.conf` prefers JetBrains Mono for the WSL
  `monospace` font family.
- `home/.config/nvim/init.vim` loads the shared workstation Vim config for
  Neovim.
- `home/.config/shell/` stores the interactive productivity and WSLg
  Wayland-first environment layers.
- `home/.config/git/productivity.gitconfig` stores presentation and workflow
  defaults without replacing Git identity configuration.
- `home/.ideavimrc` stores IdeaVim mappings for JetBrains IDEs.
- `scripts/` contains the reproducible tool bootstrap and a read-only health
  check.
- `windows/` contains the native Windows awake runtime and its scheduled-task
  installer.
- `work/build-ops/` stores FNAL/CERN build sync, archive, controller, and
  GitHub artifact watcher source files.
- `system/` stores selected system-level reference config that belongs to this
  workstation setup.
- `docs/` records excluded sensitive files and restore notes.

## Development Environment

The terminal environment includes Neovim, tmux, fzf, ripgrep, fd, bat, eza,
zoxide, Starship, Delta, Lazygit, direnv, jq, ShellCheck, btop, ncdu, Brave, and
Wayland/X11 launch helpers. A per-user Windows scheduled task can also prevent
automatic system sleep after sign-in.

- Start with `docs/dev-environment-guide.md` for commands and keybindings.
- Read `docs/shell-pipes.md` for a beginner explanation of pipes, stdin/stdout,
  `$()` command substitution, and quoting.
- Read `docs/wslg-wayland.md` for the measured WSLg graphics behavior and the
  reason XWayland remains available.

After restoring `home/`, install the external packages and checksum-verified
user binaries with:

```bash
scripts/bootstrap-dev-environment.sh
scripts/check-dev-environment.sh
```

The bootstrap pins downloaded binary versions and SHA-256 digests. It stores
only its small configuration and installer source in this repository.

## Kerberos and CERN/FNAL Access

See `docs/local-kerberos-cern-fnal.md` for the local WSL Kerberos setup,
including the `arroyave@FNAL.GOV` and `marroyav@CERN.CH` principals, the
installed `/etc/krb5.conf` reference, and the CERN SSH alias layout.

## tmux and Codex Session Recovery

`home/.local/bin/tmux-codex` and the matching user-systemd units periodically
save the `work` tmux layout and its active Codex thread UUIDs, then recreate the
layout with the exact conversations after a restart. See
`docs/tmux-codex-sessions.md` for installation, commands, and limitations.

## Restore Notes

Review paths before copying because several files contain workstation-specific
absolute paths and host aliases. For a direct restore into the same account,
copy files from `home/` over `/home/neutrino/` and preserve executable bits for
scripts.

SSH restore still requires separately restoring private keys and
`authorized_keys`; see `docs/excluded-sensitive-files.md`.

## Safety

Before pushing changes, run:

```bash
git status --short
rg -n -i "(token|secret|password|passwd|private[_-]?key|BEGIN [A-Z ]*PRIVATE KEY|github_pat|ghp_|api[_-]?key|Authorization:)" .
```

Expected hits should be documentation or code that refers to environment
variable names and token file paths, not actual secret values.
