#!/usr/bin/env bash
#
# dotfiles install: このリポジトリの設定ファイルへ $HOME からシンボリックリンクを張る。
#
#   ./install.sh            実際にリンクを作成 (既存の実ファイルはバックアップ)
#   ./install.sh --dry-run  何もせず、実行内容だけ表示
#
# - リンク元はこのスクリプト自身の場所から解決するので、clone 先パスに依存しない。
# - 一部はディレクトリ単位のリンク (.claude/skills, .config/nvim/lua) なので注意。
# - $HOME/.claude, $HOME/.config, $HOME/.tmux 自体は実ディレクトリのまま、中身を選択的にリンクする。
# - macOS 標準の bash 3.2 でも動くように書いている。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# "repo 内の相対パス|$HOME からの相対パス" の一覧。
# dest 側は中間ディレクトリが無ければ自動で作成する。
LINKS="$(cat <<'EOF'
.zshrc|.zshrc
.p10k.zsh|.p10k.zsh
.gitconfig|.gitconfig
.tmux.conf|.tmux.conf
.tmux/ip_addr.sh|.tmux/ip_addr.sh
.tmux/launch_project.sh|.tmux/launch_project.sh
.claude/keybindings.json|.claude/keybindings.json
.claude/.mcp.json|.claude/.mcp.json
.claude/skills|.claude/skills
.config/nvim/init.lua|.config/nvim/init.lua
.config/nvim/lua|.config/nvim/lua
.config/git/ignore|.config/git/ignore
lazygit/config.yml|Library/Application Support/lazygit/config.yml
EOF
)"

ts="$(date +%Y%m%d-%H%M%S)"
n_linked=0 n_skipped=0 n_backed=0

run() { # コマンドを表示しつつ実行 (dry-run なら表示のみ)
  if [ "$DRY_RUN" -eq 1 ]; then echo "  DRY: $*"; else "$@"; fi
}

link_one() {
  local src="$REPO/$1" dest="$HOME/$2"

  if [ ! -e "$src" ]; then
    echo "  [SKIP] repo に無い: $1"
    n_skipped=$((n_skipped + 1))
    return
  fi

  # 既に正しいリンクなら何もしない
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "  [OK]   $2  (既にリンク済み)"
    n_skipped=$((n_skipped + 1))
    return
  fi

  # 中間ディレクトリを用意
  local parent; parent="$(dirname "$dest")"
  [ -d "$parent" ] || run mkdir -p "$parent"

  if [ -L "$dest" ]; then
    # 別の場所を指す古いリンク → 張り替え
    echo "  [RELINK] $2  (旧: $(readlink "$dest"))"
    run rm "$dest"
  elif [ -e "$dest" ]; then
    # 実ファイル/実ディレクトリ → バックアップしてから置換
    echo "  [BACKUP] $2 -> $2.backup-$ts"
    run mv "$dest" "$dest.backup-$ts"
    n_backed=$((n_backed + 1))
  else
    echo "  [LINK] $2"
  fi

  run ln -s "$src" "$dest"
  n_linked=$((n_linked + 1))
}

echo "dotfiles repo: $REPO"
[ "$DRY_RUN" -eq 1 ] && echo "(dry-run: 実際には変更しません)"
echo "--- symlinks ---"

while IFS='|' read -r src dest; do
  [ -n "$src" ] || continue
  link_one "$src" "$dest"
done <<EOF
$LINKS
EOF

# tmux プロジェクト設定の bootstrap (git 管理外の実ファイル。無ければ example からコピー)
echo "--- tmux projects.json ---"
proj="$HOME/.tmux/projects.json"
if [ -e "$proj" ]; then
  echo "  [OK]   ~/.tmux/projects.json (既存。上書きしません)"
else
  echo "  [COPY] ~/.tmux/projects.json <- .tmux/projects.example.json"
  run mkdir -p "$HOME/.tmux"
  run cp "$REPO/.tmux/projects.example.json" "$proj"
fi

echo "--- done ---"
echo "linked: $n_linked / skipped: $n_skipped / backed-up: $n_backed"
[ "$DRY_RUN" -eq 1 ] && echo "(dry-run でした。実行するには --dry-run を外してください)"
