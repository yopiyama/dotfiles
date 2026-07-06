#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: 危険な git 操作をガードする。
# settings.json から git push / git reset の deny を外して都度許可に切り替えたため、
# 自動許可系モード (dontAsk / auto / bypassPermissions) でも
# 「仕事リポジトリの main に勝手に push」「reset --hard で成果物が消える」
# といった事故が起きないよう、hook レベルで deny / ask を返す。
#
# 判定ポリシー:
#   git push
#     - --mirror / --delete / -d               → deny（破壊的・取り消し困難）
#     - main/master への force push             → deny
#     - main/master への push（仕事リポジトリ）  → deny（remote が yopiyama 配下以外）
#     - main/master への push（個人リポジトリ）  → ask （remote が github.com/yopiyama/）
#     - その他の force push                     → ask
#     - 上記以外                                → noop（通常のパーミッション確認 = 都度許可）
#   git reset
#     - --hard / --merge で未コミット変更あり    → deny（作業内容が失われる）
#     - --hard / --merge でクリーン             → ask （ブランチ位置が動く）
#     - --soft / --mixed / paths 指定等         → noop
#
# deny > ask > noop の優先で、複合コマンド (&&, ;, |) 内の全 git 呼び出しを検査する。

PERSONAL_REMOTE_PATTERN='github\.com[:/]yopiyama/'
PROTECTED_BRANCH_PATTERN='^(main|master)$'

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""')"

[[ "$tool_name" != "Bash" ]] && exit 0

command="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
[[ -z "$command" ]] && exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // ""')"
[[ -z "$cwd" ]] && cwd="$PWD"

# 最終判定。deny が 1 つでもあれば deny、無ければ ask、どちらも無ければ noop。
decision=""
reason=""

escalate() {
  local new_decision="$1" new_reason="$2"
  if [[ "$new_decision" == "deny" ]]; then
    if [[ "$decision" != "deny" ]]; then
      decision="deny"
      reason="$new_reason"
    fi
  elif [[ "$new_decision" == "ask" && -z "$decision" ]]; then
    decision="ask"
    reason="$new_reason"
  fi
}

