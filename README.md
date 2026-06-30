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
- `home/.local/bin/` stores small wrapper scripts, not downloaded binaries.
- `home/.config/` stores selected application and XDG configs.
- `work/build-ops/` stores FNAL/CERN build sync, archive, controller, and
  GitHub artifact watcher source files.
- `system/` stores selected system-level reference config that belongs to this
  workstation setup.
- `docs/` records excluded sensitive files and restore notes.

## Kerberos and CERN/FNAL Access

See `docs/local-kerberos-cern-fnal.md` for the local WSL Kerberos setup,
including the `arroyave@FNAL.GOV` and `marroyav@CERN.CH` principals, the
installed `/etc/krb5.conf` reference, and the CERN SSH alias layout.

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
