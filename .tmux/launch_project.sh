#!/usr/bin/env bash
# fzf でプロジェクトを選び、定義済みウィンドウセットで tmux セッションを作成して attach する。
# 設定ファイル: ~/.tmux/projects.json (TMUX_PROJECTS_JSON で上書き可)
# 通常は tmux の `prefix + P` から display-popup 経由で呼ばれる。
set -euo pipefail

CONFIG="${TMUX_PROJECTS_JSON:-$HOME/.tmux/projects.json}"

die() { tmux display-message "launch_project: $*" 2>/dev/null || echo "launch_project: $*" >&2; exit 1; }

[ -f "$CONFIG" ] || die "$CONFIG が見つかりません (projects.example.json をコピーしてください)"
command -v jq  >/dev/null || die "jq が必要です"
command -v fzf >/dev/null || die "fzf が必要です"

# name<TAB>path の一覧を fzf に渡し、name を取得
selected="$(
  jq -r '.projects[] | "\(.name)\t\(.path)"' "$CONFIG" \
    | fzf --delimiter='\t' --with-nth=1,2 \
          --prompt='project> ' \
          --header='Enter: open / attach   Esc: cancel' \
          --no-multi
)" || exit 0  # Esc 等でキャンセルしたら何もしない

name="${selected%%$'\t'*}"
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
