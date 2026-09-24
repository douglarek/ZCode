#!/usr/bin/env bash
# ZCode 发版：同步 main 到上游最新 -> 基于最新源码打版本 tag -> 推送触发发布。
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

echo "==> sync main to upstream"
git checkout main
git pull --ff-only upstream main

echo "==> fast-forward package-standalone to the same commit"
git checkout package-standalone
# package-standalone 与 main 无共同历史（独立孤儿分支），用 rebase 把
# 打包提交叠到上游最新提交之上；若上游强制推送导致冲突需手工处理。
git rebase main

echo "==> tag $tag on $(git rev-parse --short HEAD)"
if [ -n "$dry_run" ]; then
  echo "dry-run: would run:"
  echo "  git tag $tag"
  echo "  git push origin package-standalone $tag"
else
  git tag "$tag"
  git push origin package-standalone "$tag"
  echo "==> pushed; watch: https://github.com/douglarek/ZCode/actions"
fi
