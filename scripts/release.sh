#!/usr/bin/env bash
# ZCode 发版：同步 main 到上游最新 -> 在 package-standalone 上打版本 tag -> 推送触发发布。
#
# 分支模型：package-standalone 是独立孤儿分支，只含 .github 打包配置，
# 与 main 零共同历史，任何情况下都不 rebase / merge main 进来。
# 构建源由 CI 的工作流自己检出 zai-org/ZCode 最新 main（独立目录），tag 只是触发器和版本标记。
#
# 用法：
#   scripts/release.sh v3.14.3          # 发布 v3.14.3
#   scripts/release.sh v3.14.3 --dry-run
#
# 前置条件：package-standalone 为仓库默认分支（否则 tag 触发不生效）。
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

echo "==> sync main to upstream latest (source branch only)"
git fetch upstream main
git push origin "upstream/main:refs/heads/main" --force-with-lease=refs/heads/main:"$(git rev-parse origin/main 2>/dev/null || echo 0000000000000000000000000000000000000000)"

echo "==> resolve upstream main tip for the record"
source_sha="$(git ls-remote https://github.com/zai-org/ZCode.git refs/heads/main | cut -f1)"
echo "building from zai-org/ZCode@$source_sha"

echo "==> tag $tag on package-standalone ($(git rev-parse --short HEAD))"
if [ -n "$dry_run" ]; then
  echo "dry-run: would run:"
  echo "  git tag $tag"
  echo "  git push origin $tag"
else
  git -c commit.gpgsign=false tag "$tag"
  git push origin "$tag"
  echo "==> pushed; watch: https://github.com/douglarek/ZCode/actions"
fi