# --- git 実行ディレクトリの解決（`git -C <path>` 対応） ---
resolve_git_dir() {
  local p="$1"
  [[ "$p" == "~" ]] && p="$HOME"
  [[ "$p" == "~/"* ]] && p="$HOME/${p#\~/}"
  if [[ "$p" == /* ]]; then
    (cd "$p" 2>/dev/null && pwd -P) || printf '%s' "$cwd"
  else
    (cd "$cwd" 2>/dev/null && cd "$p" 2>/dev/null && pwd -P) || printf '%s' "$cwd"
  fi
}

# --- git push の検査 ---
# 引数: git push 以降のトークン列と実行ディレクトリ
check_push() {
  local dir="$1"
  shift
  local force=false mirror=false delete=false
  local remote="" branches="" tok dst

  for tok in "$@"; do
    case "$tok" in
      -f|--force|--force-with-lease|--force-with-lease=*|--force-if-includes)
        force=true ;;
      --mirror) mirror=true ;;
      -d|--delete) delete=true ;;
      --all|--branches) branches="$branches all" ;;
      -*)
        # その他のフラグは無視（値を取るフラグの値がブランチ名に誤認される
        # 可能性はあるが、誤検知は安全側に倒れるだけなので許容する）
        ;;
      *)
        if [[ -z "$remote" ]]; then
          remote="$tok"
        else
          # refspec。先頭の + は force push を意味する
          if [[ "$tok" == +* ]]; then
            force=true
            tok="${tok#+}"
          fi
          # src:dst 形式なら dst 側（リモートに書き込まれる先）を見る
          dst="${tok##*:}"
          dst="${dst#refs/heads/}"
          branches="$branches $dst"
        fi
        ;;
    esac
  done

  if [[ "$mirror" == "true" ]]; then
    escalate deny "git push --mirror はリモートの全 ref を上書き・削除するため hook でブロックしています。必要なら手動で実行してください。"
    return
  fi
  if [[ "$delete" == "true" ]]; then
    escalate deny "git push --delete はリモートブランチを削除するため hook でブロックしています。必要なら手動で実行してください。"
    return
  fi

  # refspec 省略時はカレントブランチが push 対象
  if [[ -z "$branches" ]]; then
    branches="$(git -C "$dir" branch --show-current 2>/dev/null || true)"
  fi

  # remote 省略時は upstream 設定 → origin の順で解決
  local remote_url=""
  if [[ -z "$remote" ]]; then
    local cur
    cur="$(git -C "$dir" branch --show-current 2>/dev/null || true)"
    remote="$(git -C "$dir" config --get "branch.${cur}.remote" 2>/dev/null || true)"
    [[ -z "$remote" ]] && remote="origin"
  fi
  # remote が URL 直指定の場合は get-url が失敗するのでそのまま使う
  remote_url="$(git -C "$dir" remote get-url "$remote" 2>/dev/null || printf '%s' "$remote")"

  local personal=false
  printf '%s' "$remote_url" | grep -qE "$PERSONAL_REMOTE_PATTERN" && personal=true

  local br protected=false
  for br in $branches; do
    if printf '%s' "$br" | grep -qE "$PROTECTED_BRANCH_PATTERN"; then
      protected=true
      break
    fi
  done

  if [[ "$protected" == "true" ]]; then
    if [[ "$force" == "true" ]]; then
      escalate deny "main/master への force push は hook でブロックしています。必要なら手動で実行してください。（remote: ${remote_url}）"
    elif [[ "$personal" == "true" ]]; then
      escalate ask "個人リポジトリ (${remote_url}) の main/master への push です。実行してよいか確認してください。"
    else
      escalate deny "仕事リポジトリ (${remote_url}) の main/master への直接 push は hook でブロックしています。PR 経由でマージするか、必要なら手動で実行してください。"
    fi
  elif [[ "$force" == "true" ]]; then
    escalate ask "force push (${remote_url}) です。実行してよいか確認してください。"
  fi
}

# --- git reset の検査 ---
check_reset() {
  local dir="$1"
  shift
  local destructive=false mode="" tok

  for tok in "$@"; do
    case "$tok" in
      --hard)  destructive=true; mode="--hard" ;;
      --merge) destructive=true; mode="--merge" ;;
    esac
  done

  [[ "$destructive" == "false" ]] && return

  if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null | head -1)" ]]; then
    escalate deny "git reset ${mode} は未コミットの変更（git status で確認可）を破棄するため hook でブロックしています。変更を退避（stash / commit）してから実行してください。"
  else
    escalate ask "git reset ${mode} はブランチ位置を移動します。実行してよいか確認してください。"
  fi
}

# --- コマンドを複合区切り (&&, ||, ;, |) でセグメントに分割して検査 ---
# クォート内の区切り文字までは追わない簡易分割だが、分割し過ぎた場合も
# 「git push / git reset に見えるセグメントが増える」方向なので安全側。
oneline="$(printf '%s' "$command" | tr '\n' ' ')"
normalized="${oneline//&&/|}"
normalized="${normalized//||/|}"
normalized="${normalized//;/|}"

IFS='|' read -ra segments <<< "$normalized"

for segment in "${segments[@]}"; do
  trimmed="$(printf '%s' "$segment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$trimmed" ]] && continue

  # env 変数代入プレフィックスを除去 (GIT_DIR=x git push 等)
  while [[ "$trimmed" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do
    trimmed="$(printf '%s' "$trimmed" | sed -E 's/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+//')"
  done

  [[ "$trimmed" =~ ^git([[:space:]]|$) ]] || continue

  # トークン分割（クォートは剥がすだけの簡易処理）
  read -ra tokens <<< "$trimmed"

  git_dir="$cwd"
  subcommand=""
  sub_args=()
  i=1
  n=${#tokens[@]}
  while (( i < n )); do
    tok="${tokens[$i]}"
    if [[ -n "$subcommand" ]]; then
      # サブコマンド確定後はフラグ含め全トークンを引数として渡す
      sub_args+=("$tok")
    else
      case "$tok" in
        -C)
          (( i + 1 < n )) || break
          i=$((i + 1))
          path_tok="${tokens[$i]}"
          path_tok="${path_tok%\"}"; path_tok="${path_tok#\"}"
          path_tok="${path_tok%\'}"; path_tok="${path_tok#\'}"
          git_dir="$(resolve_git_dir "$path_tok")"
          ;;
        -c)
          # -c key=value は値を1つ消費
          i=$((i + 1))
          ;;
        -*)
          # その他の git グローバルフラグは無視
          ;;
        *)
          subcommand="$tok"
          ;;
      esac
    fi
    i=$((i + 1))
  done

  case "$subcommand" in
    push)  check_push "$git_dir" ${sub_args[@]+"${sub_args[@]}"} ;;
    reset) check_reset "$git_dir" ${sub_args[@]+"${sub_args[@]}"} ;;
  esac
done

if [[ -n "$decision" ]]; then
  jq -n --arg decision "$decision" --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $decision,
      permissionDecisionReason: $reason
    }
  }'
fi
