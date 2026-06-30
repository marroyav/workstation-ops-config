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
```

Then restore SSH keys and tokens from their encrypted backup, not from this
repo.

## Files That Need Separate Secret Backup

- SSH private keys and `authorized_keys`
- GitHub token at `~/.config/daphne-build-ops/github-token`
- Any future Fermilab bridge key referenced by SSH config

## Machine-specific Assumptions

Several scripts assume:

- WSL distro name: `Debian`
- Unix user: `neutrino`
- Windows user path pieces such as `C:\Users\arroyave`
- CERN username: `marroyav`
- Xilinx/Vivado 2024.1 paths under `/opt/Xilinx`, `/home/neutrino/tools`, or
  `C:\Xilinx`

Review these before restoring onto a different workstation.

## System Config Reference

The repo includes:

- `system/etc/ssh/sshd_config.d/workstation-bridge.conf`

Install it manually as root only after reviewing it. At the time this repo was
created, `/etc/wsl.conf` was not present; the bridge launcher can recreate a WSL
boot hook if `WORKSTATION_BRIDGE_INSTALL_WSL_BOOT=1` is used.
