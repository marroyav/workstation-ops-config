# Workstation SSH Bridge Draft

The old CERN bridge was retired locally on 2026-05-28. It used this pattern:

1. WSL Debian ran `sshd` on `127.0.0.1:2222`.
2. A local tmux loop kept a reverse tunnel open with `ssh -R 2222:127.0.0.1:2222 <remote>`.
3. A remote tmux session SSHed back to `neutrino@localhost -p 2222`.

## What Is Disabled Now

- Windows scheduled tasks `WorkstationBridge Launch` and `WorkstationBridge Watchdog` are disabled.
- The Windows Startup launcher was renamed to `start-workstation-bridge.cmd.disabled`.
- The local `workstation-reverse-ssh` tmux session was killed.
- The WSL boot hook and bridge sshd config were moved to disabled files under `/etc`.
- The CERN SSH host alias `np04-srv-017-bridge` is active again in `/home/neutrino/.ssh/config` as of 2026-06-05.
- `np04-srv-017-bridge` now reaches `np04-srv-017` through the CERN tunnel host alias `cern-lxtunnel`, which resolves to `marroyav@lxtunnel.cern.ch`.
- The bridge scripts no longer default to CERN; they require an explicit remote alias or `WORKSTATION_BRIDGE_REMOTE`.

The detailed CERN-era notes are preserved in:

```bash
/home/neutrino/WORKSTATION_SSH_CERN_RETIRED.md
```

## Fermilab Reuse Checklist

## CERN LxTunnel Reuse

If `np04-srv-017` is not resolvable directly from WSL, prime the CERN tunnel first:

```bash
ssh cern-lxtunnel
```

The local `/etc/krb5.conf` now maps `cern.ch`, `lxtunnel.cern.ch`, `lxplus.cern.ch`, and `np04-srv-017` to the `CERN.CH` Kerberos realm. This is required for GSSAPI to request `host/lxtunnel*.cern.ch@CERN.CH` tickets instead of service tickets with an empty realm.

After authentication, exit the shell. The SSH control master is kept for 8 hours by `ControlPersist`.

Then test the final bridge host:

```bash
ssh np04-srv-017-bridge 'hostname && whoami'
```

Launch the workstation reverse bridge through the same path:

```bash
WORKSTATION_BRIDGE_REMOTE=np04-srv-017-bridge \
  /home/neutrino/bin/launch-workstation-on-srv017.sh
```

Add a future SSH host alias in `/home/neutrino/.ssh/config`, using the commented `fnal-workstation-bridge` block as a template. Then test it directly:

```bash
ssh fnal-workstation-bridge 'hostname && whoami'
```

Start the local loopback SSH endpoint only when you are ready to use the bridge:

```bash
/home/neutrino/bin/start-workstation-sshd.sh
```

Launch the bridge explicitly:

```bash
WORKSTATION_BRIDGE_REMOTE=fnal-workstation-bridge \
  /home/neutrino/bin/launch-workstation-on-srv017.sh
```

From the Fermilab remote host, attach to:

```bash
tmux attach -t workstation-shell
```

## Optional Autostart

Do not re-enable autostart until the Fermilab host alias and key-based auth are verified.

For WSL boot autostart of the local sshd only:

```bash
WORKSTATION_BRIDGE_INSTALL_WSL_BOOT=1 /home/neutrino/bin/start-workstation-sshd.sh
```

For Windows autostart, update the disabled Startup `.cmd` or the disabled Task Scheduler entries to pass:

```bash
WORKSTATION_BRIDGE_REMOTE=fnal-workstation-bridge
```

## Files

- `/home/neutrino/bin/start-workstation-sshd.sh`
- `/home/neutrino/bin/open-np04-reverse-ssh.sh`
- `/home/neutrino/bin/launch-workstation-on-srv017.sh`
- `/home/neutrino/bin/status-workstation-on-srv017.sh`
- `/home/neutrino/.ssh/config`
- `/home/neutrino/WORKSTATION_SSH_CERN_RETIRED.md`
