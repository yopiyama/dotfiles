#!/usr/bin/env bash
# fzf でプロジェクトを選び、定義済みウィンドウセットで tmux セッションを作成して attach する。
# 設定ファイル: ~/.tmux/projects.json (TMUX_PROJECTS_JSON で上書き可)
# 通常は tmux の `prefix + C-p` から display-popup 経由で呼ばれる。
#
# --startup <名前>: iTerm 起動時 (tmux 外・既存セッション無し) に zshrc から exec される用。
#   一覧に "+ new" を加え、それを選択 or キャンセルした場合は素のセッション <名前> を作る
#   (必ず tmux に入る従来挙動を維持)。
set -euo pipefail

CONFIG="${TMUX_PROJECTS_JSON:-$HOME/.tmux/projects.json}"

STARTUP_SESSION=""
[ "${1:-}" = "--startup" ] && STARTUP_SESSION="${2:-iTerm}"

die() { tmux display-message "launch_project: $*" 2>/dev/null || echo "launch_project: $*" >&2; exit 1; }

# 起動時モードのフォールバック: ピッカーを出せない/選ばなかったときは素のセッションへ
startup_fallback() { exec tmux new-session -A -s "$STARTUP_SESSION"; }

if [ -n "$STARTUP_SESSION" ]; then
  { [ -f "$CONFIG" ] && command -v jq >/dev/null && command -v fzf >/dev/null; } || startup_fallback
else
  [ -f "$CONFIG" ] || die "$CONFIG が見つかりません (projects.example.json をコピーしてください)"
  command -v jq  >/dev/null || die "jq が必要です"
  command -v fzf >/dev/null || die "fzf が必要です"
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
if tmux has-session -t "=$name" 2>/dev/null; then
  if [ -n "${TMUX:-}" ]; then tmux switch-client -t "=$name"; else tmux attach-session -t "=$name"; fi
  exit 0
fi

# path を取得して ~ を展開
path="$(jq -r --arg n "$name" '.projects[] | select(.name==$n) | .path' "$CONFIG")"
path="${path/#\~/$HOME}"
[ -d "$path" ] || die "ディレクトリが存在しません: $path"

# ウィンドウ定義 (project.windows があればそれ、なければ defaults.windows) を name<TAB>cmd で取得
# mapfile は bash 4+ のみ。macOS 標準の bash 3.2 でも動くよう while read で組む。
windows=()
while IFS= read -r line; do
  windows+=("$line")
done < <(
  jq -r --arg n "$name" '
    (.defaults.windows // []) as $d
    | .projects[] | select(.name==$n)
    | (.windows // $d)[]
    | "\(.name)\t\(.cmd // "")"
  ' "$CONFIG"
)
[ "${#windows[@]}" -gt 0 ] || die "$name のウィンドウ定義が空です"

first_name=""
for i in "${!windows[@]}"; do
  wname="${windows[$i]%%$'\t'*}"
  wcmd="${windows[$i]#*$'\t'}"

  if [ "$i" -eq 0 ]; then
    # -n で名前を明示すると automatic-rename はそのウィンドウで自動的に無効化される
    tmux new-session -d -s "$name" -n "$wname" -c "$path"
    first_name="$wname"
  else
    tmux new-window -t "=$name:" -n "$wname" -c "$path"
  fi

  [ -n "$wcmd" ] && tmux send-keys -t "=$name:$wname" "$wcmd" C-m
done

tmux select-window -t "=$name:$first_name"

if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "=$name"
else
  tmux attach-session -t "=$name"
fi
