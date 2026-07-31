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
.tmux.conf|.tmux.conf
.tmux/ip_addr.sh|.tmux/ip_addr.sh
.tmux/launch_project.sh|.tmux/launch_project.sh
.claude/keybindings.json|.claude/keybindings.json
.claude/.mcp.json|.claude/.mcp.json
.claude/settings.json|.claude/settings.json
.claude/skills|.claude/skills
.claude/agents|.claude/agents
.claude/hooks|.claude/hooks
.config/nvim/init.lua|.config/nvim/init.lua
.config/nvim/lua|.config/nvim/lua
.config/alacritty/alacritty.toml|.config/alacritty/alacritty.toml
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

# --- Homebrew ---
# cask/brew の中身は nix-darwin (nix/nix-darwin/homebrew.nix) が
# `darwin-rebuild switch` 実行時に宣言的にインストールする。
# ここでは nix-darwin がそれを呼び出せるように Homebrew 本体だけ用意する。
echo "--- brew ---"
if ! command -v brew >/dev/null 2>&1; then
  echo "  Homebrew が見つかりません。インストールします..."
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  DRY: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Apple Silicon の場合 PATH を通す
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
  fi
else
  echo "  [OK]   Homebrew ($(brew --version | head -1))"
fi

echo "--- symlinks ---"

while IFS='|' read -r src dest; do
  [ -n "$src" ] || continue
  link_one "$src" "$dest"
done <<EOF
$LINKS
EOF

# sample からの bootstrap (git 管理外の実ファイル。無ければコピー、既存なら触らない)
# "repo 内 sample の相対パス|$HOME からの相対パス"
COPIES="$(cat <<'EOF'
.tmux/projects.json.sample|.tmux/projects.json
.zshenv.sample|.zshenv
EOF
)"

copy_one() {
  local src="$REPO/$1" dest="$HOME/$2"

  if [ ! -e "$src" ]; then
    echo "  [SKIP] repo に無い: $1"
    n_skipped=$((n_skipped + 1))
    return
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "  [OK]   $2  (既存。上書きしません)"
    n_skipped=$((n_skipped + 1))
    return
  fi

  echo "  [COPY] $2 <- $1"
  local parent; parent="$(dirname "$dest")"
  [ -d "$parent" ] || run mkdir -p "$parent"
  run cp "$src" "$dest"
}

echo "--- bootstrap (sample copy) ---"
while IFS='|' read -r src dest; do
  [ -n "$src" ] || continue
  copy_one "$src" "$dest"
done <<EOF
$COPIES
EOF

echo "--- done ---"
echo "linked: $n_linked / skipped: $n_skipped / backed-up: $n_backed"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "(dry-run でした。実行するには --dry-run を外してください)"
fi
