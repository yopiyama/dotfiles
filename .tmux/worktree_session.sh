#!/usr/bin/env bash
# git worktree を tmux セッションに 1:1 対応させて開く。
# 通常は tmux の `prefix + C-w` から display-popup 経由で呼ばれる (カレントペインの
# ディレクトリが起点)。fzf で worktree を選ぶと、それに対応するセッションへ移動する。
#
# - 一覧の正は `git worktree list`。git 自身が登録済み worktree の実パスを持っているので、
#   <repo>/.claude/worktrees/ でも ../<repo>.worktrees/ でも置き場所を問わず拾える
#   (ディレクトリを走査しないので探索パスの設定が要らない)。
# - 既にその worktree のセッションがあれば作らずに switch/attach するだけ。対応付けは
#   セッションオプション @worktree_path で持つ (名前の推測に頼らない)。
# - ウィンドウ構成は ~/.tmux/projects.json の .defaults.windows を流用する
#   (projects[] は同じ path に複数プロファイルを持てるのでパスから引き当てない)。
# - 新規作成時の置き場所: git config tmux.worktreeRoot > $TMUX_WORKTREE_ROOT
#   > <repo>/.claude/worktrees  (相対指定はメイン worktree からの相対として解決)
#
# macOS 標準の bash 3.2 でも動くように書いている。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/tmux_session.sh"

CONFIG="${TMUX_PROJECTS_JSON:-$HOME/.tmux/projects.json}"
TAB=$'\t'

# popup は -E で即閉じるため display-message ではメッセージが読めない。tty のあるうちに待つ。
die() {
  echo "worktree_session: $*" >&2
  if [ -t 0 ]; then printf '\n(Enter で閉じる) ' >&2; read -r _ || true; fi
  exit 1
}

command -v fzf >/dev/null || die "fzf が必要です"

# tmux のセッション名では ':' と '.' がターゲット指定の区切りとして解釈されるので潰す。
# '/' はブランチ名で多用されるため併せて '-' にする。
sanitize() { printf '%s' "$1" | tr ':./' '---'; }

# --- リポジトリの特定 ---------------------------------------------------------
git rev-parse --git-dir >/dev/null 2>&1 || die "git リポジトリではありません: $PWD"

