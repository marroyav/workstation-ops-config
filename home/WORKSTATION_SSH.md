# Workstation SSH Bridge

## Current FGZ Setup

This bridge was installed and tested on 2026-08-06:

1. WSL Debian runs the system OpenSSH server on `127.0.0.1:2222`.
2. A local tmux loop maintains a reverse forward to `dune-fd-test01.fnal.gov`.
3. DUNE exposes that forward only on its own loopback addresses at port 2222.
4. The DUNE tmux session `workstation-shell` logs back in as
   `marroyav@WL-144132`.

The end-to-end return login from DUNE was verified successfully.

## Security Properties

- The WSL SSH listener is loopback-only; no Windows or LAN-facing SSH port is
  opened.
- Password, keyboard-interactive, and root login are disabled.
- The server accepts public-key authentication only and allows only
  `marroyav`.
- The DUNE return key is restricted in the local `authorized_keys` file to
  connections sourced from `127.0.0.1`. Agent, X11, and TCP forwarding are
  disabled for that key.
- The reverse listener on DUNE is also loopback-only.

The DUNE host's `/home` filesystem was full when this was configured. The
dedicated private key therefore lives in a mode-0700 directory on persistent
storage:

```text
/storage/workstation-bridge-arroyave/id_ed25519_wl144132
```

The private key and the local `~/.ssh/authorized_keys` file are runtime
secrets and must not be committed to this repository.

## Login From Remote

Use `dune-fd-test01.fnal.gov` as the Kerberos-authenticated rendezvous host.
The workstations do not currently accept direct Kerberos SSH into WSL; the
reverse tunnels below expose only loopback ports on the DUNE host.

From a machine with a valid FNAL Kerberos ticket:

```bash
ssh -K arroyave@dune-fd-test01.fnal.gov
```

Then choose the workstation session:

```bash
# WL-144132 as marroyav, remote loopback port 2222.
tmux attach -t workstation-shell

# WL-123935 as neutrino, remote loopback port 2223; opens local Fermi tmux.
tmux attach -t neutrino
```

If the remote tmux shell is missing or stale, connect directly from
`dune-fd-test01`:

```bash
# WL-144132.
ssh -tt -i /storage/workstation-bridge-arroyave/id_ed25519_wl144132 \
  -o IdentitiesOnly=yes \
  -p 2222 marroyav@127.0.0.1

# WL-123935.
ssh -tt -i /tmp/arroyave/workstation-bridge/id_ed25519 \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  -p 2223 neutrino@localhost
```

Direct Kerberos login to the workstation hostnames was checked on 2026-08-06.
FNAL Kerberos did not have these service principals:

```text
host/wl-123935.dhcp.fnal.gov@FNAL.GOV
host/wl-144132.dhcp.fnal.gov@FNAL.GOV
```

Until FNAL creates those principals and matching host keytabs are installed on
the workstations, direct GSSAPI SSH cannot work. Exposing WSL directly would
also require changing the loopback-only sshd listener and Windows networking or
firewall rules, so the reverse tunnel remains the preferred access path.

## Neutrino Workstation Bridge

The same DUNE host can also reach this WSL workstation as
`neutrino@WL-123935`. Port `2222` is already used by the `marroyav@WL-144132`
session above, so this workstation uses remote loopback port `2223`.

The SSH host alias is:

```bash
ssh -K fnal-workstation-bridge
```

`fnal-workstation-bridge` points to `arroyave@dune-fd-test01.fnal.gov` and uses
Kerberos/GSSAPI.

The remote-side `neutrino` return key is intentionally kept outside the home
filesystem because `/home/arroyave` on `dune-fd-test01` can be full:

```bash
/tmp/arroyave/workstation-bridge/id_ed25519
```

Authorize its public key locally in `/home/neutrino/.ssh/authorized_keys` with a
loopback restriction, for example `from="127.0.0.1,::1" ...`.

Launch this workstation bridge:

