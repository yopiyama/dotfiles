#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: パイプ (|) を含む Bash コマンドを自動許可する。
# settings.json の allow パターンはパイプ付きコマンドにマッチしにくいため、
# command-policy.conf のプレフィックスリストで全コマンドを検証し、
# 安全なら permissionDecision: allow を返してパーミッション確認をスキップする。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="${SCRIPT_DIR}/command-policy.conf"

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""')"

[[ "$tool_name" != "Bash" ]] && exit 0

command="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
[[ -z "$command" ]] && exit 0

# --- パイプ検出（クォート内・|| を除外） ---
oneline="$(printf '%s' "$command" | tr '\n' ' ')"
cleaned="$(printf '%s' "$oneline" | sed -E 's/"[^"]*"//g')"
cleaned="$(printf '%s' "$cleaned" | sed -E "s/'[^']*'//g")"
cleaned="$(printf '%s' "$cleaned" | sed 's/||//g')"

printf '%s' "$cleaned" | grep -qF '|' || exit 0

# --- ポリシーファイル読み込み ---
[[ -f "$POLICY_FILE" ]] || exit 0

read_section() {
  sed -n "/^\[$1\]/,/^\[/p" "$POLICY_FILE" \
    | grep -v '^\[' | grep -v '^#' | grep -v '^[[:space:]]*$'
}

matches_section() {
  local cmd="$1" section="$2"
  while IFS= read -r prefix; do
    [[ -z "$prefix" ]] && continue
    [[ "$cmd" == "$prefix" || "$cmd" == "$prefix "* ]] && return 0
  done < <(read_section "$section")
  return 1
}

matches_deny_pattern() {
  local cmd="$1"
  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    if printf '%s' "$cmd" | grep -qE "$pattern"; then
      return 0
    fi
  done < <(read_section deny_pattern)
  return 1
}

# --- パイプチェーン内の全コマンドを検証 ---
# &&, ; も | に統一してから IFS split（macOS sed の \n 非互換を回避）
normalized="${cleaned//&&/|}"
normalized="${normalized//;/|}"
IFS='|' read -ra segments <<< "$normalized"

all_safe=true
for segment in "${segments[@]}"; do
  trimmed="$(printf '%s' "$segment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$trimmed" ]] && continue

  if matches_section "$trimmed" deny; then
    exit 0
  fi
  if matches_deny_pattern "$trimmed"; then
    exit 0
  fi
  if ! matches_section "$trimmed" allow; then
    all_safe=false
    break
  fi
done

if [[ "$all_safe" == "true" ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow"
    }
  }'
fi
