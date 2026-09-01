#!/usr/bin/env bash
# レビュー対象ブランチに紐付く PR の Description / コメント / レビューコメントを
# まとめて取得する。1 ラウンド目の事前情報として各レビューエージェントに渡す。
#
# 使い方:
#   fetch-pr-context.sh [PR番号 | PR URL] [--repo owner/name]
#
# 引数省略時はカレントブランチの PR を gh pr view で解決する。
# PR が無い / gh が使えない場合は 1 行目に PR=none を出して正常終了する
# (レビュー自体は PR 情報なしで続行できるため、ここでは落とさない)。
set -uo pipefail

FETCH=~/.claude/skills/pr-comments/scripts/fetch-pr-comments.sh

args=(pr view --json number,title,url,state,body)
pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) args+=(--repo "$2"); pass+=(--repo "$2"); shift 2 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) args=(pr view "$1" --json number,title,url,state,body); pass+=("$1"); shift ;;
  esac
done

if ! err=$(gh "${args[@]}" 2>&1 >/dev/null); then
  echo "PR=none"
  echo "理由: ${err:-gh pr view に失敗}"
  exit 0
fi
pr=$(gh "${args[@]}")

jq -r '"PR=#\(.number)
URL: \(.url)
タイトル: \(.title)
State: \(.state)

## PR Description
\(if (.body // "" | gsub("\\s"; "")) == "" then "(なし)" else .body end)"' <<<"$pr"

echo
if [ -x "$FETCH" ]; then
  "$FETCH" "${pass[@]+"${pass[@]}"}" --format md --include-resolved \
    || echo "(コメント取得に失敗。PR Description のみで続行する)"
else
  echo "(fetch-pr-comments.sh が見つからないためコメント取得をスキップ)"
fi
