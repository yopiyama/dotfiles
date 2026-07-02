#!/bin/bash
set -euo pipefail

# codex CLI の有無とレビューのベースブランチを判定して出力する。
# 呼び出し側 (SKILL.md ステップ1・2) はこの出力の CODEX=/BASE= 行をパースする。

if command -v codex >/dev/null 2>&1; then
  echo "CODEX=available"
else
  echo "CODEX=unavailable"
fi

if git rev-parse --verify main >/dev/null 2>&1; then
  echo "BASE=main"
elif git rev-parse --verify master >/dev/null 2>&1; then
  echo "BASE=master"
else
  echo "BASE="
fi
