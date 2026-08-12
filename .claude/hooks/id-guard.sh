#!/usr/bin/env bash
set -uo pipefail

# PreToolUse hook: 内部的な通し番号が「書いてはいけない宛先」に出るのを防ぐ。
#
# code-review の指摘 ID (P1-1)、会話の中で振った番号、Obsidian vault の
# パス、PBI 内のローカル番号（非機能要件3 等）は、その文脈の中では便利だが
# コードコメントや GitHub コメントに書くと読み手が辿れない参照になる。
# 逆に Obsidian は自分用のメモなので何を書いても構わないし、Notion なら
# PBI 内のローカル番号はそのページの文脈で通じる。
#
# そこで「ID の種類 × 宛先」の許可表を id-guard.conf に持ち、宛先が外に
# 出るほど厳しく判定する。判定はパターンマッチのみで、自然文の中の
# 「さっきの 3 番目の件」のような書き方は拾えない（拾おうとすると誤検知が
# 増えるため、意図的に見ていない）。
#
# 宛先の判定:
#   external ... Write/Edit（下記の除外パス以外）、gh のコメント系コマンド、
#                git commit。conf の [destination:external] を適用
#   notion   ... Notion MCP の書き込み系ツール。[destination:notion] を適用
#   （素通し） ... vault / ~/.claude/projects / tmp への書き込み、obs.sh、
#                Notion の読み取り系、その他すべての Bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${ID_GUARD_CONF:-${SCRIPT_DIR}/id-guard.conf}"

