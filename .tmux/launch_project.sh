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
  [ -f "$CONFIG" ] || die "$CONFIG が見つかりません (projects.json.sample をコピーしてください)"
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

# ウィンドウ/ペイン定義 (project.windows があればそれ、なければ defaults.windows) を
# 1行1レコードで取得する。区切りは US (0x1f): cmd に含まれうるタブやスペースと衝突しないため。
#   window <US> 名前 <US> cmd
#   pane   <US> split(right|bottom) <US> size <US> cmd   ← 直前の window に属する追加ペイン
# mapfile は bash 4+ のみ。macOS 標準の bash 3.2 でも動くよう while read で組む。
records=()
while IFS= read -r line; do
  records+=("$line")
done < <(
  jq -r --arg n "$name" '
    (.defaults.windows // []) as $d
    | .projects[] | select(.name==$n)
    | (.windows // $d)[]
    | "window\u001f\(.name)\u001f\(.cmd // "")",
      ((.panes // [])[]
       | "pane\u001f\(.split // "bottom")\u001f\(.size // "")\u001f\(.cmd // "")")
  ' "$CONFIG"
)
[ "${#records[@]}" -gt 0 ] || die "$name のウィンドウ定義が空です"

US=$'\x1f'

# detached で作るセッションは既定 80x24 になり、%指定の分割サイズがその幅で計算される。
# attach 時のリサイズで tmux は増分をペインへほぼ均等に配り比率を保存しないため、
# 作成時点で実クライアントのサイズを渡しておく。
if [ -n "${TMUX:-}" ]; then
  # popup 内の tput は popup サイズを返すため、外側クライアントのサイズを tmux に問い合わせる
  size_args=(-x "$(tmux display-message -p '#{client_width}')" -y "$(tmux display-message -p '#{client_height}')")
else
  size_args=(-x "$(tput cols)" -y "$(tput lines)")
fi

first_name=""
win_pane=""     # 現在のウィンドウの最初のペイン id
panes_added=""  # 現在のウィンドウで分割したか

# ウィンドウの分割が済んだら最初のペイン (メイン) にフォーカスを戻す
finish_window() {
  if [ -n "$panes_added" ]; then tmux select-pane -t "$win_pane"; fi
}

for rec in "${records[@]}"; do
  IFS="$US" read -r kind f1 f2 f3 <<<"$rec"
  case "$kind" in
    window)
      finish_window
      wname="$f1"
      panes_added=""
      if [ -z "$first_name" ]; then
        # -n で名前を明示すると automatic-rename はそのウィンドウで自動的に無効化される
        win_pane="$(tmux new-session -d "${size_args[@]}" -s "$name" -n "$wname" -c "$path" -P -F '#{pane_id}')"
        first_name="$wname"
      else
        win_pane="$(tmux new-window -t "=$name:" -n "$wname" -c "$path" -P -F '#{pane_id}')"
      fi
      [ -n "$f2" ] && tmux send-keys -t "$win_pane" "$f2" C-m
      ;;
    pane)
      case "$f1" in
        right|h)  split_flag=-h ;;
        bottom|v) split_flag=-v ;;
        *) die "不正な split 指定: $f1 (right / bottom)" ;;
      esac
      # 直前に作ったペイン (= アクティブペイン) を分割していく
      split_args=(split-window "$split_flag" -t "=$name:$wname" -c "$path" -P -F '#{pane_id}')
      [ -n "$f2" ] && split_args+=(-l "$f2")
      pane_id="$(tmux "${split_args[@]}")"
      [ -n "$f3" ] && tmux send-keys -t "$pane_id" "$f3" C-m
      panes_added=1
      ;;
  esac
done
finish_window

tmux select-window -t "=$name:$first_name"

if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "=$name"
else
  tmux attach-session -t "=$name"
fi
