#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

git -C "$ROOT" submodule update --init --recursive

if [[ ! -x "$ROOT/Dependencies/nmp/scripts/build-swift-xcframework.sh" ]]; then
  echo "NMP build script is missing; verify the Dependencies/nmp submodule." >&2
  exit 1
fi

(
  cd "$ROOT/Dependencies/nmp"
  scripts/build-swift-xcframework.sh
)
