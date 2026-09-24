#!/usr/bin/env bash
# ZCode release: sync fork main to upstream latest -> tag version on main ->
# dispatch the build workflow (tags on main cannot trigger it themselves).
#
# Branch model:
# - main: source backup branch (survives upstream takedowns), kept in
#   lockstep with zai-org/ZCode main. Version tags (vX.Y.Z) are cut here so
#   each tag marks the exact source tree being released.
# - package-standalone: standalone orphan branch holding only the packaging
#   config (.github, scripts). Zero shared history with main, never merged
#   or rebased onto it, and squashed to a single commit on every release.
# - CI builds from douglarek/ZCode main / the tag in its own checkout
#   directory; the package-standalone branch itself carries no source.
#
# Usage:
#   scripts/release.sh v3.14.3          # release v3.14.3
#   scripts/release.sh v3.14.3 --dry-run
#
# Prerequisite: package-standalone is the repo's default branch (otherwise
# the workflow cannot be registered/dispatched).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

tag="${1:?Usage: scripts/release.sh vX.Y.Z [--dry-run]}"
dry_run="${2:-}"

case "$tag" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "error: tag must look like vX.Y.Z, got: $tag" >&2; exit 1 ;;
esac

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is dirty; commit or stash first" >&2
  exit 1
fi

current="$(git rev-parse --abbrev-ref HEAD)"
[ "$current" = "package-standalone" ] || { echo "error: run this from package-standalone (on: $current)" >&2; exit 1; }

echo "==> sync fork main to upstream latest (backup/source branch)"
git fetch upstream main
local_main="$(git rev-parse refs/remotes/origin/main 2>/dev/null || echo "")"
upstream_main="$(git rev-parse refs/remotes/upstream/main)"
main_in_sync=1
if [ "$local_main" = "$upstream_main" ]; then
  echo "fork main already at upstream/main ($upstream_main)"
else
  main_in_sync=0
  echo "fork main needs update: $local_main -> $upstream_main"
fi
echo "building from douglarek/ZCode@main=$upstream_main"

dirty="$(git status --porcelain)"
branch_sha="$(git rev-parse --short HEAD)"

echo "==> tag $tag on main ($upstream_main)"
if [ -n "$dry_run" ]; then
  echo "dry-run: nothing below is executed. Would run:"
  [ "$main_in_sync" = 0 ] && echo "  git push origin $upstream_main:refs/heads/main --force-with-lease=..."
  [ -n "$dirty" ] && echo "  (commit pending packaging changes on package-standalone)"
  [ -n "$dirty" ] && echo "  git push --force-with-lease origin package-standalone  # squashed to 1 commit"
  echo "  git tag -f $tag $upstream_main"
  echo "  git push -f origin $tag"
  echo "  gh workflow run build-desktop.yml -f release_tag=$tag -f source_ref=$upstream_main"
  exit 0
fi

# --- everything below mutates state ---

if [ "$main_in_sync" = 0 ]; then
  git push origin "$upstream_main:refs/heads/main" \
    --force-with-lease="refs/heads/main:${local_main:-0000000000000000000000000000000000000000}"
fi

echo "==> squash package-standalone into a single commit and force-push"
# Amended commit hash changes on every release, so the branch is always
# rewritten; --force-with-lease guards against remote races.
if [ -n "$dirty" ]; then
  git add -A
  git -c commit.gpgsign=false commit --amend -m \
    "packaging: desktop build and release pipeline

Standalone packaging config only; builds source from
douglarek/ZCode main (zai-org/ZCode backup). See
.github/workflows/build-desktop.yml." >/dev/null
  branch_sha="$(git rev-parse --short HEAD)"
  git push --force-with-lease origin package-standalone
  echo "package-standalone pushed as $branch_sha"
else
  echo "package-standalone unchanged ($branch_sha); nothing to push"
fi

echo "==> tag $tag on main and dispatch build"
git -c commit.gpgsign=false tag -f "$tag" "$upstream_main"
git push -f origin "$tag"
# Tags on main cannot trigger the workflow (the tagged commit has no
# workflow file), so dispatch the run explicitly against the tag's source.
gh workflow run build-desktop.yml -f "release_tag=$tag" -f "source_ref=$upstream_main" \
  || echo "warning: gh workflow run failed; trigger manually at https://github.com/douglarek/ZCode/actions" >&2
echo "==> triggered; watch: https://github.com/douglarek/ZCode/actions"
