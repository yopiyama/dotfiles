# DotFiles

This repository manages shell and tool configuration files.
It is intended to be used by creating symbolic links from files in this repo to locations such as `$HOME`, so the local environment loads these settings.

## Install

Run `install.sh` (or `make install`) to create all symlinks. It resolves the
link source from the script's own location, so the repository can live
anywhere.

- `make install-dry-run` / `./install.sh --dry-run` — show what would change without touching anything
- `make install` / `./install.sh` — create the symlinks (existing real files are backed up to `*.backup-<timestamp>`; symlinks pointing elsewhere are re-pointed)

The link targets are a mix of file-level and directory-level links (e.g.
`.claude/skills` and `.config/nvim/lua` are linked as whole directories), so
edit the `LINKS` list in `install.sh` when adding new managed files.
It also bootstraps untracked real files from `*.sample` files (e.g.
`~/.tmux/projects.json` from `.tmux/projects.json.sample`, `~/.zshenv` from
`.zshenv.sample`) if they do not already exist — see the `COPIES` list in
`install.sh`.

## Directory Structure

- `.claude/`: Claude app settings.
- `.config/`: XDG config directory.
- `.config/nvim/`: Neovim configuration.
- `.p10k.zsh`: Powerlevel10k Zsh prompt configuration.
- `.pylintrc`: Pylint configuration.
- `.pythonrc.py`: Python REPL startup configuration.
- `.tmux/`: Tmux helper scripts.
- `.tmux/ip_addr.sh`: Script used by Tmux config.
- `.tmux/launch_project.sh`: `prefix + C-p` で fzf からプロジェクト別ウィンドウセットを起動するランチャー (`~/.tmux/projects.json` を参照)。
- `.tmux/projects.json.sample`: プロジェクト定義のサンプル (実体 `~/.tmux/projects.json` は untracked)。
- `.tmux.conf`: Tmux configuration.
- `.vim/`: Vim runtime directory.
- `.vim/colors/`: Vim color schemes.
- `.vim/dein/`: Dein plugin manager directory.
- `.vimrc`: Vim configuration.
- `.zshenv.sample`: Sample Zsh environment file (実体 `~/.zshenv` は untracked)。
- `.zshrc`: Zsh configuration.
- `Makefile`: `install.sh`/`darwin-rebuild` をまとめたショートカット (`make help` 参照)。
- `nix/nix-darwin/`: nix-darwin flake (system 設定・Homebrew cask/brew の宣言的管理)。
- `nix/home-manager/`: home-manager (ユーザーレベルのパッケージ管理)。
- `nix/home-manager/programs/`: 個別アプリ設定 (git/lazygit/mise 等) を `programs.*` で宣言的に管理。install.sh の symlink から順次移行中。
- `chrome/extensions/`: 自作 Chrome 拡張 (unpacked で読み込む。symlink 不要なので `install.sh` の管理対象外)。
- `chrome/extensions/slack-direct-link/`: Slack のパーマリンクをブラウザ直リンクへ書き換え、アプリ起動の中間ページをスキップする拡張。
- `iterm_main_profile.json`: iTerm2 profile export.

## Packages (Nix)

Packages are declared in Nix and applied with `darwin-rebuild`.

- CLI/GUI packages available via nixpkgs → `nix/home-manager/home.nix` (`home.packages`)
- macOS-only or self-updating apps (Homebrew cask のまま管理するもの) → `nix/nix-darwin/homebrew.nix` (`homebrew.taps` / `homebrew.brews` / `homebrew.casks`)
- 環境ごと (personal/work) の差分 → `nix/nix-darwin/hosts/{profile}.nix`

適用:

```sh
make rebuild                  # PROFILE=personal (デフォルト)
make rebuild PROFILE=work
make dry-run                  # activate せず評価だけ確認
```

または直接:

```sh
cd nix/nix-darwin
sudo darwin-rebuild switch --flake .#personal   # または #work
```
