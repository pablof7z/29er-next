#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NMP_DIR="$ROOT/Dependencies/nmp"
NMP_REMOTE="https://github.com/pablof7z/nmp.git"
NMP_BRANCH="master"

if [[ ! -e "$NMP_DIR" ]]; then
  mkdir -p "$ROOT/Dependencies"
  git clone --branch "$NMP_BRANCH" --single-branch "$NMP_REMOTE" "$NMP_DIR"
elif ! git -C "$NMP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "NMP checkout is not a Git work tree: $NMP_DIR" >&2
  exit 1
else
  actual_remote="$(git -C "$NMP_DIR" remote get-url origin)"
  if [[ "$actual_remote" != "$NMP_REMOTE" ]]; then
    echo "NMP origin must be $NMP_REMOTE; found $actual_remote" >&2
    exit 1
  fi

  if ! git -C "$NMP_DIR" diff --quiet || ! git -C "$NMP_DIR" diff --cached --quiet; then
    echo "NMP checkout has local changes; commit or discard them before bootstrapping master." >&2
    exit 1
  fi

  git -C "$NMP_DIR" fetch --prune origin "$NMP_BRANCH"
  if git -C "$NMP_DIR" show-ref --verify --quiet "refs/heads/$NMP_BRANCH"; then
    git -C "$NMP_DIR" switch --quiet "$NMP_BRANCH"
    git -C "$NMP_DIR" merge --ff-only "origin/$NMP_BRANCH"
  else
    git -C "$NMP_DIR" switch --quiet --track -c "$NMP_BRANCH" "origin/$NMP_BRANCH"
  fi
fi

if [[ ! -x "$NMP_DIR/scripts/build-swift-xcframework.sh" ]]; then
  echo "NMP build script is missing from $NMP_DIR." >&2
  exit 1
fi

(
  cd "$NMP_DIR"
  scripts/build-swift-xcframework.sh
)
