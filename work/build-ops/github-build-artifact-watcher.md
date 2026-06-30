# GitHub Build Artifact Watcher

Local watcher that scans successful DAPHNE build outputs under:

- `/w`
- `/mnt/c/w`

and, when a GitHub token is configured, publishes each new overlay zip to a
dedicated GitHub release and upserts a commit comment with the asset link.

## Files

- `github_build_artifact_watcher.sh`
- `github_commit_zip_publisher.py`

## Token

Put a GitHub token with repository write access in:

`~/.config/daphne-build-ops/github-token`

or export one of:

- `DAPHNE_GITHUB_TOKEN`
- `GH_TOKEN`
- `GITHUB_TOKEN`

The token needs enough permission to:

- create or update releases
- upload release assets
- create or edit commit comments

## Defaults

- repo: `DUNE-DAQ/daphne-firmware`
- release tag: `daphne-build-artifacts`
- release name: `DAPHNE Build Artifacts`

## Seed Current Artifacts

Mark all currently existing zips as already seen without uploading them:

```bash
/home/neutrino/work/build-ops/github_build_artifact_watcher.sh --seed-current --once
```

This is the safe first step if you only want future successful runs to be
published.

## Run Once

```bash
/home/neutrino/work/build-ops/github_build_artifact_watcher.sh --once
```

## Run Continuously

```bash
tmux new-session -d -s github-build-artifact-watcher \
  '/home/neutrino/work/build-ops/github_build_artifact_watcher.sh'
```

## What Counts As Publishable

The watcher currently looks for:

- `*_ol_<gitsha>.zip`
- `*_OL_<gitsha>.zip`

and requires a sibling `SHA256SUMS` file before it considers the artifact
complete enough to publish.

## State

State is stored under:

`/home/neutrino/work/build-ops/github-build-state`

including:

- `status.txt`
- `history.log`
- `last-publish.json`
- `seen/*.env`
