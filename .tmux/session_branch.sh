#!/bin/bash
# prefix + s (choose-tree) のセッション行に git ブランチ名を出すための前処理。
#
# 全セッションについて、一番小さい window index のペインの cwd を見て、git リポジトリなら
# ブランチ名 (detached HEAD なら短い SHA) をスタイル込みでセッションオプション @git_branch
# に入れる。リポジトリでなければ空にする (古い値を残さないため必ず上書きする)。
#
# choose-tree の -F に #() を書くとリスト構築時点ではジョブ結果が未完で空文字になり、
# 開いた直後は何も出ない (キーを押してリストが再構築されるまで反映されない)。そのため
# choose-tree の直前にこのスクリプトを走らせて値を確定させる。
set -uo pipefail

# set-option / show-options の -t は "=<名前>" を解釈しないのでセッション id を使う。
tmux list-sessions -F '#{session_id}' 2>/dev/null | while IFS= read -r sid; do
  [ -n "$sid" ] || continue

  # window index 昇順、同じ window ならアクティブペインを優先して先頭を取る。
  path=$(tmux list-panes -s -t "$sid" \
           -F '#{window_index} #{?pane_active,0,1} #{pane_current_path}' 2>/dev/null \
         | sort -k1,1n -k2,2n | head -1 | cut -d' ' -f3-)

  branch=""
  if [ -n "$path" ]; then
    branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null) \
      || branch=$(git -C "$path" rev-parse --short HEAD 2>/dev/null) \
      || branch=""
  fi

  if [ -n "$branch" ]; then
    tmux set-option -t "$sid" @git_branch "#[fg=colour179]  $branch#[default]"
  else
    tmux set-option -t "$sid" @git_branch ""
  fi
done
