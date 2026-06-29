#!/bin/bash
set -euo pipefail

BASE="${1:-}"
TITLE="${2:-}"

if [ -z "$TITLE" ]; then
  echo "Usage: codex-review.sh <BASE_BRANCH> <TITLE>" >&2
  echo "  BASE_BRANCH: ベースブランチ名 (空文字の場合は uncommitted のみ)" >&2
  echo "  TITLE: codex review の --title に渡す文字列" >&2
  exit 1
fi

has_committed=false
has_uncommitted=false

if [ -n "$BASE" ]; then
  committed_files="$(git diff --name-only "${BASE}...HEAD" 2>/dev/null || true)"
  if [ -n "$committed_files" ]; then
    has_committed=true
  fi
fi

uncommitted_files="$(git diff --name-only HEAD 2>/dev/null || true)"
untracked_files="$(git ls-files --others --exclude-standard 2>/dev/null || true)"
if [ -n "$uncommitted_files" ] || [ -n "$untracked_files" ]; then
  has_uncommitted=true
fi

if ! $has_committed && ! $has_uncommitted; then
  echo "レビュー対象の変更がありません"
  exit 0
fi

if $has_committed; then
  echo "=== コミット済み変更のレビュー ==="
  codex review --base "$BASE" --title "$TITLE"
  echo ""
fi

if $has_uncommitted; then
  echo "=== 未コミット変更のレビュー ==="
  codex review --uncommitted --title "${TITLE} | 未コミット変更"
  echo ""
fi
