# tmux and Codex Session Recovery

`home/.local/bin/tmux-codex` snapshots a tmux session's windows, panes,
working directories, layout, and active Codex thread UUIDs. It can recreate the
tmux layout after WSL or the user manager restarts and run `codex resume` in the
panes that previously hosted Codex.

The tool records recovery metadata only. It does not serialize shell processes,
terminal scrollback, or unsaved editor buffers.

## Requirements

- Python 3.10 or newer
- tmux
- Codex CLI on `PATH` when restoring panes that contain Codex threads
- Linux `/proc`, which is used to associate tmux panes with open Codex rollout
  files

## Install

From the repository root:

```bash
install -Dm755 home/.local/bin/tmux-codex ~/.local/bin/tmux-codex
install -Dm644 home/.config/systemd/user/tmux-codex-snapshot.service \
  ~/.config/systemd/user/tmux-codex-snapshot.service
install -Dm644 home/.config/systemd/user/tmux-codex-snapshot.timer \
  ~/.config/systemd/user/tmux-codex-snapshot.timer
install -Dm644 home/.config/systemd/user/tmux-codex-final-snapshot.service \
  ~/.config/systemd/user/tmux-codex-final-snapshot.service

systemctl --user daemon-reload
systemctl --user enable --now tmux-codex-snapshot.timer
systemctl --user enable --now tmux-codex-final-snapshot.service
```

The supplied units snapshot a tmux session named `work` every minute and once
more when the user systemd manager stops. Change `work` in the service units if
the persistent session uses another name.

## Use

```bash
# Save a live session now.
tmux-codex save work

# Inspect the saved pane-to-thread mapping.
tmux-codex show work

# Preview recovery without changing tmux.
tmux-codex restore work --dry-run

# Recreate a missing session.
tmux-codex restore work

# Restore if needed, then attach or switch the current tmux client.
tmux-codex up work
```

`restore` refuses to run if a tmux session with the same name already exists.
Codex panes whose thread UUID cannot be resolved are restored as ordinary shell
panes. Other processes are also restored as shells in their saved working
directories.

## Runtime State and Backups

Snapshots are written atomically with mode `0600` under
`${XDG_STATE_HOME:-~/.local/state}/tmux-codex/`. They contain host paths and
Codex thread UUIDs, so they are runtime state and are intentionally ignored by
this repository.

For recovery beyond a normal restart, back up both the snapshot directory and
the corresponding `~/.codex` session data separately. Do not commit either to
this repository.
