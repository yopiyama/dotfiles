# DotFiles

This repository manages shell and tool configuration files.
設定は Nix (パッケージと `programs.*`) と `$HOME` へのシンボリックリンクの
二層で適用する。操作の入口は `Makefile` (`make help`)。

## 構成 (二層)

設定の管理は 2 層に分かれており、これは移行途中の暫定ではなく確定した方針。

| 層 | 管理対象 | 適用 |
| --- | --- | --- |
| Nix | パッケージ全般と `programs.*` で書ける設定 (git/lazygit/mise 等) | `make rebuild` |
| symlink | nvim の lua や zsh/tmux など、生の設定ファイルのまま持ちたいもの | `make link` |

**同じパスを両方に管理させないこと。** home-manager は `backupFileExtension = "bak"`
なので、衝突すると symlink が黙って `*.bak` にリネームされ nix store のリンクに
差し替わる。nvim については `programs.neovim.enable` を有効にしないこと
(有効にすると init.lua が home-manager 管理下に入り symlink と衝突する)。
neovim 本体は `home.packages` で入れるだけに留めている。

## Install

```sh
make setup PROFILE=work  # 初回。install-nix → link → rebuild
make install-nix # nix 本体のインストール (導入済みなら何もしない)
make link        # symlink 作成 + Homebrew 本体の準備
make link-dry    # 何も変更せず、実行内容だけ表示
make doctor      # 前提コマンドと symlink の状態を確認
```

`make help` で全ターゲットを表示する。

nix 本体は `make install-nix` (公式インストーラ `https://artifacts.nixos.org/nix-installer`)
が入れる。インストーラは sudo と対話確認を求めるので非対話実行はできない。完了しても
起動中のシェルには PATH が通らないため、`rebuild` / `dry-run` は実行前に
`/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh` を読む。新しいシェルでは
`/etc/zshrc` 経由で通るが、`~/.zshenv` に `setopt no_global_rcs` を書いている場合は
読まれないので `.zshenv.sample` のように `path` へ自分で足すこと。

初回は `darwin-rebuild` がまだ無いので、`make rebuild` は flake.lock で固定した
nix-darwin を build してその中の `darwin-rebuild` で activate する。2 回目以降は
PATH 上のものを使う。

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

全ファイルは列挙しない。迷いやすい場所と、置き場所の判断が要るものだけ書く。

```text
nix/
  nix-darwin/          system 設定と Homebrew の宣言。hosts/ が personal|work の差分
  home-manager/
    home.nix           home.packages (パッケージはここ)
    programs/<name>.nix  個別アプリ設定。上流 home-manager の modules/programs/<name>.nix に命名を揃える
scripts/
  link.sh              symlink 作成 + Homebrew 本体の準備 (make link の実体)
.config/nvim/          Neovim。init.lua + lua/ を丸ごと symlink (Nix 管理下に置かない)
.claude/               Claude Code 設定。skills/ agents/ hooks/ はディレクトリ丸ごと symlink
.tmux/                 tmux から呼ぶヘルパー。launch_project.sh = prefix + C-p のプロジェクトランチャー、
                       worktree_session.sh = prefix + C-w の git worktree ランチャー、lib/ は両者の共通部品
chrome/extensions/     自作 Chrome 拡張。unpacked で直接読み込むので symlink 対象外
raycast/               自作 Raycast 拡張 (extensions/) と script command (script/)
```

トップレベルには他に `.zshrc` / `.p10k.zsh` / `.tmux.conf` などの単一設定ファイルがあり、
いずれも `scripts/link.sh` の `LINKS` 経由で `$HOME` にリンクされる。
`*.sample` は untracked な実ファイルの雛形 (`.zshenv.sample`, `.tmux/projects.json.sample`)。

## Packages (Nix)

Packages are declared in Nix and applied with `darwin-rebuild`.

- CLI/GUI packages available via nixpkgs → `nix/home-manager/home.nix` (`home.packages`)
- macOS-only or self-updating apps (Homebrew cask のまま管理するもの) →
  `nix/nix-darwin/homebrew.nix` (`homebrew.taps` / `brews` / `casks`)
- 環境ごと (personal/work) の差分 → `nix/nix-darwin/hosts/{profile}.nix`

適用:

```sh
make rebuild PROFILE=personal
make rebuild PROFILE=work
make dry-run PROFILE=work     # activate せず評価だけ確認
```

`PROFILE` にデフォルトは無く、`setup` / `rebuild` / `dry-run` では指定が必須
(取り違えると別マシン向けの設定を activate してしまうため)。指定できる値は
`nix/nix-darwin/hosts/*.nix` のファイル名から自動で拾っており、未指定・不正な値は
実行前にエラーで止まる。

または直接:

```sh
cd nix/nix-darwin
sudo darwin-rebuild switch --flake .#personal   # または #work
```

## tmux (prefix + C-p / C-w)

どちらも fzf の popup を出し、選んだものに対応する tmux セッションへ移動する。
既に同じセッションがあれば作り直さず attach (tmux 内なら switch-client) するだけ。
ウィンドウ構成は `~/.tmux/projects.json` (`.tmux/projects.json.sample` からコピー) で定義する。

| キー | スクリプト | 一覧に出るもの |
| --- | --- | --- |
| `prefix + C-p` | `.tmux/launch_project.sh` | `projects.json` の `projects[]` |
| `prefix + C-w` | `.tmux/worktree_session.sh` | カレントペインのリポジトリの git worktree |

セッション生成の実処理は `.tmux/lib/tmux_session.sh` に共通化してある。

### worktree ランチャー

一覧は `git worktree list` から作る。git 自身が登録済み worktree の実パスを持っているので、
`<repo>/.claude/worktrees/` でも `../<repo>.worktrees/` でも置き場所を問わず出てくる
(ディレクトリを走査しないので探索パスの設定は要らない)。

- セッション名は メイン worktree が `<repo>`、それ以外が `<repo>@<ブランチ名>`。
  `:` `.` `/` は tmux のターゲット指定と衝突するので `-` に潰す
- worktree との対応はセッションオプション `@worktree_path` で保持する。名前ではなく
  パスで突き合わせるので、セッションをリネームしても同じ worktree を開き直せる
- 一覧は `<マーク> <ブランチ名> │ <パス>` の 3 列。`*` は「そのセッションが既にある」印。
  ブランチ名の列幅はその場の最長ブランチ名に合わせて決める (固定幅だと溢れる)。
  パスはメイン worktree からの相対 (`./`, `../`) で見せ、メイン worktree の行だけ
  相対表示の基準として絶対パスを出す
- ウィンドウ構成は `defaults.windows` (無ければ `shell` 1 枚)。`projects[]` は同じ `path` に
  複数のプロファイルを登録できる (同じリポジトリに Local Server と Workspace がある等) ため、
  パスからプロジェクトを一意に引き当てられない。worktree 側は `defaults` だけを見る

`+ 新規 worktree を作成` を選ぶとブランチ名を聞き、`git worktree add` してからセッションを開く
(既存ブランチならそれを checkout、無ければ新規ブランチを作る)。置き場所は上から順に:

1. `git config tmux.worktreeRoot` (リポジトリごとに設定できる。相対指定はメイン worktree からの相対)
2. 環境変数 `TMUX_WORKTREE_ROOT`
3. `<repo>/.claude/worktrees`

リポジトリの作業ツリー内に置く場合は、untracked として見えないよう置き場所を
`.git/info/exclude` に登録する (共有される `.gitignore` は触らない)。

```sh
# 例: このリポジトリでは兄弟ディレクトリに置く
git config tmux.worktreeRoot ../dotfiles.worktrees
```
