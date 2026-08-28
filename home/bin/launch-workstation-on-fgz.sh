#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

export WORKSTATION_BRIDGE_REMOTE="${WORKSTATION_BRIDGE_REMOTE:-dune-fd-test01}"
export WORKSTATION_BRIDGE_REMOTE_IDENTITY="${WORKSTATION_BRIDGE_REMOTE_IDENTITY:-/storage/workstation-bridge-arroyave/id_ed25519_wl144132}"

exec "$script_dir/launch-workstation-on-srv017.sh" "$@"
