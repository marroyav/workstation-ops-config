# Development Environment Guide

This guide describes the interactive tools installed by
`scripts/bootstrap-dev-environment.sh` and configured under `home/`.

After restoring the configuration, open a new terminal or run:

```bash
source ~/.bashrc
```

Do not try to memorize everything. Start with `ll`, `rg`, `fd`, `Ctrl-R`, and
`z`. Add the other tools when a task calls for them.

For a ground-up explanation of `|`, `$()`, and quoting, read
[`shell-pipes.md`](shell-pipes.md).

## Files and Navigation

### eza: readable directory listings

```bash
l                 # simple listing
ll                # details, hidden files, and Git state
la                # include hidden files
lt                # two-level directory tree
```

### fd: find files by name

```bash
fd config
fd -e py
fd -t d src
fd -H '.env'
```

`fd` has simpler defaults than `find` and respects `.gitignore`.

### ripgrep: search inside files

```bash
rg TODO
rg -i error
rg 'function_name' src/
rg import -g '*.py'
rg -l password
```

### fzf: fuzzy selection

- `Ctrl-R`: search command history.
- `Ctrl-T`: select a file and insert its path on the command line.
- `Alt-C`: select and enter a directory.
- `command **` followed by Tab: fuzzy path completion.

Compose it with other commands:

```bash
fd --type f | fzf
nvim "$(fd --type f | fzf)"
```

### zoxide: jump to frequently used directories

Visit directories normally for a while, then jump using part of a remembered
path:

```bash
z firmware
z build ops
```

The custom `fcd` function provides a visual directory picker:

```bash
fcd
fcd ~/work
```

### bat: read files with syntax highlighting

```bash
bat README.md
bat -n script.py
bat -l json data.txt
bat --plain file.txt
```

Regular `cat` remains unchanged.

## Git

### Delta

Delta activates automatically for:

```bash
git diff
git show
git log -p
```

In its pager, use Space and `b` to move by pages, `n` and `N` to move between
diff sections, and `q` to quit.

### Lazygit

Run `lg` inside a Git repository. It provides panels for files, commits,
branches, stashes, and remotes. Press `?` for context-sensitive help and `q` to
quit.

Inside tmux, `Ctrl-A` followed by `g` opens Lazygit in a popup.

The Git include fragment also enables `zdiff3` conflict markers, histogram
diffs, automatic remote pruning, `main` for new repositories, and automatic
upstream creation on the first push.

## tmux

Start and reconnect to named sessions:

```bash
tmux new -s development
tmux ls
tmux attach -t development
```

The prefix is `Ctrl-A`: press and release it, then press the next key.

- `Ctrl-A d`: detach without stopping the session.
- `Ctrl-A c`: create a window.
- `Alt-h` / `Alt-l`: previous/next window.
- `Ctrl-A |` / `Ctrl-A -`: split horizontally/vertically.
- `Ctrl-A h/j/k/l`: move between panes.
- `Ctrl-A H/J/K/L`: resize panes.
- `Ctrl-A Enter`: enter copy mode; `v` selects and `y` copies to Windows.
- `Ctrl-A g`: Lazygit popup.
- `Ctrl-A B`: btop popup.
- `Ctrl-A e`: Neovim popup in the current pane's directory.
- `Ctrl-A D`: `ncdu` disk-usage popup in the current pane's directory.
- `Ctrl-A t`: interactive shell popup in the current pane's directory.
- `Ctrl-A r`: reload the configuration.

Popup applications close when you quit the application. For example, `:q`
closes the Neovim popup, `q` closes `ncdu` or `btop`, and `exit` closes the
shell popup.

For a persistent tmux session containing Codex conversations, `tmux-codex`
can save its pane layout and active Codex thread identifiers:

```bash
tmux-codex save work
tmux-codex show work
tmux-codex restore work --dry-run
tmux-codex up work
```

`up` restores a missing session and then attaches to it; it simply attaches
when the session already exists. See
[`tmux-codex-sessions.md`](tmux-codex-sessions.md) for installing the automatic
snapshot timer, recovery behavior, and backup requirements.

