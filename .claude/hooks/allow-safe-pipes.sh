#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: パイプ・リダイレクト・複合コマンド (&&, ||, ;) を含む
# Bash コマンドを自動許可する。settings.json の allow パターンは
# これらのシェル構文を含むコマンドにマッチしにくいため、
# command-policy.conf のプレフィックスリストで全コマンドを検証し、
# 安全なら permissionDecision: allow を返してパーミッション確認をスキップする。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="${SCRIPT_DIR}/command-policy.conf"

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""')"

[[ "$tool_name" != "Bash" ]] && exit 0

command="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
[[ -z "$command" ]] && exit 0

# --- クォート除去・正規化 ---
oneline="$(printf '%s' "$command" | tr '\n' ' ')"
cleaned="$(printf '%s' "$oneline" | sed -E 's/"[^"]*"//g')"
cleaned="$(printf '%s' "$cleaned" | sed -E "s/'[^']*'//g")"
has_compound=false
printf '%s' "$cleaned" | grep -qF '||' && has_compound=true
printf '%s' "$cleaned" | grep -qF '&&' && has_compound=true
printf '%s' "$cleaned" | grep -qF ';' && has_compound=true
cleaned="$(printf '%s' "$cleaned" | sed 's/||/\&\&/g')"

has_pipe=false
has_redirect=false
printf '%s' "$cleaned" | grep -qF '|' && has_pipe=true
printf '%s' "$cleaned" | grep -qE '(^|[[:space:]])[0-9]*>' && has_redirect=true

# --- gh api の読み取り専用 (GET/HEAD) 判定 ---
# `gh api` は同じサブコマンドでも -X/-f 等のフラグ次第で書き込みになるため、
# command-policy.conf のプレフィックス方式（サブコマンド単位）では安全に許可できない。
# 明示的に「書き込みを示すフラグが一切無い」ことを確認できた場合のみ許可する。
is_readonly_gh_api() {
  local cmd="$1"

  [[ "$cmd" =~ ^gh[[:space:]]+api([[:space:]]|$) ]] || return 1

  # コマンド置換・サブシェルを含む場合は判定不能として拒否（安全側）
  [[ "$cmd" == *'$('* ]] && return 1
  [[ "$cmd" == *'`'* ]] && return 1

  # トークン単位で走査する。gh (pflag) は短縮オプションに
  # `-X POST` (space) / `-X=POST` (equals) / `-XPOST` (attached, space無し)
  # のいずれの形式も受け付けるため、正規表現の単純な区切り文字仮定では
  # `-XPOST` のような attached 形式を見落とす（実際に発生した誤許可バグ）。
  local -a tokens
  read -ra tokens <<< "$cmd"
  local n=${#tokens[@]}
  local i tok method=""

  for ((i = 0; i < n; i++)); do
    tok="${tokens[$i]}"
    case "$tok" in
      # -f/-F/--field/--raw-field/--input は付随フラグ形式(attached/=)を問わず
      # デフォルト method を POST に変えるため常に拒否
      -f*|-F*|--field*|--raw-field*|--input*)
        return 1
        ;;
      -X|--method)
        # スペース区切り: 値は次のトークン。値が無い不完全なコマンドは安全側で拒否
        (( i + 1 < n )) || return 1
        method="${tokens[$((i + 1))]}"
        ;;
      -X?*)
        method="${tok#-X}"
        method="${method#=}"
        ;;
      --method=*)
        method="${tok#--method=}"
        ;;
    esac
  done

  if [[ -n "$method" ]]; then
    local method_upper
    method_upper="$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')"
    [[ "$method_upper" == "GET" || "$method_upper" == "HEAD" ]] || return 1
  fi

  return 0
}

if [[ "$has_pipe" == "false" && "$has_redirect" == "false" && "$has_compound" == "false" ]]; then
  single_trimmed="$(printf '%s' "$cleaned" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if is_readonly_gh_api "$single_trimmed"; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: "gh api read-only (GET/HEAD) call auto-approved"
      }
    }'
  fi
  exit 0
fi

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

# --- リダイレクトを除去するヘルパー ---
strip_redirects() {
  printf '%s' "$1" | sed -E \
    -e 's/[0-9]*>&[0-9]+ *//g' \
    -e 's/[0-9]*>> *[^ ]* *//g' \
    -e 's/[0-9]*> *[^ ]* *//g' \
    -e 's/[0-9]*< *[^ ]* *//g' \
    -e 's/[[:space:]]*$//'
}

# --- パイプチェーン内の全コマンドを検証 ---
# &&, ; も | に統一してから IFS split（macOS sed の \n 非互換を回避）
normalized="${cleaned//&&/|}"
normalized="${normalized//;/|}"
IFS='|' read -ra segments <<< "$normalized"

all_safe=true
for segment in "${segments[@]}"; do
  trimmed="$(strip_redirects "$segment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$trimmed" ]] && continue

  if matches_section "$trimmed" deny; then
    exit 0
  fi
  if matches_deny_pattern "$trimmed"; then
    exit 0
  fi
  if ! matches_section "$trimmed" allow && ! is_readonly_gh_api "$trimmed"; then
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
