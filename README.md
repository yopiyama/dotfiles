# DotFiles

This repository manages shell and tool configuration files.
It is intended to be used by creating symbolic links from files in this repo to locations such as `$HOME`, so the local environment loads these settings.

## Install

Run `install.sh` to create all symlinks. It resolves the link source from the
script's own location, so the repository can live anywhere.

- `./install.sh --dry-run` — show what would change without touching anything
- `./install.sh` — create the symlinks (existing real files are backed up to `*.backup-<timestamp>`; symlinks pointing elsewhere are re-pointed)

The link targets are a mix of file-level and directory-level links (e.g.
`.claude/skills` and `.config/nvim/lua` are linked as whole directories), so
edit the `LINKS` list in `install.sh` when adding new managed files.
It also bootstraps `~/.tmux/projects.json` from `.tmux/projects.example.json`
if it does not already exist (the real file is intentionally untracked).

## Directory Structure

- `.claude/`: Claude app settings.
- `.config/`: XDG config directory.
- `.config/git/`: Git configuration files.
- `.config/nvim/`: Neovim configuration.
- `.p10k.zsh`: Powerlevel10k Zsh prompt configuration.
- `.pylintrc`: Pylint configuration.
- `.pythonrc.py`: Python REPL startup configuration.
- `.tmux/`: Tmux helper scripts.
- `.tmux/ip_addr.sh`: Script used by Tmux config.
- `.tmux/launch_project.sh`: `prefix + C-p` で fzf からプロジェクト別ウィンドウセットを起動するランチャー (`~/.tmux/projects.json` を参照)。
- `.tmux/projects.example.json`: プロジェクト定義のサンプル (実体 `~/.tmux/projects.json` は untracked)。
- `.tmux.conf`: Tmux configuration.
- `.vim/`: Vim runtime directory.
- `.vim/colors/`: Vim color schemes.
- `.vim/dein/`: Dein plugin manager directory.
- `.vimrc`: Vim configuration.
- `.zshenv_sample`: Sample Zsh environment file.
- `.zshrc`: Zsh configuration.
- `Brewfile`: Homebrew package manifest (taps, formulae, casks) for `brew bundle`.
- `iterm_main_profile.json`: iTerm2 profile export.

## Homebrew packages

Essential packages are declared in `Brewfile` and managed with `brew bundle`.

- `brew bundle install` — install everything in `Brewfile`
- `brew bundle check` — show what's missing without installing
- `brew bundle cleanup [--force]` — list (or remove) packages not in `Brewfile`
- `brew bundle dump --force --no-vscode` — regenerate `Brewfile` from the current environment