## Neovim

Open a file, a directory, or the built-in tutorial:

```bash
nvim file.py
nvim .
nvim +Tutor
```

Essential Vim commands:

- `i`: insert mode; Escape returns to normal mode.
- `:w`, `:q`, `:wq`, `:q!`: save, quit, save-and-quit, discard-and-quit.
- `u` / `Ctrl-R`: undo/redo.
- `yy` / `p`: copy a line/paste.
- `/text`, `n`, `N`: search and move through matches.

Workstation mappings:

- Space is the leader key: press and release Space, then type the remaining
  key or keys.
- `Ctrl-S`: save.
- `Ctrl-H/J/K/L`: navigate splits.
- `Space e`: file explorer.
- `Space f`: find a file under the current search path.
- `Space g`: search project text with ripgrep.
- `Space t t`: terminal split; `Esc Esc` leaves terminal mode.
- `]d` / `[d`: next/previous diagnostic.
- `Space d`: show diagnostic details.

The `unnamedplus` clipboard connects Neovim yanks and pastes to the WSLg/
Windows clipboard.

## Project Environments

`direnv` loads project-specific environment variables from `.envrc` when you
enter a directory and unloads them when you leave.

Example `.envrc`:

```bash
export APP_ENV=development
export API_PORT=8080
```

Review it, then authorize it:

```bash
direnv allow
```

An `.envrc` can execute shell code. Run `direnv allow` only for files you
trust.

## JSON, Shell Scripts, Processes, and Storage

```bash
jq . response.json
jq -r '.users[].email' response.json
shellcheck script.sh
btop
ncdu .
```

The first argument to `jq` is a filter. A dot means "use the complete JSON
document," so include it before the filename:

```bash
jq . 2010-rav4-v6-4wd-techstream-data-list.json
jq . 2010-rav4-v6-4wd-techstream-data-list.json | less -R
```

Running `jq filename.json` makes `jq` parse the filename as filter code and
produces a compile error. In the scrollable form, press `q` to exit `less`.

`top` is aliased to `btop`. In `ncdu`, the `d` key deletes the selected item;
use it carefully.

## Prompt

Starship runs automatically. It shows the working directory, Git state,
active language environment, and commands lasting more than one second.

To understand the currently displayed prompt:

```bash
starship explain
```

## Keep Windows Awake at Sign-in

The tracked Windows scripts install a hidden per-user scheduled task named
`WorkstationOps Keep Windows Awake`. It starts at Windows sign-in and prevents
automatic system sleep and display timeout, matching the existing
`home/bin/keep-windows-awake.ps1` helper.

Start or stop the helper manually from WSL. Both commands return immediately:

```bash
awake
awake stop
```

Install or refresh the automatic sign-in task:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$PWD/windows/Install-KeepWindowsAwake.ps1")"
```

Check its state:

```bash
powershell.exe -NoProfile -Command \
  'Get-ScheduledTask -TaskName "WorkstationOps Keep Windows Awake"'
```

The installed copy and its small run log live under
`%LOCALAPPDATA%\WorkstationOps`. To keep Windows awake while allowing the
display to turn off normally, rerun the installer with `-AllowDisplaySleep`.
To remove the task and deployed files, rerun it with `-Uninstall`.

## Brave and WSLg

```bash
brave-browser             # native Wayland when available
brave-x11                 # explicit accelerated X11 fallback
gui-wayland APPLICATION   # force another application to Wayland
gui-x11 APPLICATION       # force another application to X11
```

Keep the X11 fallback. On this workstation, XWayland is D3D12 accelerated,
while some native Wayland OpenGL paths use software rendering because WSLg
does not advertise Linux DMA-BUF to the distro. See
[`wslg-wayland.md`](wslg-wayland.md).

## A Practical Daily Sequence

```bash
tmux new -s work
z project-name
ll
rg TODO
nvim "$(fd --type f | fzf)"
```

Use `Ctrl-A g` for Git, `Ctrl-A B` for system monitoring, `Ctrl-A e` for an
editor, `Ctrl-A D` for disk usage, and `Ctrl-A t` for a temporary shell.
