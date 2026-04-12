#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
git -C "$repo_root" config core.hooksPath .githooks
# Local divergence: keep the range checker and installer executable for local validation workflows.
chmod +x "$repo_root/.githooks/commit-msg" "$repo_root/scripts/check-commit-standards.sh" "$repo_root/scripts/check-commit-range.sh" "$repo_root/scripts/install-hooks.sh"

echo "Configured git hooks for $repo_root"
echo "Active hooks path: .githooks"
