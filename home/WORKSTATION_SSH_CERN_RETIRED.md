# Workstation SSH Bridge To `np04-srv-017`

This setup does not use the Windows OpenSSH server for interactive access.
The working path is:

1. WSL runs the normal root-owned Debian `ssh` service on `127.0.0.1:2222`.
2. A reverse SSH tunnel publishes that port onto `np04-srv-017:2222`.
3. A `tmux` session on `np04-srv-017` SSHes to `neutrino@localhost -p 2222`.

The result is that from `np04-srv-017` you can attach to a tmux session and land on:

```bash
neutrino@WL-123935:~$
```

## What To Launch

After a reboot, WSL restart, or if the sessions are gone, run this on the workstation:

```bash
/home/neutrino/bin/launch-workstation-on-srv017.sh
```

That single command does all of the following:

1. Starts the WSL `sshd` listener on `127.0.0.1:2222`.
2. Starts a reconnecting local tmux session that keeps the reverse tunnel alive.
3. Recreates the remote `tmux` session on `np04-srv-017`.

It is safe to run this command again.
It does not tear down a healthy local tunnel or remote `workstation-shell` session.
It also does not restart a healthy root-owned WSL `ssh` service.

## Daily Use

From `np04-srv-017`:

```bash
tmux attach -t workstation-shell
```

If you need to see that the session exists first:

```bash
tmux ls
```

## Keybindings

There are two tmux layers and they intentionally do not share the same prefix:

- Remote tmux on `np04-srv-017`: prefix `Ctrl-\`
- Local tmux on this workstation for the reverse tunnel: prefix `Ctrl-g`

This avoids the nested `Ctrl-b` collision that killed the sessions before.

## Useful Commands

Rebuild everything:

```bash
/home/neutrino/bin/launch-workstation-on-srv017.sh
```

Check status:

```bash
/home/neutrino/bin/status-workstation-on-srv017.sh
```

## Keeping It Up For Days

The setup stays alive for days if these three conditions hold:

1. WSL is still running on the workstation.
2. The local tmux session `workstation-reverse-ssh` is still alive.
3. `np04-srv-017` remains reachable over SSH.

What already helps:

- The WSL SSH endpoint is now the normal root-owned Debian `ssh` service, not the old user-owned custom daemon.
- The reverse tunnel runs inside a tmux loop and retries every 5 seconds if SSH drops.
- The remote `workstation-shell` tmux pane also retries every 5 seconds if the shell disconnects.
- SSH keepalives are enabled on the reverse tunnel.

What still breaks it:

- Windows reboot
- `wsl --shutdown`
- manually killing the local `workstation-reverse` tmux server
- manually killing the remote `workstation-shell` session

The recovery command is still just:

```bash
/home/neutrino/bin/launch-workstation-on-srv017.sh
```

## Windows Startup

I also placed a startup launcher in your Windows Startup folder:

- `C:\Users\arroyave\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\start-workstation-bridge.cmd`

That means after a normal Windows login, the bridge should relaunch automatically.
It starts WSL, runs the launcher, and writes a log to:

- `/home/neutrino/.workstation-bridge-launch.log`

WSL also has:

- `/etc/wsl.conf`

with:

```ini
[boot]
command=service ssh start
```

so the root-owned Debian `ssh` service is started automatically whenever the distro starts.

Inspect the local reverse-tunnel tmux session:

```bash
tmux -L workstation-reverse attach -t workstation-reverse-ssh
```

See the local reverse-tunnel tmux session without attaching:

```bash
tmux -L workstation-reverse ls
```

Manual remote command test from this workstation:

```bash
ssh marroyav@np04-srv-017 "ssh -o BatchMode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 2222 neutrino@localhost hostname"
```

## Files Involved

- `/home/neutrino/bin/start-workstation-sshd.sh`
- `/home/neutrino/bin/open-np04-reverse-ssh.sh`
- `/home/neutrino/bin/launch-workstation-on-srv017.sh`
- `/home/neutrino/bin/status-workstation-on-srv017.sh`
- `/etc/ssh/sshd_config.d/workstation-bridge.conf`
- `/etc/wsl.conf`
- `/home/neutrino/.ssh/authorized_keys`

## Failure Modes

If `tmux attach -t workstation-shell` on `np04-srv-017` shows nothing useful:

1. Run `/home/neutrino/bin/status-workstation-on-srv017.sh` on the workstation.
2. If the remote command test fails, rerun `/home/neutrino/bin/launch-workstation-on-srv017.sh`.
3. If the remote tmux exists but the shell exited, rerunning the launch script is still the simplest repair.

## Notes

- The remote tmux session is on the default tmux server on `np04-srv-017`, so plain `tmux ls` should show it.
- The local reverse-tunnel tmux session uses the custom socket `workstation-reverse`, so plain `tmux ls` on the workstation will not show it.
- The old user-owned sshd path is obsolete; the stable path is now the root-owned Debian `ssh` service.
