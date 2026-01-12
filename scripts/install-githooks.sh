#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

git config core.hooksPath .githooks

echo "Installed git hooks to .githooks (repo-local)."

if [[ -f "$repo_root/scripts/setup-ios-local-signing.sh" ]]; then
  "$repo_root/scripts/setup-ios-local-signing.sh" --non-interactive || true
fi
