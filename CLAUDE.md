# dotfiles リポジトリでの作業ルール

このリポジトリは `install.sh` によって `$HOME` 配下にシンボリックリンクを張る自作 dotfiles 管理です（stow/chezmoi ではない）。リンク対象は `install.sh` の `LINKS` 変数で定義されており、主なものは:

- `.zshrc`, `.p10k.zsh`, `.tmux.conf`, `.config/git/config` など単一ファイル
- `.claude/skills`, `.claude/hooks`, `.config/nvim/lua` などディレクトリ丸ごと

## ルール: `$HOME` 配下ではなくリポジトリ側の実体を編集する

`~/.claude/hooks/*` や `~/.zshrc` などは全てこのリポジトリへのシンボリックリンク。編集・調査は必ず `readlink -f` 等でリポジトリ内の実パスを確認し、そちらを直接編集する。

理由:
- Write 系ツールによっては symlink を unlink して新規ファイルで置き換えることがあり、その場合 `$HOME` 側で編集すると symlink が壊れてリポジトリと乖離する。
- リポジトリパスで編集しないと `git diff`/`git status` に変更が乗らず、コミット・レビューの対象にならない。

`~/.claude/settings.json`（グローバル設定）はこのリポジトリの管理対象外（symlink ではない）なので、グローバル設定を変更する場合は素直に `~/.claude/settings.json` を直接編集してよい。プロジェクト設定はこのリポジトリ直下の `.claude/settings.json` 自体が実体。
