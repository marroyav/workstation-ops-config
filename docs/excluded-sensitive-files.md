# Excluded Sensitive Files

These files are important but should not be committed to Git.

## SSH

- `/home/neutrino/.ssh/id_ed25519`
- `/home/neutrino/.ssh/id_ed25519_np04_bridge`
- `/home/neutrino/.ssh/wsl_sshd_ed25519`
- `/home/neutrino/.ssh/authorized_keys`
- `/home/neutrino/.ssh/known_hosts*`
- `/home/neutrino/.ssh/cm-*`
- `/home/neutrino/.ssh/*.log`

The SSH configs in this repo may reference those paths, but the key material
itself needs a separate encrypted backup.

## Tokens And Auth State

- `/home/neutrino/.config/daphne-build-ops/github-token`
- `/home/neutrino/.codex/auth.json`
- `/home/neutrino/.codex/*.sqlite*`
- `/home/neutrino/.codex/history.jsonl`
- `/home/neutrino/.codex/session_index.jsonl`
- `/home/neutrino/.codex/shell_snapshots/`

The GitHub artifact watcher stores only the token file path and environment
variable names in source code. The actual token stays out of the repo.

## Histories, Logs, And Generated State

- `/home/neutrino/.bash_history`
- `/home/neutrino/.zsh_history`
- `/home/neutrino/.viminfo`
- `/home/neutrino/.lesshst`
- `/home/neutrino/.workstation-bridge-launch.log`
- `/home/neutrino/work/build-ops/*-state/`
- `/home/neutrino/work/build-ops/*.log`
- `/home/neutrino/work/build-ops/*.out`
- `/home/neutrino/work/build-ops/*.nohup`

These can contain commands, paths, hostnames, transient build state, or other
local context that is not appropriate for source control.