```bash
WORKSTATION_BRIDGE_REMOTE=fnal-workstation-bridge \
WORKSTATION_BRIDGE_REMOTE_PORT=2223 \
WORKSTATION_BRIDGE_LOCAL_PORT=2222 \
WORKSTATION_BRIDGE_LOCAL_SESSION=workstation-reverse-ssh-dune \
WORKSTATION_BRIDGE_REMOTE_SESSION=neutrino \
WORKSTATION_BRIDGE_REMOTE_IDENTITY=/tmp/arroyave/workstation-bridge/id_ed25519 \
WORKSTATION_BRIDGE_TARGET_SESSION=Fermi \
  /home/neutrino/bin/launch-workstation-on-srv017.sh
```

From `dune-fd-test01`, attach to the ready shell:

```bash
tmux attach -t neutrino
```

This opens the workstation's existing `Fermi` tmux session. It does not create
a separate empty session. The inner `Fermi` prefix remains `Ctrl-A`; the outer
DUNE wrapper uses `Ctrl-\\`.

Or connect directly from `dune-fd-test01`:

```bash
ssh -tt -i /tmp/arroyave/workstation-bridge/id_ed25519 \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  -p 2223 neutrino@localhost \
  tmux attach-session -t =Fermi
```

For another persistent Codex session, omit
`WORKSTATION_BRIDGE_TARGET_SESSION`, reach the workstation shell, and use
`tmux-codex up <session>`. The default session used by the installed systemd
units is `work`:

```bash
tmux-codex up work
```

## Start Or Recover The Bridge

Confirm that the FNAL Kerberos ticket is valid:

```bash
klist
ssh dune-fd-test01 'hostname && whoami'
```

Install, configure, enable, or repair the local SSH service:

```bash
cd ~/work/workstation-ops-config
WORKSTATION_BRIDGE_INSTALL_WSL_BOOT=1 home/bin/start-workstation-sshd.sh
```

Launch the retrying FGZ reverse tunnel and the DUNE return-shell session:

```bash
cd ~/work/workstation-ops-config
home/bin/launch-workstation-on-fgz.sh
```

The local SSH service starts with WSL through systemd. The reverse tunnel runs
inside the local tmux server named `workstation-reverse`; it is not currently
a Windows startup task. If the workstation or WSL restarts, obtain a valid FNAL
ticket and rerun the FGZ launcher.

## Connect From DUNE

After logging in to DUNE, attach to the maintained workstation shell:

```bash
tmux attach -t workstation-shell
```

For a fresh one-shot login instead:

```bash
ssh -i /storage/workstation-bridge-arroyave/id_ed25519_wl144132 \
  -o IdentitiesOnly=yes \
  -p 2222 marroyav@127.0.0.1
```

## Status Checks

On the workstation:

```bash
systemctl is-enabled ssh.service
systemctl is-active ssh.service
ss -ltn 'sport = :2222'
tmux -L workstation-reverse list-sessions
home/bin/status-workstation-on-fgz.sh
```

On DUNE:

```bash
ss -ltn 'sport = :2222'
tmux list-sessions
```

## Stop The Runtime Bridge

These commands stop the two tmux loops but leave the local SSH service enabled:

```bash
tmux -L workstation-reverse kill-session -t workstation-reverse-ssh
ssh dune-fd-test01 'tmux kill-session -t workstation-shell'
```

## Tracked Files

- `home/bin/start-workstation-sshd.sh`
- `home/bin/open-np04-reverse-ssh.sh`
- `home/bin/launch-workstation-on-srv017.sh`
- `home/bin/launch-workstation-on-fgz.sh`
- `home/bin/status-workstation-on-srv017.sh`
- `home/bin/status-workstation-on-fgz.sh`
- `system/etc/ssh/sshd_config.d/workstation-bridge.conf`

The retired CERN-specific design remains in
`home/WORKSTATION_SSH_CERN_RETIRED.md`.
