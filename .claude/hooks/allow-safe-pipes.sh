#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: パイプ・リダイレクト・複合コマンド (&&, ||, ;) を含む
# Bash コマンドを自動許可する。settings.json の allow パターンは
# これらのシェル構文を含むコマンドにマッチしにくいため、
# command-policy.conf のプレフィックスリストで全コマンドを検証し、
# 安全なら permissionDecision: allow を返してパーミッション確認をスキップする。
#
# 加えて、auto-allow できず通常のパーミッション確認に落ちるケースのうち
# 「複数の cd を含む複合コマンド」は deny + 理由を返し、ディレクトリごとの
# 分割実行を促す。Claude Code 本体が複数 cd の複合コマンドを強制確認に
# するため、プロジェクト settings で許可済みのコマンド（gotestsum 等）でも
# 1 つに繋げると自動承認されなくなるのを防ぐ。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="${SCRIPT_DIR}/command-policy.conf"

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""')"

[[ "$tool_name" != "Bash" ]] && exit 0

command="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
[[ -z "$command" ]] && exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // ""')"

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

# --- 冗長な `git -C <path>` の検出 ---
# settings.json / command-policy.conf の allow は `git diff` 等の前方一致なので、
# `git -C <path> diff` はマッチせず毎回パーミッション確認になる。
# path が cwd（または cwd のリポジトリルート）を指していて -C が不要な場合は
# deny + 理由を返し、`-C` 無しで実行し直すよう促す（サブエージェントにも効く）。
expand_tilde() {
  local p="$1"
  [[ "$p" == "~" ]] && p="$HOME"
  [[ "$p" == "~/"* ]] && p="$HOME/${p#\~/}"
  printf '%s' "$p"
}

# base からの相対も考慮してディレクトリを物理パスに解決。失敗時は空文字。
resolve_dir() {
  local base="$1" p="$2"
  p="$(expand_tilde "$p")"
  if [[ "$p" == /* ]]; then
    (cd "$p" 2>/dev/null && pwd -P) || true
  else
    (cd "$base" 2>/dev/null && cd "$p" 2>/dev/null && pwd -P) || true
  fi
}

check_redundant_git_c() {
  [[ -n "$cwd" ]] || return 1
  printf '%s' "$oneline" | grep -qE 'git[[:space:]]+-C[[:space:]]' || return 1

  local cwd_real toplevel
  cwd_real="$(resolve_dir / "$cwd")"
  [[ -n "$cwd_real" ]] || return 1
  toplevel="$(git -C "$cwd_real" rev-parse --show-toplevel 2>/dev/null || true)"

  # `git -C` 直後のトークンを path として抽出する。クォート付きでも
  # 空白を含まない path なら剥がして解決できる。空白入り path は
  # トークンが途中で切れて解決に失敗し、安全側（noop）に倒れる。
  local -a paths
  local p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    paths+=("$p")
  done < <(printf '%s\n' "$oneline" \
    | grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:];|&]+' \
    | sed -E "s/^git[[:space:]]+-C[[:space:]]+//; s/^\"(.*)\"\$/\1/; s/^'(.*)'\$/\1/")

  [[ "${#paths[@]}" -gt 0 ]] || return 1

  # 全ての -C が cwd と同一リポジトリを指す場合のみ「冗長」と判定する。
  # 別リポジトリ向けが1つでも混ざれば通常のパーミッション確認に委ねる。
  local resolved
  for p in "${paths[@]}"; do
    resolved="$(resolve_dir "$cwd_real" "$p")"
    [[ -n "$resolved" ]] || return 1
    if [[ "$resolved" != "$cwd_real" ]] && { [[ -z "$toplevel" ]] || [[ "$resolved" != "$toplevel" ]]; }; then
      return 1
    fi
  done
  return 0
}

if check_redundant_git_c; then
  jq -n --arg cwd "$cwd" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("`git -C <path>` の path は cwd (" + $cwd + ") と同じリポジトリを指しており -C は不要です。`-C <path>` を付けると許可済みパターン (git diff, git log 等) に一致せず毎回確認が必要になるため、`-C <path>` を外して実行し直してください。")
    }
  }'
  exit 0
fi

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
  exit 0
fi

# --- 複数 cd を含む複合コマンドは分割実行を促す ---
# ここに到達するのは auto-allow できず通常のパーミッション確認に落ちるケース。
# 複数 cd のチェーンは Claude Code 本体が強制確認にするため、プロジェクト
# settings で許可済みのコマンドでも自動承認されない。deny + 理由を返して
# 「ディレクトリごとに 1 コマンドずつ」に分割し直させる。
cd_count=0
for segment in "${segments[@]}"; do
  trimmed="$(strip_redirects "$segment" | sed 's/^[[:space:](]*//;s/[[:space:]]*$//')"
  if [[ "$trimmed" == "cd" || "$trimmed" == "cd "* ]]; then
    cd_count=$((cd_count + 1))
  fi
done

if (( cd_count >= 2 )); then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "複数の cd を 1 つの複合コマンドに繋げると Claude Code が強制的にパーミッション確認を出すため、プロジェクトで許可済みのコマンドでも自動承認されません。ディレクトリごとにコマンドを分割し、`cd <dir> && <command>` の形で 1 回ずつ別々の Bash 呼び出しとして実行し直してください。"
    }
  }'
  exit 0
fi
