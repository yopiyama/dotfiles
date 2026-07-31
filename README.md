# DotFiles

This repository manages shell and tool configuration files.
設定は Nix (パッケージと `programs.*`) と `$HOME` へのシンボリックリンクの
二層で適用する。操作の入口は `Makefile` (`make help`)。

## 構成 (二層)

設定の管理は 2 層に分かれており、これは移行途中の暫定ではなく確定した方針。

| 層 | 管理対象 | 適用 |
| --- | --- | --- |
| Nix | パッケージ全般と、`programs.*` で素直に書ける設定 (git/lazygit/mise/alacritty) | `make rebuild` |
| symlink | nvim の lua や zsh/tmux など、生の設定ファイルのまま持ちたいもの | `make link` |

**同じパスを両方に管理させないこと。** home-manager は `backupFileExtension = "bak"`
なので、衝突すると symlink が黙って `*.bak` にリネームされ nix store のリンクに
差し替わる。nvim については `programs.neovim.enable` を有効にしないこと
(有効にすると init.lua が home-manager 管理下に入り symlink と衝突する)。
neovim 本体は `home.packages` で入れるだけに留めている。

## Install

```sh
make setup      # 初回。前提チェック → link → rebuild
make link       # symlink 作成 + Homebrew 本体の準備
make link-dry   # 何も変更せず、実行内容だけ表示
make doctor     # 前提コマンドと symlink の状態を確認
```

`make help` で全ターゲットを表示する。nix 本体だけは自動インストールしないので、
未導入の場合は `make setup` が案内するインストーラを先に実行する。

symlink 作成の実体は `scripts/link.sh`。単体実行 (`scripts/link.sh`,
`scripts/link.sh --dry-run`) もできる。リンク元はスクリプト自身の場所から
解決するので、リポジトリはどこに clone してもよい。既存の実ファイルは
`*.backup-<timestamp>` にバックアップし、別の場所を指す symlink は張り替える。

リンク対象はファイル単位とディレクトリ単位が混在する (`.claude/skills` や
`.config/nvim/lua` はディレクトリ丸ごと) ので、管理対象を増やすときは
`scripts/link.sh` の `LINKS` を編集する。
`*.sample` から untracked な実ファイルを bootstrap する仕組みもあり
(`~/.tmux/projects.json` ← `.tmux/projects.json.sample`、`~/.zshenv` ←
`.zshenv.sample`)、既存の場合は触らない — `COPIES` を参照。

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
- `Makefile`: 全操作の入口 (`make help` 参照)。
- `scripts/link.sh`: symlink 作成 + Homebrew 本体の準備 (`make link` の実体)。
- `scripts/vendored-skill-diff`: vendored な skill の差分確認スクリプト。
- `nix/nix-darwin/`: nix-darwin flake (system 設定・Homebrew cask/brew の宣言的管理)。
- `nix/home-manager/`: home-manager (ユーザーレベルのパッケージ管理)。
- `nix/home-manager/programs/<name>.nix`: 個別アプリ設定 (git/lazygit/mise/alacritty) を `programs.*` で宣言的に管理。上流 home-manager の `modules/programs/<name>.nix` に命名を揃えている。
- `chrome/extensions/`: 自作 Chrome 拡張 (unpacked で読み込む。symlink 不要なので symlink 管理の対象外)。
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
