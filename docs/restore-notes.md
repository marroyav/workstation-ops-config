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
chmod 755 /home/neutrino/.local/bin/tmux-codex
```

Then restore SSH keys and tokens from their encrypted backup, not from this
repo.

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
