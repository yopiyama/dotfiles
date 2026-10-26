#!/usr/bin/env bash
# git worktree の短い一覧・選択・作成・削除を fzf で行う。
# `gwt new <branch> [dir]` 以外の引数付きは素の git worktree に委譲する。
set -euo pipefail

if [ "${1:-}" != new ] && [ "$#" -gt 0 ]; then
  exec git worktree "$@"
fi

git rev-parse --git-dir >/dev/null 2>&1 || { echo 'gwt: Git リポジトリ内で実行してください' >&2; exit 1; }

worktree_root() { # worktree_root <main worktree>
  local main="$1" root
  root="$(git -C "$main" config --get worktree.root 2>/dev/null || true)"
  [ -n "$root" ] || root="${WORKTREE_ROOT:-$HOME/worktrees}"
  case "$root" in
    /*)  printf '%s' "$root" ;;
    \~*) printf '%s' "${root/#\~/$HOME}" ;;
    *)   printf '%s' "$main/$root" ;;
  esac
}

if [ "${1:-}" = new ]; then
  shift
  branch="${1:-}"
  if [ -z "$branch" ]; then
    command -v fzf >/dev/null || { echo 'gwt: fzf が必要です' >&2; exit 1; }
    branch="$(git for-each-ref --format='%(refname:short)' refs/heads | fzf \
      --prompt='branch> ' \
      --header='既存ブランチを選択   Esc: cancel')" || exit 0
    [ -n "$branch" ] || exit 0
  fi
  main="$(git rev-parse --show-toplevel)"
  repo="$(basename "$main")"
  root="$(worktree_root "$main")"
  dir="${2:-$root/$repo/${branch//\//-}}"
  mkdir -p "$(dirname "$dir")"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$dir" "$branch"
  else
    git worktree add "$dir" -b "$branch"
  fi

  cd "$dir"
  # ローカル設定のリンク、direnv allow / mise trust + install、serena MCP の登録。
  [ -x "$HOME/.local/bin/worktree-sync" ] && "$HOME/.local/bin/worktree-sync" "$PWD"
  printf 'Worktree ready at %s\n' "$PWD"
  exit 0
fi

command -v fzf >/dev/null || { echo 'gwt: fzf が必要です' >&2; exit 1; }

TAB=$'\t'
BRANCH_WIDTH=60
PR_WIDTH=8

# ブランチ列を一定幅にして、区切りとパス列を常に同じ位置から始める。
format_branch() {
  local value="$1" pad
  if [ "${#value}" -gt "$BRANCH_WIDTH" ]; then
    value="${value:0:$((BRANCH_WIDTH - 1))}…"
  fi
  printf '%s' "$value"
  pad=$((BRANCH_WIDTH - ${#value}))
  [ "$pad" -gt 0 ] && printf '%*s' "$pad" ''
}

collect_worktrees() {
  git -C "${1:-$PWD}" worktree list --porcelain | awk '
    function flush() { if (path != "") print path "\t" branch "\t" flag; path = "" }
    /^worktree / { flush(); path = substr($0, 10); branch = ""; flag = "" }
    /^branch /   { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
    /^detached$/ { branch = "(detached)"; flag = "detached" }
    END          { flush() }
  '
}

wt_list="$(collect_worktrees)"
[ -n "$wt_list" ] || { echo 'gwt: worktree を取得できませんでした' >&2; exit 1; }
main_path="${wt_list%%$'\n'*}"
main_path="${main_path%%$TAB*}"
main_parent="$(dirname "$main_path")"
repo_label="$(basename "$main_path")"

# 対象ブランチの最新 PR を 1 リクエストで取得する。未取得と PR なしは区別する。
pr_list=''
pr_available=false
collect_prs() {
  command -v gh >/dev/null || return 1
  local path branch flag index=0 fields='' variables='' query
  local args=()
  while IFS="$TAB" read -r path branch flag; do
    [ -n "$branch" ] && [ "$flag" != detached ] || continue
    variables="$variables, \$branch$index: String!"
    fields="$fields pr$index: pullRequests(headRefName: \$branch$index, first: 1, orderBy: {field: CREATED_AT, direction: DESC}) { nodes { headRefName number state } }"
    args+=(-f "branch$index=$branch")
    index=$((index + 1))
  done <<EOF
$wt_list
EOF
  [ "$index" -gt 0 ] || return 0
  query="query(\$owner: String!, \$name: String!$variables) { repository(owner: \$owner, name: \$name) { $fields } }"
  gh api graphql -F owner='{owner}' -F name='{repo}' -f "query=$query" "${args[@]}" \
    --jq '.data.repository | to_entries[] | .value.nodes[] | [.headRefName, .state, (.number | tostring)] | @tsv' 2>/dev/null
}

if pr_list="$(collect_prs)"; then
  pr_available=true
else
  pr_list=''
  echo 'gwt: PR 情報を取得できませんでした (gh の導入・認証・接続を確認してください)' >&2
fi

pr_label() {
  local branch="$1" flag="$2" head state number
  [ "$flag" != detached ] || { printf '-'; return; }
  [ "$pr_available" = true ] || { printf '?'; return; }
  while IFS="$TAB" read -r head state number; do
    [ "$head" = "$branch" ] || continue
    case "$state" in
      OPEN) printf '#%s' "$number" ;;
      CLOSED) printf 'Closed' ;;
      MERGED) printf 'Merged' ;;
    esac
    return
  done <<EOF
$pr_list
EOF
  printf '-'
}

build_list() {
  local path branch flag display note
  while IFS="$TAB" read -r path branch flag; do
    [ -n "$path" ] || continue
    [ -n "$branch" ] || branch="$(basename "$path")"
    if [ "$path" = "$main_path" ]; then
      display='./'; note='main'
    elif [[ "$path" == "$main_path/"* ]]; then
      display="./${path#"$main_path"/}"; note=''
    elif [[ "$path" == "$main_parent/"* ]]; then
      display="../${path#"$main_parent"/}"; note=''
    elif [[ "$path" == "$HOME/"* ]]; then
      display="~/${path#"$HOME"/}"; note=''
    else
      display="$path"; note=''
    fi
    [ "$flag" = detached ] && note="${note:+$note, }detached"
    printf '%-*s │ %s │ %s%s\t%s\n' "$PR_WIDTH" "$(pr_label "$branch" "$flag")" \
      "$(format_branch "$branch")" "$display" "${note:+  ($note)}" "$path"
  done <<EOF
$wt_list
EOF
}

while :; do
  fzf_out="$(build_list | fzf --delimiter="$TAB" --with-nth=1 --expect=ctrl-d \
    --prompt='worktree> ' \
    --header="$repo_label   Enter: shell   Ctrl-d: remove   Esc: cancel" \
    --no-multi)" || exit 0
  key="$(printf '%s\n' "$fzf_out" | sed -n '1p')"
  selected="$(printf '%s\n' "$fzf_out" | sed -n '2p')"
  [ -n "$selected" ] || exit 0
  target="${selected##*"$TAB"}"

  if [ "$key" != ctrl-d ]; then
    cd "$target"
    exec "${SHELL:-/bin/sh}"
  fi

  if [ "$target" = "$main_path" ]; then
    echo 'gwt: メイン worktree は削除できません' >&2
    continue
  fi
  printf '削除しますか? %s [y/N]: ' "$(basename "$target")" >&2
  read -r answer
  case "$answer" in [yY]*) ;; *) continue ;; esac
  if ! git -C "$main_path" worktree remove "$target"; then
    printf '変更を破棄して強制削除しますか? [y/N]: ' >&2
    read -r answer
    case "$answer" in [yY]*) git -C "$main_path" worktree remove --force "$target" ;; esac
  fi
  wt_list="$(collect_worktrees "$main_path")"
done