# --porcelain の先頭エントリがメイン worktree。以降がリンク worktree。
# "パス <TAB> ブランチ名 <TAB> フラグ(detached|bare|空)" に整形する。
wt_list="$(git worktree list --porcelain | awk '
  function flush() {
    if (p != "") { print p "\t" b "\t" t; p = "" }
  }
  /^worktree /  { flush(); p = substr($0, 10); b = ""; t = "" }
  /^branch /    { b = substr($0, 8); sub(/^refs\/heads\//, "", b) }
  /^detached$/  { t = "detached" }
  /^bare$/      { t = "bare" }
  END           { flush() }
')"
[ -n "$wt_list" ] || die "worktree を取得できませんでした"

main_path="$(printf '%s\n' "$wt_list" | head -1 | cut -f1)"
main_parent="$(dirname "$main_path")"
repo_label="$(basename "$main_path")"

# $HOME 配下を ~ に短縮する。${p/#$HOME/~} は使わない: bash 5 は置換文字列側の ~ を
# チルダ展開してしまい ($HOME を $HOME で置換する no-op になる)、bash 3.2 とも挙動が違う。
# shellcheck disable=SC2088  # 表示用のリテラル ~ なので展開させたくない
abbrev_home() { # abbrev_home <絶対パス>
  case "$1" in
    "$HOME")    printf '~' ;;
    "$HOME"/*)  printf '~/%s' "${1#"$HOME"/}" ;;
    *)          printf '%s' "$1" ;;
  esac
}

# ブランチが無い (detached) worktree はディレクトリ名をラベルにする。
# ラベルはセッション名の一部になるので worktree 間で衝突しないものを選ぶ。
label_for() { # label_for <パス> <ブランチ名>
  if [ -n "$2" ]; then printf '%s' "$2"; else basename "$1"; fi
}

# --- 既存セッションの対応表 ---------------------------------------------------
# "id <TAB> 名前 <TAB> @worktree_path"
sess_map="$(ts_session_map)"

# session_for <worktree パス> <想定セッション名> → セッション id (無ければ空)
# @worktree_path の完全一致を優先する。無ければ「@worktree_path を持たない同名セッション」
# (= launch_project.sh で作ったもの) を拾う。名前を持つ別 worktree のセッションへ
# 誤って attach しないよう、名前による一致は @worktree_path が空のものに限る。
session_for() {
  printf '%s\n' "$sess_map" | awk -F'\t' -v p="$1" -v n="$2" '
    $3 != "" && $3 == p  { print $1; found = 1; exit }
    $3 == "" && $2 == n  { if (cand == "") cand = $1 }
    END                  { if (!found && cand != "") print cand }
  '
}

# session_name_for <worktree パス> <ラベル>
# メイン worktree は launch_project.sh のプロジェクト名と揃うよう素の <repo> にする。
session_name_for() {
  if [ "$1" = "$main_path" ]; then sanitize "$repo_label"
  else printf '%s@%s' "$(sanitize "$repo_label")" "$(sanitize "$2")"; fi
}

# --- 一覧の組み立て -----------------------------------------------------------
# 表示は 1 列目にまとめ、payload (worktree パス) をタブ区切りの 2 列目に隠す。
# ラベル幅は固定値では溢れる (ブランチ名の長さはリポジトリ次第) ので 2 パスに分け、
# 1 回目で最大幅を測ってから 2 回目で揃える。
# 中間表現の区切りは lib と同じ US。fzf に渡す最終行のタブと衝突させないため。
NEW_SENTINEL="__new__"

rows=""
label_w=0
while IFS="$TAB" read -r wpath wbranch wflag; do
  [ -n "$wpath" ] || continue
  [ "$wflag" = "bare" ] && continue   # bare には作業ツリーが無いので開けない

  wlabel="$(label_for "$wpath" "$wbranch")"
  [ "${#wlabel}" -gt "$label_w" ] && label_w="${#wlabel}"

  mark=" "
  [ -n "$(session_for "$wpath" "$(session_name_for "$wpath" "$wlabel")")" ] && mark="*"

  # メイン worktree からの相対で見せる。絶対パスだと共通の前置きが長くて差分が読めない。
  # ../<repo>.worktrees/ に置く運用も 1 行に収まるよう親ディレクトリまで面倒を見る。
  case "$wpath" in
    "$main_path")     disp="$(abbrev_home "$wpath")" ;;   # 相対表示の基準なのでここだけ絶対パス
    "$main_path"/*)   disp="./${wpath#"$main_path"/}" ;;
    "$main_parent"/*) disp="../${wpath#"$main_parent"/}" ;;
    *)                disp="$(abbrev_home "$wpath")" ;;
  esac

  note=""
  [ "$wpath" = "$main_path" ] && note="main"
  [ "$wflag" = "detached" ] && note="${note:+$note, }detached"

  rows="$rows$mark$TS_US$wlabel$TS_US$disp$TS_US$note$TS_US$wpath"$'\n'
done <<INNER
$wt_list
INNER

# 色は fzf --ansi に解釈させる。accent はステータスバー (colour215/240) と揃えた。
C_MARK=$'\033[38;5;215m'
C_SEP=$'\033[38;5;240m'
C_PATH=$'\033[2m'
C_OFF=$'\033[0m'

list=""
while IFS="$TS_US" read -r mark wlabel disp note wpath; do
  [ -n "$wpath" ] || continue
  [ "$mark" = "*" ] && mark="$C_MARK*$C_OFF"
  list="$list$mark $(printf '%-*s' "$label_w" "$wlabel") ${C_SEP}│${C_OFF} ${C_PATH}${disp}${note:+  ($note)}${C_OFF}$TAB$wpath"$'\n'
done <<INNER
$rows
INNER

# 先頭 2 文字はマーク列ぶんの字下げ (ラベル列の頭に揃える)
list="$list  + 新規 worktree を作成$TAB$NEW_SENTINEL"

selected="$(printf '%s\n' "$list" \
  | fzf --ansi --delimiter="$TAB" --with-nth=1 \
        --prompt='worktree> ' \
        --header="$repo_label   * = セッション有り   Enter: open / attach   Esc: cancel" \
        --no-multi | head -1
)" || selected=""
[ -n "$selected" ] || exit 0

target="${selected##*"$TAB"}"

# --- 新規作成 -----------------------------------------------------------------
# worktree の置き場所。相対指定はメイン worktree からの相対で解決する。
worktree_root() {
  local root
  root="$(git -C "$main_path" config --get tmux.worktreeRoot 2>/dev/null || true)"
  [ -n "$root" ] || root="${TMUX_WORKTREE_ROOT:-.claude/worktrees}"
  case "$root" in
    /*)  printf '%s' "$root" ;;
    \~*) printf '%s' "${root/#\~/$HOME}" ;;
    *)   printf '%s' "$main_path/$root" ;;
  esac
}

# 作業ツリー内に worktree を置くと untracked として見えてしまうので、共有される
# .gitignore ではなくローカル限定の .git/info/exclude に登録する。
# 引数は正規化済み (".." を含まない) の絶対パスであること。リポジトリ外なら何もしない。
add_local_exclude() { # add_local_exclude <除外したいディレクトリ>
  local dir="$1" main common rel excl
  main="$(cd "$main_path" && pwd -P)"
  case "$dir" in "$main"/*) rel="${dir#"$main"/}" ;; *) return 0 ;; esac
  common="$(git -C "$main_path" rev-parse --git-common-dir)"
  case "$common" in /*) ;; *) common="$main_path/$common" ;; esac
  excl="$common/info/exclude"
  mkdir -p "$(dirname "$excl")"
  grep -qxF "/$rel/" "$excl" 2>/dev/null && return 0
  printf '/%s/\n' "$rel" >>"$excl"
  echo "  .git/info/exclude に /$rel/ を追加しました" >&2
}

if [ "$target" = "$NEW_SENTINEL" ]; then
  printf 'ブランチ名: ' >&2
  read -r branch || branch=""
  [ -n "$branch" ] || exit 0

  root="$(worktree_root)"
  mkdir -p "$root" || die "ディレクトリを作成できません: $root"
  # ".." 混じりの指定 (../<repo>.worktrees など) を潰してからリポジトリ内判定に使う
  root="$(cd "$root" && pwd -P)"
  add_local_exclude "$root"

  dir="$root/$(printf '%s' "$branch" | tr '/' '-')"
  [ -e "$dir" ] && die "既に存在します: $dir"

  if git -C "$main_path" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$main_path" worktree add "$dir" "$branch" || die "git worktree add に失敗しました"
  else
    git -C "$main_path" worktree add -b "$branch" "$dir" || die "git worktree add に失敗しました"
  fi

  target="$(cd "$dir" && pwd -P)"
  label="$branch"
else
  label="$(label_for "$target" \
    "$(printf '%s\n' "$wt_list" | awk -F'\t' -v p="$target" '$1 == p { print $2; exit }')")"
fi

[ -d "$target" ] || die "ディレクトリが存在しません: $target"

# --- セッションへ -------------------------------------------------------------
name="$(session_name_for "$target" "$label")"

existing="$(session_for "$target" "$name")"
if [ -n "$existing" ]; then
  ts_attach "$existing"
  exit 0
fi

# ウィンドウ構成は .defaults.windows のみを見る。projects[] は同じ path に複数の
# プロファイルを登録できる (同じリポジトリに Local Server と Workspace がある等) ので、
# パスからプロジェクトを一意に決められない。projects.json が無い/壊れていても
# 落とさず shell 1 枚に倒す。区切りは US (0x1f) で lib 側の取り決めに合わせる。
records=""
if [ -f "$CONFIG" ] && command -v jq >/dev/null 2>&1 && jq empty "$CONFIG" 2>/dev/null; then
  records="$(jq -r '
    (.defaults.windows // [])[]
    | "window\u001f\(.name)\u001f\(.cmd // "")",
      ((.panes // [])[]
       | "pane\u001f\(.split // "bottom")\u001f\(.size // "")\u001f\(.cmd // "")")
  ' "$CONFIG" 2>/dev/null || true)"
fi
[ -n "$records" ] || records="window${TS_US}shell${TS_US}"

printf '%s\n' "$records" | ts_build_session "$name" "$target" \
  || die "セッションを作成できませんでした: $name (同名セッションが既にある可能性)"

# パスとの対応をセッションに刻んでおく (次回はこれで既存判定される)
sid="$(ts_session_id "$name")"
if [ -n "$sid" ]; then tmux set-option -t "$sid" @worktree_path "$target"; fi

ts_attach "${sid:-=$name}"