[[ -f "$CONF" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# --- conf の読み出し --------------------------------------------------------

# 指定セクションの本文行をそのまま出す
section_body() {
  awk -v want="[$1]" '
    /^\[/ { inside = ($0 == want); next }
    inside { print }
  ' "$CONF"
}

# コメント・空行を落とし、前後の空白を削る
strip_comments() {
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -vE '^(#|$)'
}

kind_names() {
  grep -oE '^\[kind:[^]]+\]' "$CONF" | sed -E 's/^\[kind:(.*)\]$/\1/'
}

kind_label() {
  section_body "kind:$1" | grep -E '^label[[:space:]]*=' | head -1 |
    sed -E 's/^label[[:space:]]*=[[:space:]]*//'
}

kind_patterns() {
  section_body "kind:$1" | strip_comments | grep -vE '^label[[:space:]]*='
}

# 宛先と種類から allow / ask / deny を引く。未記載は allow
decision_for() {
  local d
  d="$(section_body "destination:$1" | strip_comments |
    awk -v k="$2" '$2 == k { print $1; exit }')"
  printf '%s' "${d:-allow}"
}

# --- Obsidian vault の場所（obs.sh と同じくレジストリから解決）-------------

VAULT=""
resolve_vault() {
  local reg="$HOME/Library/Application Support/obsidian/obsidian.json" p=""
  if [[ -f "$reg" ]]; then
    p="$(jq -r '[.vaults[]? | select(.path)] | (map(select(.open == true)) + .) | .[0].path // empty' \
      "$reg" 2>/dev/null)"
  fi
  VAULT="${p:-}"
}

# 判定対象外のパスか
path_is_exempt() {
  local p="$1" line pref
  while IFS= read -r line; do
    pref="${line//\$HOME/$HOME}"
    if [[ "$pref" == *'$VAULT'* ]]; then
      [[ -n "$VAULT" ]] || continue
      pref="${pref//\$VAULT/$VAULT}"
    fi
    [[ -n "$pref" ]] || continue
    [[ "$p" == "$pref" || "$p" == "$pref"/* ]] && return 0
  done < <(section_body allow_path | strip_comments)

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$p" == *"$line"* ]] && return 0
  done < <(section_body exempt_path | strip_comments)

  return 1
}

# 外向きの書き込みコマンドか
is_external_command() {
  local norm="$1" line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '%s' "$norm" | grep -qE "(^|[[:space:]]|[;&|(])${line}([[:space:]]|\$)" && return 0
  done < <(section_body external_command | strip_comments)
  return 1
}

# --- 入力から宛先と検査対象テキストを決める --------------------------------

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""')"
[[ -n "$tool_name" ]] || exit 0

dest=""
text=""

case "$tool_name" in
Write | Edit)
  file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')"
  [[ -n "$file_path" ]] || exit 0
  resolve_vault
  path_is_exempt "$file_path" && exit 0
  dest="external"
  if [[ "$tool_name" == "Write" ]]; then
    text="$(printf '%s' "$input" | jq -r '.tool_input.content // ""')"
  else
    text="$(printf '%s' "$input" | jq -r '.tool_input.new_string // ""')"
  fi
  ;;
Bash)
  command_line="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
  [[ -n "$command_line" ]] || exit 0
  norm="$(printf '%s' "$command_line" | tr '\n' ' ' | tr -s ' ')"
  is_external_command "$norm" || exit 0
  dest="external"
  # heredoc や -m の本文はコマンド文字列自体に載るのでそのまま見る
  text="$command_line"
  # --body-file / --file / -F で外部ファイルを渡している場合はその中身も見る
  while IFS= read -r body_file; do
    [[ -n "$body_file" && "$body_file" != "-" ]] || continue
    body_file="${body_file/#\~/$HOME}"
    [[ -f "$body_file" ]] && text+=$'\n'"$(cat "$body_file")"
  done < <(printf '%s' "$norm" |
    grep -oE '(--body-file|--file|-F)[=[:space:]][^[:space:]]+' |
    sed -E 's/^(--body-file|--file|-F)[=[:space:]]//')
  ;;
mcp__notion__notion-create-pages | mcp__notion__notion-update-page | \
  mcp__notion__notion-create-comment | mcp__notion__notion-create-database | \
  mcp__notion__notion-update-data-source | mcp__notion__notion-duplicate-page | \
  mcp__notion__notion-move-pages | mcp__notion__notion-create-view | \
  mcp__notion__notion-update-view)
  dest="notion"
  text="$(printf '%s' "$input" | jq -r '.tool_input // {} | tostring')"
  ;;
*)
  exit 0
  ;;
esac

[[ -n "$text" ]] || exit 0

# --- 種類ごとに突き合わせる ------------------------------------------------

worst="allow"
report=""

while IFS= read -r kind; do
  [[ -n "$kind" ]] || continue
  decision="$(decision_for "$dest" "$kind")"
  [[ "$decision" == "allow" ]] && continue

  hits=""
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] || continue
    matched="$(printf '%s' "$text" | grep -oE "$pattern" 2>/dev/null)"
    [[ -n "$matched" ]] && hits+="${matched}"$'\n'
  done < <(kind_patterns "$kind")

  [[ -n "$hits" ]] || continue

  listed="$(printf '%s' "$hits" | grep -v '^$' | sort -u | head -5 |
    tr '\n' '\a' | sed 's/\a$//; s/\a/, /g')"
  report+="- $(kind_label "$kind"): ${listed}"$'\n'

  if [[ "$decision" == "deny" ]]; then
    worst="deny"
  elif [[ "$worst" != "deny" ]]; then
    worst="ask"
  fi
done < <(kind_names)

[[ "$worst" == "allow" ]] && exit 0

if [[ "$dest" == "notion" ]]; then
  reason="Notion への書き込みに、Notion 側から辿れない ID が含まれています。

${report}
これらは Obsidian vault や私と Claude のやり取りの中でだけ通じる番号です。Notion を読む人が参照できる形（PBI ID、ページリンク、または番号を使わない説明）に直すか、意図的に書くなら承認してください。"
else
  reason="コード / ドキュメント / GitHub コメント / コミットメッセージへの書き込みに、内部的な通し番号が含まれています。

${report}
これらは私と Claude のやり取り・Obsidian vault・PBI の中でしか意味を持たない番号で、後から読む人（将来の自分を含む）は辿れません。Notion の PBI ID のように恒久的に引ける ID へ置き換えるか、番号ではなく内容そのものを書いてください。番号を消せない事情があるなら、その旨を私に確認してください。"
fi

jq -n --arg decision "$worst" --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: $decision,
    permissionDecisionReason: $reason
  }
}'
