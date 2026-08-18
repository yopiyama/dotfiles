# dotfiles リポジトリでの作業ルール

このリポジトリは設定を二層で管理しています（stow/chezmoi ではない）。

1. **Nix**: パッケージ全般と、`programs.*` で素直に書ける設定（git/lazygit/mise/ghostty）。`nix/home-manager/programs/<name>.nix`。適用は `make rebuild`
2. **symlink**: nvim の lua など生の設定ファイルのまま持ちたいもの。`scripts/link.sh` が `$HOME` 配下にリンクを張る。適用は `make link`

同じパスを両方に管理させないこと（home-manager が `backupFileExtension = "bak"` で symlink を黙って退避してしまう）。nvim は lua のまま維持する方針なので `programs.neovim.enable` を有効にしない。

symlink のリンク対象は `scripts/link.sh` の `LINKS` 変数で定義されており、主なものは:

- `.zshrc`, `.p10k.zsh`, `.tmux.conf`, `.config/nvim/init.lua` など単一ファイル
- `.claude/skills`, `.claude/hooks`, `.config/nvim/lua` などディレクトリ丸ごと

## ルール: パッケージを nixpkgs で入れるか Homebrew で入れるか

上から順に判定する。

1. **nixpkgs に無い / darwin で動かない** → Homebrew（`crit`, `im-select`）
2. **CLI・TUI・フォント・ライブラリ** → 常に nixpkgs。例外を作らない
3. **GUI アプリ** → 次のどれかに当たれば Homebrew の cask、当たらなければ nixpkgs
   - root 権限の installer / kext / system extension / launch daemon を入れる（`karabiner-elements`, `logitech-g-hub`）
   - 他アプリや OS の署名・固定パス前提に依存する（`1password-cli` は 1Password.app の CLI 統合、mas 経由のもの）
   - 自己更新を設定で止められない（`raycast`, `shottr`, `spotify`）

3 の分岐は「自己更新するか」ではなく「**止められるか**」で判定する。Nix store は
read-only なのでアプリ内の自己更新は必ず失敗するが、設定で無効化できるなら nixpkgs で
よい（ghostty は `auto-update = "off"`、orbstack は設定画面でオフにして nixpkgs 側）。

判断材料にしないもの:

- **nixpkgs のバージョンが cask より遅れていること**。レビューを経る以上当然の遅れで、
  ローカル完結のアプリなら実害がない。例外はサーバ/プロトコル互換で最新が要るクライアント
- **設定を Nix で管理したいかどうか**。`xdg.configFile` は Homebrew で入れたアプリの設定も
  書けるので主軸にならない。効くのは `programs.*` モジュールを使うときだけで、この場合は
  モジュールがパッケージも入れるためパッケージ側も nixpkgs に揃える

## ルール: `$HOME` 配下ではなくリポジトリ側の実体を編集する

`~/.claude/hooks/*` や `~/.zshrc` などは全てこのリポジトリへのシンボリックリンク。編集・調査は必ず `readlink -f` 等でリポジトリ内の実パスを確認し、そちらを直接編集する。

理由:
- Write 系ツールによっては symlink を unlink して新規ファイルで置き換えることがあり、その場合 `$HOME` 側で編集すると symlink が壊れてリポジトリと乖離する。
- リポジトリパスで編集しないと `git diff`/`git status` に変更が乗らず、コミット・レビューの対象にならない。

`~/.claude/settings.json`（グローバル設定）も `scripts/link.sh` の `LINKS` に含まれており、このリポジトリ直下の `.claude/settings.json` への symlink になっている。つまりグローバル設定とこのリポジトリのプロジェクト設定は同一ファイルであり、変更する際は必ずこのリポジトリ直下の `.claude/settings.json` を編集すること。

## コミットメッセージ規約

- 日本語で書く。件名に conventional prefix（`feat:` / `fix:` / `refactor:` / `chore:`。必要ならスコープ付きで `feat(hooks):` 等）を付ける
- 件名は変更内容の要約。補足が必要な場合は本文に箇条書きで「何を・なぜ」を書く
