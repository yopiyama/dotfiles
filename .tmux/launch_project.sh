#!/usr/bin/env bash
# fzf でプロジェクトを選び、定義済みウィンドウセットで tmux セッションを作成して attach する。
# 設定ファイル: ~/.tmux/projects.json (TMUX_PROJECTS_JSON で上書き可)
# 通常は tmux の `prefix + C-p` から display-popup 経由で呼ばれる。
#
# --startup <名前>: iTerm 起動時 (tmux 外・既存セッション無し) に zshrc から exec される用。
#   一覧に "+ new" を加え、それを選択 or キャンセルした場合は素のセッション <名前> を作る
#   (必ず tmux に入る従来挙動を維持)。
#
# セッション生成の実処理は lib/tmux_session.sh に切り出してあり、worktree_session.sh と共有する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/tmux_session.sh"

CONFIG="${TMUX_PROJECTS_JSON:-$HOME/.tmux/projects.json}"

STARTUP_SESSION=""
[ "${1:-}" = "--startup" ] && STARTUP_SESSION="${2:-iTerm}"

die() { tmux display-message "launch_project: $*" 2>/dev/null || echo "launch_project: $*" >&2; exit 1; }

# 起動時モードのフォールバック: ピッカーを出せない/選ばなかったときは素のセッションへ
startup_fallback() { exec tmux new-session -A -s "$STARTUP_SESSION"; }

# 起動時モードでは JSON の妥当性まで見る。壊れていると後段の jq が set -e で落ち、
# zshrc から exec された場合はシェルごと終了して端末が一切開けなくなるため。
if [ -n "$STARTUP_SESSION" ]; then
  { [ -f "$CONFIG" ] && command -v jq >/dev/null && command -v fzf >/dev/null \
    && jq empty "$CONFIG" 2>/dev/null; } || startup_fallback
else
  [ -f "$CONFIG" ] || die "$CONFIG が見つかりません (projects.json.sample をコピーしてください)"
  command -v jq  >/dev/null || die "jq が必要です"
  command -v fzf >/dev/null || die "fzf が必要です"
  jq empty "$CONFIG" 2>/dev/null || die "$CONFIG が壊れています (JSON として読めません)"
fi

# name<TAB>path の一覧。起動時モードでは先頭に "+ new" (素のセッション) を加える。
list="$(jq -r '.projects[] | "\(.name)\t\(.path)"' "$CONFIG")"
[ -n "$STARTUP_SESSION" ] && list="+ new"$'\t'"(素のセッション: $STARTUP_SESSION)
$list"

selected="$(printf '%s\n' "$list" \
  | fzf --delimiter='\t' --with-nth=1,2 \
        --prompt='project> ' \
        --header='Enter: open / attach   Esc: cancel' \
        --no-multi
)" || selected=""

name="${selected%%$'\t'*}"

# 起動時モード: "+ new" 選択 or キャンセル(空) なら素のセッションへフォールバック
if [ -n "$STARTUP_SESSION" ] && { [ -z "$name" ] || [ "$name" = "+ new" ]; }; then
  startup_fallback
fi

[ -n "$name" ] || exit 0

# 既に同名セッションがあればそのまま attach
if ts_session_exists "$name"; then
  ts_attach "=$name"
  exit 0
fi

# path を取得して ~ を展開
path="$(jq -r --arg n "$name" '.projects[] | select(.name==$n) | .path' "$CONFIG")"
path="${path/#\~/$HOME}"
[ -d "$path" ] || die "ディレクトリが存在しません: $path"

# ウィンドウ/ペイン定義 (project.windows があればそれ、なければ defaults.windows) を
# lib の取り決めどおり US (0x1f) 区切りの 1 行 1 レコードで取り出す。
records="$(jq -r --arg n "$name" '
  (.defaults.windows // []) as $d
  | .projects[] | select(.name==$n)
  | (.windows // $d)[]
  | "window\u001f\(.name)\u001f\(.cmd // "")",
    ((.panes // [])[]
     | "pane\u001f\(.split // "bottom")\u001f\(.size // "")\u001f\(.cmd // "")")
' "$CONFIG")"
[ -n "$records" ] || die "$name のウィンドウ定義が空です"

printf '%s\n' "$records" | ts_build_session "$name" "$path" \
  || die "セッションを作成できませんでした: $name"

ts_attach "=$name"
